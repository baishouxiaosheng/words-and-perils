extends SceneTree
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
var assertions := 0
var failures: Array = []
var cases: Array = []
var case_fail_start := 0
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); printerr("FAIL: " + label)
func start_case(label: String) -> void:
	cases.append({"case": label, "passed": false}); case_fail_start = failures.size()
func end_case() -> void: cases[-1].passed = failures.size() == case_fail_start
func registry() -> Dictionary:
	var result: Dictionary = {}
	for variant in ["gate", "listen", "tree", "unknown_patch", "nonfinite", "overlap"]:
		var resolver := Resolver.new(variant); result[resolver.resolver_id()] = resolver
	return result
func game(state: Dictionary = {}, seed: int = 123, policy: Dictionary = {}) -> RefCounted:
	return GMEngine.new(Story.world() if state.is_empty() else state, Rule.new(), registry(), policy, seed)
func fixture(engine: RefCounted, resolver: String = "fixture_gate", disposition: Array = ["possible", "possible"], goal: String = "拿出果酒，再和芦灯交谈") -> Dictionary:
	var begun: Dictionary = engine.begin_intent(goal)
	check(begun.ok, "Explicit intent creates an assessment request")
	if not begun.ok: return {}
	return Story.assessment(begun.request, resolver, disposition)
func resolve(engine: RefCounted, reply: Dictionary) -> Dictionary:
	var prepared: Dictionary = engine.prepare_assessment(reply); check(prepared.ok, "Assessment freezes validated candidate plans")
	if not prepared.ok: return prepared
	var rolled: Dictionary = engine.roll_once(reply.action_id); check(rolled.ok, "Program resolves the one-time check")
	if not rolled.ok: return rolled
	var staged: Dictionary = engine.stage(reply.action_id); check(staged.ok, "Selected plan stages without mutating facts")
	if not staged.ok: return staged
	return engine.commit(reply.action_id, staged.stage_hash)
func roundtrip(engine: RefCounted) -> RefCounted:
	var parser := JSON.new(); check(parser.parse(C.bytes(engine.save_data())) == OK, "Saved bytes parse as exact JSON")
	var restored := game()
	var loaded: Dictionary = restored.load_data(parser.data)
	check(loaded.ok, "Save stage is re-derived and restored")
	if not loaded.ok: printerr(str(loaded))
	return restored
func _initialize() -> void:
	start_case("01_default_calculator_missing")
	var engine := GMEngine.new(Story.world(), null, registry())
	var begun: Dictionary = engine.begin_intent("走一步")
	check(begun.ok and engine.rule_id() == "NOT_CONFIGURED", "Production default is an unconfigured calculator")
	var before: Dictionary = engine.state_copy()
	var reply: Dictionary = Story.assessment(begun.request)
	var result: Dictionary = engine.prepare_assessment(reply)
	check(not result.ok and result.code == "NOT_CONFIGURED" and engine.state_copy() == before, "Missing calculator never supplies a fixture ruling")
	check(not engine.roll_once(reply.action_id).ok, "No deliberate safe action skips assessment")
	end_case()

	start_case("02_attention_readonly_text_priority")
	engine = game(); before = engine.save_data()
	var focus := {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_z"}
	check(engine.attention(focus).ok and engine.save_data() == before, "Clicking a character only projects readonly context")
	check(not engine.begin_intent("   ", focus).ok and engine.save_data() == before, "Empty text cannot become an action")
	begun = engine.begin_intent("  明确对芦灯说话，不是桐岸  ", focus)
	check(begun.ok and begun.request.context.goal == "  明确对芦灯说话，不是桐岸  " and begun.request.context.attention_focus.id == "actor_guard_z" and begun.request.context.text_priority == "explicit_player_text", "Exact player text retains priority over a different focus")
	var frozen: Dictionary = engine.action_copy(begun.request.action_id)
	engine.attention({"world_id": "test_harbor_story", "kind": "tile", "id": "hex_1_0"})
	check(engine.action_copy(begun.request.action_id) == frozen, "New focus cannot rewrite an active snapshot")
	before = engine.state_copy(); var original_id: String = begun.request.action_id
	check(engine.cancel_intent(original_id).ok and engine.state_copy() == before, "Awaiting assessment intent cancels without factual changes")
	begun = engine.begin_intent("修正明确目标后重新提交")
	check(begun.ok and begun.request.action_id != original_id, "Cancelled intent IDs are never reused")
	end_case()

	start_case("03_true_fact_numbers")
	engine = game(); reply = fixture(engine)
	result = engine.prepare_assessment(reply)
	check(result.ok and result.checks[0].derived_facts.R == 2 and result.checks[0].derived_facts.N == 2 and result.checks[0].success_at_most == 5000 and result.checks[1].success_at_most == 8000, "Test rule derives wine quantity, soldiers and exact basis-point thresholds")
	var modified: Dictionary = Story.world(); modified.items.item_wine.hex = [1, 0]
	engine = game(modified); reply = fixture(engine); result = engine.prepare_assessment(reply)
	check(result.ok and result.checks[0].derived_facts.R == 0 and result.checks[0].success_at_most == 3000, "Distant wine cannot count as an available resource")
	modified = Story.world(); modified.items.item_wine.quantity = 1; modified.actors.actor_guard_z.health.current = 0
	engine = game(modified); reply = fixture(engine); result = engine.prepare_assessment(reply)
	check(result.ok and result.checks[0].derived_facts.R == 1 and result.checks[0].derived_facts.N == 1, "Quantity and living soldier count come from frozen facts")
	end_case()

	start_case("04_factref_type_and_version_rejections")
	engine = game(); reply = fixture(engine); before = engine.save_data()
	var bad: Dictionary = reply.duplicate(true); bad.fact_refs[0].expected = 100
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Forged fact value rejected atomically")
	bad = reply.duplicate(true); bad.fact_refs[0].path = "/actors/actor_guard_a/secrets/gate_password"; bad.fact_refs[0].expected = "low_tide"
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Private factref not implicitly public")
	bad = reply.duplicate(true); bad.components[0].parameters.A = INF
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Non-finite numeric assessment rejected")
	bad = reply.duplicate(true); bad.state_version = 3
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Stale model version rejected")
	var cyclic: Dictionary = {}; cyclic["cycle"] = cyclic
	check(not C.safe(cyclic) and C.bytes(cyclic).is_empty(), "Cyclic plugin data rejects without recursion overflow")
	var deep: Variant = 1
	for depth in range(70): deep = {"nested": deep}
	check(not C.safe(deep), "Excessively deep JSON input is bounded and rejected")
	bad = reply.duplicate(true); bad.bindings.actor_id = "actor_guard_a"
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Model binding cannot change the player acting actor")
	for field in ["schema_version", "context_hash"]:
		bad = reply.duplicate(true); bad[field] = true
		check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Boolean assessment " + field + " rejects cleanly")
	bad = reply.duplicate(true); bad.script = "do anything"
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "Model script extensions remain data and are rejected")
	end_case()

	start_case("05_candidate_plans_freeze_before_roll")
	for resolver in ["fixture_unknown_patch", "fixture_nonfinite", "fixture_overlap"]:
		engine = game(); reply = fixture(engine, resolver); before = engine.save_data()
		check(not engine.prepare_assessment(reply).ok and engine.save_data() == before, "Invalid pre-roll candidate plan rejected: " + resolver)
		check(not engine.roll_once(reply.action_id).ok, "Invalid plan cannot consume RNG: " + resolver)
	engine = game(); reply = fixture(engine); check(engine.prepare_assessment(reply).ok, "Valid exhaustive candidate plan freezes")
	before = engine.save_data(); bad = reply.duplicate(true); bad.components[0].parameters.A = 4
	check(not engine.prepare_assessment(bad).ok and engine.save_data() == before, "A frozen assessment cannot be rewritten before rolling")
	var unspent_rng: Dictionary = engine.save_data().rng
	check(engine.cancel_intent(reply.action_id).ok and engine.save_data().rng == unspent_rng, "Ready-roll intent can be cancelled without spending RNG")
	var replacement: Dictionary = fixture(engine)
	check(not engine.prepare_assessment(reply).ok and engine.prepare_assessment(replacement).ok, "Corrected intent revalidates fresh binding/fact refs; old action reply cannot carry over")
	end_case()

	start_case("06_partial_and_direct_outcomes_narration")
	engine = game(); reply = fixture(engine, "fixture_gate", ["certain", "impossible"])
	reply.narration = "叙事声称果酒已全部消失、城门也已经打开。"
	before = engine.state_copy(); result = engine.prepare_assessment(reply); check(result.ok and engine.state_copy() == before, "Assessment narrative cannot change world facts")
	result = engine.roll_once(reply.action_id); check(result.ok and result.rolls.is_empty() and result.outcomes.offer and not result.outcomes.talk, "Direct compound success/failure does not invent a roll")
	result = engine.stage(reply.action_id); check(result.ok and result.branch_id == "partial_success" and engine.state_copy() == before, "Partial success costs/effects were pre-fixed and staging is readonly")
	var staged_token: String = result.stage_hash
	var narrated_request: Dictionary = engine.narration_request(reply.action_id)
	check(not narrated_request.is_empty() and narrated_request.context.authoritative_result.outcomes.offer and not narrated_request.context.authoritative_result.outcomes.talk, "Narrator receives the program's authoritative partial outcome")
	var narrative := {"schema_version": "ai_gm_narration/v1", "action_id": reply.action_id, "state_version": narrated_request.state_version, "context_hash": narrated_request.context_hash, "narration": "城门已打开，这一句语义上并不可靠。"}
	var narrative_bad: Dictionary = narrative.duplicate(true); narrative_bad.patches = [{"type": "flag_set", "flag_id": "gate_open", "value": true}]
	var immutable_transaction: Dictionary = engine.save_data()
	check(not engine.validate_narration_reply(narrative_bad).ok and engine.save_data() == immutable_transaction, "Narrative patch attempts are rejected without changing commit/RNG")
	for field in ["schema_version", "state_version", "context_hash"]:
		narrative_bad = narrative.duplicate(true); narrative_bad[field] = true
		check(not engine.validate_narration_reply(narrative_bad).ok and engine.save_data() == immutable_transaction, "Boolean narration " + field + " rejects cleanly")
	var narrative_result: Dictionary = engine.validate_narration_reply(narrative)
	check(narrative_result.ok and not narrative_result.semantic_verified and not narrative_result.authoritative_result.outcomes.talk and engine.save_data() == immutable_transaction, "Text validation cannot certify narrative honesty or override the authoritative outcome")
	result = engine.commit(reply.action_id, staged_token)
	check(result.ok and not engine.narration_request(reply.action_id).context.provisional_until_commit, "Invalid narrative does not block a legitimate numeric commit")
	check(result.ok and engine.state_copy().items.item_wine.quantity == 2 and engine.state_copy().flags.npc_listened and not engine.state_copy().flags.gate_open and engine.state_copy().turn == 1, "Only typed partial-success patches commit; narration is not facts")
	end_case()

	start_case("07_save_reload_every_stage_real_rng")
	engine = game(); reply = fixture(engine); var id: String = reply.action_id
	engine = roundtrip(engine); check(engine.prepare_assessment(reply).ok, "Awaiting-assessment restore accepts the same frozen assessment")
	engine = roundtrip(engine); var saved_pre_roll: Dictionary = engine.save_data()
	var rolled: Dictionary = engine.roll_once(id)
	check(rolled.ok and rolled.rolls.size() == 2 and rolled.rolls[0].source == "program_rng", "Godot RNG actually generates both random component draws")
	var rolled_save: Dictionary = engine.save_data()
	check(not engine.cancel_intent(id).ok and engine.save_data() == rolled_save, "Already rolled intent cannot be cancelled for a free reroll")
	var again: Dictionary = engine.roll_once(id)
	check(again.ok and again.already_rolled and again.rolls == rolled.rolls, "Same action rolls exactly once")
	var replay := game(); check(replay.load_data(saved_pre_roll).ok and replay.roll_once(id).rolls == rolled.rolls, "Reloading before roll reproduces the same saved RNG sequence")
	var data: Dictionary = engine.save_data()
	check(data.rng.state is String and data.rng.seed is String and abs(int(data.rng.state)) > 9007199254740991, "64-bit RNG state remains a decimal string beyond JSON safe integer precision")
	engine = roundtrip(engine); check(engine.roll_once(id).rolls == rolled.rolls, "Reload after roll cannot reroll")
	var staged: Dictionary = engine.stage(id); check(staged.ok, "Random result selects its frozen candidate")
	engine = roundtrip(engine); check(engine.stage(id).stage_hash == staged.stage_hash, "Reload staged transaction preserves commit token")
	result = engine.commit(id, staged.stage_hash); check(result.ok, "Reloaded staged action commits")
	check(result.receipt.rolls == rolled.rolls and engine.authoritative_result(id).rolls == rolled.rolls, "Committed receipt preserves actual public dice for later narration/audit")
	engine = roundtrip(engine); check(engine.commit(id, staged.stage_hash).already_committed, "Reloaded committed receipt is idempotent")
	end_case()

	start_case("08_atomic_commit_tamper_and_repeat")
	engine = game(); reply = fixture(engine); check(engine.prepare_assessment(reply).ok, "Commit test prepares")
	engine.roll_once(reply.action_id); staged = engine.stage(reply.action_id); before = engine.state_copy()
	check(not engine.commit(reply.action_id, "forged token").ok and engine.state_copy() == before, "Conflicting token cannot change facts")
	var corrupt: Dictionary
	for field in ["schema_version", "rule_id"]:
		corrupt = engine.save_data(); corrupt[field] = true
		check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Boolean saved " + field + " rejects cleanly")
	corrupt = engine.save_data(); corrupt.pending[reply.action_id].context_hash = true
	check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Boolean pending context hash rejects cleanly")
	corrupt = engine.save_data(); corrupt.pending[reply.action_id].staged.items.item_wine.quantity = 0
	check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Tampered staged save is refused without replacing live state")
	corrupt = engine.save_data(); corrupt.rng.state = 123
	check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Numeric RNG save loses precision and is rejected")
	result = engine.commit(reply.action_id, staged.stage_hash); check(result.ok, "Valid staged candidate publishes atomically")
	before = engine.state_copy(); again = engine.commit(reply.action_id, staged.stage_hash)
	check(again.ok and again.already_committed and engine.state_copy() == before and before.state_version == 1 and before.turn == 1 and before.items.item_wine.quantity == 2, "Repeat commit cannot double-charge or increment turn")
	corrupt = engine.save_data(); corrupt.receipts[reply.action_id].receipt_hash = true
	check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Boolean receipt hash rejects cleanly")
	corrupt = engine.save_data(); corrupt.next_action = 1
	check(not engine.load_data(corrupt).ok and engine.state_copy() == before, "Corrupted next-action counter cannot collide with an idempotent receipt")
	check(not engine.commit(reply.action_id, "different outcome").ok and engine.state_copy() == before, "Same action ID cannot rewrite its committed outcome")
	end_case()

	start_case("09_actor_order_status_poison_patrol_once")
	modified = Story.world()
	for actor_id in ["actor_guard_z", "actor_guard_a"]:
		modified.actors[actor_id].hooks = ["patrol", "status_tick"]
		modified.actors[actor_id].statuses = {"status_poison": {"id": "status_poison", "kind": "poison", "remaining_turns": 2, "magnitude": 1}, "status_drunk": {"id": "status_drunk", "kind": "drunk", "remaining_turns": 1, "magnitude": 1}}
		modified.actors[actor_id].patrol = {"route": [modified.actors[actor_id].hex, [1, 0]], "index": 0}
	engine = game(modified); reply = fixture(engine, "fixture_listen", ["certain", "certain"]); check(engine.prepare_assessment(reply).ok, "Explicit configured status/patrol hooks freeze")
	var ordered: Dictionary = engine.action_copy(reply.action_id)
	corrupt = engine.save_data(); var reversed: Dictionary = {}
	var ids: Array = corrupt.state.actors.keys(); ids.reverse()
	for actor_id in ids: reversed[actor_id] = corrupt.state.actors[actor_id]
	corrupt.state.actors = reversed; corrupt.pending[reply.action_id].snapshot.actors = reversed.duplicate(true)
	replay = game(); result = replay.load_data(corrupt)
	check(result.ok and replay.action_copy(reply.action_id).plan_hash == ordered.plan_hash and replay.action_copy(reply.action_id).branches == ordered.branches, "Two actors and statuses retain exact hashes across reordered JSON dictionaries")
	replay.roll_once(reply.action_id); staged = replay.stage(reply.action_id); result = replay.commit(reply.action_id, staged.stage_hash)
	check(result.ok, "Hook candidate commits")
	for actor_id in ["actor_guard_a", "actor_guard_z"]:
		var npc: Dictionary = replay.state_copy().actors[actor_id]
		check(npc.health.current == 11 and npc.statuses.status_poison.remaining_turns == 1 and not npc.statuses.has("status_drunk") and npc.hex == [1, 0] and npc.patrol.index == 1, "One poison tick and one adjacent patrol step: " + actor_id)
	var public_summary: Dictionary = replay.authoritative_result(reply.action_id)
	check(not C.bytes(public_summary).contains("patrol_advance") and not C.bytes(public_summary).contains("index"), "Narrative projection hides internal patrol counters but keeps visible actor movement")
	before = replay.state_copy(); replay.commit(reply.action_id, staged.stage_hash)
	check(replay.state_copy() == before, "Idempotent receipt does not tick poison/patrol again")
	end_case()

	start_case("10_unified_ground_flight_all_air_blocks")
	modified = Story.world(); modified.hexes["1,0"].ground_blocked = true
	check(Traversal.path(modified, "actor_player", [1, 0], 19).is_empty() and not Traversal.reachable(modified, "actor_player", 19).has("1,0"), "Ground-blocked target excluded from both path and range")
	modified.actors.actor_player.statuses.status_flight = {"id": "status_flight", "kind": "flight", "remaining_turns": 3, "magnitude": 0}
	check(not Traversal.path(modified, "actor_player", [1, 0], 19).is_empty() and Traversal.reachable(modified, "actor_player", 19).has("1,0"), "Flight bypasses ground block in both APIs")
	modified.hexes["1,0"].all_blocked = true
	check(Traversal.path(modified, "actor_player", [1, 0], 19).is_empty() and not Traversal.reachable(modified, "actor_player", 19).has("1,0"), "Flight cannot bypass all-block")
	modified.hexes["1,0"].all_blocked = false; modified.hexes["1,0"].air_blocked = true
	check(Traversal.path(modified, "actor_player", [1, 0], 19).is_empty(), "Flight cannot bypass air block")
	engine = game(); reply = fixture(engine, "fixture_tree", ["certain", "certain"]); result = resolve(engine, reply)
	check(result.ok and engine.state_copy().hexes["1,0"].ground_blocked and engine.state_copy().hexes.size() == 19 and engine.state_copy().items.size() == 1, "Fallen tree uses cell blocking without a new entity/model")
	end_case()

	start_case("11_semantic_retry_requires_material_change")
	engine = game(); reply = fixture(engine, "fixture_listen", ["impossible", "impossible"], "问守卫是否愿意让我过河")
	result = resolve(engine, reply); check(result.ok, "No-cost denied attempt commits a real turn")
	reply = fixture(engine, "fixture_listen", ["possible", "possible"], "换句话问一下，她能准许我渡河吗？")
	before = engine.save_data(); result = engine.prepare_assessment(reply)
	check(not result.ok and result.code == "REPEAT_ATTEMPT" and engine.save_data() == before, "Paraphrase/new action ID/new turn alone cannot reroll unchanged semantic conditions")
	var committed_attempts: Dictionary = engine.save_data().attempt_ledger
	check(engine.cancel_intent(reply.action_id).ok and engine.save_data().attempt_ledger == committed_attempts, "Cancelling rejected pre-roll intent preserves committed semantic attempts")
	reply = fixture(engine, "fixture_listen", ["possible", "possible"], "再换个措辞询问")
	check(not engine.prepare_assessment(reply).ok and engine.save_data().attempt_ledger == committed_attempts, "Cancellation cannot erase a previous unchanged denied attempt")
	engine = game(); reply = fixture(engine); result = resolve(engine, reply); check(result.ok, "Paid attempt commits its fixed material cost")
	reply = fixture(engine); result = engine.prepare_assessment(reply)
	check(result.ok and result.checks[0].derived_facts.wine_quantity == 2, "A new paid attempt sees changed real resource/stamina conditions")
	end_case()

	start_case("12_story_model_view_secret_allowlist_file_roundtrip")
	engine = game(); begun = engine.begin_intent("听芦灯说明渡口的安排", {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_a"})
	var encoded := C.bytes(begun.request)
	check(begun.request.context.facts.story_anchors.anchor_passage.text.contains("渡船") and begun.request.context.facts.actors.actor_guard_a.observed_dialogue.size() == 1, "Fixed story anchor and authored NPC dialogue support interaction testing")
	check(not encoded.contains("low_tide") and not encoded.contains("hidden_motive") and not encoded.contains("private_notes") and not encoded.contains("private_quest_answer") and not encoded.contains('"rng"') and not encoded.contains('"seed"') and not encoded.contains('"receipts"'), "ModelView hides secrets, unknown NPC extension, private flags and internal RNG/receipts")
	var expanded: Dictionary = engine.save_data(); expanded.policy.npc_secret_allowlist = ["/actors/actor_guard_a/secrets/gate_password"]
	before = engine.save_data()
	check(not engine.load_data(expanded).ok and engine.save_data() == before, "A saved policy cannot expand the trusted runtime secret allowlist")
	var policy := {"npc_secret_allowlist": ["/actors/actor_guard_a/secrets/gate_password"], "public_flag_ids": ["gate_open"]}
	engine = game({}, 123, policy); begun = engine.begin_intent("询问通行暗号", {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_a"}); encoded = C.bytes(begun.request)
	check(encoded.contains("low_tide") and not encoded.contains("hidden_motive") and begun.request.context.attention_focus.facts.secrets.size() == 1, "Explicit one-secret allowlist reveals only that field, including focus")
	modified = Story.world(); modified.schema_version = true
	check(not game(modified).ready().ok, "Boolean world schema is cleanly INVALID_WORLD")
	modified = Story.world(); modified.actors.actor_player.id = true
	check(not game(modified).ready().ok, "Boolean stable actor ID is cleanly INVALID_WORLD")
	modified = Story.world(); modified.actors.actor_guard_a.observed_dialogue = [{"secret": "untyped private object"}]
	check(not game(modified).ready().ok, "Allowlisted public dialogue refuses arbitrary nested objects")
	var path := "/tmp/ai_gm_rebuilt/transaction_save.json"
	check(engine.save_file(path).ok, "Save file writes by temporary atomic rename")
	replay = game({}, 123, policy); check(replay.load_file(path).ok and C.bytes(replay.save_data()) == C.bytes(engine.save_data()), "Actual file JSON save/load restores the frozen request")
	end_case()
	var report := {"schema": "ai_gm_rebuilt_test_report/v1", "test_only": true, "cases_passed": cases.filter(func(entry: Dictionary) -> bool: return entry.passed).size(), "cases_total": cases.size(), "assertions_passed": assertions - failures.size(), "assertions_total": assertions, "cases": cases, "failures": failures,
		"boundaries": {"new_rebuilt_source": true, "restored_old_source": false, "ui_connected": false, "live_api_connected": false, "real_model_quality_evaluated": false, "fixture_rule_final_balance": false}}
	var file := FileAccess.open("res://artifacts/runtime_ai_capacity_20261004/regressions/integration_report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("AI-GM REBUILT: %d/%d integration cases, %d/%d assertions" % [report.cases_passed, cases.size(), assertions - failures.size(), assertions])
	quit(0 if failures.is_empty() else 1)
