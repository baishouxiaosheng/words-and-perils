extends "res://tests/status_river_gate_b/test_budget_matrix.gd"
## Supplemental bounded test only. The parent must copy this file into its
## frozen test candidate and schedule the original guarded native slot.
## No new world search, HTTP, cap change, history fabrication, or reroll.
## Reuses the real1801 fixture and the existing lossless budget/Codec probes.
const WARMUP_COMMITS := 6
const RECALL_RECORD_CAP := 6
const RECALL_BYTE_CAP := 4096
const INTENT_SAMPLES := [4095, 4096, 4097]
const OVERSIZE_INTENT_BYTES := 65537
const ORDINARY_INTENTS := {
	100: "先查看芦灯和旧灯的情况，再检查背包里的苦叶解毒剂与轻羽药剂，确认自己的中毒和飞行还会持续多久。若道路允许，就沿干地靠近旧灯，向芦灯询问安全落脚的位置，然后比较原地休息与先解毒的顺序。此时先不进行攻击。",
	300: "我想先查看芦灯、旧灯和附近河岸的情况，确认自己的生命、体力、中毒与飞行状态，再检查背包中的苦叶解毒剂、轻羽药剂、苦叶毒剂和岸木长板。请先比较原地解毒后休息与先沿干地靠近旧灯再休息这两种顺序，考虑状态剩余次数、体力消耗和落脚安全。若现有规则允许，我准备先使用自己的解毒剂，再向芦灯询问旧灯的线索，随后沿可通行的地面路线观察北坡窄口；不要把关注芦灯当成对她用药，也不要把岸木长板默认当桥。最后检查是否仍在飞行，以及目前能否安全落地。遇到未具备的动作、阻挡或缺少信息时，请保留原目标并说明需要确认的内容，让我决定下一步；整个计划不涉及攻击，也不把观察结果提前当成已经完成。请把各个步骤分别列出供我仔细确认。"
}
var full_history_rows: Array = []
var source_attempts: Array = []

func _initialize() -> void:
	case_name = "budget_full_history"
	if not storage_safe():
		finish()
		return
	run_full_history()
	report["budget_matrix"] = full_history_rows
	report["real_committed_history"] = committed_history
	report["real_source_attempts"] = source_attempts
	var required_blocked: Array = []
	var admitted_count := 0
	var expected_rejections := 0
	var diagnostic_long_blocked: Array = []
	var worst_margin: Variant = null
	for row in full_history_rows:
		var margin: int = int(row.get("public_headroom_bytes", PUBLIC_CAP))
		worst_margin = margin if worst_margin == null else mini(int(worst_margin), margin)
		if row.get("transport_admitted", false):
			admitted_count += 1
		elif row.get("expected_oversize_rejection", false):
			expected_rejections += 1
		elif row.get("required_adoption_gate", false):
			required_blocked.append(row.scenario)
		else:
			diagnostic_long_blocked.append(row.scenario)
	report["full_history_summary"] = {
		"scenarios": full_history_rows.size(), "admitted_scenarios": admitted_count,
		"expected_oversize_rejections": expected_rejections,
		"short_and_ordinary_intent_adoption_blockers": required_blocked,
		"long_intent_diagnostic_blocked_scenarios": diagnostic_long_blocked,
		"worst_candidate_public_headroom_bytes": worst_margin,
		"short_and_ordinary_intent_adoption_transport_pass": completed and failures.is_empty() and required_blocked.is_empty(),
		"ordinary_intent_character_samples": [100, 300],
		"ordinary_samples_are_request_only_not_action_support_claims": true,
		"long_intent_playability_claimed": false,
		"long_intent_support_is_deferred": true,
		"safety_rejection_is_not_playable_pass": true,
		"fixed_public_cap": PUBLIC_CAP, "existing_wrapper_cap": WRAPPER_CAP,
		"memory_record_limit": RECALL_RECORD_CAP, "memory_record_bytes_limit": RECALL_BYTE_CAP,
		"production_files_changed": false, "model_calls": 0, "network_sends": 0,
		"godot_execution_owned_by_parent": true
	}
	finish()

func run_full_history() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter):
		return
	var original: Dictionary = adapter.engine.save_data()
	if not check(original.state.turn == 0 and original.pending.is_empty() and original.receipts.is_empty() and original.campaign_memory.events.is_empty() and original.state.status_foundation.instances.is_empty(), "full-history fixture begins only in pristine real1801 new-status Coast"):
		return
	# The sole authored initial condition is the keeper's public poison. Player
	# status sources, inventory costs, resources and all memories come from play.
	var initial: Dictionary = original.duplicate(true)
	var added: Dictionary = F.Foundation.runtime().apply_status(initial.state.status_foundation, "poison", "actor", NPC_ID, "item_poison_vial", F.Content.profile("poison_vial").parameters)
	if not check(added.ok, "offline turn0 keeper-only public poison validates"):
		return
	initial.state.status_foundation = added.store
	var stripped: Dictionary = initial.duplicate(true)
	stripped.state.status_foundation = original.state.status_foundation.duplicate(true)
	if not check(C.bytes(stripped) == C.bytes(original), "turn0 setup changes only keeper status store; no player pool, source quantity, RNG, history, or pending edit"):
		return
	if not check(adapter.engine.load_data(initial).ok, "keeper-only authored setup passes real complete engine validation"):
		return
	report["fixture_provenance"] = {
		"kind": "offline_authored_turn0_keeper_poison_NOT_original_world_fact",
		"source_world": F.identity(adapter.state_copy()), "seed": F.SEED,
		"worlds_constructed": 1, "seed_search": false, "rerolls": 0,
		"initial_player_statuses": 0, "initial_npc_statuses": 1,
		"ordinary_history_commits": WARMUP_COMMITS, "ordinary_source_commits_required": 2,
		"rule": adapter.engine.rule_id(),
		"source_outcome_policy": "fixed seed1 and original resolver-owned release rule; first failed source stops, never retry or rewrite outcome"
	}
	for turn in range(1, WARMUP_COMMITS + 1):
		var before_rng: Dictionary = adapter.engine.save_data().rng
		if not commit_observe(adapter, turn):
			return
		if not check(C.bytes(adapter.engine.save_data().rng) == C.bytes(before_rng), "ordinary safe-direct observation does not advance random generator: " + str(turn)):
			return
	var warmup: Dictionary = adapter.engine.save_data()
	check(F.status(warmup.state, "poison").is_empty() and F.status(warmup.state, "flight").is_empty(), "player states are not preseeded to survive history warmup")
	report["warmup_recall"] = history_evidence(adapter)
	if not commit_actual_source(adapter, "item_poison_vial", "poison"):
		return
	if not commit_actual_source(adapter, "item_feather_vial", "flight"):
		return
	if not verify_full_state(adapter, original):
		return
	var evidence: Dictionary = history_evidence(adapter)
	report["full_history_evidence"] = evidence
	check(evidence.total_committed_events == WARMUP_COMMITS + 2 and evidence.total_receipts == WARMUP_COMMITS + 2, "eight committed receipts create eight real unreset memory events")
	check(evidence.returned_records > 2 and evidence.returned_records <= RECALL_RECORD_CAP, "full-history test genuinely exceeds the prior two-record matrix")
	check(evidence.byte_budget == RECALL_BYTE_CAP and evidence.used_record_bytes <= RECALL_BYTE_CAP and evidence.summed_record_bytes == evidence.used_record_bytes, "recall spends exact complete record bytes under original4096 cap")
	check(evidence.truncated and evidence.omitted_records > 0, "full history explicitly discloses real record-limit/byte-limit omissions")
	check(evidence.returned_records == RECALL_RECORD_CAP or evidence.omitted_records_fitting_remaining_bytes == 0, "actual6/4096 recall is saturated by count or indivisible complete-record byte capacity")
	check(evidence.record_bytes_headroom < evidence.smallest_omitted_record_bytes or evidence.returned_records == RECALL_RECORD_CAP, "near-full means no next real omitted record fits; never pad or split history to claim4096")
	report["intent_boundary_source_audit"] = {
		"coast_begin_intent_has_4096_byte_cap": false,
		"coast_path": ["view/playable_build/adapter.gd:begin_intent", "view/ai_gm_playtest/adapter.gd:begin_intent", "core/ai_gm_rebuilt/engine.gd:begin_intent"],
		"4096_limit_belongs_to": "view/generated_v3_rivers/adapter.gd:MAX_GOAL_BYTES",
		"test_policy": "4095/4096/4097 are legal Coast entry samples, not a fabricated Coast maximum; original65536 transport remains authoritative",
		"original_codec_wrapper_cap_bytes": WRAPPER_CAP,
		"wrapper_cap_enforced_at": "core/ai_gm_http/client.gd:_start_request; Codec.encode itself only serializes"
	}
	if not measure_full_history(adapter, "full_history_short_intent", "使用随身解毒剂解除自己的中毒。", false):
		return
	for characters in [100, 300]:
		var ordinary_goal: String = ORDINARY_INTENTS[characters]
		check(ordinary_goal.length() == characters and ordinary_goal.to_utf8_buffer().size() == characters * 3, "ordinary named-object Chinese request is exact " + str(characters) + " characters")
		if not measure_full_history(adapter, "full_history_ordinary_" + str(characters) + "_characters", ordinary_goal, false, true):
			return
	for bytes in INTENT_SAMPLES:
		if not measure_full_history(adapter, "full_history_intent_" + str(bytes) + "B", exact_intent(int(bytes)), false):
			return
	# The explicit text alone exceeds the public request cap. It is still below
	# the dictionary decoder's262144 capacity once this source scope is added.
	if not measure_full_history(adapter, "full_history_transport_oversize_65537B_intent", exact_intent(OVERSIZE_INTENT_BYTES), true):
		return
	var final: Dictionary = adapter.engine.save_data()
	check(C.bytes(final.state) == C.bytes(warmup_and_source_state) and C.bytes(final.rng) == C.bytes(warmup_and_source_rng) and C.bytes(final.receipts) == C.bytes(warmup_and_source_receipts) and C.bytes(final.campaign_memory) == C.bytes(warmup_and_source_memory), "all boundary measurements preserve final committed state RNG receipts and full real history")
	completed = true

var warmup_and_source_state: Dictionary = {}
var warmup_and_source_rng: Dictionary = {}
var warmup_and_source_receipts: Dictionary = {}
var warmup_and_source_memory: Dictionary = {}

func commit_actual_source(adapter: RefCounted, source_id: String, definition_id: String) -> bool:
	var before: Dictionary = adapter.engine.save_data()
	var prepared: Dictionary = F.prepare_source(adapter, source_id)
	if not check(prepared.ok, "real owned source prepares once after warmup: " + source_id):
		report["source_setup_blocker"] = prepared
		return false
	if not fixed_checks(adapter):
		return false
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok, "real owned source follows roll-stage-commit exactly once: " + source_id):
		report["source_setup_blocker"] = result
		return false
	var succeeded: bool = result.receipt.outcomes.get("delivery", false) and result.receipt.outcomes.get("effect", false)
	source_attempts.append({"source_id": source_id, "action_id": result.receipt.action_id, "receipt_hash": result.receipt.receipt_hash, "branch_id": result.receipt.branch_id, "outcomes": result.receipt.outcomes.duplicate(true), "succeeded": succeeded, "retry_count": 0})
	if not check(succeeded and result.receipt.branch_id == "status_source_applied", "fixed seed original rule source succeeds; failure is a blocker and is never rerolled: " + source_id):
		report["source_setup_blocker"] = {"source_id": source_id, "reason": "First actual source branch failed; no full-history two-status claim is made", "outcomes": result.receipt.outcomes}
		return false
	var after: Dictionary = adapter.engine.save_data()
	check(after.state.items[source_id].quantity == before.state.items[source_id].quantity - 1 and after.state.actors.actor_player.stamina.current == before.state.actors.actor_player.stamina.current - 1, "source application consumes its actual vial and stamina exactly once")
	check(not F.status(after.state, definition_id).is_empty() and F.status(after.state, definition_id).remaining == 3, "successful ordinary source creates fresh committed status without immediate countdown")
	check(after.receipts.size() == before.receipts.size() + 1 and after.campaign_memory.events.size() == before.campaign_memory.events.size() + 1, "source application appends actual receipt and memory without resetting history")
	committed_history.append({"action_id": result.receipt.action_id, "receipt_hash": result.receipt.receipt_hash, "turn": result.receipt.turn, "resolver": F.Action.ID, "source_id": source_id, "provenance": result.receipt.provenance})
	return true

func verify_full_state(adapter: RefCounted, original: Dictionary) -> bool:
	var data: Dictionary = adapter.engine.save_data()
	var state: Dictionary = data.state
	var player: Dictionary = F.Details.public_details(state, state.actors.actor_player)
	var npc: Dictionary = F.Details.public_details(state, state.actors[NPC_ID])
	var ok := check(player.available and player.rows.size() == 2 and F.status(state, "poison").get("remaining") == 2 and F.status(state, "flight").get("remaining") == 3, "full-history measurement has real live player poison2 plus flight3")
	ok = check(npc.available and npc.rows.size() == 1 and npc.rows[0].name == "中毒" and npc.rows[0].duration.remaining == 3, "keeper poison remains genuinely public and is never aged by player actions") and ok
	ok = check(state.actors[NPC_ID].health == original.state.actors[NPC_ID].health and state.actors.actor_player.health.current > 0, "NPC does not receive player-action poison ticks and acting player remains alive") and ok
	warmup_and_source_state = state.duplicate(true)
	warmup_and_source_rng = data.rng.duplicate(true)
	warmup_and_source_receipts = data.receipts.duplicate(true)
	warmup_and_source_memory = data.campaign_memory.duplicate(true)
	return ok

func history_evidence(adapter: RefCounted) -> Dictionary:
	var data: Dictionary = adapter.engine.save_data()
	var memory: Dictionary = adapter.engine.memory_context(F.PLAYER, "", "", RECALL_RECORD_CAP, RECALL_BYTE_CAP)
	var costs: Array = []
	var selected: Dictionary = {}
	var summed := 0
	for fact in memory.facts:
		var cost: int = C.bytes(fact).to_utf8_buffer().size()
		summed += cost
		selected[fact.event_id] = true
		costs.append({"action_id": fact.event_id, "receipt_hash": fact.source.receipt_hash, "record_bytes": cost, "resolver_id": fact.resolver_id})
		check(data.receipts.has(fact.event_id) and data.receipts[fact.event_id].receipt_hash == fact.source.receipt_hash and fact.truth_status == "confirmed_program_result", "recalled record binds a retained actual receipt: " + fact.event_id)
	var omitted_costs: Array = []
	var minimum := 2147483647
	var fitting := 0
	var headroom: int = RECALL_BYTE_CAP - int(memory.used_record_bytes)
	for event in data.campaign_memory.events:
		if selected.has(event.event_id) or not F.PLAYER in event.witness_ids:
			continue
		var view: Dictionary = event.duplicate(true)
		view.erase("witness_ids")
		var cost: int = C.bytes(view).to_utf8_buffer().size()
		minimum = mini(minimum, cost)
		if cost <= headroom:
			fitting += 1
		omitted_costs.append({"action_id": event.event_id, "record_bytes": cost})
	return {"total_committed_events": data.campaign_memory.events.size(), "total_receipts": data.receipts.size(), "returned_records": memory.facts.size(), "returned_beliefs": memory.beliefs.size(), "byte_budget": memory.budget_bytes, "used_record_bytes": memory.used_record_bytes, "summed_record_bytes": summed, "serialized_memory_context_bytes": C.bytes(memory).to_utf8_buffer().size(), "record_bytes_headroom": headroom, "truncated": memory.truncated, "record_costs": costs, "omitted_records": omitted_costs.size(), "omitted_record_costs": omitted_costs, "smallest_omitted_record_bytes": minimum if not omitted_costs.is_empty() else 0, "omitted_records_fitting_remaining_bytes": fitting, "memory_context_sha256": C.digest(memory), "whole_history_sha256": C.digest(data.campaign_memory), "saturation_basis": "count6_or_no_whole_real_omitted_record_fits_remaining4096_bytes"}

func exact_intent(target_bytes: int) -> String:
	var prefix := "使用随身解毒剂解除自己的中毒。以下附注仅用于离线文字长度测量，不增加任何行动："
	var remaining: int = target_bytes - prefix.to_utf8_buffer().size()
	var text: String = prefix + "测".repeat(remaining / 3) + "a".repeat(remaining % 3)
	check(text.to_utf8_buffer().size() == target_bytes, "explicit Coast intent has exact UTF8 byte length " + str(target_bytes))
	return text

func measure_full_history(adapter: RefCounted, label: String, goal: String, expected_rejection: bool, request_only: bool = false) -> bool:
	var before_begin: Dictionary = adapter.engine.save_data()
	var begun: Dictionary = adapter.begin_intent(goal, npc_reference(adapter.state_copy()))
	if not check(begun.ok, "Coast entry accepts explicit source intent without importing an unrelated4096 cap: " + label):
		report["unexpected_entry_rejection"] = {"scenario": label, "result": begun, "engine_unchanged": C.bytes(adapter.engine.save_data()) == C.bytes(before_begin)}
		return false
	var pending_before: Dictionary = adapter.engine.save_data()
	var full: Dictionary = adapter.engine.model_request(adapter.active_action)
	var memory: Dictionary = full.get("memory_context", {})
	check(full.context.goal == goal and full.context.goal.to_utf8_buffer().size() == goal.to_utf8_buffer().size(), "outgoing frozen request preserves every explicit intent byte: " + label)
	check(full.get("status_context", {}).get("active", []).size() == 2 and not full.status_context.get("truncated", true), "actual outgoing compact context contains both complete player states: " + label)
	check(full.context.attention_focus.id == NPC_ID and full.context.attention_focus.facts.get("status_details", {}).get("rows", []).size() == 1, "actual NPC focus carries its public poison in full: " + label)
	check(C.digest(memory) == report.full_history_evidence.memory_context_sha256 and memory.budget_bytes == RECALL_BYTE_CAP, "actual model_request carries the same full bounded real history without trimming: " + label)
	# A request-only compound intent must never be silently reinterpreted as an
	# antidote assessment. This diagnostic descriptor only gives probes the frozen
	# action ID; it is never imported, prepared, sent, or claimed as a model reply.
	var reply: Dictionary = {"action_id": adapter.active_action, "resolver_id": "REQUEST_ONLY_NO_ASSESSMENT", "fact_refs": []} if request_only else F.assessment(begun.request, F.Action.ID, F.source_bindings("item_status_antidote"), ["delivery", "effect"])
	if not check(not reply.is_empty(), "frozen request has a probe descriptor without inventing action support: " + label):
		return false
	# Existing matrix exercises actual Scope65536 and actual Codec serialization,
	# including rejected candidates explicitly marked as not admissible envelopes.
	var row: Dictionary = inspect_coast_request(adapter, reply, label)
	if label=="full_history_short_intent":
		var capture:RefCounted=DiagnosticScope.new(adapter.engine,func():return true,PUBLIC_CAP)
		capture.model_request(adapter.active_action)
		var witness_file:=FileAccess.open("user://full_history_public_witness.json",FileAccess.WRITE)
		check(witness_file!=null,"bounded actual public witness file opens")
		if witness_file!=null:witness_file.store_string(C.bytes(capture.raw_candidate));witness_file.close()
	row["intent_utf8_bytes"] = goal.to_utf8_buffer().size()
	row["intent_characters"] = goal.length()
	row["coast_entry_accepted"] = true
	row["expected_oversize_rejection"] = expected_rejection
	row["required_adoption_gate"] = label == "full_history_short_intent" or request_only
	row["request_only_no_assessment"] = request_only
	row["ordinary_compound_action_support_claimed"] = false
	row["long_intent_diagnostic_only"] = not row.required_adoption_gate
	row["memory_context"] = report.full_history_evidence.duplicate(true)
	row["ordinary_committed_receipts"] = WARMUP_COMMITS + 2
	# Independently reuse the existing probe. Its ok flag validates safe transport
	# behavior; admission is deliberately asserted separately below.
	var probe: Dictionary = F.BudgetProbe.inspect(adapter.engine, reply)
	F.budget_observations.append(probe.duplicate(true))
	check(probe.ok and probe.scoped_public_bytes == row.scoped_public_bytes and probe.transport_admitted == row.transport_admitted, "independent request_budget_probe agrees with actual matrix serialization: " + label)
	row["independent_probe_ok"] = probe.ok
	row["budget_rejection_preserves_entire_pending_engine"] = C.bytes(adapter.engine.save_data()) == C.bytes(pending_before)
	check(row.budget_rejection_preserves_entire_pending_engine, "budget/Codec checks do not mutate state pending RNG history or counters: " + label)
	if expected_rejection:
		check(not row.transport_admitted and row.scoped_public_bytes > PUBLIC_CAP and row.source_error.get("code") == "CONTEXT_BUDGET", "intent whose text alone exceeds65536 is explicitly refused before send")
		row["safety_only_not_playable_pass"] = true
	elif row.required_adoption_gate:
		check(row.transport_admitted, "PLAYABILITY_ACTION_BLOCK_RISK: short or ordinary100/300-character full-history Coast request must fit original65536; safe rejection is not adoption success: " + label)
	elif not row.transport_admitted:
		check(row.source_error.get("code") == "CONTEXT_BUDGET" and row.scoped_public_bytes > PUBLIC_CAP, "deferred long-intent diagnostic is safely rejected at original public budget: " + label)
		row["safety_only_not_playable_pass"] = true
		row["implementation_defect_claimed"] = false
	if row.transport_admitted:
		check(row.wrapper_bytes <= WRAPPER_CAP and row.wrapper_is_admissible_request, "real admitted Codec envelope fits unchanged4MiB wrapper boundary: " + label)
	if row.transport_admitted and not request_only:
		var scope: RefCounted = Scoped.new(adapter.engine, func(): return true, PUBLIC_CAP)
		var encoded: Dictionary = scope.model_request(adapter.active_action)
		var transformed: Dictionary = F.BudgetProbe.encoded_reply(reply, encoded)
		if check(transformed.ok, "full-history reply expected values preserve exact public references"):
			var prepared: Dictionary = scope.prepare_assessment(transformed.reply)
			row["real_scope_prepare_ok"] = prepared.ok
			check(prepared.ok and adapter.phase() == "ready_roll", "admitted full-history source reply reaches original ready-roll boundary without executing")
	if request_only:
		row["real_scope_prepare_performed"] = false
		check(adapter.phase() == "awaiting_assessment" and C.bytes(adapter.engine.save_data()) == C.bytes(pending_before), "ordinary compound sample only builds and measures a request; no assessment substitution: " + label)
	full_history_rows.append(row)
	var before_cancel: Dictionary = adapter.engine.save_data()
	if not check(adapter.cancel().ok, "explicitly cancel measurement without source roll: " + label):
		return false
	var after_cancel: Dictionary = adapter.engine.save_data()
	for key in ["state", "rng", "receipts", "campaign_memory"]:
		check(C.bytes(before_cancel[key]) == C.bytes(after_cancel[key]) and C.bytes(before_begin[key]) == C.bytes(after_cancel[key]), "begin/measure/cancel preserves committed " + key + ": " + label)
	return true
