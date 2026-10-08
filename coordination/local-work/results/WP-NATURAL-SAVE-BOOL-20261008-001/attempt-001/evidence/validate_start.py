import json, re, hashlib, sys, os
from pathlib import Path
ROOT=Path(__file__).parent
PROJECT=Path(r"E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a")
PINS={"PROTOCOL.json":"209cc25f649f2ce6635012d6d6f0bdcf09526ac68d1a7dcbf907e7398a73c05a","TASK_SCHEMA.json":"ad3a3cd71adae6c38817042e06322d0aaa0092080be3c15579ccffe1b1c8e85c","TASK.json":"b3d55be9f2cdab63b650fc25d373cfd985250ac4d26335861c0768c7baabc73e"}
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def no_dups(pairs):
    out={}
    for k,v in pairs:
        if k in out: raise ValueError("duplicate JSON key")
        out[k]=v
    return out
def load(p): return json.loads(p.read_text("utf-8-sig"),object_pairs_hook=no_dups,parse_constant=lambda x: (_ for _ in ()).throw(ValueError("nonfinite number")))
def dump(name,data): (ROOT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n","utf-8")
def path_ok(s):
    if not isinstance(s,str) or not s or re.search(r"[\x00-\x1f\x7f\\:]",s) or s.startswith("/"): return False
    parts=s.split("/")
    return all(p not in ("",".","..") and p.lower() not in (".git",".github","readme","readme.md") for p in parts)
def validate(v,s,top):
    if "$ref" in s:
        dest=top
        for k in s["$ref"][2:].split("/"): dest=dest[k]
        return validate(v,dest,top)
    if "oneOf" in s:
        ok=0
        for child in s["oneOf"]:
            try:validate(v,child,top);ok+=1
            except (ValueError,AssertionError):pass
        assert ok==1
    if "const" in s: assert v==s["const"]
    if "enum" in s: assert v in s["enum"]
    t=s.get("type")
    if t=="object":
        assert isinstance(v,dict)
        for k in s.get("required",[]): assert k in v,k
        props=s.get("properties",{})
        for k,x in v.items():
            if k in props: validate(x,props[k],top)
            elif s.get("additionalProperties") is False: raise ValueError("unknown key "+k)
            elif isinstance(s.get("additionalProperties"),dict): validate(x,s["additionalProperties"],top)
    if t=="array":
        assert isinstance(v,list) and len(v)>=s.get("minItems",0)
        for x in v: validate(x,s.get("items",{}),top)
    if t=="string":
        assert isinstance(v,str) and len(v)>=s.get("minLength",0)
        if "pattern" in s: assert re.search(s["pattern"],v),v
    if t=="integer": assert type(v) is int and v>=s.get("minimum",-float("inf"))
    if t=="boolean": assert type(v) is bool
for n,h in PINS.items(): assert sha(ROOT/n)==h,n
task=load(ROOT/"TASK.json"); schema=load(ROOT/"TASK_SCHEMA.json");validate(task,schema,schema)
assert task["task_id"]=="WP-NATURAL-SAVE-BOOL-20261008-001"
assert task["base_commit"]=="4644948268784506165ce1152215716ddf8d2854"
assert task["publication"]["result_root"]=="coordination/local-work/results/"+task["task_id"]
assert task["candidate_root"]=="candidates/t03-natural-write-result/wp-natural-save-bool-20261008-001"
for p in [task["candidate_root"],task["publication"]["result_root"]]+task["allowed_production_changes"]+[x.rstrip("/") for x in task["allowed_test_changes"]]: assert path_ok(p),p
assert task["allowed_production_changes"]==["view/generated_natural_coast_basic/adapter.gd"]
assert task["allowed_test_changes"]==["tests/t03_natural_write_result/"]
ctrl=load(ROOT/"CONTROL.json")
assert set(ctrl)=={"protocol","kind","queue_enabled","stop","resume_generation","reason"}
assert ctrl["protocol"]=="words-and-perils-local-work/v1" and ctrl["kind"]=="control"
assert type(ctrl["queue_enabled"]) is bool and ctrl["queue_enabled"] and type(ctrl["stop"]) is bool and not ctrl["stop"]
assert type(ctrl["resume_generation"]) is int and ctrl["resume_generation"]>=0 and isinstance(ctrl["reason"],str)
fixed=PROJECT/"evidence/local-dev-20261008-sol-a1b40/natural-test-type-fix/overlay/tests/natural_coast_basic/test_adapter.gd"
input_rows=[]
for x in task["inputs"]:
    assert path_ok(x["repository_path"])
    p=PROJECT/"public-input"/x["repository_path"]
    if not p.is_file() and x["sha256"]=="60e46a3b5b607d3ba5cbe3634ebcd6bd3ebbfc98fa10d4bad8732ea95b5a0ba2":p=fixed
    b=p.read_bytes()
    blob=hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()
    assert sha(p)==x["sha256"] and len(b)==x["bytes"] and blob==x["git_blob_sha"],x["repository_path"]
    input_rows.append({**x,"local_path":str(p),"verified":True})
original=PROJECT/"public-candidates/natural-save-identity/project"
pins=[]
for rel,h in task["baseline_project_pins"].items():
    assert path_ok(rel)
    p=fixed if rel=="tests/natural_coast_basic/test_adapter.gd" else original/rel
    assert sha(p)==h,rel
    pins.append({"path":rel,"sha256":h,"verified":True})
old=load(PROJECT/"evidence/local-dev-20261008-sol-a1b40/DIRECTORY_INDEX_AND_HASHES.json")
all_rows=[]
prefix="public-candidates/natural-save-identity/project/"
for x in old:
    if x["path"].startswith(prefix):
        rel=x["path"][len(prefix):];p=original/rel
        assert not p.is_symlink() and not (os.lstat(p).st_file_attributes & 0x400)
        h=sha(p);assert h==x["sha256"],rel
        all_rows.append({"path":rel,"sha256":h})
assert len(all_rows)==2564
archive=PROJECT/"evidence/local-dev-20261008-sol-a1b40/WordsAndPerils_Local_T03_20261008_Evidence.zip"
g=task["verification"]["guard_provenance"]
assert sha(archive)==g["archive_sha256"] and archive.stat().st_size==g["archive_bytes"]
assert hashlib.sha1(b"blob "+str(archive.stat().st_size).encode()+b"\0"+archive.read_bytes()).hexdigest()==g["archive_git_blob_sha"]
for leaf,h in [("WindowsGuard.cs",g["guard_source_sha256"]),("Invoke-WindowsGuard.ps1",g["guard_wrapper_sha256"])]:
    assert sha(PROJECT/"windows-guard-v3"/leaf)==h
dump("INPUT_VERIFICATION.json",{"task_valid":True,"control_valid_enabled":True,"input_rows":input_rows,"project_pins":pins,"all_original_natural_files":len(all_rows),"all_original_hashes_match":True,"archive_and_guard_hashes_verified":True,"baseline_source":"existing exact restored public-v30 plus separate Natural identity; no restorer rerun"})
dump("BASELINE_SOURCE_MAP.json",all_rows)
print(json.dumps({"task_valid":True,"input_pins":len(input_rows),"baseline_files":len(all_rows),"guard_pins":True}))

