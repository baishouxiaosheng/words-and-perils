#!/usr/bin/env python3
"""One guarded native GLX run on dot's existing display; no new Xorg/EGL loop."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--engine', default='godot')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
run = root / 'evidence' / ('slope_' + stamp)
run.mkdir(parents=True, exist_ok=False)

def hashes():
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()
            and not any(x in p.relative_to(root).parts for x in ['.godot', 'evidence'])
            and not p.name.endswith(('.uid', '.import'))}

before = hashes()
(run / 'before.json').write_text(json.dumps(before, indent=2) + '\n')
env = os.environ.copy()
if not env.get('DISPLAY'):
    raise SystemExit('Existing dot GLX display is required; do not substitute another executor')
for name in ['DATA', 'CONFIG', 'CACHE']:
    path = run / ('xdg_' + name.lower()); path.mkdir()
    env['XDG_' + name + '_HOME'] = str(path)
env['LP_NUM_THREADS'] = '2'
command = [args.engine, '--path', str(root), '--audio-driver', 'Dummy',
           '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3',
           '--display-driver', 'x11', '--script', 'tests/capture_slope.gd', '--', str(run)]
with (run / 'engine.log').open('wb') as log:
    result = subprocess.run([sys.executable, str(root / 'tests/run_owned_guard.py'),
                             '--log', str(run / 'guard.jsonl'), '--timeout', '120',
                             '--reserve-mib', '512', '--', *command],
                            env=env, stdout=log, stderr=subprocess.STDOUT)
after = hashes()
(run / 'after.json').write_text(json.dumps(after, indent=2) + '\n')
text = (run / 'engine.log').read_text()
errors = re.findall(r'^.*(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FATAL).*$', text, re.M)
status = {'process_exit': result.returncode, 'inputs_unchanged': before == after,
          'engine_errors': errors, 'pass_marker': 'SHADOW_LOCAL_PASS' in text,
          'scope': 'Real ridge slope-depth path and reversible controls; visual acceptance pending analysis'}
(run / 'validation.json').write_text(json.dumps(status, indent=2) + '\n')
print(run); print(json.dumps(status)); print(text[-15000:])
sys.exit(0 if result.returncode == 0 and before == after and not errors and status['pass_marker'] else 1)
