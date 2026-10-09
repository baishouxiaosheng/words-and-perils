from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile
root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Read-only source/static checks, no Godot")
parser.add_argument("--restored-root", type=Path, required=True)
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
with tempfile.TemporaryDirectory(prefix="status-clock-patch-") as directory:
    target = Path(directory) / change["path"]
    target.parent.mkdir(parents=True)
    target.write_bytes(before)
    subprocess.run(["git", "apply", "--check", str(patch)], cwd=directory, check=True, capture_output=True)
    subprocess.run(["git", "apply", str(patch)], cwd=directory, check=True, capture_output=True)
    check(target.read_bytes() == after, "actual patch replay equals candidate")
    check([str(p.relative_to(directory)) for p in Path(directory).rglob("*") if p.is_file()] == [change["path"]], "patch touches only allowed file")
print(json.dumps({"status": "PASSED_STATIC_ONLY_NOT_GODOT_PARSE", "count": len(checks), "checks": checks, "changed_file_sha256": digest(after), "godot_parses": 0, "runtime_runs": 0}, indent=2))
