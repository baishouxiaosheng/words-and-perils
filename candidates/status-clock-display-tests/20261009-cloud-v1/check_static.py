"""Static source/coverage checks and Python preparation replay; never runs Godot."""
from pathlib import Path
import argparse
import ast
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile

PACKAGE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    args = parser.parse_args()
    inputs = json.loads((PACKAGE / "INPUTS.json").read_text())
    manifest = json.loads((PACKAGE / "TEST_MANIFEST.json").read_text())
    checks = []

    def check(ok, label):
        checks.append({"name": label, "passed": bool(ok)})
        if not ok:
            raise AssertionError(label)

    def snapshot(root):
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}

    check(manifest["suite"] == inputs["suite"], "suite binding")
    for pin in manifest["package_files"]:
        data = (PACKAGE / pin["path"]).read_bytes()
        check(len(data) == pin["bytes"] and hashlib.sha256(data).hexdigest() == pin["sha256"], "exact test package " + pin["path"])
    for name in ["prepare.py", "check_static.py"]:
        ast.parse((PACKAGE / name).read_text(), filename=name)
        check(True, "Python syntax " + name)
    preparation = (PACKAGE / "prepare.py").read_text()
    tree = ast.parse(preparation)
    imports = {n.names[0].name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import)}
    check(imports <= {"argparse", "hashlib", "json", "re"}, "preparer has no process/network/engine modules")
    check(not any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in {"exec", "eval", "compile"} for n in ast.walk(tree)), "preparer no dynamic source execution")
    driver = (PACKAGE / inputs["test_entry"]).read_text()
    check(driver.startswith("extends SceneTree\n"), "standalone SceneTree entry")
    check('preload("res://view/playable_build/player_details.gd")' in driver and 'preload("res://tests/focused/baseline_player_details.gd")' in driver, "actual candidate and exact baseline peer")
    check("FileAccess.get_sha256(path)" in driver and "FileAccess.get_file_as_bytes(path).size()" in driver, "runtime source bytes/SHA guard written")
    check("var_to_bytes(input)" in driver and "var_to_bytes(input) == frozen" in driver, "typed input nonmutation assertions written")
    check('quit(0 if failures.is_empty() else 1)' in driver and '"main_ui_visibility_verified": false' in driver, "explicit exit and honest unit boundary")
    check(not any(token in driver for token in ["main.tscn", "HTTPRequest", "OS.execute", "OS.create_process", "FileAccess.WRITE", "ResourceSaver", "seed("]), "test entry has no Main/network/save/RNG/process side effects")
    for case in manifest["coverage"]:
        check("COVERAGE: " + case in driver, "coverage source block " + case)
    if inputs["suite"] == "clock-display":
        check('Details.public_details({}, legacy)' in driver and 'Details.valid_public_details(public)' in driver, "legacy fixtures use production adapter and validator")
        check('"owner_action", "world_step", "legacy_turn"' in driver and "mixed_output == mixed_expected" in driver, "persistent clocks and mixed exact expected output")
        check("invalid_zero.status_details.rows[0].duration.remaining = 0" in driver and "invalid_damage" in driver and "Details.UNAVAILABLE" in driver, "invalid schema and unavailable fallback assertions")
    else:
        check('for kind in ["actor", "tile", "settlement"]' in driver and '[1.0, 2]' in driver and 'PackedInt32Array([1, 2])' in driver and 'missing.erase("hex")' in driver, "valid kinds and distinct invalid hex types covered")
        check('static_output == Baseline.description(static_focus)' in driver and 'passage_output == Baseline.description(passage)' in driver and 'passage_output.count("操作落脚点：(3,-1)") == 1' in driver, "static and passage original exact output assertions")
    # Validate every literal load against the actual pinned dependency graph.
    dependency_set = set(inputs["host_dependency_paths"])
    for name in sorted(dependency_set):
        data = (args.source_root / name).read_bytes()
        if name.endswith(".gd"):
            source = data.decode("utf-8")
            refs = re.findall(r'(?:preload|load)\s*\(\s*["\']res://([^"\']+)["\']\s*\)', source)
            check(set(refs) <= dependency_set and "class_name " not in source and source.startswith("extends RefCounted\n"), "actual RefCounted dependency closure " + name)
    check('"res://data/catalog.json"' in (args.source_root / "core/status_foundation/catalog.gd").read_text(), "Catalog real data path bound")
    # Exercise copy preparation and negative admissions without an engine.
    source_before = snapshot(args.source_root)
    candidate_before = snapshot(args.candidate_root)
    with tempfile.TemporaryDirectory(prefix="focused-preparation-static-") as temporary:
        work = Path(temporary)

        def prepare(name, source=args.source_root, candidate=args.candidate_root, work_root=work):
            return subprocess.run([sys.executable, str(PACKAGE / "prepare.py"), "--source-root", str(source), "--candidate-root", str(candidate), "--work-root", str(work_root), "--name", name], capture_output=True, text=True)

        success = prepare("unit-copy")
        check(success.returncode == 0, "actual Python preparation exit 0: " + success.stderr)
        receipt = json.loads(success.stdout)
        unit = work / "unit-copy"
        check(receipt["status"] == "PREPARED_NOT_PARSED_NOT_RUN" and receipt["godot_invocations"] == 0 and not receipt["main_ui_visibility_verified"], "prepared unit never claims engine/UI run")
        check(receipt["candidate_files_verified"] == 6 and receipt["source_pins_verified"] == len(inputs["source_inputs"]), "all original candidate/source pins actually verified")
        for pin in receipt["files"]:
            data = (unit / pin["path"]).read_bytes()
            check(len(data) == pin["bytes"] and hashlib.sha256(data).hexdigest() == pin["sha256"], "actual prepared readback " + pin["path"])
        original_manifest = json.loads((args.candidate_root / "MANIFEST.json").read_text())
        change = original_manifest["changed_files"][0]
        check(hashlib.sha256((unit / change["path"]).read_bytes()).hexdigest() == change["after_sha256"], "only selected candidate overlay installed")
        check((unit / inputs["baseline_peer_path"]).read_bytes() == (args.source_root / change["path"]).read_bytes(), "unchanged baseline peer installed")
        check(len([p for p in unit.rglob("*") if p.is_file()]) == len(receipt["files"]) + 2 and not (unit / "main.gd").exists() and not (unit / ".godot").exists(), "unit host exact closure; no Main or editor cache")
        before_reject = snapshot(unit)
        check(prepare("unit-copy").returncode != 0 and snapshot(unit) == before_reject, "existing output refused without mutation")
        check(prepare("../escape").returncode != 0 and not (work.parent / "escape").exists(), "traversal name refused")
        for name, root in [("source", args.source_root), ("candidate", args.candidate_root), ("package", PACKAGE)]:
            check(prepare("forbidden-copy", work_root=root).returncode != 0 and not (root / "forbidden-copy").exists(), "overlap refused " + name)
        link = work / "linked-output"
        link.symlink_to(args.source_root.resolve(), target_is_directory=True)
        check(prepare("linked-output").returncode != 0 and link.is_symlink(), "symlink output refused")
        bad_source = work / "tampered-source"
        bad_source.mkdir()
        for pin in inputs["source_inputs"]:
            target = bad_source / pin["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(args.source_root / pin["path"], target)
        target = bad_source / "core/status_foundation/canonical.gd"
        target.write_bytes(target.read_bytes() + b"# tampered\n")
        separate = work / "separate"
        separate.mkdir()
        check(prepare("bad-input", source=bad_source, work_root=separate).returncode != 0 and not (separate / "bad-input").exists(), "tampered source refused before output creation")
        target.unlink()
        target.symlink_to((args.source_root / "core/status_foundation/canonical.gd").resolve())
        check(prepare("symlink-input", source=bad_source, work_root=separate).returncode != 0 and not (separate / "symlink-input").exists(), "symlink source refused before output creation")
        bad_candidate = work / "tampered-candidate"
        shutil.copytree(args.candidate_root, bad_candidate)
        target = bad_candidate / inputs["overlay_path"]
        target.write_bytes(target.read_bytes() + b"# wrong candidate\n")
        check(prepare("wrong-overlay", candidate=bad_candidate, work_root=separate).returncode != 0 and not (separate / "wrong-overlay").exists(), "wrong candidate refused before output creation")
    check(snapshot(args.source_root) == source_before and snapshot(args.candidate_root) == candidate_before, "source and published candidate unchanged after all replays")
    print(json.dumps({"status": "PASSED_STATIC_AND_PYTHON_PREPARATION_ONLY", "suite": inputs["suite"], "count": len(checks), "checks": checks, "gdscript_parse": "NOT_RUN", "godot_invocations": 0, "unit_runtime": "NOT_RUN", "main_ui_visibility_verified": False, "publication": "NOT_UPLOADED"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
