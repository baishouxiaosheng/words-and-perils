extends SceneTree
const Adapter = preload("res://view/generated_adventure/adapter.gd")
const Generator = preload("res://core/world_generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL "+message)
func memory(stage: String) -> void:
	var result: Dictionary={"stage":stage,"ticks_ms":Time.get_ticks_msec(),"static_bytes":OS.get_static_memory_usage(),"peak_static_bytes":OS.get_static_memory_peak_usage()}
	var output: Array=[];OS.execute("cat",PackedStringArray(["/proc/"+str(OS.get_process_id())+"/status"]),output)
	if not output.is_empty():
		for line in String(output[0]).split("\n"):
			if line.begins_with("VmRSS:") or line.begins_with("VmHWM:"):result[line.split(":")[0]]=line.split(":")[1].strip_edges()
	print("GENERATED_SCALE_MEMORY ",JSON.stringify(result))
func run() -> void:
	var args:=OS.get_cmdline_user_args();var radius:=int(args[0]) if not args.is_empty() else 12
	memory("before_source")
	var start:=Time.get_ticks_msec();var source:=Generator.generate(726381,radius,{"generator_version":Generator.BIOMES_VERSION})
	var generate_ms:=Time.get_ticks_msec()-start;memory("after_source")
	start=Time.get_ticks_msec();var adapter:=Adapter.new(source);var admit_ms:=Time.get_ticks_msec()-start
	memory("after_admission")
	check(adapter.ready().ok,"r%d source admitted"%radius)
	if not adapter.ready().ok:printerr(adapter.ready());quit(1);return
	var state:=adapter.state_copy();var biomes: Dictionary={};var landforms: Dictionary={};var dry:=0;var links:=0
	for row in state.hexes.values():
		biomes[row.biome]=true;landforms[row.landform]=true
		if not row.ground_blocked:dry+=1
	for key in adapter.source.navigation.allowed:
		for next in adapter.source.navigation.allowed[key]:
			links+=1
			check(key in adapter.source.navigation.allowed.get(next,[]),"dry edge is symmetric")
	check(state.hexes.size()==1+3*radius*(radius+1),"full map cell count")
	check(biomes.has("arid") and biomes.has("grass") and biomes.has("jungle") and biomes.has("ocean"),"desert grass jungle ocean independent source biomes")
	check(landforms.has("plateau") and landforms.has("ridge"),"independent macro plateau/ridge descriptors exist")
	var far: Array=[];var max_distance: int=-1
	for row in state.hexes.values():
		var dq: int=row.q-state.actors.actor_player.hex[0];var dr: int=row.r-state.actors.actor_player.hex[1];var distance:=maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))
		if distance>max_distance:max_distance=distance;far=[row.q,row.r]
	var focus:=adapter.tile_reference(far)
	check(adapter.begin_intent("观察这个明确选中的远处地格，但不推断任何未支持行动",focus).ok,"far focus remains bounded context")
	var request:=adapter.request();var bytes:=C.bytes(request).to_utf8_buffer().size()
	check(request.context.facts.hexes.size()<=62 and bytes<=65536,"r%d public request bounded independently of map scale"%radius)
	check(request.context.facts.hexes.has("%d,%d"%far),"exact selected remote cell included")
	check(adapter.cancel().ok,"unassessed scoped request cancels legally")
	var player: Dictionary=state.actors.actor_player;var key: String="%d,%d"%player.hex
	var next_key: String=adapter.source.navigation.allowed[key][0];var row: Dictionary=state.hexes[next_key];var target: Array=[row.q,row.r]
	focus=adapter.tile_reference(target)
	check(adapter.begin_intent(adapter.sample_goal("move",focus),focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok,"large source assessed movement locks")
	var locked:=C.bytes(adapter.save_data());var path: String="user://generated_scale_r%d.json"%radius
	check(adapter.save_file(path).ok,"large locked save")
	memory("before_restart");start=Time.get_ticks_msec()
	var restarted:=Adapter.new();check(restarted.load_file(path).ok,"large source restart verifies")
	var restart_ms:=Time.get_ticks_msec()-start;memory("after_restart")
	check(C.bytes(restarted.save_data())==locked,"large source exact pending, focus, RNG and history")
	check(restarted.stage().ok and restarted.commit().ok and restarted.state_copy().actors.actor_player.hex==target,"large source persistent move after restart")
	print("GENERATED_SCALE ",JSON.stringify({"radius":radius,"checks":checks,"failed":failures,"generate_ms":generate_ms,"admit_navigation_ms":admit_ms,"restart_ms":restart_ms,"source_bytes":C.bytes(source).to_utf8_buffer().size(),"request_bytes":bytes,"dry_anchors":dry,"directed_dry_edges":links,"biomes":biomes.keys(),"landforms":landforms.keys(),"identity":state.generated_world}))
	quit(0 if failures.is_empty() else 1)
