#!/usr/bin/env python3
"""Offline public v30 actor/status source restoration, Python 3.10+.

This small adapter executes the exact immutable v29 helper and reuses its
path, JSON, archive, rank, write-journal, closure and binary verifiers. The
historical bundles and v29 ZIP remain unchanged. Unknown edits are preserved.
Close the editor/game and do not run competing restorers. Ordinary errors
roll back each layer; this is not whole-restoration or power-loss atomicity.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
import types

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'v30-actor-status'
TITLE = 'public v30 角色/状态整合版'
BASE_PUBLIC_COMMIT = '06be017d60153fc1d018bd9f3e920ba739716e60'
LEGACY = {'path': 'tools/restore_v29.py',
 'size': 28323,
 'sha256': '438a6230a147437dcb8f359519f7e4bca9a82e67fe816a88aec31e6784314b84'}
PREVIOUS_DISTRIBUTION = {'path': 'updates/v29/distribution_manifest.json',
 'size': 207021,
 'sha256': '162a2ced850ce5c16f49ae37855e935f882d4de154fbeb7de85a96ee15c19fa2'}
PREVIOUS_MANIFEST = {'path': 'updates/v29/manifest.json',
 'size': 8997,
 'sha256': 'fc048fdad0c405bc82145e9277ae3737c0f617a22b960792469dfd12d8bec0f8'}
PREVIOUS_ARCHIVE = {'path': 'updates/v29/source_delta.zip.b64',
 'size': 105992,
 'sha256': '6e33c6919f372a8aff7cc204d556beaeb9e53a747d39fd00453060e9fbbe7bfa'}
SOURCE_FILES = [{'path': 'main.gd',
  'size': 203707,
  'sha256': '05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f',
  'before_sha256': '6e2f62e76db2f4a64a9bbdf4d348a32588d1cb991e6d869bff4c730e12e61e5c'},
 {'path': 'view/actor_action_entry/board.gd',
  'size': 7892,
  'sha256': '37af60151c95cf268157bd312957d074fe1b66c3f5e692c8b2e365459a953683',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/item_view.gd',
  'size': 540,
  'sha256': '8e4214988c3c63c793a2d353abc4a95a27c83d3ba55901eaada037f96ff606f7',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/moving_support.gd',
  'size': 4688,
  'sha256': '12bc6fa20d4bed640db0f80c4157b7ba017efc5f6779c0d78b5e972b9d1b6df1',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/panel.gd',
  'size': 1807,
  'sha256': '30cd052e330d89d82b05bd7964dba2139b3966534cb75467e2108f179608f6e6',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/render_source.gd',
  'size': 3233,
  'sha256': '25a9346826d43dc7ae6793ac0fc5a51ed202744582eb8009095cbf29622f0fea',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/runtime/actor_scope.gd',
  'size': 8408,
  'sha256': '43ecfa5bdabd576935f272421fe136070df54981fc9fe52a2473f7dc1f9b5198',
  'before_sha256': None},
 {'path': 'view/actor_action_entry/view_adapter.gd',
  'size': 26215,
  'sha256': 'e2d2cc438b00b3d933a267df73e760f108fc4b89ac5334053615fd88c3454cc6',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/adapter.gd',
  'size': 5582,
  'sha256': '82517e0004f19016dad8dba162a86097d7366d56020a84fe02820c37d7eae7d0',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/decision.gd',
  'size': 3525,
  'sha256': '293c6049fb17a505c5496fdf4fc1f9cfc5a2806cc3b16d5053abafec616dda14',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/engine.gd',
  'size': 11974,
  'sha256': 'd8218ab72d9e7f2b83fc48f96558c64b80e8760e13ac35fb47bbe5c0ea4e5353',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/history.gd',
  'size': 3379,
  'sha256': '193b7c5a2a0dbb001aef7eb5a0e72290ac1df8726a4f90fafa34b9ab25078c62',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/hooks.gd',
  'size': 1838,
  'sha256': '08d4dd8839fd29bdd2224cf72b94e9bd24423dc7aeca194f37950d8bee59716e',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/policy.gd',
  'size': 2628,
  'sha256': '8c72f0d1ab8b6812867d2bc1932bc0bc0dd2a32902f225d58fac6df3b8aefb68',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/projection.gd',
  'size': 3042,
  'sha256': '0121badfb0e4cf9189e270170de8214ce3d330d1c8b82824423a0e9cecd674b0',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/resolver.gd',
  'size': 7339,
  'sha256': '1bc27d10346ad22858a3a848baa826db31d6d587b794e3c48eeb3dbefa63c982',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/rule.gd',
  'size': 532,
  'sha256': 'cf452edababe042f1ccd2c12517e3bba581cc856ea58bdacb3d94422900b1561',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/scheduler.gd',
  'size': 10142,
  'sha256': 'fa6533672c7cebdce1f67f2c50a3358ea41d2d276833ede4202ab074d6bf34dc',
  'before_sha256': None},
 {'path': 'view/actor_action_profile_v2/source.gd',
  'size': 12173,
  'sha256': '7681a03d232452533ef584719d5f3e6c1c39942332b303ef1c2a3e973385e665',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/board.gd',
  'size': 1180,
  'sha256': '3b3f5e0aaa42b6f8cef19fce946be41324749d14e3f284fb9a5d50d72d790e3d',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/committed_effect_router.gd',
  'size': 1845,
  'sha256': 'a8141bfb2d89f289c40cd4e233da35908f5d5babb236ce0f427bbfe5b30bd5b7',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/public_events.gd',
  'size': 12262,
  'sha256': '9e537b893d63497a31aa5bad014f2f9e22366735e02c21122ab5a6a818497f64',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/render_source.gd',
  'size': 3254,
  'sha256': '7988c5c588b90308986adbd382fed9dc5f118fc6607625c74fac431c90eae4f7',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/runtime/client.gd',
  'size': 7296,
  'sha256': 'c691edfba3142bc64b69196a08b7f92881de6a3bef94439816a957dc6d17b38d',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/runtime/controller.gd',
  'size': 9349,
  'sha256': '832878afae4db541bfb4702d5b4a4e22c839b3358a01085d4033ad7946719267',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/runtime/intention_codec.gd',
  'size': 2971,
  'sha256': 'be1dfd53d922e99ccdb1a44b94bdf40e96f8185fdf3c79dae53f99f9a285f454',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/runtime/status_scope.gd',
  'size': 3254,
  'sha256': '528bd5e8c86405ab35482ad735a0dce5f52f506f0ae59e72f671973257cb069e',
  'before_sha256': None},
 {'path': 'view/actor_status_entry_v1/view_adapter.gd',
  'size': 28301,
  'sha256': 'a9a825b9096b67424e7358d2dcca32b8e39411983f7ac9be0975ef7bc869968d',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/adapter.gd',
  'size': 6527,
  'sha256': 'fd5629777dbdefc0d50bf8ce58339d12bc6e351c09b2253701b1e9ea4f9486ba',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/decision.gd',
  'size': 3532,
  'sha256': '15d02d3d0f3bb60031bb98e96ae1a83a45b69e92f3053401a17390433c4bcb7f',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/domain.gd',
  'size': 6165,
  'sha256': 'a2e1dbf15e9e3898f640e90b41eab1ecd29a3f6bf369022ea690a0634769212a',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/engine.gd',
  'size': 16382,
  'sha256': 'ea6687e72df87f4df87b9848cd1dff28c1b0888143105f74fd11c2f9587ec85f',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/history.gd',
  'size': 4062,
  'sha256': '66cd6701f5380b2045da416ef542c731bc81365dfbba13d0b36247cabe403338',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/hooks.gd',
  'size': 1167,
  'sha256': '0d0bafb609601197f9f73449b31eea8f681eff65e617ade7186a01a8fc63842f',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/projection.gd',
  'size': 3231,
  'sha256': '2decabf7c9fbe1b4c5400b502ce1e464112bb4eea489dfdcee3a5cf1c150d5e6',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/public_status.gd',
  'size': 6400,
  'sha256': '335c0eb58165e4ebb01f8963a0292176eb2deaf354bfeb5c1876e0e5c8eeded1',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/resolver.gd',
  'size': 9382,
  'sha256': 'c666a73e826080fda57aaebee341e24a65c1225e041e7685f14a5ebc75fb493b',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/rule.gd',
  'size': 531,
  'sha256': '39618f30030fc07025c67ca9f7a88e1e6870cd481613686b138b1d2e62897da1',
  'before_sha256': None},
 {'path': 'view/actor_status_profile_v1/source.gd',
  'size': 10327,
  'sha256': 'f4ca4ca0551f0b1665b58f4ee1071dbc7df5180f357de18710d55a596b88ac03',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/actor_client.gd',
  'size': 6891,
  'sha256': 'd1c2f185d70090da37a70231840c6d5445e55fe1688722ee7cba3da4349c2e74',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/actor_controller.gd',
  'size': 1585,
  'sha256': 'b9461d141ef9ef0470de2e7e3e58b53e2516859d5bd1f42644a6d992fb73d124',
  'before_sha256': None},
 {'path': 'view/dual_api_settings/provider_presets.gd',
  'size': 3798,
  'sha256': 'f64ceeb823e25c2e39c9637f49788e0082cf63eb3e02b520434870b116f6022f',
  'before_sha256': '26520871eaecc153258e036926474ade94828fb260df578bc2f3c10f1bf70dc5'}]
RUNTIME_RESOURCE_MAP_SHA256 = '735fa231eaa1e8f92532de0eb11c5f636013e810cc6ba7a1594e3162131e9809'
RUNTIME_RESOURCE_MAP = {'path': 'candidates/public-v29-enhanced/2b82fa8b37d5/runtime_876_pins.json', 'size': 177225, 'sha256': '4f61e1ce088cc0817ef2044f142f6c80edd5a6a7c3ec47688fa559ed16c1860e'}
WRAPPER_PATH = 'tools/restore_repository.py'
WRAPPER = b'''#!/usr/bin/env python3
"""Restore the current verified public source version, completely offline."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("restore_v30.py")), run_name="__main__")
'''


def legacy_helper():
    target = ROOT / LEGACY['path']
    st = target.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_size != LEGACY['size']:
        raise ValueError('Immutable v29 helper missing or non-regular')
    raw = target.read_bytes()
    if hashlib.sha256(raw).hexdigest() != LEGACY['sha256']:
        raise ValueError('Immutable v29 helper checksum differs')
    result = types.ModuleType('_exact_public_v29_restore')
    result.__file__ = str(target)
    exec(compile(raw, str(target), 'exec'), result.__dict__)
    result.ROOT = ROOT
    # The verified v29 path validator checks all project ancestors and aliases.
    if not result.good(result.path(LEGACY['path']), LEGACY):
        raise ValueError('Immutable v29 helper path differs')
    return result


def load_source_zip(r, validator, archive, rows):
    # Same bounded v29 ZIP reader, with only the final archive path changed.
    if archive.get('format') != 'zip+base64' or archive.get('encoded_path') != 'updates/v30/source_delta.zip.b64':
        raise ValueError('Unexpected actor/status source archive')
    encoded_row = archive['encoded']
    if (type(encoded_row['size']) is not int or not 0 < encoded_row['size'] <= 2 * 1024 * 1024
            or type(archive['size']) is not int or not 0 < archive['size'] <= 1024 * 1024):
        raise ValueError('Actor/status source archive exceeds its bounded size')
    expected = {'payload/' + row['path']: {'bytes': row['size'], 'sha256': row['sha256']} for row in rows}
    if archive['members'] != expected:
        raise ValueError('Actor/status ZIP member map differs')
    try:
        encoded = validator.safe_read(r.path(archive['encoded_path']), encoded_row['size'])
        if len(encoded) != encoded_row['size'] or r.digest(encoded) != encoded_row['sha256']:
            raise ValueError('Actor/status encoded ZIP checksum/size mismatch')
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) != archive['size'] or r.digest(raw) != archive['sha256']:
            raise ValueError('Actor/status ZIP checksum/size mismatch')
        return validator.read_archive(raw, expected)
    except validator.Refusal as error:
        raise ValueError('Actor/status ZIP validation failed: ' + str(error)) from error


def load_release(r):
    m, raw = r.checked_json('updates/v30/distribution_manifest.json')
    if r.path('distribution_manifest.json').read_bytes() != raw:
        raise ValueError('Root and immutable v30 distributions differ')
    if m.get('schema') != 'words-and-perils-offline-distribution/v1' or m.get('active_version') != VERSION:
        raise ValueError('Unexpected v30 distribution schema/version')
    ref = m['adoption_manifest']
    if ref['path'] != 'updates/v30/manifest.json':
        raise ValueError('Unexpected v30 adoption manifest path')
    adoption, _ = r.checked_json(ref['path'], ref)
    if (adoption.get('schema') != 'words-and-perils-public-zip-adoption/v1'
            or adoption.get('version') != VERSION or adoption.get('title') != TITLE
            or adoption.get('base_public_commit') != BASE_PUBLIC_COMMIT
            or adoption.get('distribution_identity') != 'public-source-derived'
            or adoption.get('excluded_versions') != ['v25']
            or adoption['previous_distribution'] != PREVIOUS_DISTRIBUTION
            or adoption['previous_adoption_manifest'] != PREVIOUS_MANIFEST
            or adoption['restore_base_helper'] != LEGACY):
        raise ValueError('Unexpected v30 adoption identity')
    previous, _ = r.checked_json(PREVIOUS_DISTRIBUTION['path'], PREVIOUS_DISTRIBUTION)
    prior, _ = r.checked_json(PREVIOUS_MANIFEST['path'], PREVIOUS_MANIFEST)
    if (previous['active_version'] != r.VERSION or previous['adoption_manifest'] != PREVIOUS_MANIFEST
            or prior['version'] != r.VERSION or prior['files'] != r.ENHANCED_FILES
            or prior['release_helper'] != LEGACY
            or prior['release_wrapper']['sha256'] != r.digest(r.WRAPPER)
            or prior['archive']['encoded'] != {k: PREVIOUS_ARCHIVE[k] for k in ('size', 'sha256')}
            or prior['archive']['encoded_path'] != PREVIOUS_ARCHIVE['path']):
        raise ValueError('Immutable v29 adoption differs')
    inherited = dict(m)
    inherited['active_version'] = previous['active_version']
    inherited['adoption_manifest'] = previous['adoption_manifest']
    if inherited != previous:
        raise ValueError('Inherited distribution fields changed')
    patches, previous_sha = [], None
    for update in m['update_manifests']:
        patch, _ = r.checked_json(update['path'], update)
        if (patch.get('schema') != 'words-and-perils-source-delta/v1'
                or patch['base_source_bundle_sha256'] != m['source_bundle']['sha256']
                or (previous_sha is not None and patch.get('previous_manifest_sha256') != previous_sha)):
            raise ValueError('Historical source chain differs')
        previous_sha = update['sha256']
        patches.append(patch)
    if ([p['version'] for p in patches] != r.VERSIONS
            or prior['previous_manifest_sha256'] != previous_sha
            or adoption['previous_manifest_sha256'] != PREVIOUS_MANIFEST['sha256']):
        raise ValueError('Unexpected historical/v29 source chain')
    helper_ref = {'path': r.CANDIDATE + '/apply_candidate.py', 'size': 25498, 'sha256': r.CANDIDATE_HELPER_SHA}
    manifest_ref = {'path': r.CANDIDATE + '/manifest.json', 'size': 4747, 'sha256': r.CANDIDATE_MANIFEST_SHA}
    package = adoption['zip_validator']
    if (package['helper'] != helper_ref or package['manifest'] != manifest_ref
            or prior['zip_validator']['helper'] != helper_ref or prior['zip_validator']['manifest'] != manifest_ref):
        raise ValueError('Unchanged ZIP validator identities differ')
    candidate_manifest, _ = r.checked_json(manifest_ref['path'], manifest_ref)
    validator = r.verified_module('_verified_v30_zip_validator', helper_ref['path'], helper_ref)
    old_members = r.load_source_zip(validator, prior['archive'], prior['files'])
    rows = adoption['files']
    if rows != SOURCE_FILES:
        raise ValueError('Actor/status source rows differ from the frozen release')
    r.file_rows(rows)
    members = load_source_zip(r, validator, adoption['archive'], rows)
    wrapper = adoption['release_wrapper']
    if (wrapper['path'] != WRAPPER_PATH or wrapper['size'] != len(WRAPPER)
            or wrapper['sha256'] != r.digest(WRAPPER) or wrapper['before_sha256'] != r.digest(r.WRAPPER)):
        raise ValueError('Final v30 wrapper differs')
    # The original v29 final layer is retained as an exact historical ZIP layer.
    old_layer = {'files': prior['files'] + [prior['release_wrapper']],
                 'archive': prior['archive']}
    old_model = r.build_model(m['source_files'], patches, old_layer['files'])
    if (prior['final_source_files'] != len(old_model['final'])
            or prior['final_source_map_sha256'] != r.digest(r.canonical(r.filemap(old_model['final'])))):
        raise ValueError('Immutable v29 source map differs')
    model = r.build_model(m['source_files'], patches + [old_layer], rows + [wrapper])
    if (adoption['final_source_files'] != len(model['final'])
            or adoption['final_source_map_sha256'] != r.digest(r.canonical(r.filemap(model['final'])))):
        raise ValueError('Final v30 source map/count differs')
    release_helper = adoption['release_helper']
    if release_helper['path'] != 'tools/restore_v30.py' or not r.good(r.path(release_helper['path']), release_helper):
        raise ValueError('Versioned v30 adapter differs')
    protected = {name: {'size': row['bytes'], 'sha256': row['sha256']}
                 for name, row in candidate_manifest['protected_files'].items()
                 if name not in ('distribution_manifest.json', WRAPPER_PATH)}
    if adoption['protected_public_files'] != protected or prior['protected_public_files'] != protected:
        raise ValueError('Protected public pins differ')
    for name, row in protected.items():
        if name in model['final']:
            if any(row[key] != model['final'][name][key] for key in ('size', 'sha256')):
                raise ValueError('Protected source was superseded: ' + name)
        elif not r.good(r.path(name), row):
            raise ValueError('Protected public control differs: ' + name)
    pins = {}
    for patch in patches:
        pins.update(patch.get('canonical_pins', {}))
        pins.update(patch['production_pins'])
    pins.update({row['path']: row['sha256'] for row in prior['files']})
    pins.update({row['path']: row['sha256'] for row in rows})
    if any(model['final'].get(name, {}).get('sha256') != value for name, value in pins.items()):
        raise ValueError('Final production pin differs')
    if adoption['runtime_resource_map'] != RUNTIME_RESOURCE_MAP:
        raise ValueError('Inherited runtime resource map identity differs')
    runtime, _ = r.checked_json(RUNTIME_RESOURCE_MAP['path'], RUNTIME_RESOURCE_MAP)
    r.valid_names(runtime)
    if (len(runtime) != adoption['runtime_resource_count'] or len(runtime) != 876
            or adoption['runtime_resource_map_sha256'] != RUNTIME_RESOURCE_MAP_SHA256
            or r.digest(r.canonical(runtime)) != RUNTIME_RESOURCE_MAP_SHA256):
        raise ValueError('Complete inherited runtime resource pins differ')
    for name in set(runtime) & set(model['final']):
        if (model['final'][name]['sha256'] != runtime[name]['sha256']
                or model['final'][name]['size'] != runtime[name]['bytes']):
            raise ValueError('Inherited runtime JSON source differs: ' + name)
    model.update({'distribution': m, 'adoption': adoption, 'members': members,
                  'old_zip_members': old_members, 'protected': protected, 'production_pins': pins,
                  'runtime_resource_pins': runtime})
    return model


def stage_members(r, rows, members, wrapper, directory):
    staged = {}
    for name in rows:
        target = directory / ('candidate-' + str(len(staged)))
        target.write_bytes(wrapper if name == WRAPPER_PATH else members['payload/' + name])
        staged[name] = target
    return staged


def restore_sources(r, model):
    r.preflight(model)
    writes = 0
    layers = [(model['base'], model['distribution']['source_bundle'])]
    layers.extend((r.file_rows(p['files']), p['archive']) for p in model['patches'])
    for index, (rows, archive) in enumerate(layers):
        if not r.needs_layer(rows, model['ranks'], index):
            continue
        with tempfile.TemporaryDirectory(prefix='words-and-perils-source-') as td:
            directory = Path(td)
            if archive.get('format') == 'zip+base64':
                staged = stage_members(r, rows, model['old_zip_members'], r.WRAPPER, directory)
            else:
                staged = r.stage_tar(rows, archive, directory)
            writes += r.apply_staged(rows, staged, model['ranks'], index, directory)
    rows = model['final_rows']
    index = len(layers)
    if r.needs_layer(rows, model['ranks'], index):
        with tempfile.TemporaryDirectory(prefix='words-and-perils-v30-') as td:
            directory = Path(td)
            staged = stage_members(r, rows, model['members'], WRAPPER, directory)
            writes += r.apply_staged(rows, staged, model['ranks'], index, directory)
    r.preflight(model, require_final=True)
    return writes


def check_runtime_resources(r, model):
    for name, row in model['runtime_resource_pins'].items():
        expected = {'size': row['bytes'], 'sha256': row['sha256']}
        if not r.good(r.path(name), expected):
            raise ValueError('Inherited runtime resource missing/corrupt: ' + name)
    return 876


def main(argv=None):
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, help='Exact public release project; default: parent of tools')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Read-only final sources/map/closure check; no binary resource reads')
    mode.add_argument('--sources-only', action='store_true', help='Restore and verify sources; no binary resource reads')
    args = parser.parse_args(argv)
    if args.project is not None:
        ROOT = Path(os.path.abspath(args.project))
    r = legacy_helper()
    model = load_release(r)
    writes = 0 if args.check else restore_sources(r, model)
    report = r.check_sources(model)
    if not args.check and not args.sources_only:
        report['binary_resources'] = r.restore_resources(model)
        r.check_sources(model, require_resources=True)
        report['runtime_resource_files'] = check_runtime_resources(r, model)
    report.update({'version': VERSION, 'source_writes': writes,
                   'binary_verification': 'not_requested' if args.check or args.sources_only else 'passed',
                   'scope': 'public distribution; native v28 unchanged; literal closure excludes dynamic loads'})
    print(json.dumps(report, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, tarfile.TarError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
