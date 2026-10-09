extends SceneTree
## Baseline/candidate-identical actual-Main regression. Only the existing public
## authored offline felling flow changes authoritative facts. No world writes,
## fake canopy variants, forced signatures, providers or transform injection.
const Main=preload("res://main.tscn")
const SeededMain=preload("res://tests/core_gameplay/seeded_main.gd")
const Catalog=preload("res://view/playable_build/entity_catalog.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const MockTransport=preload("res://tests/ai_gm_http/mock_transport.gd")
const SAVE_PATH="user://r24_coast_adventure_save.json"
const SOFT_LIMIT_MS=42000
var scene
var network_tripwire:Node
var guard:Timer
var started_ms:=0
var checks:Array=[]
var failures:Array[String]=[]
var stages:Array=[]
var stage_name:="initialization"
var finished:=false
var tree_id:=""
var preferred_probe:=Vector3(INF,INF,INF)
var authoritative_save:=""
var authoritative_state:=""
var selected_reference:Dictionary={}
var source_before:=""
var navigation_before:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,title:String)->bool:
	checks.append({"name":title,"passed":ok})
	if not ok:failures.append(title);printerr("MAIN_FALLEN_SUPPORT_FAIL ",title)
	return ok
func frames(count:int=2)->void:
	for i in range(count):await process_frame
func checkpoint(name_:String)->bool:
	if finished:return false
	stage_name=name_;print("MAIN_FALLEN_SUPPORT_STAGE ",name_," ",Time.get_ticks_msec()-started_ms,"ms")
	if Time.get_ticks_msec()-started_ms<SOFT_LIMIT_MS:return true
	check(false,"bounded fixture exceeded 42-second soft deadline at "+name_);finish(2);return false
func on_timeout()->void:
	if finished:return
	check(false,"42-second watchdog at "+stage_name);finish(2)
func mesh_bounds(mesh:Mesh)->AABB:
	var faces:PackedVector3Array=mesh.get_faces()
	if faces.is_empty():return mesh.get_aabb()
	var box:=AABB(faces[0],Vector3.ZERO)
	for vertex in faces:box=box.expand(vertex)
	return box
func tree_pick()->Dictionary:
	# Same actual-silhouette/ray strategy as test_integrated_journey.gd. Read the
	# DISPLAYED MultiMesh transform, not a potentially stale selection.current.
	var entry:Dictionary=scene.board.entity_selection.rows.get(tree_id,{})
	if entry.is_empty():return {}
	var node:MultiMeshInstance3D=entry.near
	var transform_:Transform3D=node.global_transform*node.multimesh.get_instance_transform(entry.index)
	var box:=mesh_bounds(node.multimesh.mesh)
	scene.board.world_view.overview=false;scene.board.world_view.target=transform_.origin+Vector3(0,.12,0)
	scene.board.world_view.pitch=1.15;scene.board.world_view.yaw=.2;scene.board.world_view.distance=8
	scene.board.camera.size=2.2;scene.board.world_view._update_camera()
	var probes:Array[Vector3]=[]
	if preferred_probe.is_finite():probes.append(preferred_probe)
	for y in [.8,.6,.4,.2]:
		for x in [.5,.35,.65]:probes.append(box.position+box.size*Vector3(x,y,.5))
	var faces:PackedVector3Array=node.multimesh.mesh.get_faces()
	# Bound source-terrain ray work: at most 37 probes, not the entire journey.
	for i in range(0,mini(faces.size(),72),3):probes.append((faces[i]+faces[i+1]+faces[i+2])/3.0)
	for probe in probes:
		if Time.get_ticks_msec()-started_ms>=SOFT_LIMIT_MS:return {}
		var point:Vector2=scene.board.camera.unproject_position(transform_*probe)
		var candidates:Array=scene.board.pick_focus(point)
		if not candidates.is_empty() and candidates[0].reference.id==tree_id:
			preferred_probe=probe
			return {"point":point,"candidates":candidates}
	return {}
func click_tree(pick:Dictionary)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=pick.point
	scene.board._input(event)
func transform_values(value:Transform3D)->Array:
	return [value.basis.x.x,value.basis.x.y,value.basis.x.z,value.basis.y.x,value.basis.y.y,value.basis.y.z,value.basis.z.x,value.basis.z.y,value.basis.z.z,value.origin.x,value.origin.y,value.origin.z]
func verify_fallen(label_:String)->void:
	if not checkpoint(label_):return
	var selection=scene.board.entity_selection
	var entry:Dictionary=selection.rows.get(tree_id,{})
	if not check(not entry.is_empty(),label_+": actual tree remains in renderer identity index"):return
	var expected:Transform3D=Catalog.instance_transform(int(entry.row))
	var shore=scene.board.world_view.natural_shorelines
	if not shore.visible:expected.origin.y=scene.board.world_view.whole_canopies.instance_rows[int(entry.row)*10+1]
	expected.basis=Basis(Vector3.FORWARD,-PI*.48)*expected.basis;expected.origin.y+=.025
	var near_:Transform3D=entry.near.multimesh.get_instance_transform(entry.index)
	var far_:Transform3D=entry.far.multimesh.get_instance_transform(entry.index)
	var current:Transform3D=entry.current
	var rendered_ok:=near_.is_equal_approx(expected) and far_.is_equal_approx(expected)
	var indexed_ok:=current.is_equal_approx(expected)
	check(rendered_ok,label_+": actual near/far meshes retain fallen pose at active support height")
	check(indexed_ok,label_+": picker transform matches fallen geometry at active support height")
	var selected_ok:bool=selection.selected_reference==selected_reference and scene.selected_focus==selected_reference
	check(selected_ok,label_+": selected catalog reference is unchanged")
	var pick:Dictionary={}
	if rendered_ok and indexed_ok:pick=tree_pick()
	check(not pick.is_empty() and pick.candidates[0].reference==selected_reference,label_+": displayed fallen silhouette resolves the same real source reference")
	check(C.bytes(scene.playtest.engine.save_data())==authoritative_save and C.bytes(scene.playtest.state_copy())==authoritative_state,label_+": complete authority/RNG/receipts/state bytes unchanged")
	stages.append({"stage":label_,"shoreline_active":shore.visible,"near":transform_values(near_),"far":transform_values(far_),"expected":transform_values(expected),"indexed":transform_values(current),"rendered_pose_matches":rendered_ok,"index_matches":indexed_ok,"geometry_pick":not pick.is_empty(),"pick_skipped_for_pose_mismatch":not rendered_ok or not indexed_ok,"selected_reference_sha256":C.bytes(selection.selected_reference).sha256_text(),"authoritative_save_sha256":C.bytes(scene.playtest.engine.save_data()).sha256_text()})
func finish(exit_code:int=-1)->void:
	if finished:return
	finished=true
	if is_instance_valid(guard):guard.stop()
	var sends:int=network_tripwire.sent.size() if is_instance_valid(network_tripwire) else -1
	var report:Dictionary={"actual_main":true,"fixture":"actual_main_fallen_support/v1","elapsed_ms":Time.get_ticks_msec()-started_ms,"checks":checks,"failures":failures,"stages":stages,"stopped_at":stage_name,"tree_row":1148,"tree_id":tree_id,"seed":scene.journey_seed if is_instance_valid(scene) else -1,"network_tripwire_send_count":sends,"live_provider_calls":false if sends==0 else null,"authority_changes":"existing signed offline felling assessment only","same_fixture_for_baseline_and_candidate":true,"expected_correction":"Shoreline presentation changes must preserve the assessed fallen pose and matching picking transform. Baseline behavior is unmeasured until this fixture runs; do not demand pixel parity with a reproduced standing-pose reset."}
	var output:=OS.get_environment("FOGBANK_VEGETATION_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MAIN_FALLEN_SUPPORT ",checks.size()-failures.size(),"/",checks.size()," ",report.elapsed_ms,"ms")
	print("MAIN_FALLEN_SUPPORT_REPORT ",JSON.stringify(report))
	if is_instance_valid(scene):scene.queue_free()
	quit(exit_code if exit_code>=0 else (0 if failures.is_empty() else 1))
func run()->void:
	started_ms=Time.get_ticks_msec()
	# This fixture exercises normal save callbacks. Refuse to touch an existing
	# player's save; coordinator must provide fresh isolated HOME/XDG directories.
	if not check(OS.get_environment("FOGBANK_VEGETATION_TEST_ISOLATED")=="1" and not FileAccess.file_exists(SAVE_PATH),"explicit fresh isolated save environment is required"):
		finish(2);return
	guard=Timer.new();guard.one_shot=true;guard.wait_time=42;root.add_child(guard);guard.timeout.connect(on_timeout);guard.start()
	root.size=Vector2i(1920,1080)
	scene=Main.instantiate();scene.set_script(SeededMain);root.add_child(scene);await frames(8)
	if not checkpoint("actual main ready"):return
	if not check(scene.coast_mode and scene.board.load_error.is_empty() and scene.board.entity_selection.ready_catalog,"actual seeded Main opens complete verified coast and real picker"):
		finish();return
	if not check(not scene.runtime_ai.client.configured() and not scene.runtime_ai.connection_enabled and not scene.runtime_ai.automatic_assessment and not scene.runtime_ai.automatic_narration and scene.runtime_ai.client.configuration_revision()==0 and not scene.runtime_ai.busy(),"runtime providers have never been configured and remain offline"):
		finish(2);return
	# Existing no-network transport is a tripwire only: no configuration or reply
	# is supplied. The ordinary authored fixture still performs the assessment.
	network_tripwire=MockTransport.new();network_tripwire.send_error=ERR_UNAVAILABLE
	if not check(scene.runtime_ai.client.set_transport(network_tripwire).get("ok",false),"no-network tripwire replaces idle transport without changing authority"):
		finish(2);return
	tree_id=Catalog.tree_id(1148)
	var state:Dictionary=scene.playtest.state_copy()
	var tree:Dictionary=Catalog.entity(tree_id,state)
	if not check(not tree.is_empty() and tree.hex==[-1,13],"real source tree 1148 owns the existing nearby route cell"):
		finish();return
	var original_state:=C.bytes(state);var original_save:=C.bytes(scene.playtest.engine.save_data());var initial_turn:int=state.turn
	var pick:=tree_pick()
	if not check(not pick.is_empty(),"actual standing silhouette is selected through source-aware board ray picking"):
		finish();return
	click_tree(pick)
	if not check(scene.selected_focus.get("id")==tree_id and C.bytes(scene.playtest.engine.save_data())==original_save and scene.playtest.phase()=="idle","real input selects tree and spends no action/RNG/turn"):
		finish();return
	scene.fill_coast_sample("fell")
	if not check(not scene.goal.text.is_empty() and C.bytes(scene.playtest.state_copy())==original_state,"existing explicit authored felling sample only fills intent"):
		finish();return
	scene.submit_button.pressed.emit()
	if not check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.state_copy())==original_state and scene.current_request.context.attention_focus.facts.entity.id==tree_id,"End Turn freezes actual tree focus without executing it"):
		finish();return
	var frozen:=C.bytes(scene.current_request)
	scene.on_hex_selected(Vector2i(-1,11))
	check(C.bytes(scene.current_request)==frozen,"later selection cannot rewrite the pending assessed tree")
	scene.playtest_fixture();await frames(2)
	if not checkpoint("offline felling committed"):return
	state=scene.playtest.state_copy()
	if not check(scene.playtest.phase()=="idle" and int(state.turn)==initial_turn+1 and state.environment_entities.has(tree_id) and state.environment_entities[tree_id].state.posture=="fallen" and state.hexes["-1,13"].ground_blocked,"existing offline assessed action commits one turn and the real fallen-tree obstruction"):
		finish();return
	check(network_tripwire.sent.is_empty(),"offline felling makes zero transport requests")
	pick=tree_pick()
	if not check(not pick.is_empty(),"committed fallen tree remains selectable from actual displayed mesh"):
		finish();return
	click_tree(pick);selected_reference=Catalog.make_reference(tree_id,state)
	check(scene.selected_focus==selected_reference and int(selected_reference.entity_revision)==1,"fallen selection uses current catalog revision one")
	authoritative_state=C.bytes(state);authoritative_save=C.bytes(scene.playtest.engine.save_data())
	navigation_before=C.bytes(scene.playtest.movement_preview([-1,11]))
	var shore=scene.board.world_view.natural_shorelines
	source_before=C.bytes(shore.source_context_at_xz(Vector2(10.240750399750986,20.4125)))
	verify_fallen("after assessed felling")
	if finished:return
	if not checkpoint("save and reload"):return
	scene.save_game()
	if not check(scene.last_save_result.get("ok",false),"actual Main save callback succeeds"):
		finish();return
	var disk_before:=FileAccess.get_file_as_bytes(SAVE_PATH)
	check(disk_before==authoritative_save.to_utf8_buffer(),"saved file is byte-exact complete authority including RNG and receipts")
	scene.load_game();await frames(2)
	if not checkpoint("reload returned"):return
	if not check(scene.last_load_result.get("ok",false) and C.bytes(scene.playtest.engine.save_data())==authoritative_save and C.bytes(scene.playtest.state_copy())==authoritative_state,"actual Main reload preserves exact complete save and state bytes"):
		finish();return
	# Loading intentionally clears UI attention; reselect through the actual ray.
	pick=tree_pick()
	if not check(not pick.is_empty(),"reloaded fallen mesh is selectable without injecting a reference"):
		finish();return
	click_tree(pick);verify_fallen("after save/reload and real reselection")
	if finished:return
	for cycle in range(2):
		if not checkpoint("shore cycle "+str(cycle)):return
		shore.set_active(false);await frames(1)
		if finished:return
		check(not shore.visible and scene.board.world_view.picks==shore.old_picks,"cycle "+str(cycle)+": actual legacy source picking is active")
		verify_fallen("shore off cycle "+str(cycle))
		if finished:return
		shore.set_active(true);await frames(1)
		if finished:return
		check(shore.visible and scene.board.world_view.picks==shore.new_picks and C.bytes(shore.source_context_at_xz(Vector2(10.240750399750986,20.4125)))==source_before,"cycle "+str(cycle)+": v03 source picking/trace returns exactly")
		verify_fallen("shore on cycle "+str(cycle))
		if finished:return
	check(C.bytes(scene.playtest.movement_preview([-1,11]))==navigation_before,"all presentation changes preserve the actual post-felling movement result")
	scene.save_game()
	check(scene.last_save_result.get("ok",false) and FileAccess.get_file_as_bytes(SAVE_PATH)==disk_before,"final Main save after support cycles is byte-identical to first committed save")
	check(network_tripwire.sent.is_empty() and not scene.runtime_ai.client.configured(),"entire actual-Main regression makes zero provider calls")
	finish()
