#!/usr/bin/env python3
"""Portable offline source/patch checks. Never launches Godot or accesses a network."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
BASE = {
    'repository': 'baishouxiaosheng/words-and-perils',
    'commit': '2b1134bd20a9d22ead3b5c3f504452f3a7e95e0e',
    'path': 'candidates/actor-public-v29-compat/05ebbe56e88d/production/main.gd',
    'bytes': 203707,
    'sha256': '05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f',
    'git_blob': '2c522dfa6942bf51c4004d2d8a69c8a667c4ca56',
}
EXPECTED = {
    'main.gd': (204035, 'fa8a8c81275b4521ebfa38cc3f4156edbc4d67ca6b25f7bcf0ce9fb19ce7401e'),
    'view/ui_motion/hud_panel_motion.gd': (6290, 'd02bf598712829a7520c7d187347f185674b048a7042065aae6e7ef28d013546'),
    'tests/ui_motion/test_hud_panel_motion.gd': (11893, '9db7b4ca06b8bd29183ec539f3771c80e9fcda76fa8251140b3caff57ef6ef6d'),
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def functions(source):
    pieces = re.split(r'(?m)^(?=func )', source)
    return {'<preamble>': pieces[0], **{
        re.match(r'func (\w+)', p).group(1): p for p in pieces[1:]}}

def verify_manifest():
    manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    paths = set()
    for row in manifest['files']:
        path = Path(row['path'])
        if path.is_absolute() or '..' in path.parts:
            raise AssertionError('manifest path must be relative and contained')
        data = (ROOT / path).read_bytes()
        if (len(data), sha(data), blob(data)) != (row['bytes'], row['sha256'], row['git_blob']):
            raise AssertionError('manifest payload mismatch: ' + row['path'])
        paths.add(row['path'])
    actual = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file()}
    if actual != paths | {'manifest.json'}:
        raise AssertionError('unexpected or missing candidate files')
    print(f'Manifest verified: {len(paths)} payload files; self hash excluded.')

def run_checks(baseline):
    checks = []
    def check(value, label):
        checks.append({'name': label, 'passed': bool(value)})
        if not value:
            raise AssertionError(label)
    before = baseline.read_bytes()
    check(len(before) == BASE['bytes'], 'baseline byte count')
    check(sha(before) == BASE['sha256'], 'baseline SHA256')
    check(blob(before) == BASE['git_blob'], 'baseline Git blob')
    files = []
    for name, (size, digest) in EXPECTED.items():
        data = (ROOT / 'overlay' / name).read_bytes()
        check((len(data), sha(data)) == (size, digest), 'final source identity: ' + name)
        check(b'\r' not in data and data.endswith(b'\n'), 'LF and final newline: ' + name)
        check(not any(line.endswith((b' ', b'\t')) for line in data.splitlines()), 'no trailing whitespace: ' + name)
        files.append({'path': 'overlay/' + name, 'bytes': len(data), 'sha256': sha(data), 'git_blob': blob(data)})
    a = functions(before.decode('utf-8'))
    b = functions((ROOT / 'overlay/main.gd').read_text(encoding='utf-8'))
    check(a.keys() == b.keys(), 'Main function topology unchanged')
    check({name for name in a if a[name] != b[name]} == {'_ready', 'set_map_dialogue_hidden', 'apply_responsive_layout'}, 'only three Main functions changed')
    ready = '\tvar hud_motion := preload("res://view/ui_motion/hud_panel_motion.gd").new()\n\tadd_child(hud_motion)\n\thud_motion.bind_control(self, action_panel)\n'
    check(b['_ready'].replace(ready, '') == a['_ready'], 'ready only installs adapter')
    check(b['set_map_dialogue_hidden'].replace('get_node("HUDPanelMotion").call("set_hidden", hidden)', 'action_panel.visible=not hidden') == a['set_map_dialogue_hidden'], 'map visibility only delegates dock presentation')
    layout = b['apply_responsive_layout'].replace('\tif has_node("HUDPanelMotion"): get_node("HUDPanelMotion").call("before_layout")\n', '').replace('\tif has_node("HUDPanelMotion"): get_node("HUDPanelMotion").call("after_layout")\n', '')
    check(layout == a['apply_responsive_layout'], 'layout only adds before/after hooks')
    source = (ROOT / 'overlay/view/ui_motion/hud_panel_motion.gd').read_text(encoding='utf-8')
    code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('#'))
    check('Tween.TRANS_CUBIC' in code and 'Tween.EASE_IN_OUT' in code, 'CUBIC ease-in-out present')
    check(not re.search(r'\.(size|scale|disabled|text|editable)\s*=', code), 'no size scale disabled text or editable writes')
    check(not re.search(r'\b(FileAccess|DirAccess|RandomNumberGenerator|request_intent|begin_intent|end_turn|save_file)\b', code), 'no persistence RNG or action transaction access')
    check(code.count('ticket != generation') == 2 and 'generation += 1' in code, 'sample and completion generation guards')
    check('weakref(control)' in code and 'tween.kill()' in code and 'func _exit_tree()' in code, 'weak snapshots and teardown cancellation present')
    check('set_input_as_handled()' in code and 'blocked_mouse' in code and 'blocked_keys' in code, 'input footprint and release tails consumed')
    check('destination.is_equal_approx(motion_goal)' in code, 'actual endpoint checked on equal resting-position resize')
    suite = (ROOT / 'overlay/tests/ui_motion/test_hud_panel_motion.gd').read_text(encoding='utf-8')
    check('root.push_input' in suite and 'submit.pressed.connect(host.submit)' in suite and '.pressed.emit' not in suite, 'test source routes GUI events instead of emitting intent')
    check('backstop.raw_clicks == blocked_raw_clicks' in suite, 'test source asserts no early input propagation')
    for label in ['half-close reverse', 'rapid toggles', 'resize-close-open', 'stale close', 'panel destruction', 'adapter destruction', 'hidden click/Enter', 'exactly one intent', 'draft retained', 'disabled changes', 'held accept key']:
        check(label in suite, 'unrun test source covers ' + label)
    check(len(list((ROOT / 'overlay').rglob('*.gd'))) == 3, 'overlay has exactly three source files')
    with tempfile.TemporaryDirectory(prefix='wp-hud-static-') as folder:
        stage = Path(folder)
        (stage / 'main.gd').write_bytes(before)
        for args, label in [(['--check'], 'git apply --check'), ([], 'git apply in disposable directory')]:
            result = subprocess.run(['git', 'apply', *args, str(ROOT / 'candidate.patch')], cwd=stage, capture_output=True)
            check(result.returncode == 0 and not result.stderr, label)
        check(all((stage / name).read_bytes() == (ROOT / 'overlay' / name).read_bytes() for name in EXPECTED), 'patch roundtrip reproduces all three source bytes')
    report = {'kind': 'offline-source-and-patch-assertions', 'status': 'passed', 'assertion_count': len(checks),
              'checks': checks, 'baseline': BASE, 'source_files': files,
              'godot_semantic_parse': 'not_run', 'godot_tests': 'not_run',
              'main_gui_video_fps_ime': 'not_run', 'adopted': False}
    (ROOT / 'static_results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(checks)} source/patch assertions passed. Godot parse/tests/GUI NOT RUN.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-main', type=Path, help='Exact public production baseline main.gd; read only')
    parser.add_argument('--verify-manifest-only', action='store_true', help='Verify all declared payload bytes without rewriting results')
    args = parser.parse_args()
    if args.verify_manifest_only:
        verify_manifest()
    elif args.baseline_main is not None:
        run_checks(args.baseline_main)
    else:
        parser.error('provide --baseline-main or --verify-manifest-only')

if __name__ == '__main__':
    main()
