extends SceneTree
const G=preload("res://core/world_generation_v3/generator.gd")
const Adapter=preload("res://view/generated_v3_village/adapter.gd")
const Board=preload("res://view/generated_v3_settlement/board.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
var checks:int=0
var failures:Array=[]
var evidence:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("VILLAGE_BOARD_FAIL ",label)
	return ok
func key(hex:Array) -> String:return "%d,%d"%hex
func path(graph:Dictionary,start:String,target:String) -> Array:
	var parent:Dictionary={start:""};var queue:Array=[start];var cursor:int=0
	while cursor<queue.size() and not parent.has(target):
		var current:String=queue[cursor];cursor+=1
		for next in graph.get(current,[]):
			if not parent.has(next):parent[next]=current;queue.append(next)
	if not parent.has(target):return []
	var result:Array=[];var current:String=target
	while not current.is_empty():result.push_front(Planner.hex_(current));current=parent[current]
	return result
func action(adapter:RefCounted,kind:String,focus:Dictionary) -> bool:
	for phase in ["begin","prepare_fixture","roll_once","stage","commit"]:
		var result:Dictionary=adapter.begin_intent(adapter.sample_goal(kind,focus),focus) if phase=="begin" else adapter.call(phase)
		if not result.get("ok",false):printerr("ACTION_FAIL ",kind," ",phase," ",result);return false
	return true
func rest(adapter:RefCounted) -> bool:
	var state:Dictionary=adapter.state_copy();var actor:Dictionary=state.actors.actor_player
	return action(adapter,"rest",{"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":actor.hex,"scene_id":actor.scene_id})
func ensure_move_budget(adapter:RefCounted,target:Array) -> bool:
	while not adapter.movement_preview(target).get("ok",false):
		var before:int=adapter.state_copy().actors.actor_player.stamina.current
		if not rest(adapter):return false
		if adapter.state_copy().actors.actor_player.stamina.current<=before:return false
	return true
func walk(adapter:RefCounted,board:Node3D,target:Array) -> bool:
	var route:Array=path(adapter.source.navigation.allowed,key(adapter.state_copy().actors.actor_player.hex),key(target))
	if route.is_empty():return false
	for i in range(1,route.size()):
		if not ensure_move_budget(adapter,route[i]):return false
		if not action(adapter,"move",adapter.tile_reference(route[i])):return false
		board.set_world(adapter.state_copy(),true,adapter.authoritative_result().public_effects)
		board.presentation._process(float(board.presentation.actors.actor_player.duration)+1.0)
		for item in board.inventory_packs.values():item.sync_position()
	return true
func box(raw:Dictionary) -> AABB:return AABB(Vector3(raw.min[0],raw.min[1],raw.min[2]),Vector3(raw.size[0],raw.size[1],raw.size[2]))
func opaque_pack_box(view:Node3D) -> AABB:
	var result:AABB;var found:bool=false
	for part in view.mesh_parts:
		var b:AABB=part.global_transform*part.mesh.get_aabb();result=result.merge(b) if found else b;found=true
	return result
func sample_local_approaches(adapter:RefCounted,board:Node3D,site:Array,report:Dictionary) -> Dictionary:
	var evidence_:Array=[];var total_candidates:int=0;var samples_:int=0
	for neighbor in adapter.source.navigation.allowed.get(key(site),[]):
		for route in [[Planner.hex_(neighbor),site],[site,Planner.hex_(neighbor)]]:
			var points:Array=adapter.source.navigation.route_points(route)
			if points.size()<2:return {"ok":false,"error":"admitted local edge has no route"}
			var first:Dictionary=board.token_support_pose(points[0],-16.0)
			var last:Dictionary=board.token_support_pose(points[-1],-16.0)
			points[0]=first.position;points[-1]=last.position
			for i in range(1,points.size()-1):points[i]+=Vector3(0,.12,0)
			board.presentation.set_actor_rotation("actor_player",first.rotation);board.presentation.reset_actor("actor_player",first.position)
			board.presentation.set_actor_rotation("actor_player",last.rotation);board.presentation.move_actor_path("actor_player",points,1)
			var duration_:float=board.presentation.actors.actor_player.duration;var candidates:int=0
			for i in range(41):
				board.presentation._process(duration_/40.0 if i>0 else 0.0);board.inventory_pack.sync_position()
				var bounds:AABB=opaque_pack_box(board.inventory_pack);samples_+=1
				for building in report.buildings:
					if bounds.intersects(box(building.actual_world_bounds)):candidates+=1
			total_candidates+=candidates;evidence_.append({"route":route,"samples":41,"aabb_candidates":candidates})
	# Presentation-only probes cannot rewrite the admitted state or custody.
	board.set_world(adapter.state_copy())
	return {"ok":true,"directed_approaches":evidence_,"samples":samples_,"aabb_candidates":total_candidates}
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/generated_v3_placement"))
	for recipe in G.RECIPES:
		var label:String=recipe;var raw:Dictionary=G.generate(726381,12,recipe).source;var adapter=Adapter.new(raw)
		if not check(adapter.ready().ok,label+" combined source admitted"):printerr(adapter.ready());continue
		var viewport=SubViewport.new();viewport.size=Vector2i(1280,800);root.add_child(viewport)
		var board=Board.new(adapter.source);viewport.add_child(board);board.set_world(adapter.state_copy());board.focus_player()
		if not check(board.load_error.is_empty(),label+" combined board ready"):board.queue_free();viewport.queue_free();await process_frame;continue
		var manifest:Dictionary=adapter.source.placement_result.manifest;var site:Array=manifest.settlements[0].center_hex;var entry:Array=manifest.settlements[0].entry_hex
		check(board.village_nodes.size()==5 and board.collision_subject_ids.size()==3,label+" five statics and three collision witnesses")
		check(board.item_surface==adapter.source.placement_result.surface,label+" single shared native support surface")
		check(board.inventory_packs.size()==1 and board.inventory_pack.carried,label+" original carried bundle remains present")
		var saved:String=C.bytes(adapter.save_data());var center:Vector3=adapter.source.navigation.cell_center(site)
		board.view_focus=center+Vector3(0,.3,0);board.camera.size=7.5;board.orbit_camera(0,0);board.village_view.update_lod(board.camera)
		var kinds:Dictionary={};var hit_records:Array=[]
		for building in manifest.buildings:
			var report:Dictionary=board.village_view.report();var bounds:AABB
			for row in report.buildings:
				if row.id==building.id:bounds=box(row.actual_world_bounds)
			var found:bool=false
			for fx in [.25,.5,.75]:
				for fy in [.25,.5,.75]:
					var target:Vector3=bounds.position+bounds.size*Vector3(fx,fy,.5)
					var pointer:Vector2=board.camera.unproject_position(target);var hits:Array=board.pick_focus(pointer)
					for hit in hits:
						kinds[hit.reference.kind]=true
						if hit.reference.get("id")==building.id:
							found=true;board.select_attention(hit.reference);check(board.selected_static_id==building.id,label+" static glow identity")
							hit_records.append({"id":building.id,"reference":hit.reference,"pointer":[pointer.x,pointer.y]});break
					if found:break
				if found:break
			check(found,label+" raw building is pickable "+str(building.asset_id))
		var road:Dictionary=manifest.roads[0];var road_center:Vector3=adapter.source.navigation.cell_center(entry).lerp(center,.2)
		var road_pointer:Vector2=board.camera.unproject_position(road_center+Vector3.UP*.012);var road_hits:Array=board.pick_focus(road_pointer)
		var road_found:bool=false
		for hit in road_hits:
			if hit.reference.get("id")==road.id:road_found=true;check(hit.reference.hex==entry,label+" road click keeps entry supporting hex")
			check(not (hit.reference.get("kind")=="settlement" and hit.reference.get("hex")==entry),label+" aggregate does not alias outside support")
		check(road_found,label+" raw road endpoint pick")
		check(C.bytes(adapter.save_data())==saved,label+" selection and camera never mutate authority")
		var timing_cases:Dictionary={}
		var targets:Dictionary={"road":road_pointer}
		if not hit_records.is_empty():
			var p:Array=hit_records[0].pointer;targets["building_and_aggregate"]=Vector2(p[0],p[1])
		for screen in [Vector2(250,650),Vector2(900,650),Vector2(850,150),Vector2(350,150),Vector2(620,600)]:
			for hit in board.pick_focus(screen):
				if hit.reference.kind=="tile":targets["terrain"]=screen;break
			if targets.has("terrain"):break
		for category in targets:
			var cold_start:int=Time.get_ticks_usec();board.pick_focus(targets[category]);var cold_us:int=Time.get_ticks_usec()-cold_start
			var samples_:Array=[]
			for i in range(50):
				var t0:int=Time.get_ticks_usec();board.pick_focus(targets[category]);samples_.append(Time.get_ticks_usec()-t0)
			samples_.sort();timing_cases[category]={"cold_usec":cold_us,"warm_p50_usec":samples_[25],"warm_p95_usec":samples_[47],"warm_max_usec":samples_[-1]}
			check(samples_[47]<20000,label+" "+category+" warm pointer p95 below20ms")
		var times:Array=[]
		for i in range(100):
			var point:Vector2=Vector2(210+(i*71)%850,85+(i*43)%600);var started:int=Time.get_ticks_usec();board.pick_focus(point);times.append(Time.get_ticks_usec()-started)
		times.sort();check(times[95]<20000,label+" complete combined pointer p95 below20ms")
		check(walk(adapter,board,entry),label+" real assessed actions reach clear entry")
		check(ensure_move_budget(adapter,site),label+" enough assessed rest before village entry")
		if not check(action(adapter,"move",adapter.tile_reference(site)),label+" real assessed entry move commits"):
			board.queue_free();viewport.queue_free();await process_frame;continue
		board.set_world(adapter.state_copy(),true,adapter.authoritative_result().public_effects)
		var duration:float=board.presentation.actors.actor_player.duration;var overlap_candidates:int=0;var samples:int=0
		var renderer_report:Dictionary=board.village_view.report()
		for i in range(41):
			board.presentation._process(duration/40.0 if i>0 else 0.0);board.inventory_pack.sync_position();var pack_bounds:AABB=opaque_pack_box(board.inventory_pack);samples+=1
			for building in renderer_report.buildings:
				if pack_bounds.intersects(box(building.actual_world_bounds)):overlap_candidates+=1
		check(overlap_candidates==0,label+" carried bundle clears building bounds during full entry motion")
		board.presentation._process(.001);board.inventory_pack.sync_position()
		check(C.bytes(adapter.state_copy().actors.actor_player.hex)==C.bytes(site) and not board.presentation.actors.actor_player.moving,label+" entry motion lands at same logical village")
		check(action(adapter,"drop_item",adapter.item_reference()),label+" real bundle drop at village plaza")
		board.set_world(adapter.state_copy());var pack:Node3D=board.inventory_pack
		check(pack.pack.visible and not pack.carried and pack.ground_pose.get("footprint_verified",false),label+" dropped bundle has complete dry support")
		check(not pack.overlaps_static_prop(pack.ground_pose),label+" village drop avoids registered solid buildings")
		check(action(adapter,"pickup_item",adapter.item_reference()),label+" real pickup in same village world")
		board.set_world(adapter.state_copy());check(board.inventory_pack.carried,label+" bundle returns to traveler")
		var before_approaches:String=C.bytes(adapter.save_data())
		var local_approaches:Dictionary=sample_local_approaches(adapter,board,site,renderer_report)
		check(local_approaches.ok and local_approaches.aabb_candidates==0,label+" carried bundle clears every admitted local approach in both directions")
		check(C.bytes(adapter.save_data())==before_approaches,label+" local motion probes do not mutate authority")
		var after:String=C.bytes(adapter.save_data());var loaded=Adapter.new();var loaded_result:Dictionary=loaded.load_data(JSON.parse_string(after))
		if not check(loaded_result.ok,label+" combined state and placement readmit"):
			printerr("READMIT_FAIL ",label," ",loaded_result)
			var bad=FileAccess.open("res://artifacts/generated_v3_placement/board_failed_save_"+label+".json",FileAccess.WRITE);bad.store_string(after);bad.close()
		check(C.bytes(loaded.save_data())==after,label+" exact combined action-history save roundtrip")
		check(C.safe(board.village_report()),label+" finite JSON-safe board report")
		evidence.append({"recipe":recipe,"site":site,"entry":entry,"placement_hash":manifest.placement_hash,"pointer_p95_usec":times[95],"pointer_max_usec":times[-1],"category_pointer_timing":timing_cases,"static_hits":hit_records,"local_approaches":local_approaches,"carried_motion_samples":samples,"carried_pack_building_aabb_candidates":overlap_candidates,"final_turn":adapter.state_copy().turn,"board_report":board.village_report()})
		board.queue_free();viewport.queue_free();await process_frame;await process_frame
	var f=FileAccess.open("res://artifacts/generated_v3_placement/board_report.json",FileAccess.WRITE);f.store_string(C.bytes({"checks":checks,"failures":failures,"cases":evidence}));f.close()
	print("V3 VILLAGE BOARD ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
