extends SceneTree
## Formatter unit fixtures only: no Main, world, status ticking, UI or visibility proof.
const Subject = preload("res://view/playable_build/player_details.gd")
const ClockOnly = preload("res://tests/focused/clock_player_details.gd")
const LocationOnly = preload("res://tests/focused/location_player_details.gd")
const Baseline = preload("res://tests/focused/baseline_player_details.gd")
const Details = preload("res://view/status_gameplay/details.gd")
const NOTE := "计时说明：之后每次行动提交成功时结算；自身和其他角色的行动均计入"
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

func actor(rows: Array) -> Dictionary:
	return {"status_details": {"available": true, "rows": rows.duplicate(true)}, "fixture_metadata": {"nested": [1, 2]}}

func row(name_: String, clock: String, persistent: bool = false) -> Dictionary:
	var text: String = "持续生效，不自动到期" if persistent else ("剩余2次自身行动" if clock == "owner_action" else "剩余2个世界时间步")
	var duration: Dictionary = {"clock": clock, "persistent": persistent, "text": text}
	if not persistent:
		duration["remaining"] = 2
	return {"name": name_, "duration": duration, "parameters": [{"label": "强度", "value": 1, "text": "强度 1"}], "stacks": 2, "effects": ["自身行动结束时结算；两项伤害各自取整，不超过当时剩余生命"], "removal": ["提前解除需有效解毒结果确认"], "damage": {"before_health_cap": 2, "at_current_health": 1}}

func observe(input: Dictionary, label: String) -> Array[String]:
	var frozen: PackedByteArray = var_to_bytes(input)
	var result: Array[String] = Subject.focus_status_lines(input)
	check(var_to_bytes(input) == frozen, label + " input byte-exact after formatter")
	check(Subject.focus_status_lines(input) == result, label + " repeatable output")
	check(var_to_bytes(input) == frozen, label + " input byte-exact after repeat")
	check(Subject.status_lines(input) == Baseline.status_lines(input), label + " HUD lines unchanged")
	check(Subject.status_caption(input) == Baseline.status_caption(input), label + " caption unchanged")
	check(var_to_bytes(input) == frozen, label + " input byte-exact after HUD calls")
	return result

func run() -> void:
	if not bind_sources():
		finish()
		return
	# COVERAGE: legacy_finite. Produce packets with the pinned real legacy adapter.
	for remaining in [1, 2, 10000]:
		var legacy: Dictionary = {"statuses": {"fixture_poison": {"kind": "poison", "remaining_turns": remaining, "magnitude": 1}}}
		var frozen_legacy: PackedByteArray = var_to_bytes(legacy)
		var public: Dictionary = Details.public_details({}, legacy)
		check(var_to_bytes(legacy) == frozen_legacy, "legacy adapter leaves raw fixture unchanged")
		check(Details.valid_public_details(public), "real legacy adapter yields valid packet")
		var input: Dictionary = {"status_details": public}
		var output: Array[String] = observe(input, "legacy " + str(remaining))
		var expected: Array[String] = Baseline.focus_status_lines(input)
		check(expected[0] == "中毒 · 剩余%d回合" % remaining, "baseline finite legacy fixture")
		expected[0] = "中毒 · 剩余%d次已提交行动" % remaining
		expected.append(NOTE)
		check(output == expected and output.count(NOTE) == 1, "legacy exact wording and single timing note")
	# COVERAGE: typed_owner
	# COVERAGE: typed_world
	# COVERAGE: persistent. Detached schema fixtures,
	# not fabricated authority state; all must pass the production validator.
	for clock in ["owner_action", "world_step"]:
		var input: Dictionary = actor([row("类型状态", clock)])
		check(Details.valid_public_details(input.status_details), clock + " finite packet valid")
		var output: Array[String] = observe(input, clock)
		check(output == Baseline.focus_status_lines(input) and not output.has(NOTE), clock + " unchanged")
	for clock in ["owner_action", "world_step", "legacy_turn"]:
		var input: Dictionary = actor([row("永久状态", clock, true)])
		check(Details.valid_public_details(input.status_details), clock + " persistent packet valid")
		var output: Array[String] = observe(input, "persistent " + clock)
		check(output == Baseline.focus_status_lines(input) and not output.has(NOTE), "persistent unchanged " + clock)
	# COVERAGE: mixed_once. Two legacy rows still produce only one shared note;
	# typed damage/effect/removal/stack/parameter formatting remains baseline-exact.
	var legacy_rows: Array = Details.public_details({}, {"statuses": {"p": {"kind": "poison", "remaining_turns": 2, "magnitude": 1}, "f": {"kind": "flight", "remaining_turns": 1, "magnitude": 0}}}).rows
	var mixed: Dictionary = actor(legacy_rows + [row("自身钟", "owner_action"), row("世界钟", "world_step"), row("永久钟", "owner_action", true)])
	check(Details.valid_public_details(mixed.status_details), "mixed packet valid")
	var mixed_output: Array[String] = observe(mixed, "mixed")
	var mixed_expected: Array[String] = Baseline.focus_status_lines(mixed)
	for index in range(mixed_expected.size()):
		mixed_expected[index] = mixed_expected[index].replace("中毒 · 剩余2回合", "中毒 · 剩余2次已提交行动").replace("飞行 · 剩余1回合", "飞行 · 剩余1次已提交行动")
	mixed_expected.append(NOTE)
	check(mixed_output == mixed_expected and mixed_output.count(NOTE) == 1, "mixed exact output; typed rows untouched; note once")
	# COVERAGE: invalid_fallback. Never convert an invalid public packet into facts.
	var invalid_zero: Dictionary = actor([row("坏计时", "owner_action")])
	invalid_zero.status_details.rows[0].duration.remaining = 0
	var invalid_clock: Dictionary = actor([row("坏计时", "owner_action")])
	invalid_clock.status_details.rows[0].duration.clock = "unknown_clock"
	var invalid_damage: Dictionary = actor([row("坏伤害", "owner_action")])
	invalid_damage.status_details.rows[0].damage.at_current_health = 3
	var invalid_inputs: Array = [{"status_details": null}, {"status_details": []}, {"status_details": {"available": true, "rows": [], "extra": 1}}, invalid_zero, invalid_clock, invalid_damage]
	for index in range(invalid_inputs.size()):
		var input: Dictionary = invalid_inputs[index]
		check(not Details.valid_public_details(input.status_details), "invalid fixture " + str(index))
		var output: Array[String] = observe(input, "invalid " + str(index))
		check(output == Baseline.focus_status_lines(input) and output == [Details.UNAVAILABLE], "invalid uses original unavailable fallback")
	# COVERAGE: unavailable_empty_raw. Raw legacy without a public packet retains
	# the original fallback wording, an explicit limit of this candidate.
	for input in [{"status_details": {"available": false, "rows": []}}, actor([]), {"statuses": {"p": {"kind": "poison", "remaining_turns": 2, "magnitude": 1}}}]:
		var output: Array[String] = observe(input, "fallback")
		check(output == Baseline.focus_status_lines(input) and not output.has(NOTE), "unavailable/empty/raw baseline fallback unchanged")
	# COVERAGE: description_no_mutation. Exercise the actual actor details caller.
	var focus: Dictionary = {"kind": "actor", "id": "fixture_actor", "hex": [2, -1], "facts": mixed}
	var frozen_focus: PackedByteArray = var_to_bytes(focus)
	var description: String = Subject.description(focus)
	check(description.contains("中毒 · 剩余2次已提交行动") and description.count(NOTE) == 1, "actor description includes wording once")
	check(description.count("选中地格：（2，-1）") == 1, "combined description includes original resolved coordinate once")
	check(var_to_bytes(focus) == frozen_focus, "whole focus byte-exact after description")
	combined_location_regression(mixed)
	finish()

func selection(kind: String, hex: Variant, public_actor: Dictionary) -> Dictionary:
	return {"kind": kind, "id": "fixture_" + kind, "hex": hex, "facts": public_actor.duplicate(true), "fixture_metadata": {"nested": [1, 2]}}

func description_observe(input: Dictionary, label: String) -> String:
	var frozen: PackedByteArray = var_to_bytes(input)
	var result: String = Subject.description(input)
	check(var_to_bytes(input) == frozen, label + " complete input byte-exact")
	check(Subject.description(input) == result, label + " repeated selection output stable")
	check(var_to_bytes(input) == frozen, label + " complete input byte-exact after repeat")
	return result

func combined_location_regression(mixed: Dictionary) -> void:
	# COVERAGE: simultaneous_actor_coordinates_clocks. Real legacy adapter
	# plus shape-valid typed/persistent packets; no world or UI proof.
	for hex in [[2, -3], [0, 0], [-5, 7]]:
		var input: Dictionary = selection("actor", hex, mixed)
		var output: String = description_observe(input, "combined actor " + str(hex))
		var coordinate: String = "选中地格：（%d，%d）" % hex
		check(output.count(coordinate) == 1 and output.count("选中地格：") == 1, "actor coordinates once")
		check(output.contains("中毒 · 剩余2次已提交行动") and output.contains("飞行 · 剩余1次已提交行动") and output.count(NOTE) == 1, "legacy wording and coordinates coexist; note once")
		check(output.replace(coordinate + "\n", "") == ClockOnly.description(input), "coordinate addition preserves exact clock-only description")
		check(Subject.focus_status_lines(input.facts) == ClockOnly.focus_status_lines(input.facts), "location does not overwrite clock function")
		check(Subject.caption(input) == LocationOnly.caption(input) and Subject.caption(input) == Baseline.caption(input), "identity and original caption preserved")
		check(Subject.status_lines(input.facts) == Baseline.status_lines(input.facts), "HUD remains unchanged in combined selection")
	# COVERAGE: persistent_coordinate. Persistent legacy packet has no
	# invented countdown/note, while its original coordinate still displays.
	for clock in ["legacy_turn", "owner_action", "world_step"]:
		var persistent: Dictionary = selection("actor", [4, -2], actor([row("永久状态", clock, true)]))
		var output: String = description_observe(persistent, "persistent " + clock)
		check(output == LocationOnly.description(persistent) and not output.contains(NOTE), "persistent exact location-only description " + clock)
	# COVERAGE: nonactor_coordinate. No status behavior is added to tile,
	# settlement, item, tree, mountain, district or prop.
	for kind in ["tile", "settlement", "item", "tree", "mountain", "district", "prop"]:
		var input: Dictionary = selection(kind, [2, -3], {"name": "同名测试对象", "status_details": {"available": true, "rows": []}})
		var output: String = description_observe(input, "nonactor " + kind)
		check(output == LocationOnly.description(input), "nonactor exact original location candidate " + kind)
		check(output.count("选中地格：（2，-3）") == 1 and not output.contains(NOTE), "nonactor coordinate without clock note " + kind)
	# COVERAGE: invalid_hex_retains_clock. Invalid/missing hex does not
	# erase valid timing wording or invent a coordinate.
	var invalid: Array = [null, [], [1], [1, 2, 3], ["1", 2], [1.0, 2], [true, 2], "1,2", {"q": 1, "r": 2}, Vector2i(1, 2), PackedInt32Array([1, 2])]
	for index in range(invalid.size()):
		var input: Dictionary = selection("actor", invalid[index], mixed)
		var output: String = description_observe(input, "invalid hex " + str(index))
		check(output == ClockOnly.description(input) and not output.contains("选中地格：") and output.count(NOTE) == 1, "invalid hex preserves complete clock-only description")
	var missing: Dictionary = selection("actor", [], mixed)
	missing.erase("hex")
	check(description_observe(missing, "missing hex") == ClockOnly.description(missing), "missing hex preserves clock-only description")
	# COVERAGE: invalid_status_retains_coordinates.
	var bad_status: Dictionary = selection("actor", [1, 2], {"status_details": null})
	var bad_output: String = description_observe(bad_status, "invalid status")
	check(bad_output == LocationOnly.description(bad_status) and bad_output.contains(Details.UNAVAILABLE) and bad_output.count("选中地格：（1，2）") == 1, "invalid status fallback retains coordinate")
	# COVERAGE: static_and_passage_unchanged. Preserve original static
	# early return and dedicated passage support point, never a new center.
	var static_focus: Dictionary = selection("settlement", [4, -2], {})
	static_focus["catalog_version"] = "source-static-focus/v1"
	static_focus.facts["descriptor"] = {"name": "固定测试对象", "description": "固定景物描述"}
	var static_output: String = description_observe(static_focus, "static")
	check(static_output == Baseline.description(static_focus) and static_output.count("所在地图位置：（4，-2）") == 1 and not static_output.contains("选中地格："), "static branch exact original position")
	var passage: Dictionary = selection("passage_edge", [9, 9], {})
	passage.facts["passage_target"] = {"name": "测试窄口", "width_mm": 400, "min_section_mm": 100, "max_section_mm": 300, "required_bearing": 1, "support_hex": [3, -1]}
	passage.facts["state"] = {"ground_blocking": false}
	var passage_output: String = description_observe(passage, "passage")
	check(passage_output == Baseline.description(passage) and passage_output.count("操作落脚点：(3,-1)") == 1 and not passage_output.contains("选中地格："), "passage exact original support coordinate independent of focus hex")
	check(description_observe({}, "empty") == Baseline.description({}), "empty selection unchanged")
	# COVERAGE: unchanged_source_identity. Formatter is read-only across
	# all probes; no canonical state or protocol fixture is substituted.

func finish() -> void:
	print(JSON.stringify({"suite": "combined_player_details_formatter_unit", "status": "UNIT_PASSED" if failures.is_empty() else "UNIT_FAILED", "checks": checks, "failures": failures, "main_ui_visibility_verified": false}))
	for failure in failures:
		printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
