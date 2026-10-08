from pathlib import Path
import argparse, hashlib, json
p=argparse.ArgumentParser(description="Offline bytes/hash/text checks only; does not parse or run Godot")
p.add_argument("baseline_adapter")
p.add_argument("baseline_focused_test")
a=p.parse_args()
root=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
manifest=json.loads((root/"PACKAGE_FILES.json").read_text())
for x in manifest["files"]:
 b=(root/x["path"]).read_bytes()
 assert len(b)==x["bytes"] and sha(b)==x["sha256"],x["path"]
old=Path(a.baseline_adapter).read_bytes()
assert sha(old)=="6f9e593303a297391995329e0a5daecb477250b69944ee471247d9cca5df1bff"
new=(root/"overlay/view/generated_natural_coast_basic/adapter.gd").read_bytes()
assert old.split(b"func save_file(")[0]==new.split(b"func save_file(")[0]
marker=b"# Virtual I/O boundaries"
assert old[old.index(marker):]==new[new.index(marker):]
block=new[new.index(b"func save_file("):new.index(marker)]
assert b'path+".tmp"' not in block
assert b"DirAccess.make_dir_recursive" not in new and b"DirAccess.make_dir_absolute(path)" in new
assert b"generate_random_bytes(32)" in new
failure=block[block.index(b"if rename_error != OK:"):block.index(b'var result: Dictionary = {"ok":true')]
assert b"_remove_save_staging" not in failure and b"_cleanup" not in failure
assert b"push_error(" in block and b"cleanup_ok" in block
oldtest=Path(a.baseline_focused_test).read_bytes()
assert sha(oldtest)=="400ca10734ae4d3774f8a9aeb7c2fbb074d814144106b930f7c79fc91e843961"
newtest=(root/"overlay/tests/t03_natural_owned_staging/test_focused_write_result.gd").read_bytes()
assert oldtest.count(b"check(")==newtest.count(b"check(")
assert oldtest.count(b"run_case(adapter,")==newtest.count(b"run_case(adapter,")
print(json.dumps({"static_checks_pass":True,"godot_parses":0,"engine_runs":0}))
