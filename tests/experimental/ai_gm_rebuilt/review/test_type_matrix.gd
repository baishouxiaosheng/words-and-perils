extends SceneTree
## Bounded typed-contract matrix: 12 selected fields x 6 replacements, seed 123.
## Cases are summarized separately, not added to independent integration counts.
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
var failures: Array = []
var calls := 0
func game() -> RefCounted:
	return GMEngine.new(Story.world(), Rule.new(), {"fixture_gate": Resolver.new("gate")}, {}, 123)
func run_save(e: RefCounted, original: Dictionary, path: Array, value: Variant, label: String) -> void:
	var bad: Dictionary = original.duplicate(true); var cursor: Dictionary = bad
	for index in range(path.size() - 1): cursor = cursor[path[index]]
	cursor[path[-1]] = value
	var before: String = C.bytes(e.save_data())
	var result: Dictionary = e.load_data(bad); calls += 1
	if result.get("ok", false) or not result.has("code") or C.bytes(e.save_data()) != before:
		failures.append({"label": label, "path": path, "returned": result}); printerr("FAIL MATRIX SAVE: ", label, " ", path, " ", result)
func run_narration(e: RefCounted, original: Dictionary, field: String, value: Variant, label: String) -> void:
	var bad: Dictionary = original.duplicate(true); bad[field] = value
	var before: String = C.bytes(e.save_data())
	var result: Dictionary = e.validate_narration_reply(bad); calls += 1
	if result.get("ok", false) or not result.has("code") or C.bytes(e.save_data()) != before:
		failures.append({"label": label, "field": field, "returned": result}); printerr("FAIL MATRIX NARRATION: ", label, " ", field, " ", result)
func _initialize() -> void:
	var awaiting := game(); var begun: Dictionary = awaiting.begin_intent("交酒问渡口")
	var id: String = begun.request.action_id
	var waiting_save: Dictionary = awaiting.save_data()
	var e := game(); e.load_data(waiting_save)
	var a: Dictionary = Story.assessment(begun.request)
	e.prepare_assessment(a); e.roll_once(id); var staged: Dictionary = e.stage(id); e.commit(id, staged.stage_hash)
	var committed_save: Dictionary = e.save_data()
	var request: Dictionary = e.narration_request(id)
	var reply := {"schema_version": "ai_gm_narration/v1", "action_id": id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "已记录的结果。"}
	var replacements: Array = [{"label": "null", "value": null}, {"label": "bool", "value": true}, {"label": "integer", "value": 7}, {"label": "fractional_float", "value": 1.5}, {"label": "array", "value": []}, {"label": "object", "value": {}}]
	var wait_paths: Array = [["schema_version"], ["rule_id"], ["pending", id, "action_id"], ["pending", id, "status"], ["pending", id, "context_hash"]]
	var done_paths: Array = [["receipts", id, "schema_version"], ["receipts", id, "action_id"], ["receipts", id, "receipt_hash"]]
	for replacement in replacements:
		for path in wait_paths: run_save(e, waiting_save, path, replacement.value, replacement.label)
		for path in done_paths: run_save(e, committed_save, path, replacement.value, replacement.label)
		for field in ["schema_version", "action_id", "state_version", "context_hash"]: run_narration(e, reply, field, replacement.value, replacement.label)
	var report := {"schema": "ai_gm_bounded_type_matrix/v1", "seed": 123, "fields": 12, "replacement_types": ["null", "bool", "integer", "fractional_float", "array", "object"], "calls": calls, "structured_atomic_rejections": calls - failures.size(), "failures": failures, "not_exhaustive_fuzzing": true, "external_ai_called": false}
	var file := FileAccess.open("res://artifacts/ai_gm_rebuilt_review_20261002/type_matrix_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("BOUNDED TYPE MATRIX: %d/%d structured atomic rejections" % [calls - failures.size(), calls])
	quit(0 if failures.is_empty() else 1)
