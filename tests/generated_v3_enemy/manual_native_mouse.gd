extends SceneTree
## Prepared local-mock scene; requests must be clicked through actual native UI.
const Main = preload("res://main.tscn")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const Examples = preload("res://view/generated_v3_enemy/assessments.gd")
const OldNPCAdapter = preload("res://view/generated_v3_npc/adapter.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const OUT = "res://artifacts/generated_v3_enemy/native_mouse_final/"
var app: Node
var mock: Node
var checks: int = 0
var failures: Array = []
var events: Array = []
var rows: Array = []
var phase_name = "setup"
var sent_seen: int = 0
var base_turn: int = 0
var initial_pending = ""
var previous_turn: int = -1
var did_player_setup = false
var finished = false
var load_diagnostics: Dictionary = {}
var old_adventure: RefCounted
var old_authority = ""
var old_file_hash = ""
var motion_diagnostics: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("NATIVE_MOUSE_FAIL ", label)
	return value
func frames(n: int = 4) -> void:
	for i in range(n): await process_frame
func gui(event: InputEvent, label: String, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		events.append({"button":label, "pressed":event.pressed, "disabled":button.disabled, "input_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "time_ms":Time.get_ticks_msec(), "position":[event.global_position.x,event.global_position.y], "phase":app.playtest.phase(), "turn":app.playtest.state_copy().turn})
func released(label: String) -> void:
	events.append({"button":label, "pressed":false, "release_signal":true, "input_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "time_ms":Time.get_ticks_msec(), "phase":app.playtest.phase(), "turn":app.playtest.state_copy().turn})
func snapshot(label: String) -> void:
	var p: Node = app.runtime_connection_panel
	var s: Dictionary = app.playtest.state_copy()
	var row: Dictionary = {"label":label, "time_ms":Time.get_ticks_msec(), "phase":app.playtest.phase(), "actor_id":app.playtest.action_copy().get("actor_id", ""), "turn":s.turn, "combat_phase":s.combat_turn.phase, "player_hp":s.actors.actor_player.health.current, "enemy_hp":s.actors[app.playtest.source.enemy_id].health.current, "busy":app.runtime_ai.busy(), "request_disabled":p.assessment_button.disabled, "cancel_disabled":p.cancel_button.disabled, "submit_disabled":app.submit_button.disabled, "panel_phase":p._phase, "mock_sends":mock.sent.size(), "cancel_count":mock.cancellations.size(), "authority_sha256":C.digest(app.playtest.save_data()), "status":p.status_label.text, "gui_events":events.size(), "vegetation":app.playtest.source.features.vegetation,"physical_left_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)}
	rows.append(row)
	FileAccess.open(OUT + "current.json", FileAccess.WRITE).store_string(JSON.stringify(row, "\t"))
	print("NATIVE_MOUSE_STATE ", JSON.stringify(row))
func shot(label: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")
func make_reply(request: Dictionary) -> Dictionary:
	var prototype: Dictionary = request.duplicate(true)
	var enemy: bool = request.context.actor_id != "actor_player"
	prototype.context.goal = Examples.goal("enemy_attack" if enemy else "observe", request.context.facts.actors.actor_player.hex)
	var made: Dictionary = Examples.build(prototype)
	if not made.get("ok", false): return {}
	made.assessment.provenance = {"provider":"mock_test_transport", "live":false, "kind":"model_reply"}
	return made.assessment
func deliver(index: int) -> void:
	var sent: Dictionary = mock.sent[index]
	var request: Dictionary = JSON.parse_string(JSON.parse_string(sent.body).messages[1].content)
	if index == 0:
		var start: int = Time.get_ticks_msec()
		while not sent.request_id in mock.cancellations and Time.get_ticks_msec() - start < 90000:
			await create_timer(.25).timeout
		await create_timer(5.0).timeout
	else: await create_timer(2.0).timeout
	if finished: return
	var reply: Dictionary = make_reply(request)
	check(not reply.is_empty(), "explicit local mock reply built " + str(index))
	var before: String = C.bytes(app.playtest.save_data())
	mock.respond(sent.request_id, C.bytes({"choices":[{"finish_reason":"stop", "message":{"content":C.bytes(reply)}}]}))
	if index == 0 and sent.request_id in mock.cancellations:
		check(C.bytes(app.playtest.save_data()) == before, "late cancelled actual-button request cannot mutate authority")
		snapshot("late_cancelled_reply_ignored")
func show_requests() -> void:
	app.show_ai_connection()
	await frames()
	app.advanced_scroll.ensure_control_visible(app.runtime_connection_panel.assessment_button)
	await frames()
	var started: int=Time.get_ticks_msec()
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Time.get_ticks_msec()-started<2000:await process_frame
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"physical native mouse release clears before ready controls")
	snapshot("ready_real_mouse_" + phase_name)
	await shot("ready_" + phase_name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	app = Main.instantiate(); app.startup_legacy = true; root.add_child(app)
	await frames()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720)); root.size = Vector2i(1280, 720)
	DisplayServer.window_set_title("Village Encounter - Native Mouse QA - Local Mock")
	old_adventure = OldNPCAdapter.new(Generator.generate("726381",4,"coastal_range").source)
	if not check(old_adventure.ready().ok,"accepted old village profile still admits"): finish(); return
	app._switch_mode_to("generated_v3_npc",old_adventure); await frames()
	app.set_player_intent("旧版村庄保留的草稿",false)
	old_authority=C.bytes(old_adventure.save_data())
	check(old_adventure.save_file().ok,"old profile save in isolated QA userdata")
	old_file_hash=FileAccess.get_sha256(old_adventure.default_save_path())
	app.v3_adventure_style.select(1); app.v3_radius_choice.select(0); app.v3_seed_input.text = "726381"; app.v3_vegetation_choice.button_pressed = true
	await app.start_v3_from_dialog(); await frames()
	if not check(app.generated_v3_enemy_mode and app.playtest.ready().ok and app.board.load_error.is_empty(), "native Main vegetation-enabled encounter admitted"):
		finish(); return
	check(app.board.vegetation_view != null, "real vegetation view exists")
	var anchor: Array = app.playtest.source.enemy_placement_result.attack_anchor_hex
	app._apply_focus(app.playtest.tile_reference(anchor)); app.fill_generated_sample("move"); app.end_turn(); app.playtest_fixture()
	await frames()
	if not check(app.playtest.phase() == "awaiting_assessment" and app.playtest.action_copy().actor_id == app.playtest.source.enemy_id, "assessed preparation reaches real enemy pending UI"):
		finish(); return
	var begun: int = Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec() - begun < 15000: await process_frame
	app.board.view_focus = app.playtest.source.navigation.cell_center(anchor)
	app.board.camera_distance = 7.5; app.board.overview_mode = false; app.board.orbit_camera(0, 0)
	mock = Mock.new(); app.runtime_ai.set_transport(mock)
	var panel: Node = app.runtime_connection_panel
	panel.endpoint_input.text = "https://example.invalid/v1/chat/completions"; panel.model_input.text = "explicit-local-mock"; panel.key_input.text = "synthetic-native-qa-only"; panel.consent_input.button_pressed = true; panel.timeout_input.value = 120; panel._apply()
	check(mock.sent.is_empty() and panel.key_input.text.is_empty(), "setup sends no request and clears synthetic key field")
	for pair in [[panel.assessment_button,"assessment"],[panel.cancel_button,"cancel"],[app.submit_button,"end_turn"]]:
		var button: Button = pair[0]; var label: String = pair[1]
		button.gui_input.connect(func(event:InputEvent): gui(event,label,button))
		button.button_up.connect(func(): released(label))
	base_turn = app.playtest.state_copy().turn; previous_turn = base_turn; initial_pending = C.bytes(app.playtest.save_data())
	phase_name = "enemy_first_cancel_retry"
	await show_requests()
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 360000:
		await create_timer(.25).timeout
		while sent_seen < mock.sent.size():
			var index: int = sent_seen; sent_seen += 1
			check(panel.assessment_button.disabled and not panel.cancel_button.disabled, "real request immediately disables duplicate and enables cancel " + str(index))
			snapshot("request_started_" + str(index)); deliver.call_deferred(index)
		if not mock.cancellations.is_empty() and app.playtest.state_copy().turn == base_turn:
			check(C.bytes(app.playtest.save_data()) == initial_pending, "cancel/retry waiting leaves exact pending intent")
		var turn: int = app.playtest.state_copy().turn
		if turn != previous_turn:
			check(turn == previous_turn + 1, "one turn per real request response")
			previous_turn = turn; snapshot("committed_" + str(turn)); await shot("committed_" + str(turn))
			if turn == base_turn + 1 and not did_player_setup:
				check(app.playtest.phase() == "idle" and app.playtest.state_copy().combat_turn.phase == "player", "enemy commit unlocks player")
				check(not app.submit_button.disabled and app.goal.editable, "real player controls enabled after enemy commit")
				did_player_setup = true; phase_name = "player_observe"
				app._apply_focus(app.playtest.tile_reference(app.playtest.state_copy().actors.actor_player.hex)); app.set_player_intent("我站在原地观察身边的道路。", false)
				snapshot("ready_real_mouse_end_turn"); await shot("player_turn_ready")
			elif turn == base_turn + 2:
				phase_name = "enemy_second"; await show_requests()
			elif turn >= base_turn + 3:
				check(app.playtest.state_copy().combat_turn.phase == "player" and not app.submit_button.disabled, "second enemy action returns usable controls")
				await create_timer(8.0).timeout
				var before: String = C.bytes(app.playtest.save_data()); app.save_game(); app.load_game(); await frames()
				load_diagnostics={"save_result":app.last_save_result.duplicate(true),"load_result":app.last_load_result.duplicate(true),"save_path":ProjectSettings.globalize_path(app.playtest.default_save_path()),"before_sha256":before.sha256_text(),"after_sha256":C.bytes(app.playtest.save_data()).sha256_text()}
				check(app.last_save_result.ok and app.last_load_result.ok and C.bytes(app.playtest.save_data()) == before, "native Main exact save/reload")
				check(app.board.committed_effects.pending.is_empty() and app.board.committed_effects.active_count() == 0, "load does not replay committed VFX")
				await shot("reloaded_final")
				app.set_player_intent("新遭遇保留的草稿",false)
				var current: RefCounted=app.playtest
				app.on_tool_selected(29); await frames()
				check(app.playtest==old_adventure and not app.generated_v3_enemy_mode and app.goal.text=="旧版村庄保留的草稿","old advanced entry restores correct session and draft")
				check(C.bytes(old_adventure.save_data())==old_authority and FileAccess.get_sha256(old_adventure.default_save_path())==old_file_hash,"new encounter leaves old authority and save bytes exact")
				var old_loaded: RefCounted=OldNPCAdapter.new()
				check(old_loaded.load_file().ok and C.bytes(old_loaded.save_data())==old_authority,"accepted old profile file still reloads")
				await shot("old_village_draft_preserved")
				app.on_tool_selected(27); await frames()
				check(app.playtest==current and app.generated_v3_enemy_mode and app.goal.text=="新遭遇保留的草稿","current village entry restores new session and draft")
				await shot("new_encounter_draft_returned")
				await fast_motion_case()
				finish(); return
		if phase_name == "player_observe" and app.playtest.phase() == "awaiting_assessment" and not app.advanced_dialog.visible:
			await show_requests()
	check(false, "manual mouse scenario timed out"); finish()
func fast_motion_case() -> void:
	# Clearly separated offline callback regression after the real mouse cases.
	# Exact authored assessments, genuine commits; no provider or RNG override.
	app.reset_playtest(); await frames()
	var anchor: Array=app.playtest.source.enemy_placement_result.attack_anchor_hex
	app._apply_focus(app.playtest.tile_reference(anchor));app.fill_generated_sample("move");app.end_turn();app.playtest_fixture()
	await frames(1)
	var track: Dictionary=app.board.presentation.actors.actor_player
	var generation: int=track.generation
	var moving_before: bool=track.moving
	var dropped: int=app.board.committed_effects.dropped_effects
	if not check(app.playtest.phase()=="awaiting_assessment" and app.playtest.action_copy().actor_id==app.playtest.source.enemy_id,"fast sequence has separate enemy pending intent"):return
	app.playtest_fixture()
	check(moving_before and app.board.presentation.actors.actor_player.moving and app.board.presentation.actors.actor_player.generation==generation,"fast enemy commit preserves ongoing player motion generation")
	var started: int=Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()-started<15000:await process_frame
	await create_timer(1.5).timeout
	check(app.board.committed_effects.emitted_effects>0 and app.board.committed_effects.dropped_effects==dropped,"enemy receipt VFX survives valid motion wait")
	var effects: Node=app.board.committed_effects
	var prior_dropped: int=effects.dropped_effects
	app._apply_focus(app.playtest.enemy_reference());app.fill_generated_sample("attack");app.end_turn();app.playtest_fixture();await frames(1)
	if app.playtest.phase()=="awaiting_assessment" and app.playtest.action_copy().actor_id==app.playtest.source.enemy_id:
		app.playtest_fixture();await create_timer(1.5).timeout
		check(effects.dropped_effects==prior_dropped,"fast consecutive player/enemy attack does not discard valid delayed feedback")
	motion_diagnostics=effects.report()
	await shot("fast_committed_effects")
func finish() -> void:
	if finished: return
	finished = true
	var counts: Dictionary = {}
	for event in events:
		if event.get("release_signal",false) and not event.input_pressed: counts[event.button] = int(counts.get(event.button, 0)) + 1
	check(counts.get("assessment", 0) >= 4, "at least four actual assessment mouse releases")
	check(counts.get("cancel", 0) >= 1, "actual cancel mouse release")
	var primary_down: bool=false
	for event in events:
		if event.button=="end_turn" and event.pressed and event.input_pressed:primary_down=true
	var primary_release: bool=false
	for row in rows:
		if row.label=="ready_real_mouse_player_observe" and not row.physical_left_pressed:primary_release=true
	check(primary_down and primary_release,"actual primary mouse-down and physical release across phase-changing disable")
	check(is_instance_valid(mock) and mock.sent.size()==4,"exactly four transmissions including one cancelled request, three committed responses")
	FileAccess.open(OUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(), "checks":checks, "failures":failures, "gui_events":events, "states":rows, "load_diagnostics":load_diagnostics,"fast_motion_diagnostics":motion_diagnostics, "mock_only":true, "network_calls":0, "setup":"authored assessed approach and memory-only synthetic transport; tested network requests from native UI; release signals cross-checked against physical Input mouse state; final old-mode and motion regressions use explicit callbacks", "transport_sends":mock.sent.size() if is_instance_valid(mock) else 0}, "\t"))
	print("NATIVE_ENEMY_MOUSE_RESULT ", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)
