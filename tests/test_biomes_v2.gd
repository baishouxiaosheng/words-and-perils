extends "res://tests/test_world_generator.gd"
## Canonical-only v2 verification. No render FPS / target-GPU claim.
const V2 := Generator.BIOMES_VERSION
const SEED := 726381
var diagnostics: Array = []

func _initialize() -> void:
 var showcase: Dictionary = {}
 for radius in [7, 10, 12, 16, 24]:
  for seed_value in [SEED, -91]:
   var start := Time.get_ticks_usec()
   var world := Generator.generate(seed_value, radius, {"generator_version": V2})
   var elapsed := (Time.get_ticks_usec() - start) / 1000.0
   _check(world.generator_version == V2, "explicit opt-in version")
   _validate_world(world)
   _validate_v2_fields(world)
   _validate_v2_sampler(world)
   diagnostics.append({"radius":radius,"seed":seed_value,"generation_ms":elapsed,"hash":world.content_hash,"statistics":world.statistics})
   print("V2 seed=%d r=%d cells=%d generation_ms=%.2f biomes=%s landforms=%s" % [seed_value,radius,world.hexes.size(),elapsed,str(world.statistics.biome_counts),str(world.statistics.landform_counts)])
   if radius == 12 and seed_value == SEED: showcase=world
 _check(Generator.generate(SEED,12,{"generator_version":V2}) == showcase, "v2 same seed/settings is byte-exact deterministic")
 _check(Generator.generate(SEED+1,12,{"generator_version":V2}).content_hash != showcase.content_hash, "v2 another seed changes geography")
 for version in ["macro_hex_biomes_v3","",null,2]:
  _check(Generator.generate(SEED,12,{"generator_version":version}).is_empty(), "unsupported generator option fails cleanly: "+str(version))
 _validate_showcase(showcase)
 _validate_versions_and_original()
 _validate_v2_recovery()
 _validate_v2_projection()
 _check(checks > 30000, "full v2 suite completed without silent early runtime termination")
 var report={"godot_version":Engine.get_version_info().string,"assertions":checks,"failures":failures,"measurements":diagnostics,"scope":"Canonical generator/state/sampler tests only; invariant-run generation_ms may overlap ordinary equivalence tests and is diagnostic, never renderer FPS or target-GPU evidence. Separate isolated timing is in biomes_generation_cpu_profile.json."}
 _write_json("res://tests/biomes_v2_generation_report.json",report)
 _write_json("res://tests/biomes_v2_showcase_726381_r12.json",showcase)
 for failure in failures: printerr("FAIL: "+str(failure))
 print("BIOMES V2: %d/%d passed" % [checks-failures.size(),checks])
 quit(0 if failures.is_empty() else 1)

func _validate_v2_fields(world:Dictionary) -> void:
 _check(Generator.validate_biomes_macro(world.macro_landscape).is_empty(),"complete valid quantized stored macro")
 for key in world.hexes:
  var cell:Dictionary=world.hexes[key]
  for field in ["temperature","moisture","plateau_weight"]:
   _check(Generator._quantized_number(cell[field],0,1),"v2 quantized finite normalized "+field+" "+key)
  _check(Generator._quantized_number(cell.plateau_height,0,8),"quantized cap target "+key)
  _check(cell.biome not in ["river","bridge","road"],"underlying biome survives overlays "+key)
  if cell.landform == "plateau":
   _check(cell.plateau_weight == 1.0 and not cell.plateau_region.is_empty(),"real macro cap identity "+key)
   _check(absf(float(cell.raw_elevation)-float(cell.plateau_height))<=Generator.SERIAL_QUANTUM,"raw plateau cap is truly flat "+key)
  if cell.plateau_region.is_empty():
   _check(cell.plateau_weight == 0 and cell.plateau_height == 0,"off-plateau complete zero metadata "+key)
 _check(world.statistics.biome_counts.values().reduce(func(a,b):return a+b,0)==world.hexes.size(),"biome counts cover exact board")

func _validate_v2_sampler(world:Dictionary) -> void:
 var field=Generator.create_height_field(world.seed,world.board_radius)
 _check(field.configure_visual_world(world),"sampler accepts complete stored v2")
 var max_error:=0.0
 for key in world.hexes:
  var c:Dictionary=world.hexes[key]
  var point:=Generator.hex_center(Vector2i(c.q,c.r))
  var sample:Dictionary=field.sample_visual_landscape(point)
  max_error=maxf(max_error,absf(float(sample.elevation)-float(c.elevation)))
  _check(absf(float(sample.elevation)-float(c.elevation))<=Generator.SERIAL_QUANTUM*2,"v2 conditioned center support "+key)
  _check(absf(float(sample.raw_elevation)-float(c.raw_elevation))<=Generator.SERIAL_QUANTUM,"v2 stored raw macro at center "+key)
  _check(absf(float(sample.temperature)-float(c.temperature))<=Generator.SERIAL_QUANTUM,"v2 stored continuous temperature "+key)
  _check(absf(float(sample.moisture)-float(c.moisture))<=Generator.SERIAL_QUANTUM,"v2 stored continuous moisture "+key)
  _check(sample.biome==c.biome and sample.landform==c.landform and sample.plateau_region==c.plateau_region,"sampler facts agree with canonical center "+key)
  for direction in [Vector2i(1,0),Vector2i(0,1)]:
   var other_key:=Generator.hex_key(Vector2i(c.q,c.r)+direction)
   if not world.hexes.has(other_key):continue
   var other:Dictionary=world.hexes[other_key]
   var center_b:=Generator.hex_center(Vector2i(other.q,other.r))
   var edge:=point.lerp(center_b,0.5)
   var a:float=field.sample_visual_height(edge)
   _check(a==field.sample_visual_height(Vector3(edge.x,0,edge.y)),"shared edge callers use one world-space height "+key)
   _check(absf(field.sample_visual_height(edge+Vector2(0.00001,0))-a)<0.001,"continuous macro/fill across shared edge "+key)
 var parser=JSON.new();parser.parse(JSON.stringify(world,"",true,true))
 var reloaded=Generator.create_height_field(world.seed,world.board_radius)
 _check(reloaded.configure_visual_world(parser.data),"direct JSON numeric parse configures stored sampler")
 for p in [Vector2.ZERO,Vector2(0.37,-0.23),Vector2(7.2,-4.7)]:
  _check(field.sample_visual_height(p)==reloaded.sample_visual_height(p),"stored sampler exact after JSON reload")
 var prior:float=field.sample_visual_height(Vector2.ZERO)
 var edited=world.duplicate(true);edited.macro_landscape.plateaus[0].height=1.5
 var edited_field=Generator.create_height_field(world.seed,world.board_radius)
 _check(edited_field.configure_visual_world(edited),"valid stored macro parameter edit configures sampler")
 var p:Array=edited.macro_landscape.plateaus[0].center_normalized
 var center=Vector2(p[0],p[1])*float(world.board_radius)*sqrt(3.0)
 _check(absf(float(edited_field.sample_visual_landscape(center).raw_elevation)-1.5)<0.000001,"sampler uses stored cap target rather than reseeded defaults")
 var bad=world.duplicate(true);bad.generator_version="macro_hex_biomes_v3"
 _check(not field.configure_visual_world(bad) and field.sample_visual_height(Vector2.ZERO)==prior,"unsupported sampler version cannot change active field")
 bad=world.duplicate(true);bad.macro_landscape.climate.temperature_axis=[0,0]
 _check(not field.configure_visual_world(bad) and field.sample_visual_height(Vector2.ZERO)==prior,"malformed macro cannot change active field")

func _validate_showcase(world:Dictionary) -> void:
 var components={}
 for biome in ["ocean","desert","grassland","jungle"]:
  var sizes:=_component_sizes(world,biome)
  components[biome]=sizes
  _check(not sizes.is_empty() and sizes[0]>=5,"showcase coherent "+biome+" region, not isolated labels")
 var core:Array=[];var apron:Array=[]
 for c in world.hexes.values():
  if c.landform=="plateau":core.append(c)
  elif c.landform=="slope":apron.append(c)
 _check(core.size()>=8 and apron.size()>=8,"showcase broad cap and adjoining apron")
 var cap_min:=INF;var cap_max:=-INF;var apron_min:=INF;var apron_max:=-INF;var fill_max:=0.0
 for c in core:
  cap_min=minf(cap_min,c.raw_elevation);cap_max=maxf(cap_max,c.raw_elevation);fill_max=maxf(fill_max,c.fill_depth)
 for c in apron:
  apron_min=minf(apron_min,c.raw_elevation);apron_max=maxf(apron_max,c.raw_elevation)
 _check(cap_max-cap_min<=Generator.SERIAL_QUANTUM,"plateau raw cap globally flat")
 _check(apron_max-apron_min>0.2,"apron has real sloping relief contrasting with cap")
 _check(fill_max<0.02,"showcase conditioning adds only millimetric cap drainage")
 var mouths:=0;var crossings:=0
 for edge in world.river_edges:
  if edge.mouth:
   mouths+=1
   _check(world.hexes[edge.to].ocean and not world.hexes[edge.from].ocean,"coastal river mouth joins land/sea")
 for c in world.hexes.values():
  if c.bridge:crossings+=1
 _check(mouths>0 and crossings>0,"showcase contains true river mouths and road/river bridge crossings")
 # Every showcased sea component reaches the cropped boundary, no painted lakes.
 for key in world.hexes:
  if not world.hexes[key].ocean:continue
  _check(_component_reaches_boundary(world,key,"ocean"),"showcase ocean connected to sea boundary "+key)
 diagnostics.append({"showcase_region_components":components,"plateau_raw_range":[cap_min,cap_max],"plateau_max_fill":fill_max,"apron_raw_range":[apron_min,apron_max],"mouths":mouths,"bridge_cells":crossings})

func _component_sizes(world:Dictionary,biome:String) -> Array:
 var seen={};var sizes:Array=[]
 for key in world.hexes:
  if seen.has(key) or world.hexes[key].biome!=biome:continue
  var queue:Array=[key];seen[key]=true;var index:=0
  while index<queue.size():
   var c:Dictionary=world.hexes[queue[index]];index+=1
   for direction in Generator.DIRS:
    var target:=Generator.hex_key(Vector2i(c.q,c.r)+direction)
    if world.hexes.has(target) and not seen.has(target) and world.hexes[target].biome==biome:
     seen[target]=true;queue.append(target)
  sizes.append(queue.size())
 sizes.sort();sizes.reverse();return sizes

func _component_reaches_boundary(world:Dictionary,start:String,biome:String)->bool:
 var seen={start:true};var queue:Array=[start];var index:=0
 while index<queue.size():
  var c:Dictionary=world.hexes[queue[index]];index+=1
  if Generator.hex_distance(Vector2i.ZERO,Vector2i(c.q,c.r))==world.board_radius:return true
  for direction in Generator.DIRS:
   var k:=Generator.hex_key(Vector2i(c.q,c.r)+direction)
   if world.hexes.has(k) and not seen.has(k) and world.hexes[k].biome==biome:seen[k]=true;queue.append(k)
 return false

func _validate_versions_and_original()->void:
 var original=GameState.new()
 _check(original.state.hexes.size()==61 and not original.state.has("generated_world"),"original61 never implicitly migrates")
 var expected={4:"fb628d0517f9c12f07f321f36aa74115a6fec17eb174fc102e3cd156d1454250",8:"16dbac4555c7aca002253a7eb9f41f188f1d0698f229fdd8f1a1586aac2c9342",10:"91f08eee5eae76f897c9241b76a0ce324be5d6dee30c75ff50ec664342c92207",16:"8d18be2c308fe9c887a399e40fbcf91611f440f05444b2fc7a14f819d7066c68",24:"e05751cc1e056652ace55f09e05dbf0d2b533dfc3c9011acfaa5c1f1552d0d0f"}
 for radius in expected:
  var v1:=Generator.generate(SEED,radius)
  _check(v1.generator_version==Generator.VERSION and v1.content_hash==expected[radius],"v1 recorded canonical content hash unchanged r%d"%radius)
  _check(not v1.hexes["0,0"].has("temperature") and not v1.macro_landscape.has("plateaus"),"no implicit v1 biome migration")
 var v1:=Generator.generate(SEED,7)
 var f=Generator.create_height_field(SEED,7)
 var initial:float=f.sample_visual_height(Vector2(0.23,-0.44))
 _check(f.configure_visual_world(Generator.generate(SEED,7,{"generator_version":V2})),"field may explicitly switch to v2")
 _check(f.configure_visual_world(v1),"field may explicitly return to v1")
 var reference=Generator.create_height_field(SEED,7);reference.configure_visual_world(v1)
 _check(f.sample_visual_height(Vector2(0.23,-0.44))==reference.sample_visual_height(Vector2(0.23,-0.44)),"return-to-v1 sampling restores original exact path")

func _new_v2_game():
 var generated:=Generator.generate(SEED,7,{"generator_version":V2})
 var game=GameState.new();game.state.board_radius=generated.board_radius;game.state.hexes=generated.hexes.duplicate(true);game.state.generated_world=generated.duplicate(true)
 for id in generated.actor_spawn_hexes:game.state.actors[id].hex=generated.actor_spawn_hexes[id].duplicate()
 return game

func _plan(request:Dictionary,roll:bool)->Dictionary:
 return {"schema_version":1,"action_id":request.action_id,"state_version":request.state_version,"phase":"planning","narration":"你准备观察这些地貌。","needs_roll":roll,"difficulty":9,"context":"This is provisional; no movement/effect has committed."}

func _roundtrip(game,label:String)->void:
 var path="user://biome_pending_roundtrip.json";var restored=GameState.new()
 _check(game.save_to_file(path).ok and restored.load_from_file(path).ok and restored.state==game.state,label)

func _validate_v2_recovery()->void:
 var game=_new_v2_game();var request:Dictionary=game.request("先穿过干燥高原，再观察丛林河口",Vector2i.ZERO).request
 _roundtrip(game,"v2 awaiting planning full snapshot/save survives")
 _check(game.apply_planning(_plan(request,true)).ok,"v2 accepts provisional freeform planning")
 _roundtrip(game,"v2 awaiting one die full snapshot/save survives")
 _check(game.roll_action(request.action_id,15).ok,"v2 player die accepted once")
 _roundtrip(game,"v2 awaiting resolution retains exact real die")
 var protected:Dictionary=game.state.duplicate(true)
 for field in ["temperature","moisture","plateau_weight","plateau_height"]:
  for value in [NAN,INF,-INF]:
   var unsafe=protected.duplicate(true);unsafe.hexes["0,0"][field]=value
   _check(not game._validate_state(unsafe).is_empty(),"nonfinite direct v2 "+field+" fails safely")
 for version in ["macro_hex_biomes_v3","future_macro_v2",null,3]:
  var bad=protected.duplicate(true);bad.generated_world.generator_version=version
  _reject_v2(bad,protected,game,"future/type generator version fails atomically "+str(version))
 for root in ["hexes","generated_world"]:
  for field in ["temperature","moisture","plateau_weight","plateau_height","landform","plateau_region","biome"]:
   var path:Array=[root,"0,0",field] if root=="hexes" else [root,"hexes","0,0",field]
   for value in [null,true,[],{}]:
    var bad=protected.duplicate(true);_mutate(bad,path,value);_reject_v2(bad,protected,game,"malformed v2 "+str(path)+" "+str(value))
   var absent=protected.duplicate(true);var cell=absent.hexes["0,0"] if root=="hexes" else absent.generated_world.hexes["0,0"]
   cell.erase(field);_reject_v2(absent,protected,game,"missing required v2 field "+str(path))
 for field in ["temperature","moisture","plateau_weight"]:
  for value in [-0.25,1.25,0.1,"warm"]:
   var bad=protected.duplicate(true);bad.hexes["0,0"][field]=value;_reject_v2(bad,protected,game,"out-of-range/nonquantized canonical "+field)
 var bad=protected.duplicate(true);bad.hexes["0,0"].plateau_region="unknown_plateau";_reject_v2(bad,protected,game,"unknown stable macro plateau reference")
 for field in ["climate","plateaus","coast_axis","mountain_ranges"]:
  bad=protected.duplicate(true);bad.generated_world.macro_landscape.erase(field);_reject_v2(bad,protected,game,"missing v2 macro "+field)
 for path in [["climate","temperature_axis"],["climate","moisture_gradient"],["plateaus",0,"height"],["plateaus",0,"radius_normalized"],["plateaus",0,"core_ratio"],["mountain_ranges",0,"control_points_normalized"]]:
  for value in [null,true,"bad",{},[]]:
   bad=protected.duplicate(true);_mutate(bad.generated_world.macro_landscape,path,value);_reject_v2(bad,protected,game,"malformed stored macro "+str(path))
 for path in [["climate","temperature_gradient"],["plateaus",0,"height"],["plateaus",0,"core_ratio"]]:
  for value in [0.1,INF,NAN]:
   var unsafe=protected.duplicate(true);_mutate(unsafe.generated_world.macro_landscape,path,value)
   _check(not game._validate_state(unsafe).is_empty(),"nonquantized/nonfinite macro fails safely "+str(path))
 bad=protected.duplicate(true);bad.pending_actions[request.action_id].snapshot.generated_world.generator_version="macro_hex_biomes_v3";_reject_v2(bad,protected,game,"future version in pending snapshot rejects atomically")
 # Full save cannot be replaced by any rejected v2 state.
 var path="user://biome_protected_save.json";_check(game.save_to_file(path).ok,"protected valid save created")
 var bytes=FileAccess.get_file_as_string(path);var original=game.state;game.state=bad
 _check(not game.save_to_file(path).ok and FileAccess.get_file_as_string(path)==bytes,"invalid v2 cannot overwrite existing good save")
 game.state=original
 var final={"schema_version":1,"action_id":request.action_id,"state_version":0,"phase":"resolution","narration":"你观察了地形，没有移动。","outcome":"部分信息确认，行动仍由 GM 裁定。","patches":[]}
 _check(game.commit_decision(final).ok and game.state.state_version==1,"valid final resolution commits exactly once")
 _check(game.commit_decision(final).already_committed and game.state.state_version==1,"v2 final resolution remains idempotent")
 game=_new_v2_game();request=game.request("无需检定的观察",Vector2i.ZERO).request;_check(game.apply_planning(_plan(request,false)).ok,"v2 no-roll phase retained");_roundtrip(game,"v2 no-roll pending resolution roundtrips")

func _reject_v2(bad:Dictionary,expected:Dictionary,game,label:String)->void:
 var path="user://biome_bad_recovery.json";_write_json(path,bad)
 var result:Dictionary=game.load_from_file(path)
 _check(not result.ok and game.state==expected,label+" preserves world/action/die")

func _validate_v2_projection()->void:
 var game=_new_v2_game()
 game.state["gm_campaign"]={"long_form":"user-defined details remain complete","nested":[true,null,0.375]}
 game.state.generated_world.macro_landscape.climate["gm_weather_history"]=["preserved",0.125]
 game.state.hexes["0,0"]["gm_cave"]={"description":"Exact extension"}
 game.state.generated_world.hexes["0,0"]["gm_cave"]=game.state.hexes["0,0"].gm_cave.duplicate(true)
 var request:Dictionary=game.request("在不同生态域执行任意复合意图",Vector2i.ZERO).request
 var snapshot:Dictionary=game.state.pending_actions[request.action_id].snapshot
 var before:Dictionary=game.state.duplicate(true)
 _check(request.snapshot.hexes==snapshot.hexes,"GM receives complete untruncated v2 canonical climate/landform/overlay facts")
 _check(request.snapshot.generated_world.hexes["0,0"].gm_cave==snapshot.hexes["0,0"].gm_cave,"even equivalent unknown extension retained at original cache path")
 for field in GameState.GENERATED_BIOMES_CELL_FIELDS:
  _check(not request.snapshot.generated_world.hexes["0,0"].has(field),"only equivalent recognized v2 cache field omitted "+field)
 _check(request.snapshot.generated_world.macro_landscape==snapshot.generated_world.macro_landscape,"stored complete macro climate/cap plus unknown extensions reach GM")
 _check(request.snapshot.gm_campaign==snapshot.gm_campaign,"unknown campaign extension unchanged")
 _check(request.gm_contract.geography.contains("never hardcoded"),"v2 model contract disclaims gameplay rule authority")
 _check(game.state==before,"projection never modifies full save/live action snapshot")
 game.state.generated_world.hexes["0,0"].temperature=0.375
 request=game.request("比较缓存与当前状态",Vector2i.ZERO).request
 _check(request.snapshot.generated_world.hexes["0,0"].temperature==0.375,"different recognized cache value preserved exactly")
 _roundtrip(game,"unknown fields/different finite cache value survive full v2 save")
 # A v2-named extension on v1 is unknown and must not be erased.
 var v1=Generator.generate(SEED,7);game=GameState.new();game.state.board_radius=7;game.state.hexes=v1.hexes.duplicate(true);game.state.generated_world=v1.duplicate(true)
 for id in v1.actor_spawn_hexes:game.state.actors[id].hex=v1.actor_spawn_hexes[id].duplicate()
 game.state.hexes["0,0"]["temperature"]="custom GM temperature";game.state.generated_world.hexes["0,0"]["temperature"]="custom GM temperature"
 request=game.request("旧地图的自定义温度",Vector2i.ZERO).request
 _check(request.snapshot.generated_world.hexes["0,0"].temperature=="custom GM temperature","v1 does not implicitly adopt/remove v2 fields")
 _roundtrip(game,"v1 qualitative extensions remain valid, no implicit migration")

func _mutate(value:Dictionary,path:Array,replacement:Variant)->void:
 var node:Variant=value
 for i in range(path.size()-1):node=node[path[i]]
 node[path[-1]]=replacement

func _write_json(path:String,value:Variant)->void:
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(value,"\t",true,true));file.close()
