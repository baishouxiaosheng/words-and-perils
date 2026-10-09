from pathlib import Path
import shutil,re,json,hashlib,argparse
parser=argparse.ArgumentParser(description='Prepare an isolated, instrumented Linux profiling copy; production bytes stay untouched.')
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--destination',type=Path,required=True)
args=parser.parse_args();src=args.source.resolve();dst=args.destination.resolve()
if not (src/'project.godot').is_file():raise SystemExit('Source must be the game project root')
if dst.exists():raise SystemExit('Destination must be a new directory')
dst.mkdir(parents=True)
for p in src.iterdir():
    q=dst/p.name
    if q.exists() or q.is_symlink(): continue
    if p.name in ['assets','artifacts']:
        q.symlink_to(p,target_is_directory=True)
    elif p.is_dir(): shutil.copytree(p,q)
    else: shutil.copy2(p,q)
probe=dst/'tests/loading_performance';probe.mkdir(exist_ok=True)
(probe/'trace.gd').write_text('''extends RefCounted
static var rows: Array = []
static func record(label_: String, start: int, memory_before: int) -> void:
	var row := {"stage":label_,"start_us":start,"end_us":Time.get_ticks_usec(),"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"static_delta_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_before,"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))}
	rows.append(row)
	print("LOAD_STAGE ", JSON.stringify(row))
''')
wraps={
'main.gd':['make_theme','build_ui','refresh_world','new_coast_adventure','coast_bundle_available','_switch_mode','prepare_world_candidate','commit_world_candidate','prepare_seeded_adventure','prepare_inventory_adventure'],
'view/playable_build/board.gd':['_ready','_install_river','set_world'],
'view/integrated_ecology_world/world_view.gd':['show_cache','_add_chunk','_add_cover','_add_grid'],
'view/integrated_ecology_world/performance_variant/world_view66.gd':['show_cache','load_compact','enable_world_canopies','apply_clear_daylight_profile','apply_natural_shorelines','apply_faceted_mountains'],
'view/integrated_ecology_world/performance_variant/runtime_adapter.gd':['load_cache'],
'view/integrated_ecology_world/natural_shorelines/shore_layer.gd':['install','_load_source_topology','_load_canopy_bindings'],
'view/integrated_ecology_world/faceted_mountains/mountain_layer.gd':['load_cache'],
'view/hex_board.gd':['set_world','build_terrain'],
'view/generated_adventure/board.gd':['set_world'],
'view/generated_adventure/seeded_adapter.gd':['start_seeded','load_file'],
'view/generated_adventure/source.gd':['admit'],
}
for rel,names in wraps.items():
 p=dst/rel
 if not p.exists(): continue
 text=p.read_text(); suffix=re.sub(r'[^a-zA-Z0-9]','_',rel)
 for name in names:
  rx=r'^(static )?func '+re.escape(name)+r'\(([^\n]*)\)\s*(->\s*[^:\n]+)?\s*:\s*([^\n]*)$'
  m=re.search(rx,text,re.M)
  if not m: print('SKIP',rel,name);continue
  args=m[2]; argnames=[]
  # Only listed methods with no comma-containing defaults are used.
  for arg in args.split(','):
   if arg.strip():argnames.append(arg.strip().split(':')[0].split('=')[0].strip())
  newname='_load_probe_'+suffix+'_'+name
  signature=m[0].split(':',1)[0] if False else (m[1] or '')+'func '+name+'('+args+')'+(m[3] or '')+':'
  oldline=m[0].replace('func '+name+'(', 'func '+newname+'(',1)
  ret=bool(m[3] and 'void' not in m[3]); result='var _perf_result = ' if ret else ''
  wrapper=signature+'\n\tvar started := Time.get_ticks_usec()\n\tvar memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))\n\t'+result+newname+'('+','.join(argnames)+')\n\tpreload("res://tests/loading_performance/trace.gd").record("'+rel+':'+name+'",started,memory_before)\n'+('\treturn _perf_result\n' if ret else '')+'\n'
  text=text[:m.start()]+wrapper+oldline+text[m.end():]
 p.write_text(text)
# The stock QA screenshot is excluded equally from all measured runs, to avoid
# overwriting existing evidence and introducing framebuffer readback into idle cost.
p=dst/'main.gd';text=p.read_text().replace('if DisplayServer.get_name() != "headless" and DirAccess.dir_exists_absolute("res://artifacts"):','if false: # benchmark excludes automatic QA PNG only');p.write_text(text)
files={str(p.relative_to(src)):hashlib.sha256(p.read_bytes()).hexdigest() for p in src.rglob('*.gd') if 'artifacts' not in p.parts and 'world_generation_v3' not in p.parts}
(dst/'profile_source_hashes.json').write_text(json.dumps(files,indent=2))
