#!/usr/bin/env python3
"""Offline public v29 enhanced-playtest restoration, Python 3.10+ only.

The seven historical tar layers and their manifests remain immutable. The final
source layer is the exact nine-file ZIP; the old helper supplies validators only.
--check verifies the complete final source map and literal script closure, not
binary resources. --sources-only restores source without touching resources.
Known historical/final states are recoverable; other candidate edits are refused.
Each staged layer rolls back ordinary write/verification errors to recognized
preimages. This is not whole-restoration, power-loss or concurrent-writer
atomicity. Close the editor/game and do not run competing restorers.
"""
from pathlib import Path, PurePosixPath
import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import types

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'v29-playtest-enhanced'
FROZEN_COMMIT = 'f630fc4ff92143f7add7d36907c317d709600e61'
TITLE = 'public v29 试玩增强版（API设置/镜头/选择反馈/离线移动）'
ENHANCED_FILES = [{'path': 'main.gd',
  'size': 184920,
  'sha256': '6e2f62e76db2f4a64a9bbdf4d348a32588d1cb991e6d869bff4c730e12e61e5c',
  'before_sha256': '2b05911a1bcde48b10a54e8d1475ef62c66aea84ff8c7f5b7cdc3052eaf9fc93'},
 {'path': 'view/dual_api_settings/client.gd',
  'size': 13777,
  'sha256': '79751f2bdebac0305a773fc81793d936fb7538e59d466fb742249831a4ca2d83',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/controller.gd',
  'size': 1022,
  'sha256': '214ccf927d266317a7fe037c18f5d1d6f6592fe4c49e7059485969735f05063a',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/panel.gd',
  'size': 24541,
  'sha256': '932dc0c71d5d95c966e961ea406d4ed8b971a5d88d7e125a42223f2f20d34c69',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/provider_presets.gd',
  'size': 3659,
  'sha256': '26520871eaecc153258e036926474ade94828fb260df578bc2f3c10f1bf70dc5',
  'before_sha256': None},
 {'path': 'view/tabletop_interaction/offline_move_demo.gd',
  'size': 7620,
  'sha256': '7ec81eca42e9e1d51d63a6c0e3d379a786caa9b18e6e40aa9159abab34629b4b',
  'before_sha256': None},
 {'path': 'view/tabletop_interaction/selection_motion.gd',
  'size': 13375,
  'sha256': '60835b0672a4426faf747c57e6a21617ebbf87e08c68b8cb3244175f813448e7',
  'before_sha256': None},
 {'path': 'view/tabletop_interaction/wasd_camera_pan.gd',
  'size': 6941,
  'sha256': 'c26abf87dd3ff1d0b76b318a6887fa5ca9c6342571d128f0ef2662d9a6a29ef0',
  'before_sha256': None},
 {'path': 'view/ui_typography/style.gd',
  'size': 14899,
  'sha256': '0ce716c357b80da23063ae8f8d678a2c4c022f58df63c34b14ad802f9b90e565',
  'before_sha256': None}]
CANDIDATE = 'candidates/api-typography/15b7faa87361'
CANDIDATE_HELPER_SHA = '4fd50e6c75206da80458eb82e8b7746b471373926d117cc4a5a2ae58946e3a45'
CANDIDATE_MANIFEST_SHA = 'b32b4920c8aab18b8f56de1138f0458a6982c636b46c53fdf526fb5c04e22a6d'
PREVIOUS_DISTRIBUTION_SHA = '6154796927071e068a8bed51e3146f9c8da5f407b4d702c127ddf42bbdcb641e'
VERSIONS = ['v22-equipment', 'v23-packed-topology', 'v24-fieldbook-ui',
            'v26-vegetation-lifecycle', 'v27-status-river', 'v28-natural-coast',
            'v28-public-entry-save-safety']
WRAPPER_PATH = 'tools/restore_repository.py'
WRAPPER = b'''#!/usr/bin/env python3
"""Restore the current verified public source version, completely offline."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("restore_v29.py")), run_name="__main__")
'''
REPARSE = getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode('utf-8')


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON key: ' + key)
            result[key] = value
        return result
    def bad_number(value):
        raise ValueError('Non-finite JSON number: ' + value)
    return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=bad_number)


def valid_name(name):
    if not isinstance(name, str) or not name or name.startswith('/'):
        raise ValueError('Unsafe relative path')
    if any(c in name for c in '\\:\x00<>"|?*') or any(ord(c) < 32 for c in name):
        raise ValueError('Unsafe relative path: ' + repr(name))
    reserved = {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'}
    reserved.update('COM' + n for n in '123456789¹²³')
    reserved.update('LPT' + n for n in '123456789¹²³')
    parts = name.split('/')
    for part in parts:
        if not part or part in ('.', '..') or part[-1:] in ('.', ' ') or part.split('.')[0].upper() in reserved:
            raise ValueError('Unsafe path component: ' + repr(name))
    return parts


def valid_names(names):
    files, folded = set(), {}
    for name in names:
        parts = valid_name(name)
        if name in files:
            raise ValueError('Duplicate path: ' + name)
        files.add(name)
        for end in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:end])
            key = prefix.casefold()
            if key in folded and folded[key] != prefix:
                raise ValueError('Case-fold path collision: ' + name)
            folded[key] = prefix
    for name in files:
        if any('/'.join(name.split('/')[:i]) in files for i in range(1, len(name.split('/')))):
            raise ValueError('File/directory collision: ' + name)


def linked(st):
    return stat.S_ISLNK(st.st_mode) or bool(getattr(st, 'st_file_attributes', 0) & REPARSE)


def path(name):
    parts = valid_name(name)
    for ancestor in [*reversed(ROOT.parents), ROOT]:
        st = ancestor.lstat()
        if linked(st) or not stat.S_ISDIR(st.st_mode):
            raise ValueError('Linked or non-directory project ancestor')
    node = ROOT
    for index, part in enumerate(parts):
        if not node.exists():
            return ROOT.joinpath(*parts)
        with os.scandir(node) as children:
            aliases = [entry.name for entry in children if entry.name.casefold() == part.casefold()]
        if aliases and aliases != [part]:
            raise ValueError('Case-fold target collision: ' + name)
        node = node / part
        try:
            st = node.lstat()
        except FileNotFoundError:
            continue
        if linked(st):
            raise ValueError('Symlink/junction/reparse path refused: ' + name)
        regular = stat.S_ISREG(st.st_mode) if index == len(parts) - 1 else stat.S_ISDIR(st.st_mode)
        if not regular:
            raise ValueError('Non-regular target or ancestor: ' + name)
    return node


def good(p, row):
    return p.is_file() and p.stat().st_size == row['size'] and sha(p) == row['sha256']


def checked_json(name, row=None):
    target = path(name)
    if target.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('Control JSON too large: ' + name)
    raw = target.read_bytes()
    if row is not None and (len(raw) != row['size'] or digest(raw) != row['sha256']):
        raise ValueError('Control file missing/corrupt: ' + name)
    result = strict_json(raw)
    if not isinstance(result, dict):
        raise ValueError('Control JSON must be an object: ' + name)
    return result, raw


def file_rows(rows):
    if not isinstance(rows, list):
        raise ValueError('File rows must be a list')
    valid_names([row['path'] for row in rows])
    for row in rows:
        if type(row['size']) is not int or row['size'] < 0 or not re.fullmatch('[0-9a-f]{64}', row['sha256']):
            raise ValueError('Invalid file size/hash: ' + row['path'])
    return {row['path']: row for row in rows}


def filemap(final):
    return [{'path': name, 'size': row['size'], 'sha256': row['sha256']}
            for name, row in sorted(final.items())]


def build_model(base_rows, patches, final_rows):
    base = file_rows(base_rows)
    final = dict(base)
    ranks = {name: {row['sha256']: 0} for name, row in base.items()}
    for index, rows in enumerate([p['files'] for p in patches] + [final_rows], 1):
        for name, row in file_rows(rows).items():
            before = row.get('before_sha256')
            if before != final.get(name, {}).get('sha256'):
                raise ValueError('Source preimage chain mismatch: ' + name)
            final[name] = row
            ranks.setdefault(name, {})[row['sha256']] = index
    valid_names(final)
    return {'base': base, 'final': final, 'ranks': ranks, 'patches': patches,
            'final_rows': file_rows(final_rows)}


def verified_module(name, relative, expected):
    target = path(relative)
    raw = target.read_bytes()
    if len(raw) != expected['size'] or digest(raw) != expected['sha256']:
        raise ValueError('Python helper missing/corrupt: ' + relative)
    module = types.ModuleType(name)
    module.__file__ = str(target)
    # Execute the verified bytes, without importing a cached or different image.
    exec(compile(raw, str(target), 'exec'), module.__dict__)
    return module


def load_source_zip(validator, archive, rows):
    """Use unchanged path/member validators, never the old five-file CONTRACT."""
    if archive.get('format') != 'zip+base64' or archive.get('encoded_path') != 'updates/v29/source_delta.zip.b64':
        raise ValueError('Unexpected enhanced source archive')
    encoded_row = archive['encoded']
    if (type(encoded_row['size']) is not int or not 0 < encoded_row['size'] <= 2 * 1024 * 1024
            or type(archive['size']) is not int or not 0 < archive['size'] <= 1024 * 1024):
        raise ValueError('Enhanced source archive exceeds its bounded size')
    expected = {'payload/' + row['path']: {'bytes': row['size'], 'sha256': row['sha256']} for row in rows}
    if archive['members'] != expected:
        raise ValueError('Enhanced ZIP member map differs from final source rows')
    try:
        encoded = validator.safe_read(path(archive['encoded_path']), encoded_row['size'])
        if len(encoded) != encoded_row['size'] or digest(encoded) != encoded_row['sha256']:
            raise ValueError('Enhanced encoded ZIP checksum/size mismatch')
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) != archive['size'] or digest(raw) != archive['sha256']:
            raise ValueError('Enhanced ZIP checksum/size mismatch')
        return validator.read_archive(raw, expected)
    except validator.Refusal as error:
        raise ValueError('Enhanced source ZIP validation failed: ' + str(error)) from error


def load_release():
    m, raw = checked_json('updates/v29/distribution_manifest.json')
    if path('distribution_manifest.json').read_bytes() != raw:
        raise ValueError('Root and immutable v29 distributions differ')
    if m.get('schema') != 'words-and-perils-offline-distribution/v1' or m.get('active_version') != VERSION:
        raise ValueError('Unexpected v29 distribution schema/version')
    ref = m['adoption_manifest']
    if ref['path'] != 'updates/v29/manifest.json':
        raise ValueError('Unexpected adoption manifest path')
    adoption, _ = checked_json(ref['path'], ref)
    if (adoption.get('schema') != 'words-and-perils-public-zip-adoption/v1'
            or adoption.get('version') != VERSION
            or adoption.get('title') != TITLE
            or adoption.get('base_public_commit') != FROZEN_COMMIT
            or adoption.get('distribution_identity') != 'public-source-derived'
            or adoption.get('excluded_versions') != ['v25']):
        raise ValueError('Unexpected v29 adoption identity')
    previous_ref = adoption['previous_distribution']
    if previous_ref != {'path': 'updates/v28-ui-safety/distribution_manifest.json',
                        'size': 206858, 'sha256': PREVIOUS_DISTRIBUTION_SHA}:
        raise ValueError('Previous public distribution differs')
    previous, _ = checked_json(previous_ref['path'], previous_ref)
    inherited = dict(m)
    inherited.pop('adoption_manifest')
    inherited['active_version'] = previous['active_version']
    if inherited != previous:
        raise ValueError('Inherited distribution fields changed')
    patches, previous_sha = [], None
    for update in m['update_manifests']:
        patch, _ = checked_json(update['path'], update)
        if patch.get('schema') != 'words-and-perils-source-delta/v1':
            raise ValueError('Unknown historical delta schema')
        if patch['base_source_bundle_sha256'] != m['source_bundle']['sha256']:
            raise ValueError('Delta/base mismatch')
        if previous_sha is not None and patch.get('previous_manifest_sha256') != previous_sha:
            raise ValueError('Historical delta chain mismatch')
        previous_sha = update['sha256']
        patches.append(patch)
    if [p['version'] for p in patches] != VERSIONS or adoption['previous_manifest_sha256'] != previous_sha:
        raise ValueError('Unexpected historical source chain')
    package = adoption['zip_validator']
    helper_ref = {'path': CANDIDATE + '/apply_candidate.py', 'size': 25498, 'sha256': CANDIDATE_HELPER_SHA}
    manifest_ref = {'path': CANDIDATE + '/manifest.json', 'size': 4747, 'sha256': CANDIDATE_MANIFEST_SHA}
    if package['helper'] != helper_ref or package['manifest'] != manifest_ref:
        raise ValueError('ZIP validator helper/manifest identity changed')
    candidate_manifest, _ = checked_json(manifest_ref['path'], manifest_ref)
    candidate = verified_module('_verified_v29_zip_validator', helper_ref['path'], helper_ref)
    # Original CONTRACT remains untouched. load_package/run/apply are not called.
    rows = adoption['files']
    if rows != ENHANCED_FILES:
        raise ValueError('Enhanced source rows differ from the frozen nine-file release')
    file_rows(rows)
    members = load_source_zip(candidate, adoption['archive'], rows)
    wrapper = adoption['release_wrapper']
    if (wrapper['path'] != WRAPPER_PATH or wrapper['size'] != len(WRAPPER)
            or wrapper['sha256'] != digest(WRAPPER)):
        raise ValueError('Final wrapper differs')
    model = build_model(m['source_files'], patches, rows + [wrapper])
    if adoption['final_source_map_sha256'] != digest(canonical(filemap(model['final']))):
        raise ValueError('Final source map differs')
    if adoption['final_source_files'] != len(model['final']):
        raise ValueError('Final source count differs')
    helper = adoption['release_helper']
    if helper['path'] != 'tools/restore_v29.py' or not good(path(helper['path']), helper):
        raise ValueError('Versioned release helper differs')
    protected = {name: {'size': row['bytes'], 'sha256': row['sha256']}
                 for name, row in candidate_manifest['protected_files'].items()
                 if name not in ('distribution_manifest.json', WRAPPER_PATH)}
    if adoption['protected_public_files'] != protected:
        raise ValueError('Protected public pins differ')
    for name, row in protected.items():
        if name in model['final']:
            expected = model['final'][name]
            if any(row[key] != expected[key] for key in ('size', 'sha256')):
                raise ValueError('Protected source was superseded: ' + name)
        elif not good(path(name), row):
            raise ValueError('Protected public control differs: ' + name)
    pins = {}
    for patch in patches:
        pins.update(patch.get('canonical_pins', {}))
        pins.update(patch['production_pins'])
    pins.update({row['path']: row['sha256'] for row in rows})
    if any(model['final'].get(name, {}).get('sha256') != value for name, value in pins.items()):
        raise ValueError('Final production pin differs')
    model.update({'distribution': m, 'adoption': adoption, 'members': members,
                  'protected': protected, 'production_pins': pins})
    return model


def preflight(model, require_final=False):
    for name, row in model['final'].items():
        target = path(name)
        if not target.exists():
            if require_final:
                raise ValueError('Final source missing: ' + name)
            continue
        current = sha(target)
        if current not in model['ranks'][name]:
            raise ValueError('Existing file has unrecognized changes; preserved: ' + name)
        if require_final and (current != row['sha256'] or target.stat().st_size != row['size']):
            raise ValueError('Final source mismatch: ' + name)


def drop_cache(p):
    if hasattr(os, 'posix_fadvise'):
        fd = None
        try:
            fd = os.open(p, os.O_RDONLY)
            os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
        except OSError:
            pass
        finally:
            if fd is not None:
                os.close(fd)


def decode(row, output):
    source = path(row['encoded_path'])
    if not good(source, row['encoded']):
        raise ValueError('Encoded file missing/corrupt: ' + row['encoded_path'])
    with source.open('rb') as stream, output.open('wb') as out:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            out.write(base64.b64decode(block, validate=True))
    if not good(output, row):
        raise ValueError('Decoded file checksum mismatch: ' + row['encoded_path'])
    drop_cache(source)


def replace_known(target, staged):
    target.parent.mkdir(parents=True, exist_ok=True)
    # Only serialize trusted internal Path objects; archive names stay strict.
    path(target.relative_to(ROOT).as_posix())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.wap-update-', delete=False) as out:
            temporary = Path(out.name)
            with staged.open('rb') as source:
                shutil.copyfileobj(source, out)
        os.replace(temporary, target)
    finally:
        if temporary is not None and (temporary.exists() or temporary.is_symlink()):
            temporary.unlink()
    drop_cache(target)


def stage_tar(rows, archive_row, directory):
    rows = file_rows(list(rows.values()))
    archive = directory / 'source.tar.xz'
    decode(archive_row, archive)
    staged, seen = {}, set()
    with tarfile.open(archive, 'r:xz') as tar:
        for member in tar:
            valid_name(member.name)
            if not member.isfile() or member.name not in rows or member.name in seen:
                raise ValueError('Unexpected source archive member')
            row = rows[member.name]
            path(member.name)
            if member.size != row['size']:
                raise ValueError('Source archive member size mismatch')
            target = directory / ('member-' + str(len(seen)))
            with tar.extractfile(member) as source, target.open('wb') as out:
                shutil.copyfileobj(source, out)
            if not good(target, row):
                raise ValueError('Source archive member checksum mismatch')
            staged[member.name] = target
            seen.add(member.name)
    if seen != set(rows):
        raise ValueError('Incomplete source archive')
    return staged


def apply_staged(rows, staged, ranks, index, directory):
    """Verified stage + per-layer journal, derived from the v28 safety restorer."""
    if set(rows) != set(staged):
        raise ValueError('Staged layer is incomplete')
    def validate():
        for name, row in rows.items():
            target = path(name)
            if not good(staged[name], row):
                raise ValueError('Staged source checksum mismatch: ' + name)
            current = sha(target) if target.exists() else None
            rank = ranks.get(name, {}).get(current, -1)
            if current is not None and rank >= index:
                continue
            if current != row.get('before_sha256'):
                raise ValueError('Unrecognized or missing preimage; preserved: ' + name)
    validate()
    journal = []
    try:
        for name, row in rows.items():
            target = path(name)
            current = sha(target) if target.exists() else None
            if current is not None and ranks.get(name, {}).get(current, -1) >= index:
                continue
            if current != row.get('before_sha256'):
                raise ValueError('File changed during restoration; preserved: ' + name)
            backup, mode = None, None
            if target.exists():
                backup = directory / ('preimage-' + str(len(journal)))
                mode = target.stat().st_mode & 0o7777
                shutil.copyfile(target, backup)
                if sha(backup) != current:
                    raise ValueError('Preimage changed during backup; preserved: ' + name)
            # Revalidate both the path kind and exact before-state after backup.
            target = path(name)
            if (sha(target) if target.exists() else None) != current:
                raise ValueError('Preimage changed before replacement; preserved: ' + name)
            journal.append((name, backup, mode, current, row['sha256']))
            replace_known(target, staged[name])
            if not good(path(name), row):
                raise ValueError('Written source mismatch: ' + name)
        # Keep the journal until every target is still this layer or newer.
        # Unknown intervening edits are preserved while our other writes undo.
        for name in rows:
            target = path(name)
            current = sha(target) if target.exists() else None
            if current is None or ranks.get(name, {}).get(current, -1) < index:
                raise ValueError('Source changed before layer commit; preserved: ' + name)
    except (OSError, ValueError) as error:
        blocked = []
        for name, backup, mode, before_sha, after_sha in reversed(journal):
            try:
                target = path(name)
                current = sha(target) if target.exists() else None
                if current == before_sha:
                    continue
                if current != after_sha:
                    blocked.append(name)
                    continue
                if backup is None:
                    target.unlink()
                else:
                    replace_known(target, backup)
                    os.chmod(target, mode)
            except (OSError, ValueError):
                blocked.append(name)
        if blocked:
            raise ValueError('Changed/inaccessible files preserved; rollback incomplete: ' + ', '.join(blocked)) from error
        raise
    return len(journal)


def needs_layer(rows, ranks, index):
    return any(not path(name).exists() or ranks[name].get(sha(path(name)), -1) < index for name in rows)


def restore_sources(model):
    preflight(model)
    writes = 0
    layers = [(model['base'], model['distribution']['source_bundle'])]
    layers.extend((file_rows(p['files']), p['archive']) for p in model['patches'])
    for index, (rows, archive_row) in enumerate(layers):
        if not needs_layer(rows, model['ranks'], index):
            continue
        with tempfile.TemporaryDirectory(prefix='words-and-perils-source-') as td:
            directory = Path(td)
            staged = stage_tar(rows, archive_row, directory)
            writes += apply_staged(rows, staged, model['ranks'], index, directory)
    rows = model['final_rows']
    index = len(layers)
    if needs_layer(rows, model['ranks'], index):
        with tempfile.TemporaryDirectory(prefix='words-and-perils-v29-') as td:
            directory = Path(td)
            staged = {}
            for name in rows:
                target = directory / ('candidate-' + str(len(staged)))
                target.write_bytes(WRAPPER if name == WRAPPER_PATH else model['members']['payload/' + name])
                staged[name] = target
            writes += apply_staged(rows, staged, model['ranks'], index, directory)
    preflight(model, require_final=True)
    return writes


def literal_closure(expected, require_resources=False):
    queue, scripts = ['main.gd'], {}
    pattern = r'''(?:preload|load)\(\s*["'](res://[^"']+)["']\s*\)|extends\s+["'](res://[^"']+)["']'''
    while queue:
        name = queue.pop()
        if name in scripts:
            continue
        source = path(name).read_bytes()
        scripts[name] = digest(source)
        for pair in re.findall(pattern, source.decode('utf-8')):
            reference = next(value for value in pair if value)
            relative = reference[6:]
            target = path(relative)
            if require_resources and not target.is_file():
                raise ValueError('Missing active literal resource: ' + reference)
            if target.suffix == '.gd':
                queue.append(relative)
    if len(scripts) != expected['scripts'] or digest(canonical(scripts)) != expected['scripts_sha256']:
        raise ValueError('Literal script closure differs')
    return len(scripts)


def check_sources(model, require_resources=False):
    preflight(model, require_final=True)
    for name, row in model['protected'].items():
        if not good(path(name), row):
            raise ValueError('Protected public file differs: ' + name)
    count = literal_closure(model['adoption']['literal_script_closure'], require_resources)
    return {'source_files': len(model['final']), 'literal_scripts': count,
            'final_source_map_sha256': digest(canonical(filemap(model['final'])))}


def restore_resources(model):
    m = model['distribution']
    # Historical binary payloads are untouched. This runs only for full restore.
    for row in m['resource_parts']:
        target = path(row['path'])
        if target.exists() and not good(target, row):
            raise ValueError('Existing resource part differs: ' + row['path'])
    with tempfile.TemporaryDirectory(prefix='words-and-perils-resources-') as td:
        for row in m['resource_parts']:
            target = path(row['path'])
            if target.exists():
                continue
            staged = Path(td) / 'resource.part'
            decode(row, staged)
            replace_known(target, staged)
    subprocess.run([sys.executable, '-B', str(path('tools/restore_large_assets.py'))], cwd=ROOT, check=True)
    verifier = verified_module('_verified_legacy_binary_verifier', 'tools/verify_publication.py',
                               model['final']['tools/verify_publication.py'])
    # Never invoke verify(): its Main and literal-closure expectations are v28.
    return verifier.verify_binary_resources()


def main(argv=None):
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, help='Project containing this exact public release; default: parent of tools')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Read-only final source/map/closure verification; excludes binary resources')
    mode.add_argument('--sources-only', action='store_true', help='Restore and verify sources only; do not read binary resource payloads')
    args = parser.parse_args(argv)
    if args.project is not None:
        ROOT = Path(os.path.abspath(args.project))
    model = load_release()
    writes = 0 if args.check else restore_sources(model)
    report = check_sources(model)
    if not args.check and not args.sources_only:
        report['binary_resources'] = restore_resources(model)
        check_sources(model, require_resources=True)
    report.update({'version': VERSION, 'source_writes': writes,
                   'binary_verification': 'not_requested' if args.check or args.sources_only else 'passed',
                   'scope': 'public distribution; native v28 unchanged; literal closure excludes dynamic loads'})
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
