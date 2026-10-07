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
names=['selection-headless-summary.json','offline-headless-summary.json','selection-headless-request.json','offline-headless-request.json','final-inputs-receipt.json','guard_effective8g.py','restore-final.log','check-final.log','restore-repeat.log','check-final-terminal.log','import-summary.json','api-headless-summary.json','wasd-headless-summary.json','api-headless-request.json','wasd-headless-request.json','inputs-before-api-wasd-receipt.json','inputs-after-api-wasd-receipt.json']
items=[row(E/name) for name in names]
logs=[]
for kind in ('selection','offline','api','wasd'):
    directories=sorted(p for p in E.glob(kind+'-headless-*') if p.is_dir() and not p.is_symlink())
    if len(directories)!=1:raise ValueError('Expected one completed strict headless gate')
    directory=directories[0]
    items.append(row(directory/'report.json'))
    logs.extend([row(directory/'runtime.log',False),row(directory/'guard.jsonl',False)])
    guard=(directory/'guard.jsonl').read_bytes()
    last=guard.splitlines(keepends=True)[-1]
    items.append({'path':str((directory/'guard.jsonl').relative_to(E))+':last-line','bytes':len(last),'sha256':hashlib.sha256(last).hexdigest(),'base64':base64.b64encode(last).decode()})
for p in [E/'selection/runtime.log',E/'selection/guard.jsonl',*E.glob('selection-20*/runtime.log'),*E.glob('selection-20*/guard.jsonl'),*E.glob('import-20*/runtime.log'),*E.glob('import-20*/guard.jsonl')]:
    if p.exists():logs.append(row(p,False))
report={'schema':'words-and-perils-dot-native-all4-raw-evidence/v1','environment':'dot native cloud Linux /workspace/wap','artifact_scope':'Four original strict headless gates on this dot project, raw reports and guard tail bytes, final9/876 before API-WASD and after all four; raw logs remain native and hash-bound','limits':['API78/WASD67/selection47/offline33 ran on the same exact dot project final nine sources; headless logic only','X11 selection assertions passed with one VSync warning; GPU/OS-input acceptance is not signed','First selection/offline had full1426+953 admission and post876; new API/WASD have explicit876+9 pre and post checkpoints'],'files':items,'raw_logs':logs}
out=E/'RAW_EVIDENCE_ALL4_EXPORT.json';b=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode();out.write_bytes(b)
print('DOT_QA_EXPORT',len(b),hashlib.sha256(b).hexdigest(),out,flush=True)
