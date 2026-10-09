extends SceneTree
## Actual main UI callbacks, one authored assessment per intent. No world patches.
const Authored=preload("res://view/playable_build/authored_assessments.gd")
const Scoped=preload("res://view/runtime_ai/scoped_engine.gd")
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
const PolicyTests=preload("res://tests/runtime_ai_capacity/test_policy.gd")
const Main=preload("res://main.tscn")
const Content=preload("res://view/playable_build/settlement_content.gd")
const Catalog=preload("res://view/playable_build/entity_catalog.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const SourceProof=preload("res://tests/settlement/source_proof.gd")
var OUT:=OS.get_environment("FOGBANK_CITY_JOURNEY_OUT")+"/"
var scene
var mock: Node
var capacity_rows: Array=[]
var count:=0
var failures:Array=[]
var resume:=false
var source_start:Dictionary={}
func check(ok:bool,label:String)->bool:
	count+=1
	if not ok:failures.append(label);printerr("SETTLEMENT_NATIVE_FAIL ",label)
	return ok
func _initialize()->void:
	resume="--resume" in OS.get_cmdline_user_args();call_deferred("run")
func frames(n:=4)->void:
	for _i in range(n):await process_frame
func capture(name_:String)->void:
	await frames();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func city_camera(pitch:=0.72,yaw:=0.2,size_:=6.0)->void:
	scene.board.world_view.overview=false;scene.board.world_view.target=scene.board._position(Content.manifest().center_hex)+Vector3(0,.45,0)
	scene.board.world_view.distance=14;scene.board.world_view.pitch=pitch;scene.board.world_view.yaw=yaw;scene.board.camera.size=size_;scene.board.world_view._update_camera()
func gate_camera()->void:
	var data:=Content.manifest();var a:Vector3=scene.board._position(data.gate_outside_hex);var b:Vector3=scene.board._position(data.gate_inside_hex)
	var outside:Vector3=(a-b).normalized()
	scene.board.world_view.overview=false;scene.board.world_view.target=(a+b)*0.5+Vector3(0,.3,0)
	scene.board.world_view.distance=12;scene.board.world_view.pitch=.58;scene.board.world_view.yaw=atan2(outside.x,outside.z);scene.board.camera.size=5.2;scene.board.world_view._update_camera()
func wait_motion()->void:
	var stop:=Time.get_ticks_msec()+18000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<stop:await process_frame
	check(not scene.board.presentation.actors.actor_player.moving,"natural-time actor route finished")
func sample(kind:String)->bool:
	var before:=C.bytes(scene.playtest.state_copy());var turn:int=scene.playtest.state_copy().turn
	scene.fill_coast_sample(kind)
	if not check(not scene.goal.text.is_empty(),"sample fills "+kind):return false
	check(C.bytes(scene.playtest.state_copy())==before,"fill read-only "+kind)
	scene.submit_button.pressed.emit()
	if not check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.state_copy())==before,"end turn awaits assessment "+kind):return false
	if not capacity_probe(kind,true):return false
	if not check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==turn+1,"assessed commit "+kind):print(scene.status_label.text);return false
	return true
func capacity_probe(label:String, complete:=false)->bool:
	var frozen:=C.bytes(scene.playtest.engine.save_data())
	var legacy:=Scoped.new(scene.playtest.engine,func():return true)
	var old_request:Dictionary=legacy.model_request(scene.playtest.active_action)
	var before:int=mock.sent.size()
	var started:Dictionary=scene.runtime_ai.request_assessment()
	if not check(started.get("ok",false) and mock.sent.size()==before+1,"native city96 one complete mock request "+label):return false
	var request:Dictionary=JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
	var metrics:Dictionary=scene.runtime_ai.last_metrics.duplicate(true)
	check(metrics.budget_bytes==98304 and metrics.sent_public_bytes<=98304,"native explicit city cap "+label)
	check(old_request.is_empty()==(metrics.sent_public_bytes>65536),"native legacy64 comparison "+label)
	check(C.bytes(request.memory_context)==C.bytes(scene.playtest.request().memory_context) and request.context_hash==scene.playtest.request().context_hash,"native exact memory and context "+label)
	check(C.bytes(scene.playtest.engine.save_data())==frozen,"native send read-only "+label)
	if complete:
		var authored:Dictionary=Authored.build(request)
		if not check(authored.get("ok",false),"native exact authored offline assessment "+label):return false
		var reply:Dictionary=authored.assessment
		reply.provenance={"provider":"mock_test_transport","live":false,"kind":"model_reply"}
		mock.respond(started.request_id,JSON.stringify({"choices":[{"finish_reason":"stop","message":{"content":JSON.stringify(reply)}}]}))
	else:
		scene.runtime_ai.cancel()
		check(C.bytes(scene.playtest.engine.save_data())==frozen and not scene.runtime_ai.busy(),"native cancel preserves pending "+label)
	capacity_rows.append({"turn":scene.playtest.state_copy().turn,"label":label,"bytes":metrics.sent_public_bytes,"legacy_admitted":not old_request.is_empty(),"city_admitted":true,"memory_records":request.memory_context.facts.size()})
	return true
func configure_budget_ui()->void:
	mock=Mock.new();scene.runtime_ai.set_transport(mock)
	var panel:Control=scene.runtime_connection_panel
	panel.endpoint_input.text="https://example.invalid/v1/chat/completions";panel.model_input.text="provided-test-model";panel.key_input.text="synthetic-native-capacity-marker"
	panel.budget_profile_input.select(1);panel.budget_profile_input.item_selected.emit(1);panel.consent_input.button_pressed=true;panel._apply()
	check(scene.runtime_ai.connection_enabled and mock.sent.is_empty(),"actual UI explicit96 apply stays offline")
func long_intent_probe()->void:
	scene.set_player_intent(PolicyTests.LONG);scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment","native realistic Chinese intent freezes")
	capacity_probe("long_chinese_intent")
	scene.cancel_pending()
func move(hex:Array)->bool:
	var state:Dictionary=scene.playtest.state_copy();var cell:Dictionary=state.hexes["%d,%d"%hex]
	scene._apply_focus({"world_id":state.world_id,"kind":"tile","id":cell.id,"hex":hex})
	return sample("move")
func pick_subject(id:String)->bool:
	for subject in scene.board.settlement_view.selection_nodes():
		if subject.id!=id:continue
		for node in subject.node.find_children("*","MeshInstance3D",true,false):
			if node.mesh==null or node.name=="SelectedEdgeGlow":continue
			var faces_:PackedVector3Array=node.mesh.get_faces()
			for i in range(0,faces_.size(),9):
				if i+2>=faces_.size():break
				var point:Vector2=scene.board.camera.unproject_position(node.global_transform*((faces_[i]+faces_[i+1]+faces_[i+2])/3.0))
				var candidates:Array=scene.board.pick_focus(point)
				if not candidates.is_empty() and candidates[0].reference.id==id:
					var before:=C.bytes(scene.playtest.state_copy());scene.on_focus_candidates(candidates,point)
					check(C.bytes(scene.playtest.state_copy())==before,"actual visible mesh click read only")
					if scene.focus_choice_popup.visible:
						check(scene.focus_choice_popup.item_count==scene.focus_choices.size(),"new selection replaces overlap popup contents")
						for j in range(scene.focus_choice_popup.item_count):check(scene.focus_choice_popup.get_item_text(j)==scene.focus_choices[j].label,"popup label matches current selection candidates")
					return scene.selected_focus.id==id
	return false
func run()->void:
	source_start=SourceProof.snapshot()
	var guard:=Timer.new();guard.wait_time=240;guard.one_shot=true;root.add_child(guard);guard.timeout.connect(func():printerr("SETTLEMENT_NATIVE_TIMEOUT");quit(2));guard.start()
	scene=Main.instantiate();root.add_child(scene);await frames(12)
	if not check(scene.coast_mode and Content.active(scene.playtest.state_copy()),"actual main installs settlement only in new coast"):quit(1);return
	configure_budget_ui()
	var data:=Content.manifest()
	if not resume:
		long_intent_probe()
		scene.show_ai_connection();await capture("native_budget_panel");scene.advanced_dialog.hide()
		city_camera();await frames()
		check(scene.board.settlement_view.report().wall_endpoint_mismatches==0,"render wall contour endpoints join")
		check(scene.board.settlement_view.report().sites[0].authored_road_sections==data.road_sections.size(),"render road uses source ribbon")
		var composition:Dictionary=scene.board.settlement_view.report()
		check(composition.sites[0].buildings>=9 and composition.sites[0].decorative_props>=3,"three-cell city has dense district roof/yard composition")
		check(composition.sites[1].buildings>=2 and composition.sites[1].decorative_props>=1,"one-cell village has cottages and well")
		check(composition.sites[2].buildings>=4 and composition.sites[2].decorative_props>=1,"one-cell citystate has civic roof cluster and court")
		check(composition.sites[1].unwalled_approach_corridors==6,"unwalled village reserves all legal entrances")
		for site_report in composition.sites:
			check(site_report.missing_district_sites.is_empty() and site_report.asset_hash_failures.is_empty() and site_report.missing_asset_resources.is_empty(),"every site district model loaded")
			if site_report.walled:
				check(site_report.wall_height<=0.45 and site_report.gate_frame_height<=0.55,"wall and gate remain below roofline")
				check(site_report.gate_open_corridor_clearance>=0.26 and site_report.gate_full_edge_clearance,"open hinged leaves clear real actor corridor")
		check(pick_subject(data.id),"actual city mesh selectable")
		await capture("native_city_closed")
		gate_camera();await frames();check(pick_subject(data.gate_id),"actual gate mesh selectable")
		await capture("native_gate_closed")
		if not move(data.gate_outside_hex):finish();return
		await wait_motion();check(not scene.playtest.movement_preview(data.gate_inside_hex).ok,"actual main closed gate path blocked")
		scene._apply_focus(Catalog.make_reference(data.gate_id,scene.playtest.state_copy()))
		if not sample("open_gate"):finish();return
		check(Content.gate_open(scene.playtest.state_copy(),data.gate_id) and scene.board.settlement_view.report().gate_open,"committed gate matches native geometry")
		var gate_report:Dictionary=scene.board.settlement_view.report()
		for i in range(gate_report.gate_leaf_angles.size()):check(is_equal_approx(float(gate_report.gate_leaf_angles[i]),float(gate_report.gate_open_leaves[i].open_yaw)),"actual hinge uses verified open pose")
		gate_camera();await capture("native_gate_open")
		if not move(data.center_hex):finish();return
		await wait_motion();check(scene.playtest.state_copy().actors.actor_player.hex==data.center_hex,"actual assessed gate entry")
		scene.board.focus_player();await capture("native_city_ordinary_player_camera")
		var title_proof:Dictionary=scene.board.settlement_view.report().sites[0]
		check(title_proof.title_uses_existing_name_style and title_proof.title_actor_overlap_count==0 and title_proof.title_actor_min_gap_px>=7.9,"ordinary city title stays white/bold/shadowed and clear of actor name")
		city_camera();await capture("native_inside_settlement")
		scene.save_game();check(scene.last_save_result.ok,"actual menu save confirmed")
		var f:=FileAccess.open(OUT+"native_saved_world.json",FileAccess.WRITE);f.store_string(C.bytes(scene.playtest.state_copy()));f.close()
		for place in Content.all_settlements():
			scene.board.world_view.target=scene.board._position(place.center_hex)+Vector3(0,.55,0)
			scene.board.world_view.pitch=1.05;scene.board.world_view.yaw=.25;scene.board.camera.size=6.8 if place.site_kind=="large_city" else 4.5;scene.board.world_view._update_camera();await frames()
			check(pick_subject(place.id),"native visible site selection "+place.site_kind)
			for district in place.districts:
				check(pick_subject(district.id),"native distinct district selection "+district.architectural_kit)
				check(scene.selected_focus.get("kind")=="district","district attention kind distinct")
			await capture("native_scale_"+place.site_kind)

	else:
		scene.load_game();check(scene.last_load_result.ok,"fresh process actual menu load confirmed")
		var expected:String=FileAccess.get_file_as_string(OUT+"native_saved_world.json")
		check(C.bytes(scene.playtest.state_copy())==expected,"fresh process exact world state and location")
		check(scene.board.settlement_view.report().gate_open,"fresh renderer restores open gate")
		long_intent_probe()
		city_camera();await capture("native_restarted_inside")
		if not sample("rest"):finish();return
		if not move(data.gate_inside_hex):finish();return
		await wait_motion()
		if not sample("close_gate"):finish();return
		check(not scene.board.settlement_view.report().gate_open and not scene.playtest.movement_preview(data.gate_outside_hex).ok,"native close restores obstruction")
		if not sample("rest"):finish();return
		if not sample("open_gate"):finish();return
		if not move(data.gate_outside_hex):finish();return
		await wait_motion()
		if not sample("rest"):finish();return
		if not move([-1,14]):finish();return
		await wait_motion();check(scene.playtest.state_copy().actors.actor_player.hex==[-1,14],"native restart trip returns home through assessed route")
		scene.board.focus_player();await capture("native_returned_to_start")
		# Continue through the village approaches to the independent one-cell gate.
		while scene.playtest.state_copy().actors.actor_player.stamina.current<7:
			if not sample("rest"):finish();return
		var citadel:Dictionary=data.additional_settlements[1]
		if not move(citadel.gate_outside_hex):finish();return
		await wait_motion()
		if not sample("open_gate"):finish();return
		if not move(citadel.center_hex):finish();return
		await wait_motion();scene.board.focus_player();await capture("native_citystate_ordinary_player_camera")
		var title_proof:Dictionary=scene.board.settlement_view.report().sites[2]
		check(title_proof.title_uses_existing_name_style and title_proof.title_actor_overlap_count==0 and title_proof.title_actor_min_gap_px>=7.9,"one-cell citystate title separates from actor name")
		check(title_proof.title_screen_offset_px>0,"one-cell collision correction moves only the title")

	finish()
func finish()->void:
	var source_end:=SourceProof.snapshot()
	check(C.bytes(source_start)==C.bytes(source_end),"runtime source unchanged through native run")
	var report:={"checks":count,"failures":failures,"passed":failures.is_empty(),"fresh_process_resume":resume,"source_start":source_start,"source_end":source_end,"display_server":DisplayServer.get_name(),"actual_viewport":[root.size.x,root.size.y],"live_api":false,"assessment_source":"Exact authored offline samples via injected mock; no live model", "capacity_rows":capacity_rows,"mock_sends":mock.sent.size(),"renderer":scene.board.settlement_view.report(),"current_world":scene.playtest.state_copy().settlement_state}
	var f:=FileAccess.open(OUT+("native_resume_report.json" if resume else "native_report.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("SETTLEMENT_NATIVE ",count," checks; failures=",failures)
	scene.queue_free();await frames(3);quit(0 if failures.is_empty() else 1)
