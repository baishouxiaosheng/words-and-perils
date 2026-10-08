#!/usr/bin/env python3
"""Static test-authoring checks only. No imports of the preparation script."""
from pathlib import Path
import argparse, ast, hashlib, json, re, tempfile

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--restored-root", type=Path, required=True)
parser.add_argument("--candidate-root", type=Path, required=True)
parser.add_argument("--guard", type=Path, required=True)
parser.add_argument("--runtime-pins", type=Path, help="Defaults to the original public runtime876 map inside restored-root")
args = parser.parse_args()
PUBLIC = args.restored_root.absolute()
CANDIDATE = args.candidate_root.absolute()
RUNTIME_PINS = args.runtime_pins.absolute() if args.runtime_pins else PUBLIC / "candidates/public-v29-enhanced/2b82fa8b37d5/runtime_876_pins.json"
GUARD = args.guard.absolute()
pins = json.loads((ROOT / "INPUT_PINS.json").read_text())
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(PUBLIC / "main.gd") == pins["base_main_sha256"]
assert sha(CANDIDATE / "overlay/main.gd") == pins["candidate_main_sha256"]
assert sha(ROOT / "tests/manual_receipt_display/helper.gd") == pins["helper_sha256"]
assert (ROOT / "tests/manual_receipt_display/helper.gd").read_bytes() == (CANDIDATE / "tests/test_manual_receipt_display.gd").read_bytes()
for path, expected in pins["source_files"].items(): assert sha(PUBLIC / path) == expected, path
assert sha(RUNTIME_PINS) == pins["runtime_876_pinmap_sha256"]
assert sha(GUARD) == pins["guard_sha256"]
prep = (ROOT / "prepare_driver.py").read_text()
tree = ast.parse(prep)
assert not re.search(r"\b(?:subprocess|exec_command|Popen|os\.system)\b", prep)
assert not any(token in prep for token in ['copytree(', '.chmod(', '.resolve('])
for token in ['"--timeout", "180"', '"--reserve-mib", "512"', '"--admission-extra-mib", "1741"', 'run_script.write_text']:
    assert token in prep, token
allowlist_path = ROOT / "RESTORED_SOURCE_ALLOWLIST.json"
assert sha(allowlist_path) == pins["restored_allowlist_sha256"]
allowlist = json.loads(allowlist_path.read_text())
rows = allowlist["files"]
assert len(rows) == 1466 and len({row["path"] for row in rows}) == 1466
allowlist_digest = hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
assert allowlist_digest == pins["restored_final_source_map_sha256"] == "34d1bfad7676d26d994eb4e8e06130a76cc05cb729b8b336842c571a7b85270e"
for row in rows:
    assert (PUBLIC / row["path"]).stat().st_size == row["size"] and sha(PUBLIC / row["path"]) == row["sha256"]
# Execute only four small path-validation functions against owned temporary
# files. Never execute prepare(), copy a game tree, invoke the guard or Godot.
names = ["no_symlink_path", "regular", "inside", "nonoverlapping_new_root"]
definitions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
namespace = {"Path": Path}
exec(compile(ast.Module(body=definitions, type_ignores=[]), "<path-safety-functions-only>", "exec"), namespace)
safety_checks = []
with tempfile.TemporaryDirectory(prefix="manual-receipt-path-check-", dir="/tmp") as directory:
    temporary = Path(directory)
    source, candidate, package, outside = [temporary / name for name in ["source", "candidate", "package", "outside"]]
    for path in [source, candidate, package, outside]: path.mkdir()
    (source / "regular.txt").write_text("owned small positive fixture")
    (outside / "sentinel.txt").write_text("outside sentinel must never be opened through a link")
    (source / "middle").symlink_to(outside, target_is_directory=True)
    (source / "leaf.txt").symlink_to(outside / "sentinel.txt")
    (temporary / "root-link").symlink_to(source, target_is_directory=True)
    def rejected(label, callback):
        try: callback()
        except ValueError: safety_checks.append({"label": label, "ok": True}); return
        raise AssertionError("Expected refusal: " + label)
    rejected("middle symlink", lambda: namespace["regular"](source / "middle/sentinel.txt"))
    rejected("leaf symlink", lambda: namespace["regular"](source / "leaf.txt"))
    rejected("symlink root ancestor", lambda: namespace["regular"](temporary / "root-link/regular.txt"))
    rejected("relative traversal", lambda: namespace["inside"](source, "../outside/sentinel.txt"))
    for root in [source, candidate, package]:
        rejected("QA inside " + root.name, lambda root=root: namespace["nonoverlapping_new_root"](root / "new-qa", [source, candidate, package]))
    rejected("input inside proposed QA", lambda: namespace["nonoverlapping_new_root"](temporary / "new-qa", [temporary / "new-qa/nested-input"]))
    rejected("existing QA root", lambda: namespace["nonoverlapping_new_root"](outside, [source, candidate, package]))
    assert namespace["regular"](namespace["inside"](source, "regular.txt")) == b"owned small positive fixture"
    assert namespace["nonoverlapping_new_root"](temporary / "accepted-qa", [source, candidate, package]) == temporary / "accepted-qa"
    safety_checks.append({"label": "regular file and new disjoint root admitted", "ok": True})
driver = (ROOT / "tests/manual_receipt_display/driver.gd").read_text()
for token in ['app.on_tool_selected(app.ACTOR_ENTRY_NEW)', 'app.submit_button.pressed.emit()',
              'app.show_import(); app.import_text.text = C.bytes(reply); app.import_decision()',
              'app._begin_required_enemy_turn()', 'Helper.pending_import(app, player_receipt.action_id',
              'Helper.pending_import(app, enemy_receipt.action_id', 'Helper.idle_latest_import(app,',
              'app.cancel_button.pressed.emit()', 'Generator.generate(726381, 4, "coastal_range")',
              'app.playtest.core.source.identity.profile_hash == AUTHORITY_SHA',
              'mock.sent.is_empty()', 'if not safety_ready:', 'movement revalidated after actual rest']:
    assert token in driver, token
assert driver.count('Helper.pending_import(') == 2 and driver.count('Helper.idle_latest_import(') == 1
for token in ['set_test_seed', 'engine._state', 'engine._rng', 'Engine.new', 'engine.commit(',
              'load_data(', 'save_data().receipts[', 'app._on_runtime_narration(', 'OS.execute', 'HTTPRequest']:
    assert token not in driver, token
for resource in re.findall(r'preload\("res://([^"\n]+)"\)', driver):
    if resource.startswith('tests/manual_receipt_display/'):
        assert (ROOT / resource).is_file()
    else:
        assert resource in pins["source_files"] or resource in ['core/world_generation_v3/generator.gd', 'view/generated_v3_enemy/adapter.gd', 'view/actor_action_profile_v2/source.gd', 'core/ai_gm_rebuilt/canonical.gd']
        assert (PUBLIC / resource).is_file()
report = {"schema": "manual-receipt-test-driver-static-check/v1", "status": "STATIC_CHECKS_PASSED_GODOT_NOT_RUN",
          "static_checker_sha256": sha(ROOT / "check_static.py"), "input_selection": "explicit_cli_paths",
          "driver_sha256": sha(ROOT / "tests/manual_receipt_display/driver.gd"), "helper_sha256": pins["helper_sha256"],
          "source_pins_matched": len(pins["source_files"]), "restored_source_allowlist_matched": len(rows),
          "restored_source_map_sha256": allowlist_digest, "published_helper_unchanged": True,
          "python_preparer_syntax": "ast.parse_passed", "preparer_stage_executed": False,
          "small_path_safety_function_checks": safety_checks, "Godot_started": False,
          "Godot_parser": "not_run", "real_Main_regression": "not_run", "Git_writes": 0,
          "finite_scope": "One contact route; first real player/enemy round trip; two pending imports and actual cancels; two additional observe commits; latest idle import.",
          "remaining_inputs": "Complete restored source/resources, exact published candidate, original876 pinmap, exact complete guard and authorized Godot4.6.3 in a compliant recovered environment."}
(ROOT / "STATIC_CHECKS.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
