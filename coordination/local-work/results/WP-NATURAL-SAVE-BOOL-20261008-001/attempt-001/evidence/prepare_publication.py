import json,hashlib,subprocess,sys,os,re
from pathlib import Path
R=Path(__file__).parent;G=R/"git"
def cmd(*a,**kw):
    p=subprocess.run(["git","-C",str(G),*a],capture_output=True,**kw)
    if p.returncode:raise RuntimeError(p.stderr.decode(errors="replace"))
    return p.stdout.decode().strip()
def load(p):return json.loads(p.read_text("utf-8-sig"))
def hashfile(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def safe(p):
    assert isinstance(p,str) and p and not re.search(r"[\x00-\x1f\x7f\\:]",p) and not p.startswith("/")
    assert all(x and x not in (".","..") and x.lower() not in (".git",".github","readme","readme.md") for x in p.split("/"))
plan=load(R/sys.argv[1])
head=plan["head"];assert re.fullmatch("[0-9a-f]{40}",head)
assert cmd("rev-parse","FETCH_HEAD")==head
assert not (Path(r"E:\WordsAndPerils-Tasks\.local-work-state\repo-1403552519")/"STOP").exists()
cmd("read-tree",head)
rows=[];prefix="coordination/local-work/results/WP-NATURAL-SAVE-BOOL-20261008-001/"
candidate="candidates/t03-natural-write-result/wp-natural-save-bool-20261008-001/"
for item in plan["files"]:
    dest=item["path"];safe(dest);assert dest.startswith(prefix) or dest.startswith(candidate)
    src=(R/item["local"]).resolve();assert src.is_relative_to(R.resolve()) and src.is_file() and not src.is_symlink()
    for ancestor in [src,*list(src.parents)[:len(src.relative_to(R).parts)]]:
        assert not (os.lstat(ancestor).st_file_attributes & 0x400)
    exists=cmd("ls-tree",head,"--",dest)
    assert not exists, "refuse overwrite "+dest
    h=hashfile(src)
    if "sha256" in item:assert h==item["sha256"]
    blob=cmd("hash-object","-w","--no-filters","--stdin",input=src.read_bytes())
    cmd("update-index","--add","--cacheinfo","100644",blob,dest)
    rows.append({"path":dest,"local":item["local"],"bytes":src.stat().st_size,"sha256":h,"git_blob_sha":blob})
tree=cmd("write-tree")
env=os.environ.copy()
env.update(GIT_AUTHOR_NAME="baishouxiaosheng",GIT_AUTHOR_EMAIL="128279531+baishouxiaosheng@users.noreply.github.com",GIT_COMMITTER_NAME="baishouxiaosheng",GIT_COMMITTER_EMAIL="128279531+baishouxiaosheng@users.noreply.github.com")
commit=cmd("commit-tree",tree,"-p",head,input=(plan["message"]+"\n").encode(),env=env)
diff=cmd("diff-tree","--no-commit-id","--name-status","-r",head,commit)
assert len(diff.splitlines())==len(rows) and all(x.startswith("A\t") for x in diff.splitlines())
(R/"git-hooks").mkdir(exist_ok=True)
(R/"git-hooks/EXPECTED_HEAD").write_text(head+"\n","ascii")
hook='#!/bin/sh\nexpected=$(cat "$(dirname "$0")/EXPECTED_HEAD") || exit 71\nwhile read local_ref local_oid remote_ref remote_oid; do\n  [ "$remote_ref" = "refs/heads/main" ] || exit 72\n  [ "$remote_oid" = "$expected" ] || { echo "Expected main HEAD changed; CAS refused" >&2; exit 73; }\ndone\nexit 0\n'
(R/"git-hooks/pre-push").write_text(hook,"utf-8",newline="\n")
receipt={"head":head,"tree":tree,"commit":commit,"files":rows,"single_parent":True,"force":False,"cas":"task-owned pre-push hook requires advertised remote old SHA == head; receive-pack old/new ref CAS; normal fast-forward only","message":plan["message"],"diff":diff}
(R/plan["receipt"]).write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n","utf-8")
print(json.dumps({"commit":commit,"tree":tree,"added_files":len(rows),"head":head}))

