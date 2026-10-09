extends SceneTree
## Native generated UI proof only; actual coast custody is covered by test_ui.gd.
const Main = preload("res://main.tscn")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL "+message)
func capture(name_: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/generated_adventure/"+name_+".png")
func run() -> void:
	var app=Main.instantiate();app.startup_legacy=true;root.add_child(app)
	await process_frame;await process_frame
	var envelope: Dictionary = Contract.generate(726381,"coast_exploration",12)
	var source: Dictionary = envelope.source
	var prepared: Dictionary=app.prepare_world_candidate(source)
	check(prepared.ok and app.commit_world_candidate(prepared.candidate).ok,"r12 source shown as readonly preview")
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	await app.start_generated_from_preview();await process_frame
	check(app.generated_mode and app.playtest.engine.rule_id()=="generated_exploration_release/v1","same r12 source enters generated authority")
	check(app.board.admitted_source.identity.content_hash==source.content_hash,"renderer and rules source identity match")
	var state: Dictionary=app.playtest.state_copy();var actor: Dictionary=state.actors.actor_player
	var key: String=app.playtest.source.navigation.allowed["%d,%d"%actor.hex][0]
	var cell: Dictionary=state.hexes[key];var target:=Vector2i(cell.q,cell.r)
	for candidate in state.hexes.values():
		var delta:=Vector2i(candidate.q-actor.hex[0],candidate.r-actor.hex[1])
		if maxi(absi(delta.x),maxi(absi(delta.y),absi(delta.x+delta.y)))!=2:continue
		var route: Dictionary=app.playtest.movement_preview([candidate.q,candidate.r])
		if route.get("ok",false) and route.route.size()==3:target=Vector2i(candidate.q,candidate.r);break
	var expected_route: Dictionary=app.playtest.movement_preview([target.x,target.y])
	var before: String=C.bytes(app.playtest.engine.save_data())
	app.on_hex_selected(target)
	check(not app.selected_focus.is_empty() and C.bytes(app.playtest.engine.save_data())==before,"native target focus is read-only")
	await capture("native_r12_focus")
	check(app.board.get_node("WorldLabelLayout").report().get("overlap_count",-1)==0,"near actor/site labels share collision avoidance")
	app.fill_generated_sample("move");app.submit_action();app.playtest_fixture();app.advance_playtest()
	check(app.playtest.phase()=="rolled","native move passes assessed fixed program and locks")
	var locked: String=C.bytes(app.playtest.save_data())
	app.save_game();app.load_game()
	check(app.last_save_result.ok and app.last_load_result.ok and C.bytes(app.playtest.save_data())==locked,"native save/load preserves locked result")
	app.advance_playtest();app.advance_playtest()
	check(app.playtest.state_copy().actors.actor_player.hex==[target.x,target.y],"native position consequence committed")
	check(app.board.presentation.actors.actor_player.route.size()==expected_route.route.size()-1,"visual motion uses every committed route waypoint")
	while app.board.presentation.actors.actor_player.moving:await process_frame
	check(app.board.token_nodes.actor_player.position.is_equal_approx(app.board.presentation.actors.actor_player.support),"visual route settles at exact supported endpoint")
	app.on_hex_selected(target);app.fill_generated_sample("observe");app.submit_action();app.playtest_fixture();app.advance_playtest();app.advance_playtest();app.advance_playtest()
	check(app.playtest.state_copy().flags.observations==1,"native observed fact committed")
	await capture("native_r12_committed")
	app.board.reset_camera();app.set_map_dialogue_hidden(true)
	await capture("native_r12_overview")
	var report: Dictionary=app.board.get_node("WorldLabelLayout").report()
	check(report.get("overlap_count",-1)==0 and report.visible_labels.any(func(row):return row.kind=="settlement") and report.visible_labels.any(func(row):return row.kind=="actor"),"overview actor/city labels both participate without overlap")
	print("GENERATED_NATIVE_LABELS ",JSON.stringify(report))
	print("GENERATED NATIVE R12 ",checks-failures.size(),"/",checks)
	app.free();quit(0 if failures.is_empty() else 1)
