extends "res://tests/committed_action_feedback/test_main_combat_capture.gd"
## Diagnostic of ordinary focus_player view before any test-only camera framing.
var ordinary_projection:Array=[]
func run()->void:
	report_stem="ordinary_camera_probe";test_seed=1
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1440,900);initial_code=code_signature()
	scene=Main.instantiate();scene.coast_adventure=Adapter.new(test_seed,true);root.add_child(scene);await frames(10)
	check(scene.coast_mode and scene.board.load_error.is_empty(),"ordinary main coast opens")
	if not sample("pickup"):await finish();return
	if not sample("equip_bow"):await finish();return
	if not await move_to(choose_position(2,3)):await finish();return
	focus_enemy();scene.board.focus_player()
	if not sample("attack"):await finish();return
	var router:Node3D=scene.board.committed_feedback
	router.set_process(false);await wait_for_production_framing();router._process(0.0);router._process(0.14);router.set_process(false)
	# No test camera values are assigned after the ordinary UI focus.
	check_feedback_region()
	for id in ["actor_player","actor_raider"]:
		var token:Node3D=scene.board.token_nodes[id]
		var body:Vector2=scene.board.camera.unproject_position(token.global_position+Vector3(0,0.5,0))
		var popup:Vector2=scene.board.camera.unproject_position(token.global_position+Vector3(0,1.3,0))
		ordinary_projection.append({"actor":id,"body_screen":[body.x,body.y],"popup_screen":[popup.x,popup.y],"body_inside_viewport":root.get_visible_rect().has_point(body),"popup_inside_viewport":root.get_visible_rect().has_point(popup)})
	var metrics:Dictionary=await sample_battle_frame_metrics("ordinary_focus_player_ranged")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(OUT+"combat_ordinary_player_camera_probe.png")
	captures.append({"file":"combat_ordinary_player_camera_probe.png" if DisplayServer.get_name()!="headless" else "","camera":"ordinary board.focus_player before End Turn; no test camera override","frame_metrics":metrics})
	await finish()
func finish()->void:
	check(C.bytes(initial_code)==C.bytes(code_signature()),"source stable during ordinary-camera probe")
	var report:={"checks":checks,"failures":failures,"actions":actions,"captures":captures,"ordinary_projection":ordinary_projection,"capture_frame_metrics":capture_frame_metrics,"no_test_reframe":true,"default_view_only":true}
	var file:=FileAccess.open(OUT+"ordinary_camera_probe_"+("headless" if DisplayServer.get_name()=="headless" else "native")+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ORDINARY COMBAT CAMERA PROBE %s: %d assertions"%["PASSED" if failures.is_empty() else "FAILED",checks])
	await frames(4);exit_test(0 if failures.is_empty() else 1)
