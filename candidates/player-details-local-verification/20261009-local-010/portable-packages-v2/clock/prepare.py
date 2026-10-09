"""Prepare one pinned formatter unit copy. Never invoke Godot or touch saves."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import os

PACKAGE = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def relative(value):
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or any(p in (".", "..") for p in path.parts) or "\\" in value or str(path) != value:
        raise ValueError("Unsafe relative input path")
    return path


def directory(value):
    path = Path(value).absolute()
    if any(p.is_symlink() or (p.exists() and (getattr(os.lstat(p), "st_file_attributes", 0) & 0x400)) for p in (path, *path.parents)):
        raise ValueError("Symlink directory refused")
    if not path.is_dir():
        raise ValueError("Expected existing directory")
    return path.resolve()


def overlaps(a, b):
    return a == b or a in b.parents or b in a.parents


def read_pin(root, pin):
    path = root / relative(pin["path"])
    if any(p.is_symlink() or (p.exists() and (getattr(os.lstat(p), "st_file_attributes", 0) & 0x400)) for p in (path, *path.parents)) or not path.is_file():
        raise ValueError("Missing or symlink pinned input: " + pin["path"])
    data = path.read_bytes()
    if len(data) != pin["bytes"] or digest(data) != pin["sha256"]:
        raise ValueError("Pinned input mismatch: " + pin["path"])
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--candidate-root", required=True)
    parser.add_argument("--work-root", required=True, help="Existing authorized disposable directory, separate from inputs")
    parser.add_argument("--name", required=True, help="New direct child; never overwrite an existing copy")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.name):
        raise ValueError("Unsafe output name")
    source = directory(args.source_root)
    candidate = directory(args.candidate_root)
    work = directory(args.work_root)
    if any(overlaps(work, root) for root in (source, candidate, PACKAGE)):
        raise ValueError("Disposable work root overlaps source/candidate/test package")
    output = work / args.name
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists; never overwrite or remove it")
    inputs = json.loads((PACKAGE / "INPUTS.json").read_text(encoding="utf-8"))
    test_manifest = json.loads((PACKAGE / "TEST_MANIFEST.json").read_text(encoding="utf-8"))
    if test_manifest["suite"] != inputs["suite"]:
        raise ValueError("Test suite binding mismatch")
    for pin in test_manifest["package_files"]:
        read_pin(PACKAGE, pin)
    original = {pin["path"]: read_pin(candidate, pin) for pin in inputs["candidate_files"]}
    baseline = {pin["path"]: read_pin(source, pin) for pin in inputs["source_inputs"]}
    manifest = json.loads(original["MANIFEST.json"].decode("utf-8"))
    if manifest["formal_release_commit"] != inputs["formal_release_commit"] or manifest["formal_source_map_sha256"] != inputs["formal_source_map_sha256"]:
        raise ValueError("Formal release binding mismatch")
    for pin in manifest["input_hashes"]:
        if len(baseline[pin["path"]]) != pin["bytes"] or digest(baseline[pin["path"]]) != pin["sha256"]:
            raise ValueError("Original candidate source input mismatch")
    change = manifest["changed_files"][0]
    if len(manifest["changed_files"]) != 1 or change["path"] != inputs["changed_path"] or change["overlay_path"] != inputs["overlay_path"]:
        raise ValueError("Exactly one original candidate overlay required")
    overlay = original[inputs["overlay_path"]]
    before = baseline[inputs["changed_path"]]
    if digest(before) != change["before_sha256"] or len(before) != change["before_bytes"] or digest(overlay) != change["after_sha256"] or len(overlay) != change["after_bytes"]:
        raise ValueError("Original before/after binding mismatch")
    # Copy the real literal preload/load closure, plus Catalog's fixed data path.
    # No fake dependencies, rewritten production scripts or full-world fallback.
    dependencies = inputs["host_dependency_paths"]
    for name in dependencies:
        relative(name)
        data = baseline[name]
        if name.endswith(".gd"):
            refs = re.findall(r'(?:preload|load)\s*\(\s*["\']res://([^"\']+)["\']\s*\)', data.decode("utf-8"))
            if any(ref not in dependencies for ref in refs):
                raise ValueError("Unbound script dependency")
    if b'"res://data/catalog.json"' not in baseline["core/status_foundation/catalog.gd"] or "data/catalog.json" not in dependencies:
        raise ValueError("Real catalog data dependency absent")
    staged = {name: baseline[name] for name in dependencies}
    staged[inputs["changed_path"]] = overlay
    staged[inputs["baseline_peer_path"]] = before
    staged[inputs["prepared_test_path"]] = (PACKAGE / inputs["test_entry"]).read_bytes()
    staged["tests/focused/candidate_manifest.json"] = original["MANIFEST.json"]
    user_leaf = "WPFocused-" + inputs["suite"] + "-" + digest(str(output).encode("utf-8"))[:16]
    project = ('config_version=5\n\n[application]\nconfig/name="Focused formatter unit"\n'
               'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_leaf + '"\n'
               '\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    staged["project.godot"] = project.encode("utf-8")
    binding = {"suite": inputs["suite"], "candidate_commit": inputs["candidate_commit"], "files": [{"path": name, "bytes": len(data), "sha256": digest(data)} for name, data in sorted(staged.items())]}
    staged["tests/focused/source_binding.json"] = (json.dumps(binding, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    # Admission and all input verification finish before creating the new copy.
    output.mkdir(exist_ok=False)
    for name, data in staged.items():
        path = output / relative(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("xb") as stream:
            stream.write(data)
        if path.read_bytes() != data:
            raise ValueError("Prepared file readback mismatch")
    receipt = {"status": "PREPARED_NOT_PARSED_NOT_RUN", "suite": inputs["suite"], "candidate_commit": inputs["candidate_commit"], "candidate_overlay_sha256": digest(overlay), "before_sha256": digest(before), "source_pins_verified": len(baseline), "candidate_files_verified": len(original), "host_dependencies": len(dependencies), "unit_project": str(output), "isolated_user_dir_leaf": user_leaf, "files": binding["files"], "binding_sha256": digest(staged["tests/focused/source_binding.json"]), "godot_invocations": 0, "main_ui_visibility_verified": False, "engine_argv_template": ["APPROVED_GODOT", "--headless", "--path", str(output), "--script", "res://" + inputs["prepared_test_path"]]}
    path = output / "PREPARATION_RECEIPT.json"
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
