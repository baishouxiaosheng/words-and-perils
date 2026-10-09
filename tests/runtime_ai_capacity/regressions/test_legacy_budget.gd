extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Scope = preload("res://tests/runtime_ai_budget/capture_scoped_engine.gd")
const Baseline = preload("res://tests/runtime_ai_budget/capture_baseline_engine.gd")
const Adapter = preload("res://view/playable_build/adapter.gd")
const Content = preload("res://view/playable_build/settlement_content.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const BASELINE_GOAL = "只观察围寨，不开门。"
const LONG_GOAL = "只观察围寨，不开门。我想看清城门、围墙与城内街区的现状，分辨附近有哪些已经公开的人物和物品。保持原地，不移动，不消耗物品，也不把关注某个目标当成执行动作的许可。"
var checks := 0
var failures: Array = []
var measurements: Array = []
class RequestSource extends RefCounted:
	var request: Dictionary = {}
	func model_request(_id: String) -> Dictionary: return request.duplicate(true)
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: " + label)
func _initialize() -> void: run.call_deferred()
func reverse_maps(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}; var keys: Array = value.keys(); keys.reverse()
		for key in keys: result[key] = reverse_maps(value[key])
		return result
	if value is Array:
		var result: Array = []
		for row in value: result.append(reverse_maps(row))
		return result
	return value
func measure(a: RefCounted, label: String, goal: String) -> Dictionary:
	var focus: Dictionary = Catalog.make_reference(Content.manifest().id, a.state_copy())
	check(a.begin_intent(goal, focus).ok, label + " begins exact intent")
	var frozen: Dictionary = a.engine.save_data()
	var full: Dictionary = a.request()
	var before := Baseline.new(a.engine, func(): return true)
	var after := Scope.new(a.engine, func(): return true)
	var old_sent: Dictionary = before.model_request(a.active_action)
	var new_sent: Dictionary = after.model_request(a.active_action)
	var old_projection: Dictionary = before.captured_request.duplicate(true)
	var new_projection: Dictionary = after.captured_request.duplicate(true)
	old_projection.transport_scope.erase("selection")
	check(C.bytes(old_projection) == C.bytes(new_projection), label + " only redundant metadata differs")
	check(before.last_metrics.sent_public_bytes - after.last_metrics.sent_public_bytes == 425, label + " exactly 425 UTF-8 bytes saved")
	check(C.bytes(frozen) == C.bytes(a.engine.save_data()), label + " projection leaves pending/state/RNG/receipts exact")
	check(C.bytes(new_projection.context.attention_focus) == C.bytes(full.context.attention_focus) and new_projection.context.goal == goal and new_projection.context.text_priority == "explicit_player_text", label + " frozen selection and text priority preserved")
	check(C.bytes(new_projection.contract) == C.bytes(full.contract) and new_projection.context_hash == full.context_hash and new_projection.transport_scope.authority_context_hash == full.context_hash and new_projection.transport_scope.full_public_request_sha256 == C.digest(full), label + " contract and authority identity preserved")
	check(C.bytes(new_projection.memory_context) == C.bytes(full.memory_context), label + " public memory neither dropped nor shortened")
	check(new_sent.is_empty() == (after.last_metrics.sent_public_bytes > Scope.MAX_REQUEST_BYTES), label + " exact fail-closed cap")
	if new_sent.is_empty(): check(after.last_error.get("code") == "CONTEXT_BUDGET" and after._sent_requests.is_empty(), label + " oversized projection is not admitted")
	for field in ["actors", "items", "flags", "story_anchors", "environment_entities", "settlements", "scene_transitions", "passage_targets"]:
		check(C.bytes(new_projection.context.facts.get(field)) == C.bytes(full.context.facts.get(field)), label + " complete required facts " + field)
	for forbidden in ['"rng"', '"seed"', '"receipts"', '"snapshot"', '"private_notes"', '"secrets"']:
		check(not C.bytes(new_projection).contains(forbidden), label + " excludes " + forbidden)
	var record: Dictionary = {"label":label, "goal_utf8_bytes":goal.to_utf8_buffer().size(), "before_bytes":before.last_metrics.sent_public_bytes, "after_bytes":after.last_metrics.sent_public_bytes, "remaining_bytes":Scope.MAX_REQUEST_BYTES-after.last_metrics.sent_public_bytes, "before_admitted":not old_sent.is_empty(), "after_admitted":not new_sent.is_empty(), "memory_records":full.memory_context.facts.size(), "memory_record_bytes":full.memory_context.used_record_bytes, "memory_truncated":full.memory_context.truncated}
	measurements.append(record); print("BUDGET_MEASUREMENT ", JSON.stringify(record))
	if label == "baseline_city":
		check(before.last_metrics.sent_public_bytes == 65866 and old_sent.is_empty(), "exact previously failing baseline reproduced")
		check(after.last_metrics.sent_public_bytes == 65441 and not new_sent.is_empty(), "baseline now fits unchanged 65536 cap")
		var source := RequestSource.new(); source.request = reverse_maps(full)
		var reordered := Scope.new(source, func(): return true)
		check(C.bytes(reordered.model_request(a.active_action)) == C.bytes(new_sent), "dictionary insertion order does not change serialization")
		check(C.bytes(after.model_request(a.active_action)) == C.bytes(new_sent), "repeat projection serializes identically")
		var pending := C.bytes(a.action_copy())
		a.attention(Catalog.make_reference(Content.manifest().gate_id, a.state_copy()))
		check(C.bytes(a.action_copy()) == pending and C.bytes(after.model_request(a.active_action)) == C.bytes(new_sent), "new UI attention cannot replace frozen selected context")
		check(a.save_file("user://public_budget_pending.json").ok, "pending budget save writes")
		var restored := Adapter.new()
		check(restored.load_file("user://public_budget_pending.json").ok and C.bytes(restored.engine.save_data()) == C.bytes(frozen), "pending budget save restores exact registry/hash/state/RNG")
		var restored_scope := Scope.new(restored.engine, func(): return true)
		check(C.bytes(restored_scope.model_request(restored.active_action)) == C.bytes(new_sent), "pending restored request byte-exact")
		var omitted: String = ""
		for key in full.context.facts.hexes:
			if not new_sent.context.facts.hexes.has(key): omitted = key; break
		check(not omitted.is_empty(), "baseline still omits distant cells")
		var unseen: Dictionary = {"action_id":a.active_action, "fact_refs":[{"path":"/hexes/"+omitted, "expected":full.context.facts.hexes[omitted]}]}
		check(after.prepare_assessment(unseen).get("code") == "OUT_OF_SCOPE_FACT", "unseen exact public fact cannot be cited")
		check(C.bytes(a.engine.save_data()) == C.bytes(frozen), "invalid reference leaves save exact")
		DirAccess.remove_absolute("user://public_budget_pending.json")
	check(a.cancel().ok, label + " cancel remains available")
	return record
func boundary_tests() -> void:
	var probe := Scope.new(null, func(): return true)
	for size in [65535, 65536, 65537]:
		# CJK + escaped quote/backslash ensure the limit counts serialized UTF-8.
		var request: Dictionary = {"context":{"goal":"围寨\"\\"}}
		request.context.goal += "x".repeat(size-C.bytes(request).to_utf8_buffer().size())
		var exact := C.bytes(request)
		check(exact.to_utf8_buffer().size() == size, "fixture exact serialized byte count " + str(size))
		var result: Dictionary = probe._budget(request, request, str(size))
		check(result.is_empty() == (size > 65536) and probe.last_metrics.sent_public_bytes == size, "boundary admission " + str(size))
		check(C.bytes(request) == exact, "boundary never truncates data " + str(size))
		check(probe._sent_requests.has(str(size)) == (size <= 65536), "boundary stores only admitted request " + str(size))
		if size > 65536: check(probe.last_error.get("code") == "CONTEXT_BUDGET", "over-cap boundary fails explicitly")
func finish(a: RefCounted, goal: String) -> bool:
	if not a.begin_intent(goal).ok: return false
	if not a.prepare_fixture().ok: return false
	if not a.roll_once().ok: return false
	if not a.stage().ok: return false
	return a.commit().ok
func run() -> void:
	boundary_tests()
	var a := Adapter.new(751, true)
	check(a.engine.ready().ok, "actual release test adapter ready")
	measure(a, "baseline_city", BASELINE_GOAL)
	measure(a, "long_chinese_intent", LONG_GOAL)
	var gate: Array = Content.manifest().gate_outside_hex
	for i in range(6):
		# Distinct legal steps avoid the intentional same-opportunity retry guard.
		var goal: String
		match i:
			0: goal = a.movement_goal(gate)
			1: goal = a.sample_goal("open_gate")
			2, 5: goal = a.sample_goal("rest")
			3: goal = a.movement_goal(Content.manifest().gate_inside_hex)
			4: goal = a.sample_goal("close_gate")
		if not finish(a, goal): check(false, "actual public-memory journey commit " + str(i)); break
		if i in [0, 2, 5]:
			var result: Dictionary = measure(a, "after_%d_commits" % (i+1), BASELINE_GOAL)
			check(result.memory_records > 0 and result.memory_record_bytes > 0, "actual receipt-derived memory present after " + str(i+1))
	var report: Dictionary = {"checks":checks, "failures":failures, "passed":failures.is_empty(), "live_api":false, "cap_bytes":Scope.MAX_REQUEST_BYTES, "removed_bytes":425, "measurements":measurements, "scope":"Redundant transport metadata only; not general city capacity acceptance"}
	var output := FileAccess.open("res://artifacts/runtime_ai_capacity_20261004/regressions/budget_report.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t")); output.close()
	print("PUBLIC_BUDGET ", checks-failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
