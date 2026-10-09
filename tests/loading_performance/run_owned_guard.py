#!/usr/bin/env python3
"""Bound one newly launched Godot child by time and true cgroup headroom.

Never signals a platform process or a process group. Before every signal it
verifies the owned PID's executable, parent and start-time identity.
"""
import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('--timeout', type=float, default=180.0)
parser.add_argument('--reserve-mib', type=int, default=512)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command:
    raise SystemExit('A Godot command is required')
executable = Path(shutil.which(command[0]) or command[0]).resolve(strict=True)
if 'godot' not in executable.name.lower():
    raise SystemExit('Only an explicitly owned Godot executable is supported')
command[0] = str(executable)
cgroup = Path('/sys/fs/cgroup')
limit = int((cgroup / 'memory.max').read_text())
if not 0 < limit <= 8 * 1024**3:
    raise SystemExit('A verified physical cgroup limit of at most8GiB is required')
threshold = limit - args.reserve_mib * 1024**2
args.log.parent.mkdir(parents=True, exist_ok=True)
log = args.log.open('w', buffering=1)
start = time.monotonic()
child = None
identity = None

def emit(event, **fields):
    row = {'event': event, 'elapsed_s': round(time.monotonic() - start, 4), 'utc_epoch': time.time(), **fields}
    log.write(json.dumps(row) + '\n'); log.flush()
    if event != 'sample': print('OWNED_GODOT_GUARD', json.dumps(row), flush=True)

def memory():
    return int((cgroup / 'memory.current').read_text())

def owned_identity():
    if child is None or child.poll() is not None: return None
    proc = Path('/proc') / str(child.pid)
    try:
        exe = Path(os.readlink(proc / 'exe')).resolve()
        tail = (proc / 'stat').read_text().rsplit(') ', 1)[1].split()
        parent, ticks = int(tail[1]), int(tail[19])
        if exe != executable or parent != os.getpid(): return None
        return str(exe), parent, ticks
    except (OSError, ValueError, IndexError):
        return None

def snapshot():
    result = {'cgroup_current': memory(), 'owned_pid': child.pid if child else None}
    if child:
        try:
            tail = Path('/proc', str(child.pid), 'stat').read_text().rsplit(') ', 1)[1].split()
            result['process_cpu_seconds'] = (int(tail[11]) + int(tail[12])) / os.sysconf('SC_CLK_TCK')
        except (OSError, ValueError, IndexError): pass
    if child:
        try:
            values = dict(line.split(':', 1) for line in Path('/proc', str(child.pid), 'status').read_text().splitlines() if ':' in line)
            for key in ['VmRSS', 'VmHWM', 'VmSize']:
                result[key + '_kib'] = int(values.get(key, '0 kB').split()[0])
        except (OSError, ValueError): pass
    return result

def stop_owned(reason):
    if child is None or child.poll() is not None: return
    if owned_identity() != identity or identity is None:
        emit('signal_refused_identity_mismatch', reason=reason, owned_pid=child.pid)
        return
    emit('term_owned', reason=reason, identity=identity, **snapshot())
    child.send_signal(signal.SIGTERM)
    deadline = time.monotonic() + 5.0
    while child.poll() is None and time.monotonic() < deadline: time.sleep(.05)
    if child.poll() is None:
        if owned_identity() == identity:
            emit('kill_owned', reason=reason, identity=identity, **snapshot())
            child.kill()
        else: emit('kill_refused_identity_mismatch', reason=reason)
    try: child.wait(timeout=2)
    except subprocess.TimeoutExpired: emit('owned_exit_unconfirmed', reason=reason)

def interrupted(signum, _frame):
    stop_owned('supervisor_signal_' + str(signum))
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
baseline = memory()
emit('baseline', cgroup_current=baseline, cgroup_limit=limit, stop_threshold=threshold, reserve_bytes=args.reserve_mib * 1024**2, timeout_s=args.timeout, executable=str(executable))
if baseline >= threshold:
    emit('admission_blocked_headroom'); raise SystemExit(78)
try:
    child = subprocess.Popen(command, shell=False)
    identity = owned_identity()
    if identity is None:
        # Popen starts the exact executable without a shell. Do not signal any
        # unverified PID; report the admission failure rather than guessing.
        emit('identity_not_verified', owned_pid=child.pid)
        raise SystemExit(2)
    emit('owned_launched', owned_pid=child.pid, identity=identity)
    next_log = 0.0
    while child.poll() is None:
        elapsed = time.monotonic() - start
        current = memory()
        if current >= threshold:
            emit('memory_guard_triggered', **snapshot())
            stop_owned('cgroup_reserve'); emit('guard_complete', child_exit=child.poll(), **snapshot()); raise SystemExit(78)
        if elapsed >= args.timeout:
            emit('external_timeout', **snapshot())
            stop_owned('external_timeout'); emit('timeout_complete', child_exit=child.poll(), **snapshot()); raise SystemExit(124)
        if elapsed >= next_log:
            emit('sample', **snapshot()); next_log = elapsed + .25
        time.sleep(.05)
    code = child.returncode
    emit('exited', child_exit=code, **snapshot())
    raise SystemExit(code if code >= 0 else 128 - code)
finally:
    log.flush()
