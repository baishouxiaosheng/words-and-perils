extends "res://tests/actor_status_death/frozen_finite_main.gd"
## Test-only extension of the exact accepted finite Main driver. One fresh lineage,
## at most eight actual commits, original production RNG, no success search.
const BASE_SHA = "89df6d366413a4624793f6668f31f08b4f7736729c32ba60f85ab9148fc74577"
const FIXTURE_SHA = "b94c3a78924dd7c3f8f125b1c6830bbdb66dd7062b4342217da11fe0cc3cc6b8"
const MOCK_SHA = "8d8e3fafc18e9ed9bb1295bb2d3eff3a52771afeb9ccc162017a2402001ec2df"
const POISON = "item_poison_vial"
const MAX_COMMITS = 8
var inconclusive_reason := ""
var death_witness := false
var stale_proposal: Dictionary = {}
var stale_assessment: Dictionary = {}

func run() -> void:
	var isolated: String = OS.get_environment("FOGBANK_ACTOR_FINITE_USER_DIR")
	if not expect(not isolated.is_empty() and OS.get_user_data_dir() == isolated, "exact isolated user directory"): finish(); return
	for pin in [["res://main.gd", MAIN_SHA], ["res://tests/actor_status_death/frozen_finite_main.gd", BASE_SHA], ["res://tests/actor_status_entry/entry_fixture.gd", FIXTURE_SHA], ["res://tests/ai_gm_http/mock_transport.gd", MOCK_SHA]]:
		if not expect(FileAccess.get_sha256(pin[0]) == pin[1], "exact input: " + str(pin[0])): finish(); return
	root.gui_embed_subwindows = true; root.size = Vector2i(1280, 720)
	app = Main.instantiate(); root.add_child(app); current_scene = app; await frames(6)
	mock = Mock.new()
	if not expect(app.runtime_ai.set_transport(mock).get("ok", false) and not mock.info().live, "mock installed before configuration"): finish(); return
	if not await configure_real_controls(): finish(); return
	# Use only admit/assessment helpers. Never call fresh or successful_sequence.
	if not f.admit(): failures.append_array(f.failures); finish(); return
	var original = OldEnemy.new(f.source_data)
	if not expect(original.ready().get("ok", false), "original generated source admitted"): finish(); return
	app._switch_mode_to("generated_v3_enemy", original); await frames()
	app.on_tool_selected(app.ACTOR_STATUS_ENTRY_NEW); await frames()
	if not expect(app.actor_status_mode and app.playtest.core.source.identity.profile_hash == F.FROZEN_PROFILE, "real Main enters exact status profile"): finish(); return
	var initial: Dictionary = app.playtest.state_copy()
	world_id = initial.world_id
	if not expect(initial.actors[F.PLAYER].health == {"current":12,"max":12} and initial.items[POISON].quantity == 2 and initial.items[POISON].owner_actor_id == F.PLAYER and POISON in initial.actors[F.PLAYER].inventory, "authored player12 and two owned poison vials"): finish(); return
	if not expect(app.playtest.current_actor_id() == F.PLAYER and not app._waiting_enemy_phase(), "spawn has a genuine player slot outside contact"): finish(); return
	for bottle in range(2):
		var before: Dictionary = app.playtest.state_copy()
		if not expect(F.status(before, F.PLAYER, "poison").is_empty(), "previous typed poison expired before the next vial"): finish(); return
		var applied: Dictionary = await action("status_source", {"target_actor_id":F.PLAYER,"source_id":POISON})
		if applied.is_empty(): finish(); return
		var after: Dictionary = app.playtest.state_copy()
		if not expect(after.items[POISON].quantity == 1-bottle and after.actors[F.PLAYER].health.current == before.actors[F.PLAYER].health.current, "one legitimate source cost and no new-generation owner damage"): finish(); return
		if not F.applied(applied):
			inconclusive_reason = "Actual contested RNG consumed vial %d without applying poison; death boundary not reached. No retry or fresh lineage." % (bottle+1)
			finish(); return
		for tick in range(3):
			if bottle == 1 and tick == 2:
				var saved: String = C.bytes(app.playtest.save_data())
				var grant: Dictionary = app.playtest.decision_request()
				if not expect(grant.get("ok", false), "real pre-death proposal grant"): finish(); return
				stale_proposal = f.proposal(grant.request, "Late ordinary player observation")
				app.cancel_pending(); await frames()
				if not expect(not app.playtest.decision_pending() and C.bytes(app.playtest.save_data()) == saved, "Main cancels grant without gameplay cost"): finish(); return
			var hp: int = app.playtest.state_copy().actors[F.PLAYER].health.current
			var observed: Dictionary = await action("observe", {"target_hex":initial.actors[F.PLAYER].hex})
			if observed.is_empty(): finish(); return
			if not expect(app.playtest.state_copy().actors[F.PLAYER].health.current == maxi(0, hp-2), "actual typed owner tick removes two authored health"): finish(); return
			if not expect(actions.size() <= MAX_COMMITS, "bounded eight-commit lineage"): finish(); return
	if not expect(app.playtest.state_copy().actors[F.PLAYER].health.current == 0 and actions.size() == MAX_COMMITS, "actual poison reaches player death in eight commits"): finish(); return
	death_witness = true
	var receipt: Dictionary = app.playtest.committed()
	stale_assessment = app.playtest.core.journal.back().assessment.duplicate(true)
	var terminal: String = C.bytes(app.playtest.save_data())
	for repeat in range(2):
		var duplicate: Dictionary = app.playtest.core.commit(receipt.action_id, receipt.stage_hash)
		expect(duplicate.get("ok", false) and duplicate.get("already_committed", false) and C.bytes(app.playtest.save_data()) == terminal, "death receipt duplicate preserves pools/RNG/records/history: " + str(repeat))
	expect(not app._waiting_enemy_phase() and not app.playtest.enemy_response_available(), "death grants no enemy slot")
	expect(app.submit_button.disabled and not app.goal.editable and app.phase_label.text.contains("倒下"), "actual Main death controls disable deliberate action")
	# Explicit test consent removes consent-denial as an explanation for no send.
	# The installed transport has no HTTP client or socket capability.
	app.runtime_ai.authorize_intention_requests(true)
	var request: Dictionary = app.runtime_ai.request_intention()
	expect(not request.get("ok", false) and request.get("code") == "ACTOR_DOWNED", "terminal actor cannot request a new external intention")
	app._queue_required_enemy_turn(); app._begin_required_enemy_turn(); await frames()
	expect(mock.sent.is_empty() and C.bytes(app.playtest.save_data()) == terminal, "terminal Main dispatch sends no enemy request or gameplay change")
	expect(not app.apply_playtest_reply(stale_proposal) and C.bytes(app.playtest.save_data()) == terminal, "Main rejects cancelled late proposal after death")
	expect(not app.apply_playtest_reply(stale_assessment) and C.bytes(app.playtest.save_data()) == terminal, "Main rejects committed late assessment after death")
	var blocked: Dictionary = app.playtest.begin_intent("Observe after death")
	expect(not blocked.get("ok", false) and blocked.get("code") == "ACTOR_DOWNED" and C.bytes(app.playtest.save_data()) == terminal, "dead player cannot allocate another action or pay")
	expect(mock.sent.is_empty(), "entire one-lineage run has zero transport sends")
	finish()

func finish() -> void:
	if finished: return
	finished = true
	var outcome := "FAILED" if not failures.is_empty() else ("INCONCLUSIVE" if not inconclusive_reason.is_empty() else ("PASSED" if death_witness else "FAILED"))
	var report: Dictionary = {"schema":"actor_status_player_poison_regression/v1","status":outcome,"checks":checks,"failures":failures,"inconclusive_reason":inconclusive_reason,"death_witness":death_witness,"actions":actions,"max_commits":MAX_COMMITS,"fresh_lineages":1,"world_id":world_id,"main_sha256":MAIN_SHA,"profile_hash":F.FROZEN_PROFILE,"driver_sha256":FileAccess.get_sha256("res://tests/actor_status_death/test_player_poison.gd"),"mock_sends":mock.sent.size() if is_instance_valid(mock) else 0,"network_calls":0,"scope":"one real Main status-v1 player typed-poison death; no RNG injection, state/save/receipt fabrication, repeated lineages, enemy-death or double-death claim; headless logic only"}
	var path: String = OS.get_environment("FOGBANK_ACTOR_PLAYER_POISON_REPORT")
	var out := FileAccess.open(path, FileAccess.WRITE) if not path.is_empty() else null
	if out == null:
		printerr("ACTOR_PLAYER_POISON_REPORT_OPEN_FAILED missing_output_env=", path.is_empty(), " open_error=", FileAccess.get_open_error())
		quit(2); return
	var stored: bool = out.store_string(JSON.stringify(report, "\t"))
	var write_error: Error = out.get_error()
	out.flush()
	var flush_error: Error = out.get_error()
	out.close()
	if not stored or write_error != OK or flush_error != OK:
		printerr("ACTOR_PLAYER_POISON_REPORT_WRITE_FAILED stored=", stored, " write_error=", write_error, " flush_error=", flush_error)
		quit(2); return
	if is_instance_valid(app): app.free()
	print("ACTOR_PLAYER_POISON_RESULT ", JSON.stringify(report))
	quit(0 if outcome == "PASSED" else (3 if outcome == "INCONCLUSIVE" else 1))
