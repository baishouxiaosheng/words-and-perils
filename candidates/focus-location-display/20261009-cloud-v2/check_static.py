from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile, sys
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Read-only focus-location source checks; no Godot")
parser.add_argument("--restored-root", type=Path, required=True)
parser.add_argument("--replay-evidence-root", type=Path, help="Existing owned evidence parent; failures are retained in a new child")
args = parser.parse_args()
manifest = json.loads((root / "MANIFEST.json").read_text())
checks = []
def check(ok, label):
    checks.append({"name": label, "passed": bool(ok)})
    if not ok: raise AssertionError(label)
def sha(data): return hashlib.sha256(data).hexdigest()
for pin in manifest["input_hashes"]:
    data = (args.restored_root / pin["path"]).read_bytes()
    check(len(data) == pin["bytes"] and sha(data) == pin["sha256"], "exact source " + pin["path"])
check(len(manifest["changed_files"]) == 1, "one changed UI file")
change = manifest["changed_files"][0]
before = (args.restored_root / change["path"]).read_bytes()
after = (root / change["overlay_path"]).read_bytes()
check(len(after) == change["after_bytes"] and sha(after) == change["after_sha256"], "overlay exact bytes/SHA")
check(b"\r" not in after and after.endswith(b"\n"), "UTF8/LF overlay")
addition = ('\tvar hex: Variant = focus.get("hex")\n'
            '\tif focus.kind != "passage_edge" and hex is Array and hex.size() == 2 and hex[0] is int and hex[1] is int:\n'
            '\t\tlines.append("选中地格：（%d，%d）" % [hex[0], hex[1]])\n').encode()
check(after.count(addition) == 1 and after.replace(addition, b"") == before,
      "only three-line snapshot display insertion; all other code byte-exact")
check(b'\t\treturn "\\n".join(lines)\n' + addition + b'\tif focus.kind == "item":' in after,
      "static focus existing location/early return unchanged")
passage_start = b'\telif focus.kind == "passage_edge":\n'
passage_end = b'\telif focus.kind == "actor":\n'
passage_before = before.split(passage_start, 1)[1].split(passage_end, 1)[0]
passage_after = after.split(passage_start, 1)[1].split(passage_end, 1)[0]
check(b'if focus.kind != "passage_edge" and hex is Array' in addition and
      after.count("选中地格：（%d，%d）".encode()) == 1 and
      passage_after == passage_before and
      "操作落脚点：(%d,%d)".encode() in passage_after,
      "passage skips sole generic coordinates; dedicated support description byte-exact")
contract = (args.restored_root / "core/focus_contract.gd").read_text()
check('Canonical.bytes(reference.hex)!=Canonical.bytes(hex)' in contract and
      '"hex":hex,"facts":facts' in contract, "original ID/hex binding already provided")
projection = (args.restored_root / "core/ai_gm_rebuilt/model_view.gd").read_text()
check('pick(focus, ["schema_version", "world_id", "kind", "id", "hex",' in projection,
      "original public projection already retains frozen hex")
for name in ["view/actor_action_profile_v2/source.gd", "view/actor_status_profile_v1/source.gd"]:
    source = (args.restored_root / name).read_text()
    check("res://" + change["path"] not in re.findall(r'"(res://[^"\n]+)"', source),
          "UI file outside authority hash dependencies " + name)
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
        return {"bytes": len(data), "sha256": sha(data), "CRLF": data.count(b"\r\n"), "LF": data.count(b"\n")}
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
        check(target.read_bytes() == after, "actual patch replay equals overlay")
        check([str(p.relative_to(directory)) for p in Path(directory).rglob("*") if p.is_file()] == [change["path"]],
              "patch touches only allowed file")
    except Exception as error:
        retain_replay_failure(target, before, after, patch, commands, error)
        raise

print(json.dumps({"status": "PASSED_STATIC_ONLY_NOT_GODOT_PARSE", "count": len(checks),
                  "checks": checks, "overlay_sha256": sha(after), "godot_parses": 0,
                  "runtime_runs": 0}, ensure_ascii=False, indent=2))
