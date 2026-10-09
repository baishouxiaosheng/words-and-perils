extends SceneTree
## Shape-valid detached formatter fixtures, not real-world FocusContract/UI proof.
const Subject = preload("res://view/playable_build/player_details.gd")
const Baseline = preload("res://tests/focused/baseline_player_details.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func bind_sources() -> bool:
	var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/focused/source_binding.json"))
	if not packet is Dictionary or not packet.get("files") is Array:
		check(false, "source binding readable")
		return false
	var bound: bool = true
	for pin in packet.files:
		var path: String = "res://" + str(pin.path)
		var ok: bool = FileAccess.get_sha256(path) == pin.sha256 and FileAccess.get_file_as_bytes(path).size() == pin.bytes
		check(ok, "fixed source " + str(pin.path))
		bound = bound and ok
	check(ProjectSettings.get_setting("application/config/use_custom_user_dir", false) == true, "isolated custom user directory configured")
	return bound

func focus(kind: String, hex: Variant) -> Dictionary:
	var facts: Dictionary = {"name": "同名测试对象", "status_details": {"available": true, "rows": []}}
	return {"kind": kind, "id": "fixture_" + kind, "hex": hex, "facts": facts, "fixture_metadata": {"nested": [1, 2]}}

func observe(input: Dictionary, label: String) -> String:
	var frozen: PackedByteArray = var_to_bytes(input)
	var result: String = Subject.description(input)
	check(var_to_bytes(input) == frozen, label + " input byte-exact")
	check(Subject.description(input) == result, label + " repeatable output")
	check(var_to_bytes(input) == frozen, label + " input byte-exact after repeat")
	return result

func run() -> void:
	if not bind_sources():
		finish()
		return
	# COVERAGE: actor_tile_settlement. Formatter accepts two integers; these
	# fixtures do not assert world support, observer visibility or actor movement.
	for kind in ["actor", "tile", "settlement"]:
		for hex in [[2, -3], [0, 0], [-5, 7]]:
			var input: Dictionary = focus(kind, hex)
			var output: String = observe(input, kind + " " + str(hex))
			var coordinate: String = "选中地格：（%d，%d）" % hex
			check(output.count(coordinate) == 1 and output.count("选中地格：") == 1, "valid " + kind + " coordinates once")
			check(output.replace(coordinate + "\n", "") == Baseline.description(input), "only coordinate line added " + kind)
	# COVERAGE: invalid_hex. Float 2.0, bool, Vector2i and packed arrays are not
	# accepted as two-int Array; retain baseline description with no coordinate.
	var invalid: Array = [null, [], [1], [1, 2, 3], ["1", 2], [1, "2"], [1.0, 2], [true, 2], "1,2", {"q": 1, "r": 2}, Vector2i(1, 2), PackedInt32Array([1, 2])]
	for kind in ["actor", "tile", "settlement"]:
		for index in range(invalid.size()):
			var input: Dictionary = focus(kind, invalid[index])
			var output: String = observe(input, "invalid " + kind + " " + str(index))
			check(not output.contains("选中地格：") and output == Baseline.description(input), "invalid hex baseline fallback " + kind)
		var missing: Dictionary = focus(kind, [])
		missing.erase("hex")
		var missing_output: String = observe(missing, "missing " + kind)
		check(not missing_output.contains("选中地格：") and missing_output == Baseline.description(missing), "missing hex baseline fallback " + kind)
	# COVERAGE: static_early_return. Original coordinate and whole body unchanged.
	var static_focus: Dictionary = focus("settlement", [4, -2])
	static_focus["catalog_version"] = "source-static-focus/v1"
	static_focus.facts["descriptor"] = {"name": "固定测试对象", "description": "固定景物描述"}
	var static_output: String = observe(static_focus, "static")
	check(static_output == Baseline.description(static_focus), "static early-return byte-exact output")
	check(static_output.count("所在地图位置：（4，-2）") == 1 and not static_output.contains("选中地格："), "static only original coordinate once")
	# COVERAGE: passage_original_only. Complete original formatter-required
	# target fields; the coordinate is its support point, not an invented center.
	var passage: Dictionary = focus("passage_edge", [3, -1])
	passage.facts["passage_target"] = {"name": "测试窄口", "width_mm": 400, "min_section_mm": 100, "max_section_mm": 300, "required_bearing": 1, "support_hex": [3, -1]}
	passage.facts["state"] = {"ground_blocking": false}
	var passage_output: String = observe(passage, "passage")
	check(passage_output == Baseline.description(passage), "passage entire original semantics unchanged")
	check(passage_output.count("操作落脚点：(3,-1)") == 1 and not passage_output.contains("选中地格："), "passage only original support coordinates")
	# COVERAGE: empty_and_independent. No clock wording candidate merged.
	check(observe({}, "empty") == Baseline.description({}), "empty selection unchanged")
	var legacy_actor: Dictionary = focus("actor", [0, 1])
	legacy_actor.facts.status_details = {"available": true, "rows": [{"name": "中毒", "duration": {"clock": "legacy_turn", "persistent": false, "remaining": 2, "text": "剩余2回合"}, "parameters": [], "stacks": 1, "effects": [], "removal": []}]}
	var legacy_output: String = observe(legacy_actor, "independent legacy")
	check(legacy_output.contains("中毒 · 剩余2回合") and not legacy_output.contains("次已提交行动") and not legacy_output.contains("计时说明："), "location candidate not combined with clock candidate")
	finish()

func finish() -> void:
	print(JSON.stringify({"suite": "focus_location_formatter_unit", "status": "UNIT_PASSED" if failures.is_empty() else "UNIT_FAILED", "checks": checks, "failures": failures, "main_ui_visibility_verified": false}))
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
