"""Read-only exact composition and LF Git replay checks; never invokes Godot."""
import argparse,hashlib,json,re,subprocess,tempfile
from pathlib import Path

def digest(data):
    return hashlib.sha256(data).hexdigest()

def validate(root, source):
    checks=[]
    def check(ok,label):
        checks.append(dict(name=label,passed=bool(ok)))
        if not ok:
            raise AssertionError(label)
    manifest=json.loads((root/'MANIFEST.json').read_bytes())
    frozen={}
    for pin in manifest['input_hashes']:
        data=(source/pin['path']).read_bytes()
        check(len(data)==pin['bytes'] and digest(data)==pin['sha256'],'exact immutable input '+pin['path'])
        frozen[pin['path']]=data
    check(manifest['source_commit']=='c5b42ea26115e72047e2a715dcc2960d7642eb14','fixed original source commit')
    check(len(manifest['changed_files'])==1,'one changed production file')
    change=manifest['changed_files'][0]
    check(change['path']=='view/playable_build/player_details.gd','only allowed view file')
    base=frozen[change['path']]
    combo=(root/change['overlay_path']).read_bytes()
    clock=(root/'inputs/clock_player_details.gd').read_bytes()
    location=(root/'inputs/location_player_details.gd').read_bytes()
    check(digest(base)==change['before_sha256'] and len(base)==change['before_bytes'],'exact formal baseline')
    check(digest(combo)==change['after_sha256'] and len(combo)==change['after_bytes'],'exact combined candidate')
    check(digest(clock)=='8f6f69b236aa1701e43dc809433f68c0fe158ccbdccc1b46dcc4e3751e12f88c','fixed clock candidate')
    check(digest(location)=='28ef19c291e3a9d7a0468dcb21024e155cbb91c9c625e3078e56513c7daeaba5','fixed location candidate')
    check(b'\r' not in combo and combo.endswith(b'\n'),'UTF8 LF output')
    combo.decode('utf-8')
    pattern=rb'(?ms)^static func focus_status_lines\(actor: Dictionary\) -> Array\[String\]:\n.*?(?=^static func )'
    blocks=[re.search(pattern,data) for data in (base,clock,location,combo)]
    check(all(blocks),'four existing function boundaries')
    b,c,l,m=blocks
    check(clock[:c.start()]==base[:b.start()] and clock[c.end():]==base[b.end():],'clock has only its original function change')
    check(l.group()==b.group(),'location preserves original status function')
    check(m.group()==c.group(),'combined preserves whole original clock function')
    addition=b'\tvar hex: Variant = focus.get("hex")\n\tif focus.kind != "passage_edge" and hex is Array and hex.size() == 2 and hex[0] is int and hex[1] is int:\n\t\tlines.append("'+'选中地格：（%d，%d）'.encode()+b'" % [hex[0], hex[1]])\n'
    check(location.count(addition)==1 and location.replace(addition,b'')==base,'location exactly its original coordinate insertion')
    check(combo.count(addition)==1 and combo.replace(addition,b'')==clock,'remove coordinate yields exact clock-only candidate')
    check(combo[:m.start()]+b.group()+combo[m.end():]==location,'restore status function yields exact location-only candidate')
    check(combo.index(addition)>combo.index(b'\t\treturn "\\n".join(lines)'),'coordinate follows unchanged static early return')
    check(b'focus.kind != "passage_edge"' in addition,'dedicated passage support coordinate excluded')
    check(b'StatusDetails.valid_public_details(details)' in m.group() and b'details.duplicate(true)' in m.group(),'validated deep display copy retained')
    check(b'row.duration.clock == "legacy_turn" and not row.duration.persistent' in m.group(),'only finite legacy wording changes')
    for path in ('view/actor_status_profile_v1/source.gd','view/actor_action_profile_v2/source.gd'):
        refs=re.findall(rb'"(res://[^"\n]+)"',frozen[path])
        check(b'res://view/playable_build/player_details.gd' not in refs,'view remains outside authority dependencies '+path)
    testroot=root/'focused-tests'
    testmanifest=json.loads((testroot/'TEST_MANIFEST.json').read_bytes())
    test=(testroot/testmanifest['test_entry']).read_bytes()
    for coverage in testmanifest['coverage'][1:]:
        check(('# COVERAGE: '+coverage).encode() in test,'authored focused regression '+coverage)
    check(b'ClockOnly.description(input)' in test and b'LocationOnly.description(input)' in test,'independent original candidates used as comparison oracles')
    check(b'var_to_bytes(input) == frozen' in test and b'output.count(NOTE) == 1' in test,'full input immutability and single note checks authored')
    for pin in testmanifest['package_files']:
        data=(testroot/pin['path']).read_bytes()
        check(len(data)==pin['bytes'] and digest(data)==pin['sha256'],'test package pin '+pin['path'])
    # Reuse the existing command-local LF replay, without repository/global config.
    with tempfile.TemporaryDirectory(prefix='player-details-combined-replay-') as tmp:
        target=Path(tmp)/change['path'];target.parent.mkdir(parents=True);target.write_bytes(base)
        for flags in (['--check'],[]):
            result=subprocess.run(['git','-c','core.autocrlf=false','-c','core.eol=lf','apply',*flags,str((root/'CHANGE.patch').resolve())],cwd=tmp,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            check(result.returncode==0 and not result.stderr,'actual Git patch '+('check' if flags else 'apply'))
        check(target.read_bytes()==combo,'actual patch replay byte-exact combined output')
        check([p.relative_to(tmp).as_posix() for p in Path(tmp).rglob('*') if p.is_file()]==[change['path']],'strict one-file replay allowlist')
    check(all((source/name).read_bytes()==data for name,data in frozen.items()),'all original source inputs unchanged after checks')
    return dict(status='PASSED_STATIC_ONLY_NOT_GODOT_PARSE',count=len(checks),checks=checks,combined_overlay_sha256=digest(combo),godot_invocations=0,single_item_runtime='PENDING_008_009_RESULTS',combined_runtime='NOT_RUN',main_ui_visibility='NOT_RUN',adopted=False)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--restored-root',type=Path,required=True)
    parser.add_argument('--candidate-root',type=Path,default=Path(__file__).resolve().parent)
    args=parser.parse_args()
    print(json.dumps(validate(args.candidate_root,args.restored_root),ensure_ascii=False,indent=2))
