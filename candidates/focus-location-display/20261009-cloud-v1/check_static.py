from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Read-only focus-location source checks; no Godot")
parser.add_argument("--restored-root", type=Path, required=True)
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
with tempfile.TemporaryDirectory(prefix="focus-location-patch-") as directory:
    target = Path(directory) / change["path"]
    target.parent.mkdir(parents=True)
    target.write_bytes(before)
    for flags in [["--check"], []]:
        subprocess.run(["git", "apply"] + flags + [str(root / "CHANGE.patch")],
                       cwd=directory, check=True, capture_output=True)
    check(target.read_bytes() == after, "actual patch replay equals overlay")
    check([str(p.relative_to(directory)) for p in Path(directory).rglob("*") if p.is_file()] == [change["path"]],
          "patch touches only allowed file")
print(json.dumps({"status": "PASSED_STATIC_ONLY_NOT_GODOT_PARSE", "count": len(checks),
                  "checks": checks, "overlay_sha256": sha(after), "godot_parses": 0,
                  "runtime_runs": 0}, ensure_ascii=False, indent=2))
