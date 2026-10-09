extends SceneTree
const Main = preload("res://main.tscn")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL "+message)
func run() -> void:
	var app=Main.instantiate();root.add_child(app)
	await process_frame;await process_frame
	check(app.coast_mode,"default remains coast")
	app.set_player_intent("保留海岸文字草稿")
	app.on_hex_selected(Vector2i(-2,15))
	var coast: String=C.bytes(app.playtest.engine.save_data());var draft: String=app.goal.text;var journal: String=app.journal.text;var focus: Dictionary=app.selected_focus.duplicate(true)
	var coast_object: RefCounted=app.playtest
	app.switch_playtest(false)
	var envelope: Dictionary = Contract.generate(726381,"coast_exploration",4)
	var source: Dictionary = envelope.source
	var prepared: Dictionary=app.prepare_world_candidate(source)
	check(prepared.ok and app.commit_world_candidate(prepared.candidate).ok,"same exact source renders readonly preview")
	var preview: String=C.bytes(app.game.state)
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	await app.start_generated_from_preview()
	await process_frame
	check(app.generated_mode and app.playtest_mode and not app.coast_mode and not app.is_map_preview(),"explicit new mode uses current engine without enabling preview authority")
	check(app.runtime_ai._adapter==null,"generated first slice makes no live API calls")
	check(app.playtest.engine.rule_id()=="generated_exploration_release/v1" and app.board.admitted_source.identity.content_hash==source.content_hash,"renderer and authority share same admitted seed/source hash")
	check(C.bytes(app.game.state)==preview and C.bytes(coast_object.engine.save_data())==coast,"preview model and coast engine remain untouched")
	check(app.map_title.text.contains("多地貌") and app.map_stats_label.text.contains("第一阶段") and app.generated_panel.visible,"honest first-slice labels and small action panel")
	var state: Dictionary=app.playtest.state_copy();var actor: Dictionary=state.actors.actor_player
	var key: String=app.playtest.source.navigation.allowed["%d,%d"%actor.hex][0]
	var cell: Dictionary=state.hexes[key];var target:=Vector2i(cell.q,cell.r)
	var before: String=C.bytes(app.playtest.engine.save_data())
	app.on_hex_selected(target);app.show_focus_details()
	check(not app.selected_focus.is_empty() and app.focus_details_text.text.contains("生态：") and C.bytes(app.playtest.engine.save_data())==before,"tile selection gives source facts without action or RNG")
	app.focus_details_dialog.hide()
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/generated_adventure/native_r4_focus.png")
	app.fill_generated_sample("move")
	check(not app.goal.text.contains("署名") and app.submitted_player_intent().contains("署名多地貌"),"sample display stays natural with exact signed protocol goal")
	app.submit_action();check(app.playtest.phase()=="awaiting_assessment","UI intentional movement awaits assessment")
	app.playtest_fixture();check(app.playtest.phase()=="ready_roll","UI exact authored assessment freezes")
	app.advance_playtest();check(app.playtest.phase()=="rolled","UI lock before facts change")
	var locked: String=C.bytes(app.playtest.save_data())
	app.return_from_map_preview();check(app.generated_mode and C.bytes(app.playtest.save_data())==locked,"pending generated action prevents returning to coast")
	app.save_game();check(app.last_save_result.ok,"generated UI saves separate envelope")
	app.load_game();check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==locked,"UI load retains exact locked action")
	app.advance_playtest();app.advance_playtest()
	check(app.playtest.phase()=="idle" and app.playtest.state_copy().actors.actor_player.hex==[target.x,target.y],"UI movement commits to map position")
	app.on_hex_selected(target);app.fill_generated_sample("observe");app.submit_action();app.playtest_fixture();app.advance_playtest();app.advance_playtest();app.advance_playtest()
	check(app.playtest.state_copy().flags.observations==1,"UI observation persists")
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/generated_adventure/native_r4_committed.png")
	var generated: RefCounted=app.playtest;var generated_exact: String=C.bytes(generated.save_data())
	app.return_from_map_preview();await process_frame
	check(app.coast_mode and app.playtest==coast_object and C.bytes(app.playtest.engine.save_data())==coast,"coast engine object/facts/RNG exact after complete roundtrip")
	check(app.goal.text==draft and app.journal.text==journal and app.selected_focus==focus,"coast draft/history/focus restored")
	app.continue_generated_adventure();await process_frame
	check(app.generated_mode and app.playtest==generated and C.bytes(app.playtest.save_data())==generated_exact,"continue generated keeps existing persistent engine exactly")
	app.switch_playtest(false)
	check(app.is_map_preview() and C.bytes(app.game.state)==preview,"old preview remains unchanged and readonly after generated play")
	app.submit_action();app.roll_dice();app.save_game()
	check(app.last_save_result.code=="READ_ONLY_PREVIEW" and C.bytes(generated.save_data())==generated_exact and C.bytes(coast_object.engine.save_data())==coast,"preview guards still block old authority and both live adventures")
	app.return_from_map_preview();check(app.coast_mode and C.bytes(app.playtest.engine.save_data())==coast,"final coast return exact")
	print("GENERATED UI VERTICAL SLICE ",checks-failures.size(),"/",checks)
	app.free();quit(0 if failures.is_empty() else 1)
