#!/usr/bin/env python3
"""Restore the complete source and assets, offline, using Python 3.10+ only."""
from pathlib import Path, PurePosixPath
import base64, hashlib, json, os, shutil, subprocess, sys, tarfile, tempfile
ROOT = Path(__file__).resolve().parents[1]
def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()
def path(name):
    p = PurePosixPath(name)
    if not name or '\\' in name or ':' in name or p.is_absolute() or any(x in ('', '.', '..') for x in name.split('/')):
        raise ValueError('Unsafe path: ' + repr(name))
    target = ROOT.joinpath(*p.parts)
    for part in [target, *target.parents]:
        if part == ROOT: break
        if part.is_symlink(): raise ValueError('Symlink is not allowed: ' + name)
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
        for b in iter(lambda: f.read(1024*1024), b''): out.write(base64.b64decode(b, validate=True))
    if not good(output, row): raise ValueError('Decoded file checksum mismatch: ' + row['encoded_path'])
    drop_cache(source)
def main():
    m = json.loads(path('distribution_manifest.json').read_text())
    if m.get('schema') != 'words-and-perils-offline-distribution/v1': raise ValueError('Unknown distribution schema')
    expected = {row['path']: row for row in m['source_files']}
    if len(expected) != len(m['source_files']): raise ValueError('Duplicate source path')
    for name, row in expected.items():
        target = path(name)
        if target.exists() and not good(target, row): raise ValueError('Existing file differs; preserve it elsewhere first: ' + name)
    with tempfile.TemporaryDirectory(prefix='words-and-perils-') as td:
        archive = Path(td) / 'source.tar.xz'
        decode(m['source_bundle'], archive)
        seen = set()
        with tarfile.open(archive, 'r:xz') as tar:
            for member in tar:
                if not member.isfile() or member.name not in expected or member.name in seen: raise ValueError('Unexpected archive member')
                row = expected[member.name]; target = path(member.name)
                if member.size != row['size']: raise ValueError('Unexpected member size')
                staged = Path(td) / 'member.tmp'
                with tar.extractfile(member) as source, staged.open('wb') as out: shutil.copyfileobj(source, out)
                if not good(staged, row): raise ValueError('Source checksum mismatch: ' + member.name)
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True); path(member.name)
                    with target.open('xb') as out, staged.open('rb') as source: shutil.copyfileobj(source, out)
                    drop_cache(target)
                seen.add(member.name)
        if seen != set(expected): raise ValueError('Incomplete source archive')
        for row in m['resource_parts']:
            target = path(row['path'])
            if target.exists():
                if not good(target, row): raise ValueError('Existing resource part differs: ' + row['path'])
                continue
            staged = Path(td) / 'resource.part'; decode(row, staged)
            target.parent.mkdir(parents=True, exist_ok=True); path(row['path'])
            with target.open('xb') as out, staged.open('rb') as source: shutil.copyfileobj(source, out)
            drop_cache(target)
    subprocess.run([sys.executable, str(path('tools/restore_large_assets.py'))], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(path('tools/verify_publication.py'))], cwd=ROOT, check=True)
    print('Complete source and resources restored and verified. Open project.godot in Godot 4.6.3.')
if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error: raise SystemExit(str(error))
