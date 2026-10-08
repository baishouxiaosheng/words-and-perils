#!/usr/bin/env python3
"""Prepare one disposable source-bound test copy and print its guarded command.

Does not invoke Godot or the guard. Does not change the source/candidate inputs.
"""
from pathlib import Path
import argparse, hashlib, json, re, shlex, sys

PACKAGE = Path(__file__).absolute().parent
def digest(data): return hashlib.sha256(data).hexdigest()
def no_symlink_path(path, missing_final=False):
    path = Path(path).absolute()
    if ".." in path.parts: raise ValueError("Parent traversal is not accepted")
    current = Path(path.anchor)
    for index, part in enumerate(path.parts[1:], 1):
        current = current / part
        if current.is_symlink(): raise ValueError("Symlink path component refused: " + str(current))
        if not current.exists():
            if missing_final and index == len(path.parts) - 1: return path
            raise ValueError("Missing path component: " + str(current))
    return path
def regular(path):
    path = no_symlink_path(path)
    if not path.is_file(): raise ValueError(f"Regular input required: {path}")
    return path.read_bytes()
def inside(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValueError("Input path leaves its root")
    return no_symlink_path(path)

def nonoverlapping_new_root(path, input_roots):
    work = no_symlink_path(path, missing_final=True)
    if work.exists(): raise ValueError("QA root must be a new directory")
    for input_root in input_roots:
        if work.is_relative_to(input_root) or input_root.is_relative_to(work):
            raise ValueError("QA root and input root overlap in either direction")
    return work

def prepare(args):
    pins = json.loads(regular(PACKAGE / "INPUT_PINS.json"))
    source = no_symlink_path(args.restored_root)
    candidate = no_symlink_path(args.candidate_root)
    package = no_symlink_path(PACKAGE)
    work = nonoverlapping_new_root(args.qa_root, [source, candidate, package])
    if not all(path.is_dir() for path in [source, candidate, package]): raise ValueError("Directory inputs required")
    if digest(regular(source / "main.gd")) != pins["base_main_sha256"]:
        raise ValueError("Restore the exact public-v30 Main first; repository root Main is not a valid input")
    for path, expected in pins["source_files"].items():
        if digest(regular(inside(source, path))) != expected: raise ValueError("Frozen source mismatch: " + path)
    manifest_bytes = regular(candidate / "MANIFEST.json")
    if digest(manifest_bytes) != "d703dd7bfa142fbb27a31c774b36cfffd354d283e544e980bf3da51e22e9fb9e":
        raise ValueError("Published seven-file candidate manifest changed")
    manifest = json.loads(manifest_bytes)
    for row in manifest["files"]:
        data = regular(inside(candidate, row["path"]))
        if len(data) != row["bytes"] or digest(data) != row["sha256"]: raise ValueError("Published payload changed: " + row["path"])
    allowlist_bytes = regular(PACKAGE / "RESTORED_SOURCE_ALLOWLIST.json")
    if digest(allowlist_bytes) != pins["restored_allowlist_sha256"]: raise ValueError("Fixed restored source allowlist changed")
    allowlist = json.loads(allowlist_bytes)
    source_rows = allowlist["files"]
    encoded_rows = json.dumps(source_rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if len(source_rows) != 1466 or digest(encoded_rows) != "34d1bfad7676d26d994eb4e8e06130a76cc05cb729b8b336842c571a7b85270e":
        raise ValueError("Complete formal public-v30 restored source map required")
    allowed = {}
    for row in source_rows:
        if row["path"] in allowed: raise ValueError("Duplicate source path")
        data = regular(inside(source, row["path"]))
        if len(data) != row["size"] or digest(data) != row["sha256"]: raise ValueError("Restored source mismatch: " + row["path"])
        allowed[row["path"]] = {"bytes": row["size"], "sha256": row["sha256"]}
    runtime_bytes = regular(args.runtime_pins)
    if digest(runtime_bytes) != pins["runtime_876_pinmap_sha256"]: raise ValueError("Original runtime876 pinmap changed")
    runtime = json.loads(runtime_bytes)
    if len(runtime) != 876: raise ValueError("Complete original876 resource map required")
    for path, row in runtime.items():
        data = regular(inside(source, path))
        if len(data) != row["bytes"] or digest(data) != row["sha256"]: raise ValueError("Runtime input mismatch: " + path)
        entry = {"bytes": row["bytes"], "sha256": row["sha256"]}
        if path in allowed and allowed[path] != entry: raise ValueError("Source/resource allowlists conflict: " + path)
        allowed[path] = entry
    guard = no_symlink_path(args.guard)
    if digest(regular(guard)) != pins["guard_sha256"]: raise ValueError("Exact complete reviewed guard required; no fallback")
    helper = PACKAGE / "tests/manual_receipt_display/helper.gd"
    if digest(regular(helper)) != pins["helper_sha256"]: raise ValueError("Published helper copy changed")
    project = work / "project"
    # Read/copy only the fixed formal source/resource allowlists. Unknown files
    # and links are neither traversed nor copied. Recheck bytes at copy time.
    work.mkdir(); project.mkdir()
    for path, row in sorted(allowed.items()):
        data = regular(inside(source, path))
        if len(data) != row["bytes"] or digest(data) != row["sha256"]: raise ValueError("Input changed before copy: " + path)
        target = project / path; target.parent.mkdir(parents=True, exist_ok=True)
        no_symlink_path(target, missing_final=True).write_bytes(data)
    if args.variant == "candidate":
        (project / "main.gd").write_bytes(regular(candidate / "overlay/main.gd"))
    for name in ["driver.gd", "helper.gd"]:
        target = project / "tests/manual_receipt_display" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(regular(PACKAGE / "tests/manual_receipt_display" / name))
    session = work / "session"; session.mkdir()
    env = {}
    for name in ["DATA", "CACHE", "CONFIG"]:
        path = session / name.lower(); path.mkdir(); env["XDG_" + name + "_HOME"] = str(path)
    application = re.search(r'^config/name="([^"]+)"$', regular(project / "project.godot").decode(), re.M)[1]
    env.update({"WAP_RECEIPT_PRIVATE_ROOT": str(session),
                "WAP_RECEIPT_USER_DIR": str(session / "data/godot/app_userdata" / application),
                "WAP_RECEIPT_REPORT": str(session / "result.json"),
                "WAP_RECEIPT_MAIN_SHA": pins["candidate_main_sha256"] if args.variant == "candidate" else pins["base_main_sha256"]})
    command = [sys.executable, "-B", str(guard), "--log", str(session / "guard.jsonl"),
               "--timeout", "180", "--reserve-mib", "512", "--admission-extra-mib", "1741", "--", args.godot]
    if args.headless: command.append("--headless")
    command += ["--path", str(project), "--audio-driver", "Dummy", "--script", "res://tests/manual_receipt_display/driver.gd"]
    launch = ["#!/bin/sh", "set -eu", *["export " + key + "=" + shlex.quote(value) for key, value in env.items()],
              "cd " + shlex.quote(str(project)), "exec " + shlex.join(command) + " > " + shlex.quote(str(session / "runtime.log")) + " 2>&1"]
    run_script = work / "run_prepared.sh"
    run_script.write_text("\n".join(launch) + "\n")
    plan = {"status": "prepared_only_not_run", "variant": args.variant, "runtime_resources_verified": 876,
            "restored_source_files_verified": 1466, "allowlisted_input_files_copied": len(allowed),
            "source_dependencies_verified": len(pins["source_files"]), "main_sha256": env["WAP_RECEIPT_MAIN_SHA"],
            "driver_sha256": digest(regular(PACKAGE / "tests/manual_receipt_display/driver.gd")),
            "helper_sha256": pins["helper_sha256"], "guard_sha256": pins["guard_sha256"], "command": command,
            "environment": env, "headless": args.headless, "scope": "finite real-Main narration display regression only"}
    (work / "RUN_PLAN.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n")
    print("Prepared only. Execute in the approved recovered environment: sh " + shlex.quote(str(run_script)))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--restored-root", type=Path, required=True)
    parser.add_argument("--candidate-root", type=Path, required=True)
    parser.add_argument("--qa-root", type=Path, required=True)
    parser.add_argument("--runtime-pins", type=Path, required=True)
    parser.add_argument("--guard", type=Path, required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--variant", choices=["candidate", "baseline"], default="candidate")
    parser.add_argument("--headless", action="store_true", help="Logic-only, never visual/GPU acceptance")
    prepare(parser.parse_args())
