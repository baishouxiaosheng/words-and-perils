#!/usr/bin/env python3
"""Bounded text/path checks only. This is not a Godot or save-reload test."""
from pathlib import Path, PurePosixPath
import hashlib, json, re, subprocess, tempfile
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'CANDIDATE_MANIFEST.json').read_text())
raw=(ROOT/'payload/project.godot').read_bytes()
row=manifest['candidate_files'][0]
assert len(raw)==row['bytes']
assert hashlib.sha256(raw).hexdigest()==row['sha256']
text=raw.decode()
settings=dict(re.findall(r'^(config/[^=]+)=(.*)$',text,re.M))
assert json.loads(settings['config/name'])=='Words and Perils'
assert settings['config/use_custom_user_dir']=='true'
legacy='雾岸纪事 · AI 沙盘'
expected={'windows':'Godot/app_userdata/'+legacy,'macos':'Godot/app_userdata/'+legacy,'linux':'godot/app_userdata/'+legacy,'bsd':'godot/app_userdata/'+legacy}
checks=[]
for platform, old_relative in expected.items():
    suffix='.linuxbsd' if platform in ('linux','bsd') else ''
    new_relative=json.loads(settings['config/custom_user_dir_name'+suffix])
    assert PurePosixPath(new_relative)==PurePosixPath(old_relative)
    checks.append({'platform':platform,'documented_old_and_new_relative_paths_equal':True})
assert text.count(legacy)==2
assert not re.search(r'^config/(?:name|description|name_localized)[^=]*=.*雾岸纪事',text,re.M)
old=text.replace('config/name="Words and Perils"\n; Keep the existing desktop storage identity so saves and settings remain available.\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="Godot/app_userdata/'+legacy+'"\nconfig/custom_user_dir_name.linuxbsd="godot/app_userdata/'+legacy+'"','config/name="'+legacy+'"',1)
assert hashlib.sha256(old.encode()).hexdigest()==row['before_sha256']
with tempfile.TemporaryDirectory(prefix='word-peril-name-static-') as tmp:
    p=Path(tmp)/'project.godot'; p.write_text(old)
    patch=ROOT/'game_name.patch'
    subprocess.run(['git','apply','--check',str(patch)],cwd=tmp,check=True,capture_output=True)
    subprocess.run(['git','apply',str(patch)],cwd=tmp,check=True,capture_output=True)
    assert p.read_bytes()==raw
report={'schema':'words-and-perils-game-name-static-check/v1','status':'passed','scope':'Text integrity, exact-old SHA reconstruction, isolated patch application and documented desktop path model only','project_before_sha256':row['before_sha256'],'project_after_sha256':row['sha256'],'checks':['candidate byte count and SHA','formal display name exact','two legacy occurrences exclusively desktop compatibility identities','visible name/description free of legacy title','old configuration reconstructs exact original SHA','git apply --check and apply in temporary fixture']+checks,'native_godot':'not_run','window_title':'not_run','actual_save_reload':'not_run','data_writes':'Temporary fixture only; no real project or user data changed'}
(ROOT/'STATIC_CHECK.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
