#!/usr/bin/env python3
"""Export only this task's own small QA artifacts; raw reports stay byte-exact."""
from pathlib import Path
import base64, hashlib, json
ROOT=Path(__file__).resolve().parents[3]
E=ROOT/'artifacts/dot_native_qa_20261007'
def row(path,include=True):
    if path.is_symlink() or not path.is_file():raise ValueError('Expected owned regular QA file')
    b=path.read_bytes()
    r={'path':str(path.relative_to(E)),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
    if include:r['base64']=base64.b64encode(b).decode()
    return r
names=['selection-headless-summary.json','offline-headless-summary.json','selection-headless-request.json','offline-headless-request.json','final-inputs-receipt.json','guard_effective8g.py','restore-final.log','check-final.log','restore-repeat.log','check-final-terminal.log','import-summary.json']
items=[row(E/name) for name in names]
logs=[]
for kind in ('selection','offline'):
    directories=sorted(E.glob(kind+'-headless-*'))
    if len(directories)!=1:raise ValueError('Expected one completed strict headless gate')
    directory=directories[0]
    items.append(row(directory/'report.json'))
    logs.extend([row(directory/'runtime.log',False),row(directory/'guard.jsonl',False)])
    guard=(directory/'guard.jsonl').read_bytes()
    last=guard.splitlines(keepends=True)[-1]
    items.append({'path':str((directory/'guard.jsonl').relative_to(E))+':last-line','bytes':len(last),'sha256':hashlib.sha256(last).hexdigest(),'base64':base64.b64encode(last).decode()})
for p in [E/'selection/runtime.log',E/'selection/guard.jsonl',*E.glob('selection-20*/runtime.log'),*E.glob('selection-20*/guard.jsonl'),*E.glob('import-20*/runtime.log'),*E.glob('import-20*/guard.jsonl')]:
    if p.exists():logs.append(row(p,False))
report={'schema':'words-and-perils-dot-native-raw-evidence/v1','environment':'dot native cloud Linux /workspace/wap','artifact_scope':'Own final two headless gates, original reports and guard tail bytes, exact final9/876 post-gate check and restore records; raw logs remain native and are hash-bound','limits':['Only selection47/offline33 were rerun here; prior API78/WASD67 are a different QA environment','X11 selection assertions passed with one VSync warning; GPU/OS-input acceptance is not signed','New dot 876 check was post-gate only; before-gate full restore checked final1426 and binary953'],'files':items,'raw_logs':logs}
out=E/'RAW_EVIDENCE_EXPORT.json';b=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode();out.write_bytes(b)
print('DOT_QA_EXPORT',len(b),hashlib.sha256(b).hexdigest(),out,flush=True)
