#!/usr/bin/env python3
"""Restore the accepted v21 base and ordered v22/v23/v24/v26/v27/v28 and public UI-safety source deltas offline."""
from pathlib import Path, PurePosixPath
import base64, hashlib, json, os, shutil, subprocess, sys, tarfile, tempfile
ROOT = Path(__file__).resolve().parents[1]
def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''): h.update(b)
    return h.hexdigest()
def path(name):
    p = PurePosixPath(name)
    if not name or '\\' in name or ':' in name or p.is_absolute() or any(x in ('', '.', '..') for x in name.split('/')):
        raise ValueError('Unsafe path: ' + repr(name))
    target = ROOT.joinpath(*p.parts)
    for item in [target, *target.parents]:
        if item == ROOT: break
        if item.is_symlink(): raise ValueError('Symlink is not allowed: ' + name)
    if not target.resolve().is_relative_to(ROOT): raise ValueError('Path escaped project')
    return target
def good(p, row):
    return p.is_file() and p.stat().st_size == row['size'] and sha(p) == row['sha256']
def drop_cache(p):
    if hasattr(os, 'posix_fadvise'):
        try:
            fd = os.open(p, os.O_RDONLY)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            os.close(fd)
        except OSError: pass
def decode(row, output):
    source = path(row['encoded_path'])
    if not good(source, row['encoded']): raise ValueError('Encoded file missing/corrupt: ' + row['encoded_path'])
    with source.open('rb') as f, output.open('wb') as out:
        for b in iter(lambda: f.read(1024 * 1024), b''): out.write(base64.b64decode(b, validate=True))
    if not good(output, row): raise ValueError('Decoded file checksum mismatch: ' + row['encoded_path'])
    drop_cache(source)
def replace_known(target, staged):
    target.parent.mkdir(parents=True, exist_ok=True)
    path(str(target.relative_to(ROOT)))
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.wap-update-', delete=False) as out:
            temporary = Path(out.name)
            with staged.open('rb') as source: shutil.copyfileobj(source, out)
        os.replace(temporary, target)
    finally:
        if temporary is not None and (temporary.exists() or temporary.is_symlink()):
            temporary.unlink()
    drop_cache(target)
def apply_delta(patch, ranks, patch_index):
    """Apply one verified layer. Used by the full restorer and isolated delta tests."""
    if patch.get('schema') != 'words-and-perils-source-delta/v1': raise ValueError('Unknown delta schema')
    rows = {row['path']: row for row in patch['files']}
    if len(rows) != len(patch['files']): raise ValueError('Duplicate delta path')
    def preflight():
        for name, row in rows.items():
            target = path(name)
            if target.exists():
                if not target.is_file(): raise ValueError('Target is not a regular file: ' + name)
                current = sha(target)
                rank = ranks.get(name, {}).get(current, -1)
                if rank < patch_index and current != row.get('before_sha256'):
                    raise ValueError('Existing file has unrecognized changes; preserved: ' + name)
            elif row.get('before_sha256') is not None:
                raise ValueError('Required preimage is absent: ' + name)
    preflight()
    with tempfile.TemporaryDirectory(prefix='words-and-perils-delta-') as td:
        archive = Path(td) / 'delta.tar.xz'; decode(patch['archive'], archive); staged_rows = {}; seen = set()
        with tarfile.open(archive, 'r:xz') as tar:
            for member in tar:
                if not member.isfile() or member.name not in rows or member.name in seen:
                    raise ValueError('Unexpected delta archive member')
                row = rows[member.name]; path(member.name)
                if member.size != row['size']: raise ValueError('Delta member size mismatch')
                staged = Path(td) / ('member-' + str(len(seen)))
                with tar.extractfile(member) as source, staged.open('wb') as out: shutil.copyfileobj(source, out)
                if not good(staged, row): raise ValueError('Delta checksum mismatch')
                staged_rows[member.name] = staged; seen.add(member.name)
        if seen != set(rows): raise ValueError('Incomplete delta archive')
        # All paths, bytes and preimages are validated before the first replacement.
        preflight()
        # Journal only files this layer actually replaces. Ordinary failures
        # roll those writes back; detected concurrent user edits are preserved.
        journal = []
        try:
            for name, staged in staged_rows.items():
                row = rows[name]; target = path(name)
                current = sha(target) if target.is_file() else None
                if ranks.get(name, {}).get(current, -1) >= patch_index: continue
                if current != row.get('before_sha256'):
                    raise ValueError('File changed during restoration; preserved: ' + name)
                backup = None; mode = None
                if target.exists():
                    backup = Path(td) / ('preimage-' + str(len(journal)))
                    mode = target.stat().st_mode & 0o7777
                    shutil.copyfile(target, backup)
                    if sha(backup) != current:
                        raise ValueError('Preimage changed during backup; preserved: ' + name)
                journal.append((name, backup, mode, current, row['sha256']))
                replace_known(target, staged)
        except (OSError, ValueError) as error:
            blocked = []
            for name, backup, mode, before_sha, after_sha in reversed(journal):
                try:
                    target = path(name)
                    if target.exists() and not target.is_file():
                        blocked.append(name); continue
                    current = sha(target) if target.is_file() else None
                    if current == before_sha: continue
                    if current != after_sha:
                        blocked.append(name); continue
                    if backup is None:
                        target.unlink()
                    else:
                        replace_known(target, backup)
                        os.chmod(target, mode)
                except (OSError, ValueError):
                    blocked.append(name)
            if blocked:
                raise ValueError('Restoration stopped; changed or inaccessible files preserved; rollback incomplete: ' + ', '.join(blocked)) from error
            raise

def main():
    m = json.loads(path('updates/v28-ui-safety/distribution_manifest.json').read_text())
    if m.get('schema') != 'words-and-perils-offline-distribution/v1': raise ValueError('Unknown distribution schema')
    expected = {row['path']: row for row in m['source_files']}
    if len(expected) != len(m['source_files']): raise ValueError('Duplicate base path')
    patches = []
    previous_manifest_sha = None
    for update in m.get('update_manifests', []):
        manifest_path = path(update['path'])
        if not good(manifest_path, update): raise ValueError('Update manifest is missing or corrupt')
        patch = json.loads(manifest_path.read_text())
        if patch.get('schema') != 'words-and-perils-source-delta/v1': raise ValueError('Unknown delta schema')
        if patch['base_source_bundle_sha256'] != m['source_bundle']['sha256']: raise ValueError('Delta/base mismatch')
        if previous_manifest_sha is not None and patch.get('previous_manifest_sha256') != previous_manifest_sha:
            raise ValueError('Delta chain mismatch')
        previous_manifest_sha = sha(manifest_path)
        patches.append(patch)
    if [p['version'] for p in patches] != ['v22-equipment', 'v23-packed-topology', 'v24-fieldbook-ui', 'v26-vegetation-lifecycle', 'v27-status-river', 'v28-natural-coast', 'v28-public-entry-save-safety']:
        raise ValueError('Unexpected source version chain')
    known = {name: {row['sha256']} for name, row in expected.items()}
    ranks = {name: {row['sha256']: 0} for name, row in expected.items()}
    final = dict(expected)
    for patch_index, patch in enumerate(patches, 1):
        rows = {row['path']: row for row in patch['files']}
        if len(rows) != len(patch['files']): raise ValueError('Duplicate delta path')
        for name, row in rows.items():
            path(name)
            before = row.get('before_sha256')
            if before is not None and final.get(name, {}).get('sha256') != before:
                raise ValueError('Delta preimage chain mismatch: ' + name)
            if before is None and name in final:
                raise ValueError('Delta unexpectedly recreates a file: ' + name)
            known.setdefault(name, set()).add(row['sha256'])
            ranks.setdefault(name, {})[row['sha256']] = patch_index
            final[name] = row
    for name, hashes in known.items():
        target = path(name)
        if target.exists() and (not target.is_file() or sha(target) not in hashes):
            raise ValueError('Existing file has unrecognized changes; preserved: ' + name)
    with tempfile.TemporaryDirectory(prefix='words-and-perils-base-') as td:
        archive = Path(td) / 'source.tar.xz'; decode(m['source_bundle'], archive); seen = set()
        with tarfile.open(archive, 'r:xz') as tar:
            for member in tar:
                if not member.isfile() or member.name not in expected or member.name in seen:
                    raise ValueError('Unexpected base archive member')
                row = expected[member.name]; target = path(member.name)
                if member.size != row['size']: raise ValueError('Base member size mismatch')
                staged = Path(td) / 'member.tmp'
                with tar.extractfile(member) as source, staged.open('wb') as out: shutil.copyfileobj(source, out)
                if not good(staged, row): raise ValueError('Base member checksum mismatch')
                if not target.exists(): replace_known(target, staged)
                seen.add(member.name)
        if seen != set(expected): raise ValueError('Incomplete base archive')
        for row in m['resource_parts']:
            target = path(row['path'])
            if target.exists():
                if not good(target, row): raise ValueError('Existing resource part differs: ' + row['path'])
                continue
            staged = Path(td) / 'resource.part'; decode(row, staged); replace_known(target, staged)
    for patch_index, patch in enumerate(patches, 1):
        apply_delta(patch, ranks, patch_index)
    for name, row in final.items():
        if not good(path(name), row): raise ValueError('Final source mismatch: ' + name)
    pins = {}
    for patch in patches: pins.update(patch['production_pins'])
    for name, expected_sha in pins.items():
        if sha(path(name)) != expected_sha: raise ValueError('Production pin mismatch: ' + name)
    subprocess.run([sys.executable, str(path('tools/restore_large_assets.py'))], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(path('tools/verify_publication.py'))], cwd=ROOT, check=True)
    print('Complete v28 public UI-safety source and resources restored and verified. Open project.godot in Godot 4.6.3.')
if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error: raise SystemExit(str(error))
