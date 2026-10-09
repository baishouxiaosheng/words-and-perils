extends SceneTree
## Bounded actual-main native flow; authored offline assessment, no model service.
const Main = preload("res://main.tscn")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT := "res://artifacts/integration_candidate_20261003/"
var checks := 0
var failures: Array = []
var app
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("INTEGRATION_FAIL " + label)
func settle(frames: int = 4) -> void:
	for i in range(frames): await process_frame
func capture(name_: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name_ + ".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1180, 812)
	app = Main.instantiate(); root.add_child(app); await settle(8)
	check(app.coast_mode and app.board.load_error.is_empty(), "actual default main loads verified coast")
	check(app.board.tiles.size() == 1801, "actual complete coast map is instantiated")
	check(not app.runtime_ai.client.configured(), "provider remains unconfigured, no network request")
	if "--restart" in OS.get_cmdline_user_args():
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + "native_expected.json"))
		app.load_game(); await settle()
		check(app.last_load_result.get("ok", false), "fresh actual main loads saved coast successfully")
		check(expected is Dictionary and C.digest(app.playtest.engine.save_data()) == expected.engine_hash, "fresh process restores exact world, RNG, receipts and memory")
		check(app.playtest.engine.memory_context().facts.size() == 1, "fresh process recalls committed authored observation")
		await capture("native_restart_coast"); finish(); return
	var initial: String = C.bytes(app.playtest.engine.save_data())
	var player: Dictionary = app.playtest.state_copy().actors.actor_player
	app.on_hex_selected(Vector2i(player.hex[0], player.hex[1]))
	check(C.bytes(app.playtest.engine.save_data()) == initial, "actual-main selection consumes no turn or RNG")
	app.set_player_intent("我看看眼前海岸，先等待评估，不擅自执行。")
	app.end_turn()
	check(app.playtest.phase() == "awaiting_assessment" and C.bytes(app.playtest.state_copy()) == C.bytes(JSON.parse_string(initial).state), "free text honestly waits for assessment without facts changing")
	app.cancel_pending(); check(app.playtest.phase() == "idle", "unassessed action cancels through main UI callback")
	app.fill_coast_sample("observe"); app.end_turn(); app.playtest_fixture(); await settle()
	check(app.playtest.phase() == "idle" and app.playtest.state_copy().turn == 1, "authored offline assessment completes one actual-main observation")
	check(app.playtest.engine.memory_context().facts.size() == 1, "committed player observation creates one public memory event")
	check(app.playtest.engine.memory_context("actor_keeper").facts.is_empty(), "nearby keeper gains no unwitnessed omniscient memory")
	var catalog: Dictionary = app.playtest.engine.capability_catalog()
	check(catalog.entries.size() == app.playtest.engine.save_data().resolver_ids.size(), "API catalog covers actual installed coast resolver registry")
	app.save_game(); check(app.last_save_result.get("ok", false), "actual-main save succeeds")
	var coast_object: RefCounted = app.playtest
	var committed: String = C.bytes(app.playtest.engine.save_data())
	app.load_game(); check(app.last_load_result.get("ok", false) and C.bytes(app.playtest.engine.save_data()) == committed, "actual-main load preserves exact committed state and memory")
	await capture("native_committed_coast")
	app.set_player_intent("返回海岸后保留这段草稿")
	var draft: String = app.goal.text
	app.seed_input.text = "integration-雪岸"; app.radius_input.value = 4
	app.request_world_build(true)
	var deadline: int = Time.get_ticks_msec() + 60000
	while app.world_build_busy and Time.get_ticks_msec() < deadline: await process_frame
	await settle()
	check(not app.world_build_busy and app.is_map_preview(), "text seed creates actual read-only rendered preview")
	check(app.last_world_generation_metadata.get("request", {}).get("seed_token", "") == "integration-雪岸", "actual preview retains exact text seed metadata")
	check(C.bytes(coast_object.engine.save_data()) == committed, "preview never changes saved coast authority")
	await capture("native_text_seed_preview")
	app.return_from_map_preview(); await settle()
	check(app.coast_mode and C.bytes(app.playtest.engine.save_data()) == committed, "return restores exact actual coast authority")
	check(app.goal.text == draft, "preview return preserves draft")
	app.save_game(); check(app.last_save_result.get("ok", false), "post-roundtrip save succeeds")
	var expected := {"engine_hash": C.digest(app.playtest.engine.save_data()), "turn": app.playtest.state_copy().turn, "memory_events": app.playtest.engine.memory_context().facts.size()}
	var f := FileAccess.open(OUT + "native_expected.json", FileAccess.WRITE); f.store_string(JSON.stringify(expected)); f.close()
	await capture("native_return_coast")
	finish()
func finish() -> void:
	var name_: String = "native_restart" if "--restart" in OS.get_cmdline_user_args() else "native_flow"
	var report := {"passed": checks - failures.size(), "total": checks, "failures": failures, "display": DisplayServer.get_name(), "actual_main": true, "complete_coast_map": true, "authored_offline_assessment": true, "manual_mouse_self_play": false, "live_model_calls": false, "scope": "Bounded observation, save/load, text-seed read-only preview and exact coast return; not complete gameplay/art/performance acceptance."}
	var f := FileAccess.open(OUT + name_ + ".json", FileAccess.WRITE); f.store_string(JSON.stringify(report, "\t")); f.close()
	print("COMBINED_", name_.to_upper(), " ", checks-failures.size(), "/", checks, " ", JSON.stringify(failures))
	app.queue_free(); await settle(4)
	quit(0 if failures.is_empty() else 1)
