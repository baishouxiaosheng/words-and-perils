extends SceneTree
## Actual Main callbacks in two separate OS processes; no state/plan/RNG writes.
const Main = preload("res://main.tscn")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generated = preload("res://view/generated_adventure/seeded_adapter.gd")
var app
var checks := 0
var failures: Array[String] = []
var stage := "create"
var output := ""
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): stage = argument.trim_prefix("--phase=")
	output = OS.get_environment("FOGBANK_DELIVERY_EVIDENCE")
	run.call_deferred()
func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures.append(message); printerr("GENERATED_RESTART_FAIL ", message)
	return value
func frames(n := 4) -> void:
	for _i in range(n): await process_frame
func sample(kind: String) -> bool:
	var before: int = int(app.playtest.state_copy().turn)
	app.fill_generated_sample(kind); app.end_turn()
	if not check(app.playtest.phase() == "awaiting_assessment", kind + " primary waits for assessment"): return false
	app.playtest_fixture()
	return check(app.playtest.phase() == "idle" and int(app.playtest.state_copy().turn) == before + 1, kind + " assessed primary commits once")
func capture(name_: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name_ + ".png")
func run() -> void:
	if not check(not output.is_empty(), "explicit isolated evidence directory supplied"): finish(); return
	DirAccess.make_dir_recursive_absolute(output)
	app = Main.instantiate(); root.add_child(app); await frames()
	if not check(app.coast_mode and app.board.load_error.is_empty(), "fresh ordinary main opens unchanged coast"): finish(); return
	if stage == "create": await create_locked()
	elif stage == "resume": await resume_locked()
	else: check(false, "known restart stage")
	finish()
func create_locked() -> void:
	app.fill_coast_sample("observe"); app.end_turn(); app.playtest_fixture()
	if not check(app.playtest.phase() == "idle" and int(app.playtest.state_copy().turn) == 1, "ordinary coast primary still commits assessed observation"): return
	app.save_game()
	if not check(app.last_save_result.get("ok",false), "coast saved independently before mode switch"): return
	var coast: String = C.digest(app.playtest.engine.save_data())
	app.set_player_intent("保留原海岸草稿"); app.on_hex_selected(Vector2i(-2,15))
	var coast_journal: String = app.journal.text
	app.switch_playtest(false)
	var envelope: Dictionary = Contract.generate("雪岸-playable","compact_coast",4)
	var source: Dictionary = envelope.source
	var prepared: Dictionary = app.prepare_world_candidate(source)
	if not check(prepared.get("ok",false) and app.commit_world_candidate(prepared.candidate).get("ok",false), "exact seed creates independent readonly preview"): return
	var preview: String = C.digest(app.game.state)
	app.last_world_generation_metadata = envelope.metadata.duplicate(true)
	await app.start_generated_from_preview(); await frames()
	if not check(app.generated_mode and app.playtest.ready().ok, "explicit preview entry creates generated authority"): return
	check(app.runtime_ai._adapter == null, "generated mode never binds live provider")
	check(app.playtest.save_data().schema_version == Generated.SEEDED_SAVE_SCHEMA and app.playtest.generation_metadata.request.seed_token == "雪岸-playable", "actual main preserves text-seed provenance in versioned v2 envelope")
	check(app.board.visual_profile.report().id == "generated_macro_matte/v1" and app.board.visual_profile.enabled, "packaged generated-only material profile is active")
	var state: Dictionary = app.playtest.state_copy()
	var hex: Array = state.actors.actor_player.hex
	var key: String = app.playtest.source.navigation.allowed["%d,%d" % hex][0]
	var cell: Dictionary = state.hexes[key]
	var target: Array = [cell.q,cell.r]
	var route: Dictionary = app.playtest.movement_preview(target)
	app.on_hex_selected(Vector2i(cell.q,cell.r))
	app.fill_generated_sample("move"); app.submit_action(); app.playtest_fixture(); app.advance_playtest()
	if not check(app.playtest.phase() == "rolled", "actual advanced UI locks assessed move before commit"): return
	var locked: String = C.digest(app.playtest.save_data())
	app.return_from_map_preview()
	check(app.generated_mode and C.digest(app.playtest.save_data()) == locked, "locked action blocks coast return without mutation")
	app.save_game()
	if not check(app.last_save_result.get("ok",false), "actual main writes generated locked envelope"): return
	check(C.digest(app.coast_adventure.engine.save_data()) == coast and C.digest(app.game.state) == preview, "generated save preserves coast engine and readonly preview")
	var expected: Dictionary = {"locked_sha256":locked,"coast_sha256":coast,"source_hash":source.content_hash,"target":target,"cost":route.cost,"turn":state.turn,"stamina":state.actors.actor_player.stamina.current,"rng":app.playtest.engine.save_data().rng,"save_sha256":FileAccess.get_sha256(Generated.SEEDED_SAVE),"coast_journal":coast_journal}
	var file := FileAccess.open(output + "/expected.json",FileAccess.WRITE); file.store_string(C.bytes(expected)); file.close()
	check(FileAccess.file_exists(output + "/expected.json"), "cross-process expected facts recorded from real save")
	await capture("native_seeded_locked")
func resume_locked() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/expected.json"))
	if not check(not expected.is_empty(), "new OS process finds preceding checkpoint"): return
	app.load_game()
	if not check(app.last_load_result.get("ok",false), "fresh process restores original coast save"): return
	check(C.digest(app.playtest.engine.save_data()) == expected.coast_sha256, "coast facts and RNG match prior process")
	app.set_player_intent("新进程中的海岸草稿"); app.on_hex_selected(Vector2i(-2,15))
	var coast_draft: String = app.goal.text
	var coast_journal: String = app.journal.text
	var coast_focus: Dictionary = app.selected_focus.duplicate(true)
	var coast_object: RefCounted = app.playtest
	check(FileAccess.get_sha256(Generated.SEEDED_SAVE) == expected.save_sha256, "generated file bytes survive exact process boundary")
	app.continue_generated_adventure(); await frames()
	if not check(app.generated_mode and app.playtest.phase() == "rolled", "continue menu restores locked generated action in new process"): return
	check(C.digest(app.playtest.save_data()) == expected.locked_sha256, "source, pending plan, context, RNG and frozen result restore exactly")
	check(app.playtest.source.identity.content_hash == expected.source_hash and app.board.admitted_source == app.playtest.source, "renderer and authority reuse exact readmitted source")
	check(app.board.visual_profile.enabled and app.board.visual_profile.report().source_geometry_changed == false, "generated material profile survives fresh reconstruction")
	check(app.runtime_ai._adapter == null, "restored generated mode remains offline")
	app.return_from_map_preview();check(app.generated_mode, "restored locked turn still cannot be abandoned through mode switch")
	app.end_turn(); await frames()
	var after: Dictionary = app.playtest.state_copy()
	check(app.playtest.phase() == "idle" and C.bytes(after.actors.actor_player.hex) == C.bytes(expected.target), "primary button finishes locked route at exact target")
	check(int(after.turn) == int(expected.turn)+1 and int(after.actors.actor_player.stamina.current) == int(expected.stamina)-int(expected.cost), "saved route charges exact cost and one turn")
	check(C.bytes(app.playtest.engine.save_data().rng) == C.bytes(expected.rng), "resume completion does not reroll")
	var committed: String = C.digest(app.playtest.save_data());app.complete_requested_turn()
	check(C.digest(app.playtest.save_data()) == committed, "repeated completion remains idempotent")
	app.on_hex_selected(Vector2i(int(expected.target[0]),int(expected.target[1])))
	if not sample("observe") or not sample("rest"): return
	check(int(app.playtest.state_copy().flags.observations) == 1, "current-or-adjacent observation records persistent fact")
	app.save_game();check(app.last_save_result.get("ok",false), "completed generated adventure saves through UI")
	var generated_object: RefCounted = app.playtest
	var generated_exact: String = C.digest(app.playtest.save_data())
	app.return_from_map_preview();await frames()
	check(app.coast_mode and app.playtest == coast_object and C.digest(app.playtest.engine.save_data()) == expected.coast_sha256, "return restores identical original coast object, facts and RNG")
	check(app.goal.text == coast_draft and app.journal.text == coast_journal and app.selected_focus == coast_focus, "coast draft, history and selected focus survive roundtrip")
	app.continue_generated_adventure();await frames()
	check(app.generated_mode and app.playtest == generated_object and C.digest(app.playtest.save_data()) == generated_exact, "continue retains committed generated progress")
	app.load_game();await frames()
	check(app.last_load_result.get("ok",false) and C.digest(app.playtest.save_data()) == generated_exact, "UI reload accepts exact committed generated file")
	var saved_hash: String = FileAccess.get_sha256(Generated.SEEDED_SAVE)
	var lineage: String = C.bytes(app.playtest.generation_metadata)
	app.reset_playtest(); await frames()
	check(app.playtest.state_copy().turn == 0 and C.bytes(app.playtest.generation_metadata) == lineage, "actual UI reset keeps original seed/preset lineage")
	check(FileAccess.get_sha256(Generated.SEEDED_SAVE) == saved_hash, "UI reset does not overwrite saved progress")
	app.load_game(); await frames()
	check(app.last_load_result.get("ok",false) and C.digest(app.playtest.save_data()) == generated_exact, "reset adventure reloads exact saved v2 progress")
	await capture("native_seeded_committed")
	app.return_from_map_preview();await frames()
	check(app.coast_mode and C.digest(app.playtest.engine.save_data()) == expected.coast_sha256, "final coast return preserves original save authority")
func finish() -> void:
	var report: Dictionary = {"stage":stage,"checks":checks,"failures":failures,"passed":failures.is_empty(),"actual_main":true,"display":DisplayServer.get_name(),"live_api":false,"process_id":OS.get_process_id()}
	if not output.is_empty():
		var file := FileAccess.open(output + "/" + stage + "_report.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"));file.close()
	print("GENERATED_PROCESS_RESTART ",stage," ",checks-failures.size(),"/",checks)
	if is_instance_valid(app):app.queue_free();await frames(3)
	quit(0 if failures.is_empty() else 1)
