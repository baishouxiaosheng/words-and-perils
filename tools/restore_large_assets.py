#!/usr/bin/env python3
"""Safely restore all bundled binary resources using only Python's standard library.
No download, credentials, network connection, or Godot process is needed.
Existing differing files are never overwritten.
"""
from pathlib import Path, PurePosixPath
import hashlib
import json
import os
import shutil
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def digest_file(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def safe_path(name):
    posix = PurePosixPath(name)
    if (not isinstance(name, str) or not name or '\\' in name
            or posix.is_absolute() or any(p in ('', '.', '..') for p in name.split('/'))
            or ':' in name):
        raise ValueError('Unsafe resource path: ' + repr(name))
    path = ROOT.joinpath(*posix.parts)
    for parent in [path, *path.parents]:
        if parent == ROOT:
            break
        if parent.is_symlink():
            raise ValueError('Symlink is not allowed in resource path: ' + name)
    if not path.resolve().is_relative_to(ROOT):
        raise ValueError('Resource path escapes project: ' + name)
    return path

def matches(path, row):
    return path.is_file() and path.stat().st_size == row['size'] and digest_file(path) == row['sha256']

def main():
    manifest = json.loads((ROOT / 'resource_packs/manifest.json').read_text())
    if manifest.get('schema') != 'words-and-perils-resource-packs/v1':
        raise ValueError('Unknown resource manifest schema')
    expected = {}
    for row in manifest['files']:
        name = row['path']; path = safe_path(name)
        if name in expected or not isinstance(row['size'], int) or row['size'] < 0:
            raise ValueError('Invalid or duplicate resource entry')
        expected[name] = row
        if path.exists() and not matches(path, row):
            raise ValueError('Existing resource differs; move it aside first: ' + name)
    if all(matches(safe_path(n), row) for n, row in expected.items()):
        print(f'All {len(expected)} binary resources already restored; SHA-256 verified')
        return
    with tempfile.TemporaryDirectory(prefix='words-and-perils-restore-') as temp:
        archive = Path(temp) / 'resources.tar.xz'
        with archive.open('wb') as output:
            for part in manifest['parts']:
                path = safe_path(part['path'])
                if not matches(path, part):
                    raise ValueError('Resource part missing or corrupt: ' + part['path'])
                with path.open('rb') as stream:
                    shutil.copyfileobj(stream, output)
        if archive.stat().st_size != manifest['archive_size'] or digest_file(archive) != manifest['archive_sha256']:
            raise ValueError('Assembled archive checksum mismatch')
        seen = set()
        with tarfile.open(archive, mode='r:xz') as tar:
            for member in tar:
                name = member.name
                target = safe_path(name)
                if not member.isfile() or name not in expected or name in seen:
                    raise ValueError('Unexpected archive member: ' + name)
                row = expected[name]
                if member.size != row['size']:
                    raise ValueError('Archive resource size mismatch: ' + name)
                seen.add(name)
                stream = tar.extractfile(member)
                staged = Path(temp) / 'resource.tmp'
                with staged.open('wb') as output:
                    shutil.copyfileobj(stream, output)
                if not matches(staged, row):
                    raise ValueError('Resource checksum mismatch: ' + name)
                if not target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    # Recheck parent symlinks immediately before writing.
                    safe_path(name)
                    with target.open('xb') as output, staged.open('rb') as source:
                        shutil.copyfileobj(source, output)
        if seen != set(expected):
            raise ValueError('Archive did not contain every declared resource')
    for name, row in expected.items():
        if not matches(safe_path(name), row):
            raise ValueError('Final resource verification failed: ' + name)
    print(f'Restored {len(expected)} binary resources; every SHA-256 verified')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        raise SystemExit(str(error))
