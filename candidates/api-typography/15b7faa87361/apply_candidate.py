#!/usr/bin/env python3
"""Offline, opt-in candidate applier. Python 3.9+; standard library only.

Run --check (default), --apply, or --rollback with --project PATH.
Only the five frozen production paths can change. A restored public baseline
is required. Exact mixed states are refused by check/apply; explicit rollback
can recover an exact mixed state. Unknown edits are always refused.

This is ordinary-exception recovery, not a power-loss transaction. The lock
coordinates this helper only; it cannot prevent external editors. Detected
concurrent unknown edits are preserved and reported. Empty directories may
remain after a successful rollback. No network or Godot is used.
"""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import zipfile

CONTRACT = {'schema': 'words-and-perils-public-candidate/v1',
 'candidate_id': 'api-typography-15b7faa87361',
 'status': 'unadopted_candidate',
 'base_commit': 'f630fc4ff92143f7add7d36907c317d709600e61',
 'base_tree': '72bbdbe88a70eae14c2161c947715227faaaa618',
 'source_manifest_sha256': '300676b3eda9bbb61b72b71ae3d2bfa5e52f70dcd969762daa82c7a9cb701e8f',
 'source_filemap_sha256': '15b7faa873617ef53ced0c0f7488b55b5948cf5f993ed743f63d18456305a4b7',
 'files': [{'path': 'main.gd',
            'bytes': 184435,
            'sha256': '48d166879987b7285c21ce2bf7388a37654f1710131db851dfc0f70b0d6deb42',
            'before_sha256': '2b05911a1bcde48b10a54e8d1475ef62c66aea84ff8c7f5b7cdc3052eaf9fc93'},
           {'path': 'view/dual_api_settings/client.gd',
            'bytes': 9256,
            'sha256': '5d84992c2f3a7e28f02795511b0b0c79bc24f2ae0e0cbf0e5a8b4ec8f2db7ffc',
            'before_sha256': None},
           {'path': 'view/dual_api_settings/controller.gd',
            'bytes': 1022,
            'sha256': '214ccf927d266317a7fe037c18f5d1d6f6592fe4c49e7059485969735f05063a',
            'before_sha256': None},
           {'path': 'view/dual_api_settings/panel.gd',
            'bytes': 15049,
            'sha256': '3c7c0298e79bf334dae4d7dc67d334f11e0d46aee1ed145672ae7bc6a1853c75',
            'before_sha256': None},
           {'path': 'view/ui_typography/style.gd',
            'bytes': 14899,
            'sha256': '0ce716c357b80da23063ae8f8d678a2c4c022f58df63c34b14ad802f9b90e565',
            'before_sha256': None}],
 'protected_files': {'README.md': {'bytes': 1,
                                   'sha256': '01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b'},
                     'project.godot': {'bytes': 808,
                                       'sha256': '34343acc9519c5479f0c0e86028fa7ed47bf207147d43a804c71ab504358c1fd'},
                     'main.tscn': {'bytes': 253,
                                   'sha256': '1e191898de710cf7d4fd1388e9798e8b4f39cf48fcd9c826ddc5169915e53f2b'},
                     'distribution_manifest.json': {'bytes': 206858,
                                                    'sha256': '6154796927071e068a8bed51e3146f9c8da5f407b4d702c127ddf42bbdcb641e'},
                     'updates/v28-ui-safety/manifest.json': {'bytes': 2701,
                                                             'sha256': 'b188cfddaf8e11878acdf2df2b861a0a4a87bd85d429e2bc4692f7b4c59296cb'},
                     'tools/restore_repository.py': {'bytes': 227,
                                                     'sha256': '7acc199c51befb1cc8ee4c65df5694b968af32c0b36220eb80c2898f6b95ecb2'},
                     'view/integrated_ecology_world/performance_variant/source_receipt.gd': {'bytes': 1093,
                                                                                             'sha256': 'dbc75c69f734f0ca0565947f609c55f483278e87334ebdd9e7e61e2a53431ff9'},
                     'view/playable_build/settlement_content.gd': {'bytes': 9184,
                                                                   'sha256': 'a0ad49733a6b85b5d9b113d395a845d95bab95455e1ffdc05d59e0df5bc86af8'},
                     'view/generated_natural_coast_entry/view.gd': {'bytes': 8403,
                                                                    'sha256': '0b41c8536c048adc12243972a5cfa81ccaa9c978446fa0c5ce50dc3624ec384f'}},
 'payload': {'file': 'payload.zip.b64',
             'encoded_bytes': 154296,
             'encoded_sha256': 'c94faab9b23ed3f3add262d7b944aae12e2d5299840acfca5d91b590752b9fe3',
             'zip_bytes': 115722,
             'zip_sha256': '5dd27afdd3f310396b3becbc01619d4aa4a46f4c6135c793bf1049fd5ed81de0',
             'members': {'PRODUCTION_MANIFEST.json': {'bytes': 1421,
                                                      'sha256': '300676b3eda9bbb61b72b71ae3d2bfa5e52f70dcd969762daa82c7a9cb701e8f'},
                         'main.patch': {'bytes': 6530,
                                        'sha256': 'f3d938e65f873e89f990da3df5807acd9718d4bbba2f720373756558b4ae91d3'},
                         'payload/main.gd': {'bytes': 184435,
                                             'sha256': '48d166879987b7285c21ce2bf7388a37654f1710131db851dfc0f70b0d6deb42'},
                         'payload/view/dual_api_settings/client.gd': {'bytes': 9256,
                                                                      'sha256': '5d84992c2f3a7e28f02795511b0b0c79bc24f2ae0e0cbf0e5a8b4ec8f2db7ffc'},
                         'payload/view/dual_api_settings/controller.gd': {'bytes': 1022,
                                                                          'sha256': '214ccf927d266317a7fe037c18f5d1d6f6592fe4c49e7059485969735f05063a'},
                         'payload/view/dual_api_settings/panel.gd': {'bytes': 15049,
                                                                     'sha256': '3c7c0298e79bf334dae4d7dc67d334f11e0d46aee1ed145672ae7bc6a1853c75'},
                         'payload/view/ui_typography/style.gd': {'bytes': 14899,
                                                                 'sha256': '0ce716c357b80da23063ae8f8d678a2c4c022f58df63c34b14ad802f9b90e565'},
                         'preimages/main.gd': {'bytes': 182315,
                                               'sha256': '2b05911a1bcde48b10a54e8d1475ef62c66aea84ff8c7f5b7cdc3052eaf9fc93'}}},
 'scope': 'API-only routing and typography over the verified public base. No actor/status upgrade, '
          'authority-data replacement, save migration or font assets.'}
LOCK_NAME = '.api-typography-15b7faa87361.lock'
REPARSE = getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)


class Refusal(Exception):
    """The package/project is not a verified safe input."""


def sha(data):
    return hashlib.sha256(data).hexdigest()


def strict_json(raw):
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                raise Refusal('Duplicate JSON key: ' + key)
            out[key] = value
        return out
    try:
        return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
                          parse_constant=lambda value: (_ for _ in ()).throw(Refusal('Non-finite JSON number')))
    except (ValueError, UnicodeError) as exc:
        raise Refusal('Invalid UTF-8 JSON') from exc


def valid_name(name):
    # Never normalize an untrusted archive name, especially backslashes.
    if not isinstance(name, str) or not name or name.startswith('/'):
        raise Refusal('Unsafe relative path')
    if any(c in name for c in '\\:\x00<>"|?*') or any(ord(c) < 32 for c in name):
        raise Refusal('Unsafe relative path: ' + repr(name))
    parts = name.split('/')
    reserved = {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'}
    reserved.update('COM' + n for n in '123456789¹²³')
    reserved.update('LPT' + n for n in '123456789¹²³')
    for part in parts:
        if not part or part in ('.', '..') or part[-1:] in ('.', ' '):
            raise Refusal('Unsafe path component: ' + repr(name))
        if part.split('.')[0].upper() in reserved:
            raise Refusal('Reserved Windows path: ' + repr(name))
    return parts


def valid_names(names):
    seen = {}
    files = set()
    for name in names:
        parts = valid_name(name)
        if name in files:
            raise Refusal('Duplicate archive path: ' + name)
        files.add(name)
        for end in range(1, len(parts) + 1):
            part = '/'.join(parts[:end])
            folded = part.casefold()
            if folded in seen and seen[folded] != part:
                raise Refusal('Case-fold path collision: ' + name)
            seen[folded] = part
    for name in files:
        if any('/'.join(name.split('/')[:i]) in files for i in range(1, len(name.split('/')))):
            raise Refusal('File/directory path collision: ' + name)


def reparse(st):
    return stat.S_ISLNK(st.st_mode) or bool(getattr(st, 'st_file_attributes', 0) & REPARSE)


def identity(st):
    return (st.st_dev, st.st_ino)


def stamp(st):
    return (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def lst(path):
    try:
        return path.lstat()
    except FileNotFoundError:
        return None


def safe_ancestors(path, include_leaf=False):
    chain = list(reversed(path.parents))
    if include_leaf:
        chain.append(path)
    for node in chain:
        st = lst(node)
        if st is None or reparse(st) or not stat.S_ISDIR(st.st_mode):
            raise Refusal('Missing, linked, or non-directory ancestor: ' + str(node))


def safe_read(path, limit):
    safe_ancestors(path)
    first = lst(path)
    if first is None or reparse(first) or not stat.S_ISREG(first.st_mode):
        raise Refusal('Missing, linked, or non-regular file: ' + str(path))
    if first.st_size > limit:
        raise Refusal('Unexpected file size: ' + str(path))
    flags = os.O_RDONLY | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(str(path), flags)
    with os.fdopen(fd, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        if reparse(opened) or not stat.S_ISREG(opened.st_mode) or stamp(first) != stamp(opened):
            raise Refusal('File changed while opening: ' + str(path))
        data = stream.read(limit + 1)
        final = os.fstat(stream.fileno())
    last = lst(path)
    if len(data) > limit or last is None or stamp(first) != stamp(final) or stamp(first) != stamp(last):
        raise Refusal('File changed while reading: ' + str(path))
    return data


def read_archive(raw, members):
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            infos = archive.infolist()
            valid_names([i.orig_filename for i in infos])
            if any(i.orig_filename != i.filename for i in infos):
                raise Refusal('Archive path was normalized by ZIP reader')
            if len(infos) != len(members) or {i.filename for i in infos} != set(members):
                raise Refusal('Archive members differ from frozen allowlist')
            result = {}
            for info in infos:
                expected = members[info.filename]
                kind = (info.external_attr >> 16) & 0o170000
                if info.is_dir() or kind not in (0, stat.S_IFREG) or info.flag_bits & 1:
                    raise Refusal('Archive contains a non-regular or encrypted member')
                if info.file_size != expected['bytes'] or info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    raise Refusal('Archive member size/compression mismatch')
                with archive.open(info) as stream:
                    data = stream.read(expected['bytes'] + 1)
                if len(data) != expected['bytes'] or sha(data) != expected['sha256']:
                    raise Refusal('Archive member content mismatch: ' + info.filename)
                result[info.filename] = data
            return result
    except (zipfile.BadZipFile, RuntimeError, EOFError, NotImplementedError) as exc:
        raise Refusal('Invalid archive') from exc


def load_package(directory, helper):
    manifest = strict_json(safe_read(directory / 'manifest.json', 1024 * 1024))
    if not isinstance(manifest, dict):
        raise Refusal('Manifest must be an object')
    for key, expected in CONTRACT.items():
        if json.dumps(manifest.get(key), sort_keys=True) != json.dumps(expected, sort_keys=True):
            raise Refusal('Manifest differs from frozen contract: ' + key)
    own = safe_read(helper, 1024 * 1024)
    if manifest.get('helper') != {'path': 'apply_candidate.py', 'bytes': len(own), 'sha256': sha(own)}:
        raise Refusal('Helper self hash/size mismatch')
    valid_names([row['path'] for row in CONTRACT['files']] + list(CONTRACT['protected_files']))
    p = CONTRACT['payload']
    encoded = safe_read(directory / p['file'], p['encoded_bytes'])
    if len(encoded) != p['encoded_bytes'] or sha(encoded) != p['encoded_sha256']:
        raise Refusal('Encoded payload hash/size mismatch')
    try:
        raw = base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        raise Refusal('Invalid base64 payload') from exc
    if len(raw) != p['zip_bytes'] or sha(raw) != p['zip_sha256']:
        raise Refusal('Archive hash/size mismatch')
    members = read_archive(raw, p['members'])
    production = strict_json(members['PRODUCTION_MANIFEST.json'])
    if json.dumps(production['files'], sort_keys=True) != json.dumps(CONTRACT['files'], sort_keys=True):
        raise Refusal('Production file map differs from frozen contract')
    return members


def project_path(value):
    path = Path(os.path.abspath(value))
    safe_ancestors(path, include_leaf=True)
    return path


def target_path(root, relative):
    parts = valid_name(relative)
    node = root
    safe_ancestors(root, include_leaf=True)
    for index, part in enumerate(parts):
        parent_st = lst(node)
        if parent_st is None:
            return root.joinpath(*parts)
        if reparse(parent_st) or not stat.S_ISDIR(parent_st.st_mode):
            raise Refusal('Linked or non-directory parent: ' + str(node))
        with os.scandir(node) as children:
            aliases = [entry.name for entry in children if entry.name.casefold() == part.casefold()]
        if aliases and aliases != [part]:
            raise Refusal('Case-fold target collision: ' + str(node / part))
        node = node / part
        st = lst(node)
        if st is not None:
            if reparse(st):
                raise Refusal('Symlink/junction/reparse target refused: ' + str(node))
            expected_kind = stat.S_ISREG if index == len(parts) - 1 else stat.S_ISDIR
            if not expected_kind(st.st_mode):
                raise Refusal('Non-regular target or ancestor: ' + str(node))
    return node


def known_bytes(members, relative, state):
    if state == 'after':
        return members['payload/' + relative]
    return members.get('preimages/' + relative)


def file_state(root, row, members):
    path = target_path(root, row['path'])
    before = known_bytes(members, row['path'], 'before')
    after = known_bytes(members, row['path'], 'after')
    if lst(path) is None:
        if before is None:
            return 'before'
        raise Refusal('Required baseline file missing: ' + row['path'])
    data = safe_read(path, max(len(before or b''), len(after)))
    if before is not None and data == before:
        return 'before'
    if data == after:
        return 'after'
    raise Refusal('Unknown edits; refusing to overwrite: ' + row['path'])


def preflight(root, members):
    for name, pin in CONTRACT['protected_files'].items():
        data = safe_read(target_path(root, name), pin['bytes'])
        if len(data) != pin['bytes'] or sha(data) != pin['sha256']:
            raise Refusal('Protected baseline pin mismatch: ' + name)
    return {row['path']: file_state(root, row, members) for row in CONTRACT['files']}


def state_label(states):
    return next(iter(set(states.values()))) if len(set(states.values())) == 1 else 'mixed'


def assert_states(root, members, expected):
    if preflight(root, members) != expected:
        raise Refusal('Project changed since preflight')


def make_parents(root, path, created):
    # OS-native path internally, canonical slash form only for relative checks.
    relative = path.relative_to(root).as_posix()
    parts = valid_name(relative)
    current = root
    for part in parts[:-1]:
        current = current / part
        if lst(current) is None:
            current.mkdir(mode=0o755)
            created.append((current, identity(current.lstat())))
        safe_ancestors(current, include_leaf=True)


def stage_write(path, data, mode):
    with path.open('xb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(path, mode)


def guarded_recover(root, members, journal, staged):
    failures = []
    rows = {row['path']: row for row in CONTRACT['files']}
    for name, original, desired, backup in reversed(journal):
        try:
            state = file_state(root, rows[name], members)
            if state == original:
                continue
            if state != desired:
                raise Refusal('Unexpected recovery state')
            target = target_path(root, name)
            if file_state(root, rows[name], members) != desired:
                raise Refusal('File changed during recovery')
            if known_bytes(members, name, original) is None:
                target.unlink()
            else:
                safe_ancestors(target)
                os.replace(str(staged / backup), str(target))
            if file_state(root, rows[name], members) != original:
                raise Refusal('Recovery postcondition failed')
        except Exception as exc:
            failures.append(name + ': ' + str(exc))
    return failures


def cleanup_stage(stage, stage_id, names):
    if stage is None:
        return []
    failures = []
    try:
        safe_ancestors(stage)
        st = lst(stage)
        if st is None:
            return []
        if reparse(st) or not stat.S_ISDIR(st.st_mode) or identity(st) != stage_id:
            raise Refusal('Staging directory changed; preserving it')
        for name in names:
            child = stage / name
            st = lst(child)
            if st is not None:
                if reparse(st) or not stat.S_ISREG(st.st_mode):
                    raise Refusal('Unknown staging entry; preserving it')
                child.unlink()
        stage.rmdir()
    except Exception as exc:
        failures.append('Staging cleanup incomplete: ' + str(exc))
    return failures


def mutate(root, members, initial, desired):
    lock = root / LOCK_NAME
    lock_fd = None
    lock_id = None
    stage = None
    stage_id = None
    staged_names = []
    created = []
    journal = []
    error = None
    warnings = []
    try:
        target_path(root, LOCK_NAME)
        try:
            lock_fd = os.open(str(lock), os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        except FileExistsError as exc:
            raise Refusal('Project lock exists; another run or manual recovery may be active') from exc
        lock_id = identity(os.fstat(lock_fd))
        os.write(lock_fd, (CONTRACT['candidate_id'] + '\n').encode('ascii'))
        os.close(lock_fd)
        lock_fd = None
        assert_states(root, members, initial)
        stage = Path(tempfile.mkdtemp(prefix='.candidate-stage-', dir=str(root)))
        stage_id = identity(stage.lstat())
        operations = []
        for index, row in enumerate(CONTRACT['files']):
            name = row['path']
            original = initial[name]
            if original == desired:
                continue
            current_path = target_path(root, name)
            current_st = lst(current_path)
            mode = stat.S_IMODE(current_st.st_mode) if current_st else 0o644
            forward = str(index) + '.forward'
            backup = str(index) + '.recovery'
            for stage_name, state in ((forward, desired), (backup, original)):
                data = known_bytes(members, name, state)
                if data is not None:
                    staged_names.append(stage_name)
                    stage_write(stage / stage_name, data, mode)
            operations.append((name, original, forward, backup))
        # All forward data and recovery preimages are durable before target edits.
        assert_states(root, members, initial)
        expected = dict(initial)
        for name, original, forward, backup in operations:
            assert_states(root, members, expected)
            target = target_path(root, name)
            if known_bytes(members, name, desired) is not None:
                make_parents(root, target, created)
            assert_states(root, members, expected)
            # Record the attempt before replace/unlink: an operation may take
            # effect and then raise. Recovery recognizes either exact outcome.
            journal.append((name, original, desired, backup))
            if known_bytes(members, name, desired) is None:
                target.unlink()
            else:
                os.replace(str(stage / forward), str(target))
            expected[name] = desired
            assert_states(root, members, expected)
        assert_states(root, members, {name: desired for name in initial})
    except Exception as exc:
        error = exc
        if stage is not None and journal:
            warnings.extend(guarded_recover(root, members, journal, stage))
            try:
                assert_states(root, members, initial)
            except Exception as recovery_exc:
                warnings.append('Post-recovery verification: ' + str(recovery_exc))
        for directory, created_id in reversed(created):
            try:
                st = lst(directory)
                if st is not None and not reparse(st) and identity(st) == created_id:
                    directory.rmdir()  # Only empty directories created by this run.
            except OSError:
                pass
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
        warnings.extend(cleanup_stage(stage, stage_id, staged_names))
        if lock_id is not None:
            try:
                safe_ancestors(lock)
                st = lst(lock)
                if st is None or reparse(st) or identity(st) != lock_id:
                    raise Refusal('Lock changed; preserving replacement')
                lock.unlink()
            except Exception as exc:
                warnings.append('Lock cleanup incomplete: ' + str(exc))
    if error is not None:
        detail = str(error)
        if warnings:
            detail += '; INCOMPLETE RECOVERY: ' + '; '.join(warnings)
        elif journal:
            detail += '; prior known state restored'
        raise Refusal(detail) from error
    if warnings:
        raise Refusal('Target operation completed, but cleanup needs attention: ' + '; '.join(warnings))


def run(project, action, directory=None, helper=None):
    helper = Path(os.path.abspath(__file__)) if helper is None else helper
    directory = helper.parent if directory is None else directory
    members = load_package(directory, helper)
    root = project_path(project)
    states = preflight(root, members)
    label = state_label(states)
    if action == 'check':
        if label == 'mixed':
            raise Refusal('Exact mixed candidate state; use explicit --rollback to restore baseline')
        return 'Verified ' + ('public baseline' if label == 'before' else 'already-applied candidate') + '; no changes made'
    desired = 'after' if action == 'apply' else 'before'
    if label == desired:
        return ('Already applied' if desired == 'after' else 'Already at public baseline') + '; no changes made'
    if action == 'apply' and label == 'mixed':
        raise Refusal('Exact mixed state; apply refused. Use --rollback first')
    mutate(root, members, states, desired)
    return 'Candidate applied and verified' if desired == 'after' else 'Public baseline restored and verified'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True, help='Fully restored public project directory')
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--check', action='store_true', help='Verify only (default)')
    actions.add_argument('--apply', action='store_true', help='Apply the five-file candidate')
    actions.add_argument('--rollback', action='store_true', help='Restore exact baseline, including exact mixed states')
    args = parser.parse_args(argv)
    action = 'apply' if args.apply else 'rollback' if args.rollback else 'check'
    try:
        print(run(args.project, action))
        return 0
    except (Refusal, OSError, ValueError, KeyError, TypeError) as exc:
        print('REFUSED: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
