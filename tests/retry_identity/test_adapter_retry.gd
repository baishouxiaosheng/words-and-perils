extends "res://tests/retry_identity/reproduce_legacy.gd"
const Adapter = preload("res://view/playable_build/adapter.gd")
const Examples = preload("res://view/playable_build/effect_examples.gd")
func run() -> void:
	if not setup(): quit(1); return
	var fresh := Adapter.new()
	expect(fresh.engine.supports_resolver("coast_manipulate_environment_v2") and not fresh.engine.supports_resolver("coast_manipulate_environment_v1"), "fresh release exposes only current generic resolver")
	var data: Dictionary = fresh.engine.save_data()
	data.state.actors.actor_player.hex = chosen.hex.duplicate()
	for actor in data.state.actors.values(): actor.hooks = []
	expect(fresh.engine.load_data(data).ok, "explicit positioned production-world test fixture")
	var focus := Catalog.make_reference(chosen.id, fresh.state_copy())
	expect(fresh.begin_intent(Examples.goal("fell", fresh.state_copy(), focus), focus).ok, "fresh production exact fixture begins")
	var built := Examples.assessment(fresh.request(), "fell")
	expect(built.ok and built.assessment.resolver_id == "coast_manipulate_environment_v2", "fixture selects advertised v2")
	var injected: Dictionary = built.assessment.duplicate(true); injected.resolver_id = "coast_manipulate_environment_v1"
	expect(fresh.engine.prepare_assessment(injected).get("code") == "INVALID_ASSESSMENT", "legacy resolver cannot bypass current release policy")
	expect(fresh.prepare_fixture().ok, "production fixture verifier accepts exact v2 felling example")
	var legacy_seeded := Adapter.new(1)
	expect(legacy_seeded.engine.supports_resolver("coast_manipulate_environment_v1") and not legacy_seeded.engine.supports_resolver("coast_manipulate_environment_v2"), "explicit historical test adapter remains v1")
	var old := Adapter.new(1, true)
	old.engine = old._make_engine(1, false, true, true, true, true, true, false, true, true, true, false)
	data = old.engine.save_data(); data.state.actors.actor_player.hex = chosen.hex.duplicate(); data.state.actors.actor_player.stamina.current = 6
	for actor in data.state.actors.values(): actor.hooks = []
	expect(old.engine.load_data(data).ok, "exact old release registry fixture configured")
	var a := reply(old.engine, 1); old.active_action = a.action_id
	expect(old.engine.prepare_assessment(a).ok, "old release v1 pending freezes")
	var committed_snapshot: Dictionary = {}
	for phase in ["ready_roll", "rolled", "staged"]:
		var path: String = OUT + "adapter_old_" + phase + ".json"
		expect(old.save_file(path).ok, "adapter old pending writes " + phase)
		var restored := Adapter.new()
		var loaded: Dictionary = restored.load_file(path)
		expect(loaded.ok, "adapter identifies old registry exactly " + phase + " " + str(loaded))
		if loaded.ok:
			expect(C.bytes(restored.engine.save_data()) == C.bytes(old.engine.save_data()), "adapter pending contents not migrated " + phase)
			expect(restored.engine.supports_resolver("coast_manipulate_environment_v1") and not restored.engine.supports_resolver("coast_manipulate_environment_v2"), "adapter retains old pending resolver " + phase)
			if phase == "ready_roll": restored.roll_once()
			if phase != "staged": restored.stage()
			var result: Dictionary = restored.commit()
			expect(result.ok and false in result.receipt.outcomes.values(), "old pending resumes same failed dice " + phase)
			if committed_snapshot.is_empty(): committed_snapshot = restored.engine.save_data()
			else: expect(C.bytes(committed_snapshot) == C.bytes(restored.engine.save_data()), "every old phase reaches exact same commit " + phase)
			var old_receipts := C.bytes(restored.engine.save_data().receipts)
			focus = Catalog.make_reference(chosen.id, restored.state_copy())
			expect(restored.begin_intent(Examples.goal("fell", restored.state_copy(), focus), focus).ok, "idle migration begins fresh assessed intent " + phase)
			expect(restored.engine.supports_resolver("coast_manipulate_environment_v2") and not restored.engine.supports_resolver("coast_manipulate_environment_v1"), "idle migration activates only v2 " + phase)
			var blocked_result: Dictionary = restored.prepare_fixture()
			expect(blocked_result.get("code") == "RETRY_HISTORY_INCOMPATIBLE", "old unresolved exact attempt visibly incompatible " + phase)
			expect(not str(blocked_result.get("errors", [])).contains("RETRY_HISTORY_INCOMPATIBLE") and str(blocked_result.get("errors", [])).contains("其他行动"), "player explanation is specific and human-readable " + phase)
			expect(C.bytes(restored.engine.save_data().receipts) == old_receipts, "idle migration never rewrites old receipts " + phase)
			restored.engine.cancel_intent(restored.active_action); restored.active_action = ""
			expect(restored.begin_intent(restored.sample_goal("rest")).ok and restored.prepare_fixture().ok, "other legal actions remain available after legacy retry guard " + phase)
		if phase == "ready_roll": old.roll_once()
		elif phase == "rolled": old.stage()
	write_json("adapter_report.json", {"checks": checks, "passed": checks - failures.size(), "failures": failures})
	print("RETRY ADAPTER ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
