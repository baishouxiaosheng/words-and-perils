from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile, sys
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Read-only source/static checks, no Godot")
parser.add_argument("--restored-root", type=Path, required=True)
parser.add_argument("--replay-evidence-root", type=Path, help="Existing owned evidence parent; failures are retained in a new child")
args = parser.parse_args()
manifest = json.loads((root / "MANIFEST.json").read_text())
checks = []
def check(ok, label):
    checks.append({"name": label, "passed": bool(ok)})
    if not ok: raise AssertionError(label)
def digest(data): return hashlib.sha256(data).hexdigest()
for pin in manifest["input_hashes"]:
    data = (args.restored_root / pin["path"]).read_bytes()
    check(len(data) == pin["bytes"] and digest(data) == pin["sha256"], "exact source " + pin["path"])
change = manifest["changed_files"][0]
check(len(manifest["changed_files"]) == 1, "one changed production file")
before = (args.restored_root / change["path"]).read_bytes()
after = (root / change["overlay_path"]).read_bytes()
check(len(after) == change["after_bytes"] and digest(after) == change["after_sha256"], "candidate actual bytes and SHA")
check(b"\r" not in after and after.endswith(b"\n"), "UTF8/LF candidate")
def split_function(data):
    pattern = rb"(?ms)^static func focus_status_lines\(actor: Dictionary\) -> Array\[String\]:\n.*?(?=^static func )"
    match = re.search(pattern, data)
    check(match is not None, "existing function boundary")
    return data[:match.start()], data[match.start():match.end()], data[match.end():]
b0, body0, b1 = split_function(before)
a0, body1, a1 = split_function(after)
check(b0 == a0 and b1 == a1, "all other functions incl HUD and signatures byte-exact")
check(body0.splitlines()[0] == body1.splitlines()[0], "function signature unchanged")
check(b'StatusDetails.valid_public_details(details)' in body1 and b'details.duplicate(true)' in body1, "validate and deep-copy public packet before display")
check(b'row.duration.clock == "legacy_turn" and not row.duration.persistent' in body1, "bounded legacy wording only")
for source_path in ["view/actor_action_profile_v2/source.gd", "view/actor_status_profile_v1/source.gd"]:
    source = (args.restored_root / source_path).read_text()
    paths = re.findall(r'"(res://[^"\n]+)"', source)
    check("res://" + change["path"] not in paths, "UI file excluded from authority dependencies " + source_path)
patch = root / "CHANGE.patch"
git_lf = ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf"]
def retain_replay_failure(target, before, after, patch, commands, error):
    # Persistent owned diagnostic directory is separate from the auto-cleaned replay.
    parent = args.replay_evidence_root
    if parent is not None:
        parent = parent.absolute()
        if not parent.is_dir() or any(p.is_symlink() for p in (parent, *parent.parents)):
            raise ValueError("Replay evidence root must be an existing non-symlink owned directory")
    saved = Path(tempfile.mkdtemp(prefix="git-replay-failure-", dir=parent))
    actual = target.read_bytes() if target.is_file() else b""
    for name, data in [("before.gd", before), ("expected.gd", after), ("actual.gd", actual), ("CHANGE.patch", patch.read_bytes())]:
        (saved / name).write_bytes(data)
    def describe(data):
        return {"bytes": len(data), "sha256": digest(data), "CRLF": data.count(b"\r\n"), "LF": data.count(b"\n")}
    diagnostic = {"error_type": type(error).__name__, "before": describe(before), "expected": describe(after),
                  "actual": describe(actual), "actual_equals_expected": actual == after,
                  "commands": commands, "original_bytes_retained": True, "godot_invocations": 0}
    (saved / "DIAGNOSIS.json").write_text(json.dumps(diagnostic, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Replay failure evidence retained: " + str(saved), file=sys.stderr)

with tempfile.TemporaryDirectory(prefix="focused-display-patch-") as directory:
    target = Path(directory) / change["path"]
    target.parent.mkdir(parents=True)
    target.write_bytes(before)
    patch = root / "CHANGE.patch"
    commands = []
    try:
        for flags in [["--check"], []]:
            completed = subprocess.run(git_lf + ["apply"] + flags + [str(patch)],
                                       cwd=directory, capture_output=True)
            commands.append({"argv": git_lf + ["apply"] + flags + ["HASH_BOUND_PATCH"],
                             "exit_code": completed.returncode,
                             "stdout": completed.stdout.decode("utf-8", errors="replace"),
                             "stderr": completed.stderr.decode("utf-8", errors="replace")})
            completed.check_returncode()
        check(target.read_bytes() == after, "actual patch replay equals candidate")
        check([str(p.relative_to(directory)) for p in Path(directory).rglob("*") if p.is_file()] == [change["path"]],
              "patch touches only allowed file")
    except Exception as error:
        retain_replay_failure(target, before, after, patch, commands, error)
        raise

print(json.dumps({"status": "PASSED_STATIC_ONLY_NOT_GODOT_PARSE", "count": len(checks), "checks": checks, "changed_file_sha256": digest(after), "godot_parses": 0, "runtime_runs": 0}, indent=2))
