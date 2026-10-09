extends SceneTree
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
class PreviewController:
	extends "res://main.gd"
	var preview := false
	var allow_leave := true
	var switched := 0
	var begun := 0
	var commits := 0
	var reject_commit := false
	var stored_candidate: Dictionary = {"protected": true}
	var last_status := ""
	var last_journal := ""
	func is_map_preview() -> bool: return preview
	func _can_leave_current_adventure() -> bool: return allow_leave
	func _switch_mode(_mode: String) -> void: preview = true; switched += 1
	func begin_world_build() -> void: begun += 1
	func set_status(text: String) -> void: last_status = text
	func append_journal(_speaker: String, text: String) -> void: last_journal = text
	func commit_world_candidate(candidate: Dictionary) -> Dictionary:
		if reject_commit: return {"ok": false}
		stored_candidate = candidate.duplicate(true); commits += 1
		return {"ok": true}
var checks := 0
var failures: Array = []
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
func _initialize() -> void:
	var scene := PreviewController.new()
	scene.seed_input = LineEdit.new(); scene.add_child(scene.seed_input)
	scene.radius_input = SpinBox.new(); scene.radius_input.min_value = 0; scene.radius_input.max_value = 30; scene.radius_input.value = 4; scene.add_child(scene.radius_input)
	scene.world_dialog = AcceptDialog.new(); scene.add_child(scene.world_dialog)
	scene.world_build_seed = 777
	scene.last_world_generation_metadata = {"protected": true}
	scene.seed_input.text = ""
	scene.request_world_build(true)
	check(scene.switched == 0 and scene.begun == 0 and scene.world_build_seed == 777, "empty seed rejection precedes mode switch and request mutation")
	check(scene.last_status.contains("种子设置无效") and scene.stored_candidate == {"protected": true}, "input failure preserves existing world and gives Chinese status")
	scene.seed_input.text = "雪线[预设]"; scene.request_world_build(true)
	check(scene.world_build_seed_token == "雪线[预设]" and scene.world_build_seed == Contract.normalize_seed("雪线[预设]").normalized_seed, "text seed is preserved and normalized, never replaced with default")
	check(scene.switched == 1 and scene.begun == 1, "valid request enters existing preview custody once")
	check(scene.commits == 0, "request only schedules generation")
	scene.build_selected_world()
	check(scene.commits == 1 and scene.stored_candidate.has("generated_world"), "wrapper output passes existing GameState candidate validation")
	check(scene.stored_candidate.generated_world.seed == scene.world_build_seed, "preview uses the disclosed effective seed")
	check(Contract.validate_metadata(scene.last_world_generation_metadata).ok, "audit metadata retained separately after successful commit")
	check(not scene.stored_candidate.generated_world.has("generation_metadata"), "legacy source schema unchanged")
	check(scene.last_journal.contains("雪线［预设］") and scene.last_journal.contains("实际种子") and scene.last_journal.contains("固定地图冒险"), "journal distinguishes seed identity and fixed coast without BBCode seed injection")
	check(scene.last_status.contains("实际种子") and scene.last_status.contains(str(scene.stored_candidate.generated_world.seed)), "status reports actual seed")
	var protected := C.bytes(scene.stored_candidate)
	var metadata := C.bytes(scene.last_world_generation_metadata)
	scene.world_build_radius = 25; scene.build_selected_world()
	check(scene.commits == 1 and C.bytes(scene.stored_candidate) == protected and C.bytes(scene.last_world_generation_metadata) == metadata, "generation failure preserves prior source and audit metadata")
	check(scene.last_status.contains("原世界与待处理行动保留"), "generation failure is explicit")
	scene.world_build_radius = 4; scene.world_build_busy = true; scene.seed_input.text = "other"; scene.request_world_build(true)
	check(scene.begun == 1 and scene.world_build_seed_token == "雪线[预设]", "busy duplicate request cannot change seed")
	scene.world_build_busy = false; scene.allow_leave = false; scene.request_world_build(true)
	check(scene.begun == 1 and scene.world_build_seed_token == "雪线[预设]", "pending-action custody remains authoritative")
	scene.allow_leave = true; scene.radius_input.value = 25; scene.request_world_build(true)
	check(scene.begun == 1 and scene.world_build_radius == 4, "invalid radius not silently clamped or scheduled")
	scene.radius_input.value = 4; scene.seed_input.text = "9223372036854775807"; scene.request_world_build(true)
	check(scene.world_build_seed_token == "9223372036854775807" and scene.world_build_seed == Contract.normalize_seed(scene.world_build_seed_token).normalized_seed, "long numeric UI seed never overflows int conversion")
	scene.reject_commit = true; scene.build_selected_world()
	check(scene.commits == 1 and C.bytes(scene.stored_candidate) == protected and C.bytes(scene.last_world_generation_metadata) == metadata, "failed candidate commit does not replace old metadata")
	scene.preview = false; scene.reject_commit = false; scene.build_selected_world()
	check(scene.commits == 1, "nonpreview mode cannot publish generated map")
	scene.free()
	for failure in failures: printerr("FAIL: " + str(failure))
	var report := {"checks": checks, "failures": failures, "scope": "Actual main.gd seed input and build methods with renderer/commit lifecycle mocked; no terrain bake, frame-time or visual claim."}
	var file := FileAccess.open("res://tests/seeded_world/controller_report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("SEEDED PREVIEW CONTROLLER: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
