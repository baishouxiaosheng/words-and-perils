extends SceneTree
## Independent finite fixture review. No API or production balance assertions.
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
var checks := 0
var failures: Array = []
var cases: Array = []
var observed: Dictionary = {}
var case_start := 0

class BrokenPlan extends RefCounted:
	var variant: String
	func _init(v: String) -> void: variant = v
	func resolver_id() -> String: return "review_" + variant
	func attempt_key(_s: Dictionary, _a: Dictionary) -> String: return variant
	func attempt_fingerprint(_s: Dictionary, _a: Dictionary) -> Dictionary: return {}
	func freeze(_s: Dictionary, _a: Dictionary) -> Dictionary:
		var patches: Array = [{"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": -1}]
		if variant == "half_invalid": patches.append({"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": -999})
		elif variant == "bool_delta": patches.append({"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": true})
		elif variant == "unknown_cell": patches.append({"type": "cell_blocking_set", "cell_id": "hex_no_such_cell", "ground_blocked": true, "air_blocked": false, "all_blocked": false})
		return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": "only", "requires": {}, "patches": patches}]}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ", label)
func start(label: String) -> void:
	cases.append({"case": label, "passed": false}); case_start = failures.size()
func finish() -> void: cases[-1].passed = case_start == failures.size()
func registry() -> Dictionary:
	var result: Dictionary = {}
	for v in ["gate", "listen", "tree"]:
		var r := Resolver.new(v); result[r.resolver_id()] = r
	for v in ["half_invalid", "bool_delta", "unknown_cell"]:
		var r := BrokenPlan.new(v); result[r.resolver_id()] = r
	return result
func game(state: Dictionary = {}, policy: Dictionary = {}) -> RefCounted:
	return GMEngine.new(Story.world() if state.is_empty() else state, Rule.new(), registry(), policy, 123)
func fixture(e: RefCounted, resolver: String = "fixture_gate", dispositions: Array = ["possible", "possible"], goal: String = "交酒并询问通行") -> Dictionary:
	return Story.assessment(e.begin_intent(goal).request, resolver, dispositions)
func commit_action(e: RefCounted, a: Dictionary) -> Dictionary:
	var p: Dictionary = e.prepare_assessment(a)
	if not p.get("ok", false): return p
	var r: Dictionary = e.roll_once(a.action_id)
	if not r.get("ok", false): return r
	var s: Dictionary = e.stage(a.action_id)
	if not s.get("ok", false): return s
	return e.commit(a.action_id, s.stage_hash)
func reverse_dicts(v: Variant) -> Variant:
	if v is Dictionary:
		var out: Dictionary = {}; var keys: Array = v.keys(); keys.reverse()
		for key in keys: out[key] = reverse_dicts(v[key])
		return out
	if v is Array:
		var out: Array = []
		for item in v: out.append(reverse_dicts(item))
		return out
	return v
func parsed(v: Variant) -> Variant:
	var p := JSON.new()
	check(p.parse(JSON.stringify(v)) == OK, "Actual JSON parse succeeds")
	return p.data
func refused_atomic(e: RefCounted, data: Variant, label: String) -> void:
	var before: String = C.bytes(e.save_data())
	var r: Dictionary = e.load_data(data)
	check(not r.get("ok", false) and r.has("code") and C.bytes(e.save_data()) == before, label)

func _initialize() -> void:
	start("01_policy_authority_and_honest_defaults")
	var e := game(); var save: Dictionary = e.save_data()
	save.policy.npc_secret_allowlist = ["/actors/actor_guard_a/secrets/gate_password"]
	refused_atomic(e, save, "Saved policy cannot authorize an NPC secret")
	var policy := {"npc_secret_allowlist": ["/actors/actor_guard_a/secrets/gate_password"], "public_flag_ids": []}
	var configured := game({}, policy); var target := game({}, policy)
	check(target.load_data(parsed(configured.save_data())).get("ok", false), "Matching explicitly authorized projection can reload")
	var default := GMEngine.new(Story.world(), null, registry())
	var request: Dictionary = default.begin_intent("尝试动作").request
	var r: Dictionary = default.prepare_assessment(Story.assessment(request))
	check(default.rule_id() == "NOT_CONFIGURED" and r.get("code") == "NOT_CONFIGURED", "Production default never imports test rule A")
	finish()

	start("02_action_identity_counter_and_binding")
	e = game(); var a: Dictionary = fixture(e, "fixture_gate", ["certain", "certain"])
	var result: Dictionary = commit_action(e, a)
	check(result.get("ok", false), "Valid baseline commit")
	save = e.save_data(); save.next_action = 1
	refused_atomic(e, save, "Counter rewind cannot reuse a committed ID")
	save = e.save_data(); save.next_action = true
	refused_atomic(e, save, "Boolean is not an action counter")
	e = game(); a = fixture(e); var before := C.bytes(e.save_data())
	a.bindings.actor_id = "actor_guard_z"
	check(not e.prepare_assessment(a).get("ok", false) and C.bytes(e.save_data()) == before, "Assessment cannot replace frozen acting actor")
	finish()

	start("03_pending_plan_rng_stage_and_receipt_tampering")
	e = game(); a = fixture(e)
	save = e.save_data(); save.pending[a.action_id].goal = "另一项行动"
	refused_atomic(e, save, "Frozen pending goal/context mismatch is rejected")
	save = e.save_data(); save.pending[a.action_id].context_hash = true
	refused_atomic(e, save, "Pending context hash bool is a typed atomic rejection")
	check(e.prepare_assessment(a).get("ok", false), "Valid plan freezes")
	save = e.save_data(); save.pending[a.action_id].branches[0].patches[0].delta = 0
	refused_atomic(e, save, "Ready candidate patches cannot change after freeze")
	save = e.save_data(); save.rng.state = "1"
	refused_atomic(e, save, "Ready top RNG must agree with frozen RNG before")
	var rolled: Dictionary = e.roll_once(a.action_id)
	check(rolled.get("ok", false) and rolled.rolls.size() == 2, "Compound action uses actual Godot component draws once")
	save = e.save_data(); save.pending[a.action_id].outcomes.offer = not save.pending[a.action_id].outcomes.offer
	refused_atomic(e, save, "Rolled outcome cannot be rewritten")
	save = e.save_data(); save.pending[a.action_id].rolls[0].value += 1
	refused_atomic(e, save, "Rolled number cannot be rewritten")
	var staged: Dictionary = e.stage(a.action_id)
	save = e.save_data(); save.pending[a.action_id].staged.actors.actor_player.stamina.current = 0
	refused_atomic(e, save, "Staged facts cannot be overwritten")
	check(e.commit(a.action_id, staged.stage_hash).get("ok", false), "Unchanged staged plan still commits after rejected loads")
	save = e.save_data(); save.receipts[a.action_id].after_version += 1
	refused_atomic(e, save, "Committed receipt tampering is rejected")
	save = e.save_data(); save.receipts[a.action_id].receipt_hash = true
	refused_atomic(e, save, "Committed receipt hash bool is a typed atomic rejection")
	before = C.bytes(e.save_data())
	check(e.commit(a.action_id, staged.stage_hash).get("already_committed", false) and C.bytes(e.save_data()) == before, "Committed token remains fully idempotent")
	check(not e.commit(a.action_id, "alternate_token").get("ok", false) and C.bytes(e.save_data()) == before, "Different plan/token cannot overwrite a committed action")
	finish()

	start("04_numeric_json_and_rng_string_boundaries")
	e = game()
	for v in ["9223372036854775808", "-9223372036854775809", "+1", "01", "-0", "", true, 123]:
		save = e.save_data(); save.rng.state = v
		refused_atomic(e, save, "Malformed exact RNG decimal rejected: " + str(v))
	check(C.int64_string("9223372036854775807") and C.int64_string("-9223372036854775808"), "Signed int64 edge strings remain representable")
	check(not C.safe(-9223372036854775808), "Unsafe int64 minimum is outside JSON number domain")
	a = fixture(e)
	for v in [NAN, INF, -INF, true]:
		var bad: Dictionary = a.duplicate(true); bad.components[0].parameters.A = v
		before = C.bytes(e.save_data())
		check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "Nonfinite/bool numeric parameter rejected")
	finish()

	start("05_scratch_candidate_failure_is_atomic")
	for resolver in ["review_half_invalid", "review_bool_delta", "review_unknown_cell"]:
		e = game(); a = fixture(e, resolver)
		before = C.bytes(e.save_data()); r = e.prepare_assessment(a)
		check(not r.get("ok", false) and C.bytes(e.save_data()) == before and e.state_copy().actors.actor_player.stamina.current == 8, "Failed later patch cannot half-apply earlier cost: " + resolver)
		check(not e.roll_once(a.action_id).get("ok", false) and C.bytes(e.save_data()) == before, "Rejected candidate cannot consume RNG: " + resolver)
	finish()

	start("06_fact_refs_plugin_switch_and_focus_are_frozen")
	e = game(); var begun: Dictionary = e.begin_intent("我找芦灯", {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_z"})
	a = Story.assessment(begun.request)
	var bad: Dictionary = a.duplicate(true); bad.components[0].fact_ref_ids.append("unregistered_fact")
	before = C.bytes(e.save_data())
	check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "Unknown fact_ref ID is rejected")
	bad = a.duplicate(true); bad.fact_refs[0].path = "/scenes/scene_wrong/name"; bad.fact_refs[0].expected = "暮潮渡口"
	check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "A path in the wrong scene cannot match a fact by name")
	bad = a.duplicate(true); bad.calculator = "always_win"
	check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "Model cannot choose an unregistered calculator")
	bad = a.duplicate(true); bad.resolver_id = "no_such_resolver"
	check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "Unregistered resolver is rejected")
	check(e.prepare_assessment(a).get("ok", false), "Original assessment freezes")
	before = C.bytes(e.save_data()); bad = a.duplicate(true); bad.resolver_id = "fixture_listen"
	check(not e.prepare_assessment(bad).get("ok", false) and C.bytes(e.save_data()) == before, "Changing registered resolver after freeze cannot revise action")
	check(e.attention({"world_id": "test_harbor_story", "kind": "tile", "id": "hex_1_0"}).get("ok", false) and C.bytes(e.save_data()) == before, "New focus cannot revise frozen assessment or RNG")
	check(not e.attention({"world_id": "another_world", "kind": "actor", "id": "actor_guard_a"}).get("ok", false), "Wrong-world focus rejected")
	finish()

	start("07_reordered_nested_json_multiple_actors_and_randoms")
	var state: Dictionary = Story.world()
	for id in ["actor_guard_z", "actor_guard_a"]:
		state.actors[id].hooks = ["patrol", "status_tick"]
		state.actors[id].patrol = {"route": [state.actors[id].hex, [1, 0]], "index": 0}
		state.actors[id].statuses = {"z_poison": {"id": "z_poison", "kind": "poison", "remaining_turns": 2, "magnitude": 2}, "a_poison": {"id": "a_poison", "kind": "poison", "remaining_turns": 2, "magnitude": 1}}
	e = game(state); a = fixture(e)
	check(e.prepare_assessment(a).get("ok", false), "Multi-actor/status compound plan freezes")
	var reference: Dictionary = e.action_copy(a.action_id)
	var restored := game(state)
	check(restored.load_data(parsed(reverse_dicts(e.save_data()))).get("ok", false), "All nested dictionary key orders survive actual JSON reload")
	check(restored.action_copy(a.action_id).plan_hash == reference.plan_hash, "Plan hash stable across reordered actors/status dictionaries")
	rolled = e.roll_once(a.action_id); var second: Dictionary = restored.roll_once(a.action_id)
	check(second.get("ok", false) and second.rolls == rolled.rolls and second.outcomes == rolled.outcomes, "Both random component values/order match across reordered reload")
	check(restored.load_data(parsed(reverse_dicts(restored.save_data()))).get("ok", false) and restored.roll_once(a.action_id).rolls == rolled.rolls, "Post-roll nested reload cannot reroll")
	staged = restored.stage(a.action_id)
	check(restored.commit(a.action_id, staged.stage_hash).get("ok", false), "Multi-actor hook plan commits")
	for id in ["actor_guard_z", "actor_guard_a"]:
		check(restored.state_copy().actors[id].health.current == 9 and restored.state_copy().actors[id].statuses.z_poison.remaining_turns == 1 and restored.state_copy().actors[id].statuses.a_poison.remaining_turns == 1, "Both sorted poison statuses tick exactly once: " + id)
	before = C.bytes(restored.save_data()); restored.commit(a.action_id, staged.stage_hash)
	check(C.bytes(restored.save_data()) == before, "Repeated receipt does not reapply hooks")
	finish()

	start("08_scene_and_traversal_isolation")
	state = Story.world()
	state.hexes["2,0"].scene_id = "scene_remote"
	state.scenes.scene_harbor.hex_ids.erase("hex_2_0")
	state.scenes.scene_remote = {"id": "scene_remote", "name": "远处房间", "layer_id": "other", "hex_ids": ["hex_2_0"]}
	state = C.normalized(state)
	var scene_validation: Dictionary = World.validate(state)
	if not scene_validation.get("ok", false): printerr("SCENE_FIXTURE: ", scene_validation)
	check(scene_validation.get("ok", false), "Two-scene fixture remains valid")
	check(Traversal.path(state, "actor_player", [2, 0], 19).is_empty() and not Traversal.reachable(state, "actor_player", 19).has("2,0"), "Movement cannot cross another scene through same coordinate space")
	r = World.apply(state, {"type": "actor_move", "actor_id": "actor_player", "scene_id": "scene_harbor", "hex": [2, 0]})
	check(not r.get("ok", false) and state.actors.actor_player.hex == [-1, 0], "Wrong-scene move cannot patch actor")
	state = Story.world(); state.actors.actor_player.statuses.flight = {"id": "flight", "kind": "flight", "remaining_turns": 2, "magnitude": 0}
	state.hexes["1,0"].ground_blocked = true
	check(not Traversal.path(state, "actor_player", [1, 0], 19).is_empty(), "Flight bypasses ground-only block")
	state.hexes["1,0"].air_blocked = true
	check(Traversal.path(state, "actor_player", [1, 0], 19).is_empty(), "Flight cannot bypass air block")
	state.hexes["1,0"].air_blocked = false; state.hexes["1,0"].all_blocked = true
	check(Traversal.path(state, "actor_player", [1, 0], 19).is_empty(), "Flight cannot bypass all block")
	finish()

	start("09_retry_and_narration_boundaries")
	e = game(); a = fixture(e, "fixture_listen", ["impossible", "impossible"], "请让我们过河")
	a.narration = "你已经成功过河并交掉所有酒。"
	before = C.bytes(e.state_copy())
	check(e.prepare_assessment(a).get("ok", false) and C.bytes(e.state_copy()) == before, "Narrative claiming success cannot commit facts")
	rolled = e.roll_once(a.action_id); staged = e.stage(a.action_id)
	check(rolled.rolls.is_empty() and not rolled.outcomes.offer and C.bytes(e.state_copy()) == before, "Impossible direct outcome still does not happen until commit")
	check(e.commit(a.action_id, staged.stage_hash).get("ok", false) and not e.state_copy().flags.gate_open and e.state_copy().items.item_wine.quantity == 3, "Committed facts follow outcome, not premature success prose")
	a = fixture(e, "fixture_listen", ["possible", "possible"], "换种说法，我能够渡河吗？")
	before = C.bytes(e.save_data()); r = e.prepare_assessment(a)
	check(r.get("code") == "REPEAT_ATTEMPT" and C.bytes(e.save_data()) == before, "No-cost paraphrase in unchanged resolver/facts cannot free-reroll")
	observed["narration_semantics_not_enforced"] = true
	observed["general_intent_equivalence_not_certified"] = true
	finish()

	start("10_public_projection_type_depth_boundary")
	e = game(); begun = e.begin_intent("观察芦灯", {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_a"})
	var encoded: String = C.bytes(begun.request)
	check(not encoded.contains("low_tide") and not encoded.contains("hidden_motive") and not encoded.contains("private_notes") and not encoded.contains('"rng"') and not encoded.contains('"receipts"'), "Default request/focus excludes named secrets and internal ledgers")
	var deep: Array = []
	for i in range(96): deep = [deep]
	check(not C.safe(deep), "Deep non-JSON-contract nested input is rejected with a bound")
	var cyclic: Dictionary = {}; cyclic.self = cyclic
	check(not C.safe(cyclic), "Cycle rejected without exhausting the GDScript stack")
	cyclic.clear()
	finish()

	start("11_final_narration_authority_privacy_and_replay")
	state = Story.world(); state.actors.actor_guard_z.hooks = ["patrol"]
	state.actors.actor_guard_z.patrol = {"route": [[0, 1], [1, 0]], "index": 0}
	e = game(state)
	begun = e.begin_intent("交酒问渡口", {"world_id": state.world_id, "kind": "actor", "id": "actor_guard_a"})
	a = Story.assessment(begun.request, "fixture_gate", ["possible", "possible"])
	check(e.narration_request(a.action_id).is_empty(), "Awaiting assessment cannot request final outcome narration")
	check(e.prepare_assessment(a).get("ok", false), "Narration baseline plan freezes")
	rolled = e.roll_once(a.action_id)
	check(e.narration_request(a.action_id).is_empty(), "Unstaged rolls cannot publish final outcome narration")
	staged = e.stage(a.action_id)
	var nreq: Dictionary = e.narration_request(a.action_id)
	encoded = C.bytes(nreq)
	check(nreq.context.provisional_until_commit and nreq.context.authoritative_result.rolls == rolled.rolls, "Staged narration numbers are real and explicitly provisional")
	check(not encoded.contains("patrol_advance") and not encoded.contains("low_tide") and not encoded.contains("private_quest_answer") and not encoded.contains('"rng"') and not encoded.contains('"receipt"'), "Narration view excludes private patrol metadata, secret flags and internal receipt/RNG")
	var nreply := {"schema_version": "ai_gm_narration/v1", "action_id": a.action_id, "state_version": nreq.state_version, "context_hash": nreq.context_hash, "narration": "你已经无代价通关，所有失败都改成成功。"}
	before = C.bytes(e.save_data())
	var nbad: Dictionary = nreply.duplicate(true); nbad.patches = [{"type": "flag_set", "flag_id": "gate_open", "value": true}]
	check(e.validate_narration_reply(nbad).get("code") == "INVALID_NARRATION" and C.bytes(e.save_data()) == before, "Narrator cannot inject a patch")
	nbad = nreply.duplicate(true); nbad.state_version = true
	check(e.validate_narration_reply(nbad).get("code") == "INVALID_NARRATION" and C.bytes(e.save_data()) == before, "Boolean narration version is a typed rejection")
	nbad = nreply.duplicate(true); nbad.context_hash = true
	check(e.validate_narration_reply(nbad).get("code") == "INVALID_NARRATION" and C.bytes(e.save_data()) == before, "Nonstring narration context hash is a typed rejection")
	result = e.validate_narration_reply(nreply)
	check(result.get("ok", false) and not result.semantic_verified and result.authoritative_result.rolls == rolled.rolls and C.bytes(e.save_data()) == before, "Untrue prose stays text-only and expressly uncertified")
	check(e.commit(a.action_id, staged.stage_hash).get("ok", false), "Commit remains independent of narrator quality")
	check(e.validate_narration_reply(nreply).get("code") == "STALE_NARRATION", "A staged/provisional context cannot be reused as committed narration")
	nreq = e.narration_request(a.action_id)
	check(not nreq.context.provisional_until_commit, "Committed narration is no longer provisional")
	var historical: String = C.bytes(nreq)
	var next: Dictionary = fixture(e, "fixture_listen", ["certain", "certain"], "等守卫说明另一件事")
	check(commit_action(e, next).get("ok", false) and C.bytes(e.narration_request(a.action_id)) == historical, "Later turns cannot replace historical narration with current state")
	finish()

	start("12_malformed_type_rejection_has_structured_errors")
	e = game(); a = fixture(e)
	for field in ["schema_version", "context_hash"]:
		bad = a.duplicate(true); bad[field] = true
		before = C.bytes(e.save_data()); result = e.prepare_assessment(bad)
		check(not result.get("ok", false) and result.has("code") and C.bytes(e.save_data()) == before, "Assessment malformed type rejected cleanly: " + field)
	for field in ["schema_version", "rule_id"]:
		save = e.save_data(); save[field] = true
		before = C.bytes(e.save_data()); result = e.load_data(save)
		check(not result.get("ok", false) and result.has("code") and C.bytes(e.save_data()) == before, "Save malformed type rejected cleanly: " + field)
	state = Story.world(); state.schema_version = true
	result = World.validate(state)
	check(not result.get("ok", false) and result.get("code") == "INVALID_WORLD", "World malformed schema type has a structured rejection")
	state = Story.world(); state.actors.actor_player.id = true
	result = World.validate(state)
	check(not result.get("ok", false) and result.get("code") == "INVALID_WORLD", "World malformed actor stable ID has a structured rejection")
	finish()

	start("13_pre_roll_cancel_recovery_boundaries")
	e = game(); a = fixture(e, "fixture_listen", ["impossible", "impossible"], "请准许过河")
	commit_action(e, a)
	a = fixture(e, "fixture_listen", ["possible", "possible"], "换句话问能否过河")
	e.prepare_assessment(a)
	var before_cancel: Dictionary = e.save_data()
	result = e.cancel_intent(a.action_id)
	var after_cancel: Dictionary = e.save_data()
	check(result.get("ok", false) and after_cancel.pending.is_empty() and after_cancel.attempt_ledger == before_cancel.attempt_ledger and after_cancel.receipts == before_cancel.receipts and after_cancel.rng == before_cancel.rng and after_cancel.state == before_cancel.state and after_cancel.next_action == before_cancel.next_action, "Pre-roll cancellation releases pending but preserves prior attempts, receipts, RNG and facts")
	begun = e.begin_intent("进行一个不同的新意图")
	check(begun.get("ok", false) and begun.request.action_id != a.action_id, "New intent can start after cancellation without reusing ID")
	e = game(); a = fixture(e); e.prepare_assessment(a); e.roll_once(a.action_id)
	before = C.bytes(e.save_data()); result = e.cancel_intent(a.action_id)
	check(result.get("code") == "OUTCOME_FROZEN" and C.bytes(e.save_data()) == before, "Post-roll cancellation is refused with full state/RNG unchanged")
	finish()

	var report := {"schema": "ai_gm_independent_review/v1", "assertions_total": checks, "assertions_passed": checks - failures.size(), "cases_total": cases.size(), "cases_passed": cases.filter(func(x: Dictionary) -> bool: return x.passed).size(), "cases": cases, "failures": failures, "observations": observed, "test_only": true, "external_ai_called": false, "ui_integration_tested": false, "production_formula_evaluated": false, "live_model_quality_evaluated": false}
	var file := FileAccess.open("res://artifacts/ai_gm_rebuilt_review_20261002/adversarial_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("INDEPENDENT AI-GM REVIEW: %d/%d cases, %d/%d assertions" % [report.cases_passed, cases.size(), checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
