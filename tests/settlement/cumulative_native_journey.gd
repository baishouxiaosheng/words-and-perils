extends SceneTree
## One same-main offline journey. Real renderer picking and public UI callbacks;
## no world writes, invisible teleports, synthetic AI replies or asset changes.
const Main=preload("res://main.tscn")
const SeededMain=preload("res://tests/core_gameplay/seeded_main.gd")
const Catalog=preload("res://view/playable_build/entity_catalog.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const DisplayText=preload("res://view/playable_build/display_text.gd")
const OUT="res://artifacts/settlement_20261003/cumulative_core/"
var scene
var count:=0
var failures:Array[String]=[]
var report:Dictionary={}
var initial_code:Dictionary={}
var ui_timings:Array=[]
func check(ok:bool,title:String)->void:
	count+=1
	if not ok:failures.append(title);printerr("CORE_JOURNEY_FAIL "+title)
func _initialize()->void:call_deferred("run")
func settle(frames:=8)->void:
	for i in range(frames):await process_frame
func capture(name_:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func wait_for_route()->void:
	var deadline:int=Time.get_ticks_msec()+18000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<deadline:await process_frame
	check(not scene.board.presentation.actors.actor_player.moving,"committed multi-edge animation finishes")
func sample(kind:String)->bool:
	var failures_before:int=failures.size()
	var started:int=Time.get_ticks_msec()
	print("JOURNEY_SAMPLE_BEGIN ",kind," @",started)
	var before:=C.bytes(scene.playtest.state_copy())
	var turn:int=scene.playtest.state_copy().turn
	scene.fill_coast_sample(kind)
	var filled:int=Time.get_ticks_msec()
	check(not scene.goal.text.is_empty() and not DisplayText.is_signed_sample(scene.goal.text),kind+" sample shows natural player wording")
	check(C.bytes(scene.playtest.state_copy())==before and scene.playtest.phase()=="idle",kind+" filling does not act")
	if failures.size()!=failures_before:return sample_failure(kind,"fill")
	scene.submit_button.pressed.emit()
	var submitted:int=Time.get_ticks_msec()
	check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.state_copy())==before,kind+" End Turn waits without mutation")
	if failures.size()!=failures_before:return sample_failure(kind,"submit")
	scene.playtest_fixture()
	var committed:int=Time.get_ticks_msec()
	ui_timings.append({"sample":kind,"fill_ms":filled-started,"submit_ms":submitted-filled,"assessment_commit_ms":committed-submitted,"total_ms":committed-started})
	print("JOURNEY_SAMPLE_END ",kind," ",committed-started,"ms")
	check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==turn+1,kind+" accepted assessment completes exactly one turn")
	if failures.size()!=failures_before:return sample_failure(kind,"assessment/commit")
	var after:=C.bytes(scene.playtest.state_copy());scene.complete_requested_turn()
	check(C.bytes(scene.playtest.state_copy())==after,kind+" duplicate completion leaves facts unchanged")
	return failures.size()==failures_before
func sample_failure(kind:String,step:String)->bool:
	report["stopped_at"]={"sample":kind,"step":step,"phase":scene.playtest.phase(),"status":scene.status_label.text,"request":scene.current_request}
	printerr("JOURNEY_STOP ",kind," / ",step," phase=",scene.playtest.phase()," status=",scene.status_label.text)
	return false
func mesh_bounds(mesh:Mesh)->AABB:
	var faces:PackedVector3Array=mesh.get_faces()
	if faces.is_empty():return mesh.get_aabb()
	var box:=AABB(faces[0],Vector3.ZERO)
	for vertex in faces:box=box.expand(vertex)
	return box
func tree_pick(id:String)->Dictionary:
	var entry:Dictionary=scene.board.entity_selection.rows.get(id,{})
	if entry.is_empty():return {}
	var node:MultiMeshInstance3D=entry.near
	var transform_:Transform3D=node.global_transform*entry.get("current",entry.base)
	var box:AABB=mesh_bounds(node.multimesh.mesh)
	scene.board.world_view.overview=false; scene.board.world_view.target=transform_.origin+Vector3(0,.12,0); scene.board.world_view.pitch=1.15; scene.board.world_view.yaw=.2; scene.board.world_view.distance=8; scene.board.camera.size=2.2; scene.board.world_view._update_camera()
	# Project candidate points on this actual rendered silhouette, not a cell proxy.
	for y in [.8,.6,.4,.2]:
		for x in [.5,.35,.65]:
			var point:Vector2=scene.board.camera.unproject_position(transform_*(box.position+box.size*Vector3(x,y,.5)))
			var candidates:Array=scene.board.pick_focus(point)
			if not candidates.is_empty() and candidates[0].reference.id==id:return {"point":point,"candidates":candidates}
	var faces:PackedVector3Array=node.multimesh.mesh.get_faces()
	for i in range(0,mini(faces.size(),360),3):
		var point:Vector2=scene.board.camera.unproject_position(transform_*((faces[i]+faces[i+1]+faces[i+2])/3.0))
		var candidates:Array=scene.board.pick_focus(point)
		if not candidates.is_empty() and candidates[0].reference.id==id:return {"point":point,"candidates":candidates}
	return {}
func mountain_pick()->Dictionary:
	for node in scene.board.world_view.faceted_mountains.get_children():
		if not node is MeshInstance3D or node.mesh==null:continue
		var id:String=Catalog.mountain_id(str(node.get_meta("source_region","")))
		if id.is_empty():continue
		var box:AABB=mesh_bounds(node.mesh)
		scene.board.world_view.overview=false;scene.board.world_view.target=node.global_transform*box.get_center();scene.board.world_view.pitch=1.0;scene.board.world_view.yaw=.2;scene.board.world_view.distance=18;scene.board.camera.size=maxf(6,maxf(box.size.x,box.size.z)*1.2);scene.board.world_view._update_camera()
		var faces:PackedVector3Array=node.mesh.get_faces()
		var centers:Array[Vector3]=[]
		for i in range(0,faces.size(),3):centers.append(node.global_transform*((faces[i]+faces[i+1]+faces[i+2])/3.0))
		centers.sort_custom(func(a:Vector3,b:Vector3):return a.y>b.y)
		for i in range(mini(24,centers.size())):
			var point:Vector2=scene.board.camera.unproject_position(centers[i])
			var candidates:Array=scene.board.pick_focus(point)
			if not candidates.is_empty() and candidates[0].reference.id==id:return {"point":point,"candidates":candidates}
	return {}
func collect_code(path:String, records:Dictionary)->void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	directory.list_dir_begin()
	var name_:String=directory.get_next()
	while not name_.is_empty():
		var child:String=path.path_join(name_)
		if directory.current_is_dir():collect_code(child,records)
		elif name_.get_extension() in ["gd","gdshader","tscn","tres"]:records[child]=FileAccess.get_sha256(child)
		name_=directory.get_next()
	directory.list_dir_end()
func code_signature()->Dictionary:
	var records:Dictionary={}
	for path in ["res://main.gd","res://main.tscn","res://project.godot","res://artifacts/world_bundle_20261002/manifest.json"]:records[path]=FileAccess.get_sha256(path)
	for path in ["res://core","res://view","res://shared","res://relay","res://tests/core_gameplay","res://tests/committed_action_feedback","res://tests/runtime_ai","res://tests/traversal_scene","res://tests/settlement"]:collect_code(path,records)
	return records
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	initial_code=code_signature()
	root.size=Vector2i(1920,1080)
	scene=Main.instantiate();scene.set_script(SeededMain);root.add_child(scene);await settle(12)
	check(scene.coast_mode and scene.board.load_error.is_empty(),"actual main opens verified coast")
	check(scene.board.entity_selection.ready_catalog,"real environmental picker is ready")
	var original:=C.bytes(scene.playtest.state_copy())
	var mountain:Dictionary=mountain_pick()
	check(not mountain.is_empty(),"real mountain surface resolves stable group plus supporting ground")
	if not mountain.is_empty():
		scene.on_focus_candidates(mountain.candidates,mountain.point)
		check(scene.selected_focus.kind=="mountain" and scene.target_label.text.contains("山群"),"mountain click shows player-readable group detail")
		await capture("00_mountain_selection")
	scene.board.world_view.target=scene.board.lighthouse.global_position+Vector3(0,.8,0);scene.board.camera.size=3;scene.board.world_view._update_camera()
	var lamp_point:Vector2=scene.board.camera.unproject_position(scene.board.lighthouse.lantern.global_position)
	var lamp_candidates:Array=scene.board.pick_focus(lamp_point)
	check(not lamp_candidates.is_empty() and lamp_candidates[0].reference.id==Catalog.lamp_id(),"real old lamp is selectable as its own object")
	if not lamp_candidates.is_empty():scene.on_focus_candidates(lamp_candidates,lamp_point)
	check(C.bytes(scene.playtest.state_copy())==original,"mountain and lamp inspection do not alter world")
	scene.clear_target()
	var tree_id:String=Catalog.tree_id(1148)
	var tree:Dictionary=Catalog.entity(tree_id,scene.playtest.state_copy())
	check(not tree.is_empty() and tree.hex==[-1,13],"nearby real tree owns intended route cell")
	var initial_route:Dictionary=scene.playtest.movement_preview([-1,11])
	check(initial_route.get("ok",false) and tree.hex in initial_route.get("route",[]),"original route goes through future fallen-tree cell")
	var pick:Dictionary=tree_pick(tree_id)
	check(not pick.is_empty(),"real native silhouette can be picked")
	if pick.is_empty():finish();return
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=pick.point
	scene.board._input(event)
	check(scene.selected_focus.id==tree_id and scene.selected_focus.kind=="tree","click selects actual tree entity")
	check(C.bytes(scene.playtest.state_copy())==original and scene.goal.text.is_empty() and scene.playtest.phase()=="idle","tree click never starts or invents an action")
	check(scene.target_label.text.contains("直立") and not scene.target_label.text.contains("tree:"),"selection shows readable real-tree state")
	scene.show_focus_details();await capture("01_real_tree_details");scene.focus_details_dialog.hide()
	scene.fill_coast_sample("fell")
	check(not scene.goal.text.contains("tree:") and not scene.goal.text.contains("署名"),"tree protocol ID and authoring marker hidden from input")
	scene.submit_button.pressed.emit()
	var frozen:=C.bytes(scene.current_request)
	check(scene.current_request.context.attention_focus.facts.entity.id==tree_id,"export freezes exact tree facts")
	check(C.bytes(JSON.parse_string(FileAccess.get_file_as_string(scene.playtest.COAST_REQUEST)))==C.bytes(scene.current_request),"auto-export matches current frozen request")
	scene.on_hex_selected(Vector2i(-1,11))
	check(C.bytes(scene.current_request)==frozen,"new selection cannot rewrite pending tree context")
	scene.playtest_fixture()
	var state:Dictionary=scene.playtest.state_copy()
	check(scene.playtest.phase()=="idle" and state.environment_entities.has(tree_id) and state.hexes["-1,13"].ground_blocked,"adjudicated felling atomically persists entity and ground block")
	scene._apply_focus(Catalog.make_reference(tree_id,state))
	check(scene.target_label.text.contains("已倒下") and scene.target_label.tooltip_text.contains("阻挡"),"fallen state remains inspectable")
	var entry:Dictionary=scene.board.entity_selection.rows[tree_id]
	check(not entry.get("current",entry.base).basis.is_equal_approx(entry.base.basis),"same real tree render instance visibly falls after commit")
	await capture("02_fallen_tree_blocked")
	scene.on_hex_selected(Vector2i(-1,13))
	check(not scene.movement_preview.get("ok",false) and scene.route_preview_label.text.contains("步行参考"),"blocked ground selection shows noncommitting route refusal")
	if not await sample("poison"):finish();return
	state=scene.playtest.state_copy()
	check(state.actors.actor_player.statuses.condition_poison.remaining_turns==2 and state.actors.actor_player.health.current==state.actors.actor_player.health.max,"new poison waits until next committed turn to tick")
	check(scene.hero_subtitle.text.contains("中毒"),"ongoing condition shown on hero")
	scene.show_inventory();await settle();await capture("03_condition_inventory");scene.inventory_dialog.hide()
	scene.on_hex_selected(Vector2i(-1,11))
	var detour:Dictionary=scene.movement_preview.duplicate(true)
	check(detour.get("ok",false) and not tree.hex in detour.get("route",[]) and int(detour.get("cost",0))>int(initial_route.get("cost",0)),"read-only route detours around committed fallen tree")
	check(scene.route_preview_label.visible and scene.route_preview_label.text.contains("整段1回合"),"route distance cost and one-turn scope shown before action")
	report["detour"]=detour
	scene.board.focus_player(); scene.board.camera.size=8; scene.board.world_view._update_camera()
	await capture("04_route_around_fallen_tree")
	root.size=Vector2i(1280,720);await settle();scene.apply_responsive_layout();await settle()
	var small_screen:=Rect2(0,0,1280,720)
	check(small_screen.encloses(scene.action_panel.get_global_rect()) and small_screen.encloses(scene.hero_panel.get_global_rect()),"selection route and status fit smaller viewport")
	check(not scene.action_panel.get_global_rect().intersects(scene.hero_panel.get_global_rect()),"route and condition additions preserve existing HUD separation")
	await capture("04b_route_status_1280")
	var history_open_before:bool=scene.journal_open
	if not history_open_before:scene.toggle_journal()
	await settle();scene.apply_responsive_layout();await settle()
	var feedback_area:Rect2=scene.board.committed_camera.usable_rect()
	check(feedback_area.size.x>=96 and feedback_area.size.y>=96,"compact open-history layout retains real feedback space")
	for panel in [scene.area_panel,scene.map_cluster,scene.hero_panel,scene.action_panel,scene.journal_panel]:
		check(not feedback_area.intersects(panel.get_global_rect()),"feedback space avoids visible "+str(panel.name))
	report["compact_history_feedback_rect"]=[feedback_area.position.x,feedback_area.position.y,feedback_area.size.x,feedback_area.size.y]
	if not history_open_before:scene.toggle_journal()

	root.size=Vector2i(1920,1080);await settle();scene.apply_responsive_layout();await settle()
	var before_move:Dictionary=scene.playtest.state_copy()
	if not await sample("move"):finish();return
	var before_camera_cancel:=C.bytes(scene.playtest.state_copy())
	check(scene.board.committed_camera.active,"fresh offscreen route begins ordinary bounded framing")
	if not scene.journal_open:scene.toggle_journal()
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;scene._input(escape)
	check(not scene.board.committed_camera.active and not scene.journal_open,"main Escape closes history and cancels automatic framing")
	check(C.bytes(scene.playtest.state_copy())==before_camera_cancel,"manual camera cancellation never cancels or changes committed movement")
	var track:Dictionary=scene.board.presentation.actors.actor_player
	check(track.route.size()==detour.route.size()-1,"main passes ordered committed route to per-edge animation")
	state=scene.playtest.state_copy()
	check(state.actors.actor_player.stamina.current==before_move.actors.actor_player.stamina.current-int(detour.cost),"whole route charges exact edge cost once")
	check(state.turn==before_move.turn+1 and state.actors.actor_player.statuses.condition_poison.remaining_turns==1 and state.actors.actor_player.health.current==before_move.actors.actor_player.health.current-1,"multi-edge movement advances condition exactly once")
	await wait_for_route();await capture("05_route_arrived_one_tick")
	if not await sample("rest"):finish();return
	check(not scene.playtest.state_copy().actors.actor_player.statuses.has("condition_poison"),"poison expires on its second later committed turn")
	if not await sample("flight"):finish();return
	check(scene.hero_subtitle.text.contains("飞行"),"flight has visible ongoing state")
	var prose_request:Dictionary=scene.playtest.engine.narration_request(scene.playtest.last_action)
	var prose:String="轻羽药剂的光晕缓缓散开，你检查行囊，准备继续沿岸前行。"
	var prose_before:String=C.bytes(scene.playtest.engine.save_data())
	check(scene.apply_playtest_reply({"schema_version":"ai_gm_narration/v1","action_id":prose_request.action_id,"state_version":prose_request.state_version,"context_hash":prose_request.context_hash,"narration":prose}),"optional manual narration accepted only for committed result")
	check(C.bytes(scene.playtest.engine.save_data())==prose_before,"optional prose does not alter facts dice receipts or pending phase")
	var save_before:=C.bytes(scene.playtest.state_copy())
	var history_before:Array=scene.playtest.journal_entries()
	scene.save_game();check(scene.last_save_result.get("ok",false),"save actually reports success "+str(scene.last_save_result));scene.journal.clear();scene.load_game();check(scene.last_load_result.get("ok",false),"load actually reports success "+str(scene.last_load_result))
	check(C.bytes(scene.playtest.state_copy())==save_before,"load restores exact persistent world effects inventory status and positions")
	check(scene.playtest.journal_entries()==history_before,"load rebuilds each historical turn without later-state rewriting")
	check(scene.journal.get_parsed_text().count(prose)==1 and scene.playtest.narration_entries().size()==1,"non-authoritative optional prose restores once beside authoritative history")
	check(scene.journal.get_parsed_text().contains("叙事记录 · 第") and not scene.journal.get_parsed_text().contains("非权威"),"restored narration title is natural while protocol remains separate")
	check(scene.journal.get_parsed_text().contains("树已倒下") and scene.journal.get_parsed_text().contains("毒性消退") and not scene.journal.get_parsed_text().contains("署名") and not scene.journal.get_parsed_text().contains("tree:"),"restored history contains readable consequences without protocol identifiers")
	check(scene.board.world_state==scene.playtest.state_copy(),"renderer replays same loaded authoritative facts")
	if not scene.journal_open:scene.toggle_journal()
	preserve_restart_fixture("effects")
	await capture("06_restored_effect_history")
	scene.toggle_journal()
	# Save a locked pending result and finish through the same primary action.
	scene.fill_coast_sample("observe");scene.submit_action();scene.playtest_fixture();scene.advance_playtest()
	var locked:=C.bytes(scene.playtest.action_copy())
	scene.save_game();check(scene.last_save_result.get("ok",false),"save actually reports success "+str(scene.last_save_result));scene.journal.clear();scene.load_game();check(scene.last_load_result.get("ok",false),"load actually reports success "+str(scene.last_load_result))
	check(scene.playtest.phase()=="rolled" and C.bytes(scene.playtest.action_copy())==locked,"pending result and ongoing status snapshot survive save/load exactly")
	preserve_restart_fixture("pending")
	scene.end_turn();check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().actors.actor_player.statuses.condition_flight.remaining_turns==2,"restored turn commits one flight tick")
	# Existing lamp story and long natural route remain ordinary independent journeys.
	scene.reset_playtest()
	for kind in ["move","observe","talk","rest","repair"]:
		if not await sample(kind):finish();return
	check(scene.playtest.story_complete(),"existing old-lamp story still finishes through primary UI")
	scene.reset_playtest()
	if not await sample("flight"):finish();return
	scene.on_hex_selected(Vector2i(3,8))
	check(scene.movement_preview.get("ok",false) and scene.movement_preview.cost==7,"active assessed flight makes seven-edge dry detour fit remaining budget")
	report["seven_edge_route"]=scene.movement_preview.duplicate(true)
	if not await sample("move"):finish();return
	check(scene.board.presentation.actors.actor_player.route.size()==7,"seven-edge commit preserves every animation waypoint")
	await wait_for_route();check(scene.playtest.state_copy().actors.actor_player.hex==[3,8],"seven-edge journey arrives at exact assessed destination")
	var arrival_screen:Vector2=scene.board.camera.unproject_position(scene.board.token_nodes.actor_player.global_position+Vector3(0,.7,0))
	check(scene.board.committed_camera.usable_rect().has_point(arrival_screen),"ordinary committed route keeps actual arrival inside HUD-safe view")
	check(scene.route_preview_label.text.contains("已在选中"),"arrived selection reads as current position rather than route failure")
	await capture("07_seven_edge_arrival")
	check(not scene.playtest.state_copy().has("scene_transitions"),"test interior is never silently installed into ordinary game")
	var before_framework:=C.bytes(scene.playtest.state_copy())
	scene.ask_scene_framework_test()
	check(scene.scene_test_confirm_dialog.visible and C.bytes(scene.playtest.state_copy())==before_framework,"new framework test requires explicit replacement confirmation")
	scene.scene_test_confirm_dialog.confirmed.emit();scene.scene_test_confirm_dialog.hide();await settle()
	check(scene.playtest.state_copy().has("scene_transitions") and scene.playtest.state_copy().actors.actor_player.scene_id=="scene_coast","explicit fresh framework session starts on unchanged coast")
	var supplies:Array=scene.playtest.state_copy().actors.actor_player.inventory.duplicate()
	if not await sample("enter_scene"):finish();return
	await settle()
	check(scene.playtest.state_copy().actors.actor_player.scene_id=="scene_framework_room" and scene.board.get_meta("active_scene_id")=="scene_framework_room","assessed transition swaps to registered room renderer")
	check(scene.board.tiles.size()==7 and scene.board.token_nodes.size()==1 and scene.minimap.points.size()==7,"room renderer and minimap show only seven local cells and present actors")
	check(scene.selected_focus.is_empty() and scene.map_title.text.contains("测试"),"scene change clears transient attention and labels test-only content")
	check(scene.playtest.state_copy().actors.actor_player.inventory==supplies,"owned inventory follows actor without duplication on transition")
	var before_room_overview:=C.bytes(scene.playtest.state_copy())
	for cycle in range(3):
		scene.minimap.activated.emit();await settle()
		check(scene.board.world_view.overview and scene.dialogue_hidden_for_map,"room minimap enters overview cycle "+str(cycle))
		scene.minimap.activated.emit();await settle()
		check(not scene.board.world_view.overview and not scene.dialogue_hidden_for_map,"room minimap returns to action view cycle "+str(cycle))
	check(C.bytes(scene.playtest.state_copy())==before_room_overview,"repeated room overview never changes game facts")
	await capture("11_scene_framework_room")
	scene.on_hex_selected(Vector2i(1,0))
	check(scene.selected_focus.get("scene_id")=="scene_framework_room" and scene.movement_preview.get("cost")==1,"overlapping local coordinates bind room identity and floor cost")
	if not await sample("move"):finish();return
	await settle()
	scene.save_game();check(scene.last_save_result.get("ok",false),"room world actually saves")
	var room_saved:=C.bytes(scene.playtest.state_copy())
	scene.on_hex_selected(Vector2i(0,0))
	if not await sample("move"):finish();return
	if not await sample("return_scene"):finish();return
	await settle()
	check(scene.playtest.state_copy().actors.actor_player.scene_id=="scene_coast" and scene.board.tiles.size()==1801,"assessed return restores original coast renderer")
	scene.load_game();await settle()
	check(scene.last_load_result.get("ok",false) and C.bytes(scene.playtest.state_copy())==room_saved and scene.board.tiles.size()==7,"loading a room save from coast restores both canonical scene and matching renderer")
	scene.on_hex_selected(Vector2i(0,0))
	if not await sample("move"):finish();return
	if not await sample("return_scene"):finish();return
	await settle()
	check(scene.playtest.state_copy().actors.actor_player.inventory==supplies,"room save/load/return keeps exact inventory custody")
	check(not scene.journal.get_parsed_text().contains("entrance_") and not scene.journal.get_parsed_text().contains("署名"),"transition history is natural and preserves hidden protocol identities")
	await capture("12_scene_return_same_coast")
	scene.show_advanced();await capture("08_advanced_offline_actions")
	scene.show_ai_connection();await settle();await capture("09_optional_connection_offline")
	check(not scene.runtime_ai.client.configured() and not scene.runtime_ai.automatic_assessment_enabled(),"native connection panel remains visibly unconfigured/offline")
	check(scene.runtime_connection_panel.get_combined_minimum_size().x<=scene.advanced_scroll.size.x,"connection panel fits advanced scroll width")
	scene.advanced_scroll.scroll_vertical=10000;await capture("10_connection_apply_controls")
	scene.advanced_dialog.hide()
	finish()
func preserve_restart_fixture(stage:String)->void:
	var prefix:String=OUT+"restart_"+("headless_" if DisplayServer.get_name()=="headless" else "native_")+stage
	var save_path:String=scene.playtest.COAST_SAVE
	check(DirAccess.copy_absolute(save_path,prefix+".json")==OK,"preserve actual "+stage+" core save for separate restart")
	check(DirAccess.copy_absolute(save_path+".narration.json",prefix+".json.narration.json")==OK,"preserve bound "+stage+" prose sidecar for separate restart")
	var expected:Dictionary={"stage":stage,"display":DisplayServer.get_name(),"save_sha256":FileAccess.get_sha256(prefix+".json"),"state_sha256":C.bytes(scene.playtest.state_copy()).sha256_text(),"action_sha256":C.bytes(scene.playtest.action_copy()).sha256_text(),"phase":scene.playtest.phase(),"history":scene.playtest.journal_entries(),"prose":scene.playtest.narration_entries(),"tree_id":Catalog.tree_id(1148)}
	var file:=FileAccess.open(prefix+"_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected,"\t"));file.close()

func finish()->void:
	check(C.bytes(initial_code)==C.bytes(code_signature()),"tested source remains unchanged throughout journey")
	report["tested_code_sha256"]=initial_code
	report["ui_timings"]=ui_timings
	report.merge({"passed":count-failures.size(),"total":count,"failures":failures,"display":DisplayServer.get_name(),"live_ai_tested":false,"offline_exact_examples":true,"source_world_unchanged":true,"release_rule_test_seed":scene.journey_seed,"genuine_program_rng":true})
	var f:=FileAccess.open(OUT+"integrated_journey.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("CORE_MAIN_JOURNEY ",count-failures.size(),"/",count)
	scene.queue_free();quit(0 if failures.is_empty() else 1)
