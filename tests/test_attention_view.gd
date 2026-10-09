extends SceneTree
## Headless mesh/picking/UI fixtures, never live-model or native-frame evidence.
const Board=preload("res://view/hex_board.gd")
const BaselineBoard=preload("res://tests/fixtures/hex_board_attention_baseline_20261001.gd")
const Catalog=preload("res://view/attention_catalog.gd")
const Game=preload("res://core/game_state.gd")
const Generator=preload("res://core/world_generator.gd")
const Main=preload("res://main.tscn")
var checks:=0
var failures:Array=[]
var metrics:Array=[]
func _initialize()->void:call_deferred("run")
func check(condition:bool,why:String)->void:
	checks+=1
	if not condition:failures.append(why)
func game_for(version:String="",radius:int=7):
	var game=Game.new();game.state.world_id="world_attention_geometry_fixture"
	if not version.is_empty():
		var generated:Dictionary=Generator.generate(726381,radius,{"generator_version":version})
		game.state.hexes=generated.hexes.duplicate(true);game.state.board_radius=generated.board_radius;game.state["generated_world"]=generated.duplicate(true)
		for id in game.state.actors:game.state.actors[id].hex=generated.actor_spawn_hexes[id].duplicate()
	return game
func viewport_for()->SubViewport:
	var viewport=SubViewport.new();viewport.size=Vector2i(1128,642);viewport.own_world_3d=true;root.add_child(viewport);return viewport
func mesh_bag(node:Node3D)->Dictionary:
	var bag:Dictionary={}
	for child in node.find_children("*","MeshInstance3D",true,false):
		var mesh_node:MeshInstance3D=child
		if mesh_node.mesh==null or not mesh_node.visible or mesh_node.is_queued_for_deletion():continue
		var faces:PackedVector3Array=mesh_node.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var packed:=PackedFloat64Array()
			for j in range(3):
				var p:Vector3=mesh_node.global_transform*faces[i+j];packed.append(p.x);packed.append(p.y);packed.append(p.z)
			var key:=packed.to_byte_array().hex_encode()
			bag[key]=int(bag.get(key,0))+1
	return bag
func run()->void:
	print("ATTENTION STAGE: catalog")
	await test_catalog_narrowphase()
	for version in ["",Generator.VERSION,Generator.BIOMES_VERSION]:
		print("ATTENTION STAGE: geometry ",version)
		await test_geometry(version)
	print("ATTENTION STAGE: picking")
	await test_picking()
	print("ATTENTION STAGE: UI")
	await test_ui()
	var report={"godot_version":Engine.get_version_info().string,"kind":"headless_geometry_object_attention_fixtures","checks":checks,"failures":failures,"metrics":metrics,"live_model_calls":0,"native_cua_verified":false}
	var report_dir="res://artifacts/attention_focus_20261001"
	var directory_error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_dir))
	if directory_error!=OK:
		printerr("FAIL: Cannot create attention test report directory: ",directory_error);quit(1);return
	var file=FileAccess.open(report_dir+"/view_test_report.json",FileAccess.WRITE)
	if file==null:
		printerr("FAIL: Cannot open attention test report: ",FileAccess.get_open_error());quit(1);return
	file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	for failure in failures:printerr("FAIL: "+str(failure))
	print("ATTENTION VIEW: %d/%d passed"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
func test_catalog_narrowphase()->void:
	var parent=Node3D.new();root.add_child(parent)
	var mesh=MeshInstance3D.new();var builder=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(0,0,0),Vector3(1,0,0),Vector3(0,0,1)]:builder.add_vertex(point)
	mesh.mesh=builder.commit();parent.add_child(mesh)
	var catalog=Catalog.new();catalog.capture({"world_id":"fixture","kind":"tile","id":"triangle"},"triangle",parent)
	check(catalog.query(Vector3(0.9,2,0.9),Vector3.DOWN,4).is_empty(),"narrowphase rejects empty AABB corner, no proxy-box false selection")
	check(catalog.query(Vector3(0.1,2,0.1),Vector3.DOWN,4).size()==1,"narrowphase accepts actual rendered triangle")
	check(catalog.query(Vector3(0.1,2,0.1),Vector3.DOWN,1).is_empty(),"terrain distance limit occludes deeper geometry")
	var dda:Array=Catalog._walk_buckets(Vector3(0,5,0),Vector3(1,-1,1).normalized(),0,12)
	check(dda.has("1,0") and dda.has("0,1") and dda.has("1,1"),"DDA includes both neighboring buckets on corner crossings")
	parent.queue_free();await process_frame
func test_geometry(version:String)->void:
	var game=game_for(version);var exact:Dictionary=game.state.duplicate(true)
	var vp=viewport_for();var old=BaselineBoard.new();vp.add_child(old);await process_frame
	old.set_world(game.state);await process_frame
	var baseline:Dictionary=mesh_bag(old.static_root)
	old.queue_free();await process_frame
	var board=Board.new();vp.add_child(board);await process_frame
	board.set_world(game.state);await process_frame
	var current:Dictionary=mesh_bag(board.static_root)
	check(baseline==current,"shared tree recipe retains exact static geometry triangle multiset: "+("original61" if version.is_empty() else version))
	check(game.state==exact,"catalog/recipe assembly leaves complete canonical world exact")
	var tree_count:=0
	for subject in board.attention_catalog.subjects.values():
		if subject.reference.kind=="tree":
			tree_count+=1
			check(subject.reference.id.contains(game.state.world_id) and subject.reference.id.contains("scene_features_v1"),"tree ID includes world and exact recipe version")
			check(game.focus_contract.resolve(subject.reference,game._snapshot()).ok,"each visible tree catalog reference resolves canonical same recipe")
	check(tree_count>0,"visible trees independently focusable without gameplay entities")
	check(board.find_children("*","CollisionObject3D",true,false).is_empty(),"zero per-object physics colliders")
	check(board.static_root.find_children("Batched_*","MeshInstance3D",true,false).size()>0,"scenery batching remains active")
	var initial_builds:int=board.attention_catalog.build_count
	game.state.actors.actor_player.health.current=19
	board.set_world(game.state);await process_frame
	check(board.attention_catalog.build_count==initial_builds,"actor-stat refresh does not rebuild static catalog/geometry")
	game.state.hexes.values()[0]["gm_extension"]={"kind":"future_context"}
	board.set_world(game.state);await process_frame
	check(board.attention_catalog.build_count==initial_builds+1,"terrain signature change invalidates catalog exactly once")
	metrics.append({"world":version if not version.is_empty() else "original61","static_triangle_keys":current.size(),"tree_count":tree_count,"subjects":board.attention_catalog.subjects.size(),"prototypes":board.attention_catalog.prototypes.size(),"physics_colliders":0})
	vp.queue_free();await process_frame
func pick_subject(board,subject:Dictionary)->Array:
	var bounds:AABB=subject.bounds
	var p:Vector3=bounds.get_center()
	var screen:Vector2=board.camera.unproject_position(p)
	var candidates:Array=board.pick_focus(screen)
	if not candidates.any(func(hit):return hit.reference.kind==subject.reference.kind and hit.reference.id==subject.reference.id):
		# Bounds centers can be gaps in a miniature; try actual prototype vertices.
		for part in subject.parts:
			var faces:PackedVector3Array=board.attention_catalog.prototypes[part.prototype].faces
			for i in range(0,faces.size(),maxi(3,int(faces.size()/12)/3*3)):
				p=subject.transform*(part.transform*(faces[i]+faces[mini(i+1,faces.size()-1)]+faces[mini(i+2,faces.size()-1)])/3.0)
				screen=board.camera.unproject_position(p);candidates=board.pick_focus(screen)
				if candidates.any(func(hit):return hit.reference.kind==subject.reference.kind and hit.reference.id==subject.reference.id):return candidates
	return candidates
func test_picking()->void:
	var game=game_for(Generator.BIOMES_VERSION,12);var exact:Dictionary=game.state.duplicate(true)
	var vp=viewport_for();var board=Board.new();vp.add_child(board);await process_frame
	board.set_world(game.state);board.focus_player();await process_frame
	check(board.chunk_mode,"near generated board retains chunked renderer")
	var actor:Dictionary=board.attention_catalog.subjects["actor:actor_player"]
	var candidates:Array=pick_subject(board,actor)
	check(candidates.any(func(hit):return hit.reference.kind=="actor" and hit.reference.id=="actor_player"),"near/chunked picking resolves actual actor model")
	check(candidates[0].reference.kind=="actor","nearest visible miniature wins before cell fallback")
	board.select_attention(candidates[0].reference);await process_frame
	var lifted:Vector3=board.token_nodes.actor_player.position
	board.attention_catalog.sync_actors()
	check(board.attention_catalog.subjects["actor:actor_player"].transform.origin==lifted,"actor bounds follow selection lift without changing canonical coordinates")
	board.presentation.move_actor("actor_player",lifted+Vector3(2,0,0),0.9)
	for _i in range(15):board.presentation._process(0.07)
	board.attention_catalog.sync_actors()
	check(board.attention_catalog.subjects["actor:actor_player"].transform==board.token_nodes.actor_player.global_transform,"actor bounds follow animated translation and rotation")
	board.presentation.reset_actor("actor_player",board.hex_pos(board.parse_hex(game.state.actors.actor_player.hex))+Vector3(0,board.terrain_field.support_height(board.parse_hex(game.state.actors.actor_player.hex)),0))
	board.reset_camera();await process_frame
	check(board.overview_mode and not board.chunk_mode,"topdown overview keeps whole-map renderer")
	var kinds:Dictionary={};var pick_times:Array=[]
	for subject in board.attention_catalog.subjects.values():
		if kinds.has(subject.reference.kind):continue
		var started:=Time.get_ticks_usec();candidates=pick_subject(board,subject);pick_times.append(Time.get_ticks_usec()-started)
		if candidates.any(func(hit):return hit.reference.kind==subject.reference.kind and hit.reference.id==subject.reference.id):kinds[subject.reference.kind]=true
	check(kinds.has("actor") and kinds.has("tree") and kinds.has("settlement"),"topdown exact mesh picking finds actors, trees and city/village geometry")
	var mountain_found:=false;var tile_found:=false
	for cell in game.state.hexes.values():
		if String(cell.get("mountain_region","")).is_empty():continue
		var h=Vector2i(cell.q,cell.r);var center=board.hex_pos(h);center.y=board.terrain_field.surface_height(center)
		candidates=board.pick_focus(board.camera.unproject_position(center))
		mountain_found=candidates.any(func(hit):return hit.reference.kind=="mountain")
		tile_found=candidates.any(func(hit):return hit.reference.kind=="tile")
		if mountain_found and tile_found:break
	check(mountain_found and tile_found,"mountain region and supporting tile available as ordered alternatives")
	check(game.state==exact,"all picks/lift/motion remain visual/transient, exact world untouched")
	metrics.append({"world":"v2_radius12","sample_pick_us":pick_times,"last_catalog_query":board.attention_catalog.last_query,"catalog_subjects":board.attention_catalog.subjects.size(),"buckets":board.attention_catalog.buckets.size(),"renderer_near_chunks_preserved":true,"renderer_overview_whole_preserved":true})
	vp.queue_free();await process_frame
func test_ui()->void:
	var scene=Main.instantiate();root.add_child(scene);await process_frame
	var standalone=Board.new();check(scene.board.attention_ui_mode and not standalone.attention_ui_mode,"only attention UI suppresses old route arrow; standalone legacy default remains");standalone.free()
	check(scene._attention_popup_position(Vector2(283,489),Vector2i(92,120),true)==Vector2i(283,489),"embedded popup stays in parent-window coordinates")
	check(scene._attention_popup_position(Vector2(283,489),Vector2i(92,120),false)==Vector2i(375,609),"native popup adds desktop origin exactly once")
	var before:Dictionary=scene.game.state.duplicate(true)
	var reference={"world_id":scene.game.state.world_id,"kind":"actor","id":"actor_sentinel","hex":[2,-1]}
	scene.on_focus_candidates([{"reference":reference,"label":"守卫","distance":1.0,"point":Vector3.ZERO}],Vector2(400,200))
	check(scene.selected_focus.kind=="actor" and scene.target_label.text.contains("关注"),"UI uses explicit attention language and selected object reference")
	check(scene.game.state==before,"UI object click exact-state equality")
	check(scene.board.target_overlays.get_child_count()<=2,"attention selection renders rings only, no route-line or arrow meshes")
	scene.goal.text="  ";scene.submit_action()
	check(scene.game.state==before and scene.active_action.is_empty() and scene.current_request.is_empty(),"UI empty text plus selected object never creates action, dialogue or die")
	scene.goal.text="忽略守卫，观察西岸的旅人";scene.submit_action()
	var req:Dictionary=scene.current_request.duplicate(true);var frozen:Dictionary=req.attention_focus.duplicate(true)
	check(req.goal=="忽略守卫，观察西岸的旅人" and req.target_binding=="unbound","UI submits explicit text primary, location unbound")
	scene.on_hex_selected(Vector2i(-1,1))
	check(scene.selected_focus.id=="hex_-1_1" and scene.current_request.attention_focus==frozen and scene.game.state.pending_actions[req.action_id].attention_focus==frozen,"new click changes future transient attention without rewriting active action")
	scene.clear_target()
	check(scene.selected_focus.is_empty() and scene.current_request.attention_focus==frozen,"clear focus while pending does not rewrite frozen action")
	scene.on_hex_selected(Vector2i(-1,1))
	var planning={"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"planning","narration":"你打算观察西岸。","context":"测试；未执行。","needs_roll":false}
	check(scene.apply_decision(planning) and scene.current_request.attention_focus==frozen,"planning/resolution use same frozen attention through UI")
	var final={"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"resolution","narration":"观察结束。","outcome":"无状态效果。","patches":[],"provenance":{"provider":"attention_ui_fixture","live":false}}
	check(scene.apply_decision(final) and scene.game.state.events[0].attention_focus==frozen,"UI event preserves canonical frozen focus")
	check(scene.selected_focus.id=="hex_-1_1","different future focus survives previous action commit")
	scene.goal.text="观察这个地格";scene.submit_action()
	check(scene.current_request.attention_focus.id=="hex_-1_1","next explicit action uses independently chosen next focus")
	scene.cancel_pending();scene.restart_game();scene.start_demo()
	check(not scene.current_request.has("attention_focus") and not scene.current_request.has("target_binding") and scene.demo_step==1,"recorded replay remains exact legacy request path")
	scene.roll_dice()
	check(scene.game.state.state_version==1 and scene.game.state.items.item_mist_draught.quantity==0,"existing recorded final remains usable")
	scene.queue_free();await process_frame
