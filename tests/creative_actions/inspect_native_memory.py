#!/usr/bin/env python3
"""Read-only native-host diagnostics. Run in the existing desktop terminal.

Reports executable identities and owned Godot test selectors only; never process
credentials/environment or arbitrary arguments, and never kills any process.
"""
import json
import os
import shutil
from pathlib import Path
root = Path(__file__).resolve().parents[2]
out = root / 'artifacts/creative_actions_20261003/native'
rows = []
for directory in Path('/proc').iterdir():
    if not directory.name.isdigit():
        continue
    try:
        status = directory.joinpath('status').read_text()
        values = dict(line.split(':', 1) for line in status.splitlines() if ':' in line)
        rss = int(values.get('VmRSS', '0 kB').split()[0])
        if rss < 100000:
            continue
        exe = os.readlink(directory / 'exe')
        row = {'pid': int(directory.name), 'ppid': int(values['PPid']), 'comm': values['Name'].strip(), 'rss_kib': rss, 'exe': exe}
        if 'godot' in Path(exe).name.lower() or '/godot' in exe.lower():
            args = directory.joinpath('cmdline').read_bytes().decode(errors='replace').split('\0')
            selectors = {}
            for flag in ['--path', '--script']:
                if flag in args and args.index(flag) + 1 < len(args): selectors[flag] = args[args.index(flag) + 1]
            for flag in ['--headless', '--editor', '--check-only']:
                if flag in args: selectors[flag] = True
            row['godot_test_selectors'] = selectors
        rows.append(row)
    except (OSError, ValueError, KeyError):
        continue
rows.sort(key=lambda value: -value['rss_kib'])
files = []
for file in Path('/tmp/fogbank-creative-qa/data').rglob('r24_coast_adventure_save.json*'):
    if file.is_file():
        row = {'name': file.name, 'bytes': file.stat().st_size, 'mtime_ns': file.stat().st_mtime_ns}
        # Only this explicitly isolated test session's own game save.
        if file.name == 'r24_coast_adventure_save.json':
            copied = out / 'attempt2_saved_game.json'
            shutil.copyfile(file, copied)
            row['copied_test_snapshot'] = str(copied.relative_to(root))
        files.append(row)
report = {'processes_over_100mb': rows, 'isolated_native_test_saves': files}
for name in ['memory.max', 'memory.current', 'memory.peak', 'memory.events']:
    try: report[name] = Path('/sys/fs/cgroup', name).read_text().strip()
    except OSError: pass
(out / 'native_host_inventory.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
