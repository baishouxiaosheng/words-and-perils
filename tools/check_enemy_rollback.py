#!/usr/bin/env python3
"""Validate or restore only the exact allowlisted v20 preimages.

Default is read-only. Close Godot before --apply. No saves, new source modules,
assets or user files are deleted. Unrecognized edits cause refusal.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--apply', action='store_true', help='Restore verified v20 integration files; close Godot first')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
audit = root / 'artifacts/generated_v3_enemy'
manifest = json.loads((audit / 'CHANGE_ALLOWLIST.json').read_text())
allowed = set(manifest['existing_file_allowlist'] + manifest.get('documentation_file_allowlist', []))
rows = manifest['existing_changes']
if {row['path'] for row in rows} != allowed:
    raise SystemExit('Refused: allowlist and preimage inventory differ')
verified = []
for row in rows:
    rel = Path(row['path'])
    if rel.is_absolute() or '..' in rel.parts:
        raise SystemExit('Refused: invalid relative path')
    current, before = root / rel, audit / 'preimages' / rel
    old_bytes = before.read_bytes()
    if hashlib.sha256(old_bytes).hexdigest() != row['before_sha256']:
        raise SystemExit(f'Refused: preimage hash mismatch: {rel}')
    current_hash = hashlib.sha256(current.read_bytes()).hexdigest()
    if current_hash not in (row['after_sha256'], row['before_sha256']):
        raise SystemExit(f'Refused: unrecognized edits: {rel}')
    verified.append((current, old_bytes, current_hash == row['before_sha256']))
if args.apply:
    for path, data, restored in verified:
        if not restored:
            temp = path.with_name(path.name + '.v20-restore.tmp')
            temp.write_bytes(data)
            os.replace(temp, path)
    print('Restored the verified v20 integration files. Saves and extra modules were untouched.')
else:
    print(f'Rollback preimages verified for {len(verified)} exact files; no files changed.')
