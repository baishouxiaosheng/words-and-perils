#!/usr/bin/env python3
"""Offline v2 source/diff checks only; no Godot, network or GDScript parser."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
COMMIT = '4be6cf5d271889f2680b3bb50aa2f93c75ed14a4'
BASE = {
    'main.gd': (204035, 'fa8a8c81275b4521ebfa38cc3f4156edbc4d67ca6b25f7bcf0ce9fb19ce7401e'),
    'view/ui_motion/hud_panel_motion.gd': (6290, 'd02bf598712829a7520c7d187347f185674b048a7042065aae6e7ef28d013546'),
    'tests/ui_motion/test_hud_panel_motion.gd': (11893, '9db7b4ca06b8bd29183ec539f3771c80e9fcda76fa8251140b3caff57ef6ef6d'),
}

def digest(data):
    return hashlib.sha256(data).hexdigest()

def functions(source):
    parts = re.split(r'(?m)^(?=func )', source)
    return {'<preamble>': parts[0], **{re.match(r'func (\w+)', p).group(1): p for p in parts[1:]}}

def run(baseline):
    checks = []
    def check(value, label):
        checks.append({'name': label, 'passed': bool(value)})
        if not value: raise AssertionError(label)
    old = {}
    for name, (size, sha) in BASE.items():
        data = (baseline / 'overlay' / name).read_bytes()
        check((len(data), digest(data)) == (size, sha), 'published v1 baseline identity: ' + name)
        old[name] = data
    main_old = functions(old['main.gd'].decode())
    main_new = functions((ROOT / 'overlay/main.gd').read_text(encoding='utf-8'))
    check(main_old.keys() == main_new.keys(), 'Main function topology preserved')
    check({name for name in main_old if main_old[name] != main_new[name]} == {'_ready'}, 'v2 changes only Main ready binding')
    check(main_new['_ready'].replace('hud_motion.bind_control(self, action_panel, dialogue_restore_button)', 'hud_motion.bind_control(self, action_panel)') == main_old['_ready'], 'Main only passes actual RestoreDialogue control')
    source = (ROOT / 'overlay/view/ui_motion/hud_panel_motion.gd').read_text(encoding='utf-8')
    a, b = functions(old['view/ui_motion/hud_panel_motion.gd'].decode()), functions(source)
    check(set(b) - set(a) == {'_restore_available', '_has_visible_window', '_handle_restore_mouse'} and not set(a) - set(b), 'adapter adds only Restore click helpers')
    check({name for name in a if a[name] != b[name]} == {'<preamble>', 'bind_control', '_input', '_process', '_exit_tree'}, 'existing adapter changes limited to binding routing and cleanup')
    check(a['blocks_event'] == b['blocks_event'], 'original dock mouse keyboard and tail shielding unchanged')
    check(all(a[name] == b[name] for name in ['before_layout', 'after_layout', '_start', '_present', '_completed', '_lock_input', '_capture_input', '_restore_input']), 'layout tween generation and input snapshots preserved')
    handle = b['_handle_restore_mouse']
    check(handle.count('host.call("set_map_dialogue_hidden", false)') == 1, 'one existing Main UI callback site')
    check(handle.index('get_viewport().set_input_as_handled()') < handle.index('host.call("set_map_dialogue_hidden", false)'), 'event consumed before Main callback')
    check(handle.index('restore_mouse_down = false') < handle.index('host.call("set_map_dialogue_hidden", false)'), 'captured click cleared before callback')
    check('button.button_index != MOUSE_BUTTON_LEFT' in handle and 'phase == &"closing"' in handle, 'capture restricted to primary click during close')
    check(handle.count('not button.canceled') == 2 and 'blocked_mouse.has(MOUSE_BUTTON_LEFT)' in handle, 'canceled events and dock-origin press tails cannot restore')
    check('_handle_restore_mouse(event) or blocks_event(event)' in b['_input'], 'Restore capture precedes ordinary shield')
    available = b['_restore_available']
    for label, token in [('visible button', 'restore_button.is_visible_in_tree()'), ('business disabled veto', 'restore_button.disabled'), ('same viewport', 'restore_button.get_viewport() != get_viewport()'), ('API modal veto', '_api_settings_open'), ('visible window veto', '_has_visible_window(host)')]:
        check(token in available, 'Restore availability checks ' + label)
    code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('#'))
    check(not re.search(r'\.(size|scale|disabled|text|editable)\s*=', code), 'adapter does not write geometry size disabled or draft text')
    check(not re.search(r'\b(FileAccess|DirAccess|RandomNumberGenerator|request_intent|begin_intent|end_turn|save_file)\b', code), 'no authority persistence RNG or action transaction access')
    suite = (ROOT / 'overlay/tests/ui_motion/test_hud_panel_motion.gd').read_text(encoding='utf-8')
    regression = suite.split('# Real RestoreDialogue geometry and input route, not adapter.set_hidden(false).', 1)[1].split('check(JSON.stringify(host.authority)', 1)[0]
    check('push_click(restore_point)' in regression and 'root.push_input' in suite and 'restore_button.name = "RestoreDialogue"' in suite, 'regression sends actual input at the sibling RestoreDialogue control')
    check('motion.set_hidden(false)' not in regression and 'host.set_map_dialogue_hidden(false)' not in regression and '.pressed.emit' not in suite, 'regression does not replace Restore input with a direct reopen or signal emission')
    check('Vector2(800, 1043)' in regression and 'Vector2(380, 856)' in regression and 'Vector2(840, 198)' in regression, 'regression reproduces public layout overlap')
    for label in ['actual RestoreDialogue click reverses closing exactly once', 'actual RestoreDialogue reversal starts at displayed position', 'RestoreDialogue click synchronizes all Main visibility state', 'RestoreDialogue click neither submits nor reaches board input', 'after actual RestoreDialogue recovery one click yields one intent', 'dock-to-Restore release', 'Restore drag-out release', 'canceled Restore release', 'modal API gate blocks RestoreDialogue']:
        check(label in regression, 'unrun input regression covers ' + label)
    check('backstop.raw_clicks == before_restore_raw' in regression and 'backstop.clicks == before_restore_gui' in regression, 'unrun regression asserts zero early input and GUI penetration')
    check('goal.text == draft' in regression and 'business_disabled.disabled' in regression and 'JSON.stringify(host.authority) == authority_before' in suite, 'unrun regression retains draft business flags and authority bytes')
    check(len(list((ROOT / 'overlay').rglob('*.gd'))) == 3, 'v2 overlay contains exactly three final sources')
    with tempfile.TemporaryDirectory(prefix='wp-hud-v2-static-') as folder:
        stage = Path(folder)
        for name, data in old.items():
            path = stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        for arguments, label in [(['--check'], 'v2 patch application precheck'), ([], 'v2 patch application')]:
            result = subprocess.run(['git', 'apply', *arguments, str(ROOT / 'candidate.patch')], cwd=stage, capture_output=True)
            check(result.returncode == 0 and not result.stderr, label)
        check(all((stage / name).read_bytes() == (ROOT / 'overlay' / name).read_bytes() for name in BASE), 'patch roundtrip reproduces all three v2 sources')
    check(all((baseline / 'overlay' / name).read_bytes() == data for name, data in old.items()), 'baseline source files unchanged after checks')
    report = {'kind': 'source-and-patch-only', 'baseline_commit': COMMIT, 'status': 'passed', 'assertion_count': len(checks), 'checks': checks, 'source_defect': {'dock_rect': [380, 856, 840, 198], 'restore_center': [800, 1043], 'center_inside_resting_dock': True}, 'godot_semantic_parse': 'not_run', 'godot_tests': 'not_run', 'real_main_gui': 'not_run', 'independent_review': 'not_run', 'phase': 'prepublication_static_check', 'adopted': False}
    (ROOT / 'static_results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(checks)} v2 source/patch assertions passed; Godot parse/tests NOT RUN.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-dir', type=Path, required=True, help='Read-only published v1 candidate directory')
    run(parser.parse_args().baseline_dir)
