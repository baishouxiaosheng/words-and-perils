#!/usr/bin/env python3
"""Fail closed before adoption if any serialized vegetation recipe pin differs.
Small source-only gate: no world payloads or historical ZIPs are read.
The native catalog/save gates remain required; this is an early dependency check.
"""
from pathlib import Path
import argparse,hashlib,json,re,sys
ap=argparse.ArgumentParser();ap.add_argument('project',type=Path);ap.add_argument('--out',type=Path);args=ap.parse_args()
source=args.project/'core/generated_v3_vegetation/assets.gd';text=source.read_text();m=re.search(r'^const PINS=(\{[^\n]+\})$',text,re.M)
if not m:raise SystemExit('Unrecognized serialized asset pin declaration; require native contract review')
pins=json.loads(m.group(1));rows=[]
for path,expected in pins.items():
 if not path.startswith('res://') or '..' in Path(path[6:]).parts or not re.fullmatch(r'[0-9a-f]{64}',expected):raise SystemExit('Unsafe pin schema')
 p=args.project/path[6:];actual=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None;rows.append({'path':path,'expected':expected,'actual':actual,'passed':expected==actual})
result={'scope':'exact production vegetation recipe/source/material/license pins before generated profile admission','passed':all(x['passed'] for x in rows),'pins':rows,'save_contract_unchanged_required':True}
if args.out:args.out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result));raise SystemExit(0 if result['passed'] else 1)
