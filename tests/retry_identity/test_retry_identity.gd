extends "res://tests/retry_identity/reproduce_legacy.gd"
const V2 = preload("res://core/ai_gm_rebuilt/generic_actions_v2.gd")
var cases: Dictionary = {}
func mark(id: String, start_count: int) -> void:
	cases[id] = {"assertions": checks - start_count, "failures_total": failures.size()}
func failure_case(initial: Dictionary = {}, kind := "fell") -> Dictionary:
	var e := make(2, initial); var a := reply(e, 2, kind)
	var result := finish(e, a)
	expect(result.ok, "failed-attempt fixture committed " + kind + " " + str(result.get("code", "")))
	if result.ok: expect(false in result.receipt.outcomes.values(), "fixture real dice actually failed " + kind)
	return {"engine": e, "assessment": a, "result": result}
func blocked(e: RefCounted, kind := "fell") -> void:
	var a := reply(e, 2, kind); var before: Dictionary = e.save_data()
	var result: Dictionary = e.prepare_assessment(a)
	expect(result.get("code") == "REPEAT_ATTEMPT", "identical fresh action blocked " + kind + " " + str(result))
	expect(C.bytes(before) == C.bytes(e.save_data()), "repeat rejection costs no RNG/turn/resource or plan change")
	e.cancel_intent(a.action_id)
func run() -> void:
	if not setup(): quit(1); return
	var n := checks
	var f := failure_case(); var e: RefCounted = f.engine
	expect(e.state_copy().actors.actor_player.stamina.current == 4, "RF01 actual 6 to 4 cost")
	blocked(e); mark("RF01", n)
	n = checks
	var state := base.duplicate(true); state.actors.actor_player.stamina.current = 4
	f = failure_case(state); e = f.engine
	expect(e.state_copy().actors.actor_player.stamina.current == 2, "RF02 cost crosses fatigue threshold")
	blocked(e); mark("RF02", n)
	n = checks
	state = base.duplicate(true); state.actors.actor_player.hooks = ["status_tick"]
	state.actors.actor_player.statuses.test_drunk = {"id": "test_drunk", "kind": "drunk", "remaining_turns": 3, "magnitude": 1}
	f = failure_case(state); e = f.engine
	expect(e.state_copy().actors.actor_player.statuses.test_drunk.remaining_turns == 2, "RF03 duration tick remains real")
	blocked(e); mark("RF03", n)
	n = checks
	state.actors.actor_player.statuses.test_drunk.remaining_turns = 1
	f = failure_case(state); e = f.engine
	expect(e.state_copy().actors.actor_player.statuses.is_empty(), "RF04 own hook expires modifier")
	blocked(e); mark("RF04", n)
	n = checks
	state = base.duplicate(true); state.actors.actor_player.stamina.current = 4
	f = failure_case(state); e = f.engine
	var rested := finish(e, reply(e, 2, "rest", "Rest to restore actual capability."))
	expect(rested.ok and e.state_copy().actors.actor_player.stamina.current == 4, "RF05 independent assessed rest restores F band")
	var a := reply(e, 2); var p: Dictionary = e.prepare_assessment(a)
	expect(p.ok and p.checks[0].derived_facts.F == 0, "RF05 restored effective capability is new opportunity")
	e.cancel_intent(a.action_id)
	# Same-band rest after 6 to 4 is merely extra fuel and cannot reopen felling.
	f = failure_case(); e = f.engine
	expect(finish(e, reply(e, 2, "rest")).ok, "RF05 same-band rest legal")
	blocked(e); mark("RF05", n)
	n = checks
	f = failure_case(); e = f.engine
	var saved: Dictionary = e.save_data()
	saved.state.actors.actor_player.name = "Only a display rename"
	saved.state.actors.actor_player.inventory.reverse()
	saved.state.items.item_poison_vial.name = "Renamed source"
	saved.state.items.item_poison_vial.custody_revision = 19
	saved.state.actors.actor_scout.hex = saved.state.actors.actor_keeper.hex.duplicate()
	expect(e.load_data(saved).ok, "RF06 explicit irrelevant-metadata fixture is valid")
	blocked(e)
	var resolver := V2.new("manipulate_environment")
	var binding := {"bindings": {"actor_id": "actor_player", "target_entity_id": chosen.id, "operation": "fell"}}
	var raw: Dictionary = e.state_copy(); var renamed: Dictionary = raw.duplicate(true)
	renamed.actors.actor_player["equipment"] = {}
	expect(C.digest(resolver.attempt_fingerprint(raw, binding)) == C.digest(resolver.attempt_fingerprint(renamed, binding)), "RF06 nonexistent felling-tool bonus cannot create opportunity")
	mark("RF06", n)
	n = checks
	state = base.duplicate(true); state.actors.actor_player.hooks = ["status_tick"]; state.items.item_poison_vial.quantity = 3
	f = failure_case(state, "condition"); e = f.engine
	expect(e.state_copy().items.item_poison_vial.quantity == 2, "RF07 failure pays one of several source units")
	blocked(e, "condition"); mark("RF07", n)
	n = checks
	f = failure_case(); e = f.engine
	var old: Dictionary = f.assessment
	expect(e.prepare_assessment(old).get("code") == "UNKNOWN_ACTION", "RF08 old envelope belongs to committed action")
	a = reply(e, 2)
	var stale := old.duplicate(true); stale.action_id = a.action_id
	expect(e.prepare_assessment(stale).get("code") == "STALE_ASSESSMENT", "RF08 old world version is stale")
	stale = a.duplicate(true); stale.fact_refs = old.fact_refs.duplicate(true)
	expect(e.prepare_assessment(stale).get("code") == "INVALID_FACT_REF", "RF08 old references are stale evidence")
	expect(e.prepare_assessment(a).get("code") == "REPEAT_ATTEMPT", "RF08 fresh valid envelope reaches semantic retry guard")
	e.cancel_intent(a.action_id); mark("RF08", n)
	n = checks
	for disposition in ["certain", "impossible", "possible"]:
		a = reply(e, 2, "fell", "Different words: make the tree fall now.")
		a.fact_refs.reverse()
		for component in a.components:
			component.parameters = {"A": 4, "D": 0, "P": 2}; component.disposition = disposition; component.fact_ref_ids.reverse()
		var before: Dictionary = e.save_data()
		expect(e.prepare_assessment(a).get("code") == "REPEAT_ATTEMPT", "RF09 advisory wording/numbers/order/disposition cannot mint retry " + disposition)
		expect(C.bytes(before) == C.bytes(e.save_data()), "RF09 failed bypass is atomic")
		e.cancel_intent(a.action_id)
	mark("RF09", n)
	n = checks
	state = base.duplicate(true); state.actors.actor_player.hooks = ["status_tick"]; state.items.item_poison_vial.quantity = 4
	var success_seed := 0
	for seed_ in range(1, 100):
		var rng := RandomNumberGenerator.new(); rng.seed = seed_
		if rng.randi_range(1, 10000) <= 5000 and rng.randi_range(1, 10000) <= 5000: success_seed = seed_; break
	e = make(2, state, success_seed)
	a = reply(e, 2, "condition"); var success := finish(e, a)
	expect(success.ok and not false in success.receipt.outcomes.values(), "RF10 actual program full success")
	expect(e.save_data().attempt_ledger.is_empty(), "RF10 successful generic action clears only its failure entry")
	expect(finish(e, reply(e, 2, "observe")).ok and e.state_copy().actors.actor_player.statuses.is_empty(), "RF10 assessed later turn expires completed condition")
	a = reply(e, 2, "condition")
	expect(e.prepare_assessment(a).ok, "RF10 legal repeated successful condition use remains available")
	e.cancel_intent(a.action_id)
	mark("RF10", n)
	n = checks
	e = make(2); a = reply(e, 2); expect(e.prepare_assessment(a).ok, "RF11 new policy prepare")
	for phase in ["ready_roll", "rolled", "staged"]:
		write_json("v2_" + phase + ".json", e.save_data())
		var restored := make(2); var snapshot: Dictionary = e.save_data()
		expect(restored.load_data(snapshot).ok and C.bytes(restored.save_data()) == C.bytes(snapshot), "RF11 same-process exact new pending " + phase)
		if phase == "ready_roll": e.roll_once(a.action_id)
		elif phase == "rolled": e.stage(a.action_id)
	var token: String = e.action_copy(a.action_id).stage_hash
	expect(e.commit(a.action_id, token).ok, "RF11 new policy commit")
	write_json("v2_committed.json", e.save_data()); mark("RF11_files_for_separate_process", n)
	n = checks
	var committed_bytes := C.bytes(e.save_data())
	expect(e.commit(a.action_id, token).already_committed and C.bytes(e.save_data()) == committed_bytes, "RF12 repeated commit no extra state/ledger/RNG")
	expect(e.commit(a.action_id, "wrong-token").get("code") == "COMMIT_CONFLICT" and C.bytes(e.save_data()) == committed_bytes, "RF12 conflicting commit no publication")
	mark("RF12", n)
	n = checks
	# Explicit valid fixture arrangements isolate the documented single-baseline policy.
	# This is not a claim of stronger no-cycling episode history.
	f = failure_case(); e = f.engine
	var arrangement_a: Array = e.state_copy().actors.actor_player.hex.duplicate()
	var arrangement_b: Array = []
	for direction in Traversal.DIRECTIONS:
		var candidate := [chosen.hex[0] + direction[0], chosen.hex[1] + direction[1]]
		if base.hexes.has(Traversal.key(candidate)) and not base.hexes[Traversal.key(candidate)].ground_blocked:
			arrangement_b = candidate; break
	expect(not arrangement_b.is_empty(), "RF13 nearby valid second approach exists")
	if not arrangement_b.is_empty():
		saved = e.save_data(); saved.state.actors.actor_player.hex = arrangement_b; saved.state.actors.actor_player.stamina.current = 6
		expect(e.load_data(saved).ok, "RF13 explicit approach-B fixture")
		a = reply(e, 2); var next_result := finish(e, a)
		expect(next_result.ok and false in next_result.receipt.outcomes.values(), "RF13 actual failed roll at arrangement B")
		if next_result.ok and false in next_result.receipt.outcomes.values():
			saved = e.save_data(); saved.state.actors.actor_player.hex = arrangement_a; saved.state.actors.actor_player.stamina.current = 4
			expect(e.load_data(saved).ok, "RF13 explicit return-to-A fixture")
			a = reply(e, 2)
			expect(e.prepare_assessment(a).ok, "RF13 LIMITED POLICY allows historical A after failed B; documented rather than hidden")
			e.cancel_intent(a.action_id)
	mark("RF13_documented_limit", n)
	n = checks
	var new_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + "v2_ready_roll.json"))
	var old_engine := make(1)
	expect(old_engine.load_data(new_data).get("code") == "INVALID_SAVE", "RF14 wrong resolver version visibly incompatible")
	var changed: Dictionary = new_data.duplicate(true); changed.state.generated_world.bundle_id = "untrusted-catalog-version"
	expect(not make(2).load_data(changed).ok, "RF14 changed pinned catalog cannot replay")
	var old_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + "legacy_committed.json"))
	e = make(2); old_data.resolver_ids = e.save_data().resolver_ids
	var receipts_before := C.bytes(old_data.receipts); var ledger_before := C.bytes(old_data.attempt_ledger)
	var migration: Dictionary = e.load_data(old_data)
	expect(migration.ok, "RF14 exact old idle records retained under new registry without hash relabel " + str(migration))
	a = reply(e, 2)
	expect(e.prepare_assessment(a).get("code") == "RETRY_HISTORY_INCOMPATIBLE", "RF14 version nonce cannot reset unresolved legacy failure")
	expect(C.bytes(e.save_data().receipts) == receipts_before and C.bytes(e.save_data().attempt_ledger) == ledger_before, "RF14 old receipts and opaque history never rewritten")
	mark("RF14", n)
	write_json("focused_report.json", {"checks": checks, "passed": checks - failures.size(), "failures": failures, "cases": cases, "scope": "seeded real release calculation; no production seed or provider execution; RF11 separate-process outcome is in process_reload_report.json; RF13 explicitly documents latest-baseline limitation"})
	print("RETRY IDENTITY ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
