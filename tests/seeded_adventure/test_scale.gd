extends SceneTree
const Adapter = preload("res://view/generated_adventure/seeded_adapter.gd")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
	return ok
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var radius := int(args[0]) if not args.is_empty() else 24
	var preset := "wide_coast" if radius == 24 else "coast_exploration"
	var start := Time.get_ticks_msec()
	var envelope := Contract.generate("726381", preset, radius)
	var source_ms := Time.get_ticks_msec() - start
	if not check(envelope.ok, "representative large source passes deterministic preset validation"): finish(radius, {}); return
	var adapter := Adapter.new(); start = Time.get_ticks_msec()
	if not check(adapter.start_seeded(envelope).ok, "large source passes exact renderer-navigation starting gate"): finish(radius, {}); return
	var admission_ms := Time.get_ticks_msec() - start
	check(adapter.state_copy().hexes.size() == 1 + 3 * radius * (radius + 1), "complete large map domain remains intact")
	check(adapter.gameplay_admission.navigation.reachable_start_cells >= radius, "actual start meets versioned component threshold")
	check(adapter.generation_metadata.request.preset_id == preset and C.bytes(adapter.source.data) == C.bytes(envelope.source), "large preset lineage and original source remain exact")
	var state := adapter.state_copy(); var actor: Dictionary = state.actors.actor_player
	var far: Array = []; var far_distance := -1
	for cell in state.hexes.values():
		var dq: int = cell.q - actor.hex[0]; var dr: int = cell.r - actor.hex[1]
		var distance := maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))
		if distance > far_distance: far_distance = distance; far = [cell.q, cell.r]
	check(adapter.begin_intent("查看远处地格但不授予任何未注册能力", adapter.tile_reference(far)).ok, "large map focus can request bounded assessment")
	var request_bytes := C.bytes(adapter.request()).to_utf8_buffer().size()
	check(adapter.request().context.facts.hexes.size() <= 62 and request_bytes <= 65536, "large-world context retains existing cell and byte limits")
	check(adapter.cancel().ok, "unassessed large map request cancels without action")
	var key: String = adapter.source.navigation.allowed["%d,%d" % actor.hex][0]
	var cell: Dictionary = state.hexes[key]; var target := [cell.q, cell.r]
	var focus := adapter.tile_reference(target)
	check(adapter.begin_intent(adapter.sample_goal("move", focus), focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok, "large map movement requires valid assessment and locks normally")
	var path := "user://seeded_scale_r%d.json" % radius
	var exact := C.bytes(adapter.save_data())
	check(adapter.save_file(path).ok, "large v2 source and locked engine save within budget")
	var restored := Adapter.new(); start = Time.get_ticks_msec()
	check(restored.load_file(path).ok and C.bytes(restored.save_data()) == exact, "large v2 reload preserves exact metadata/pending/RNG without reroll")
	var reload_ms := Time.get_ticks_msec() - start
	check(restored.stage().ok and restored.commit().ok and restored.state_copy().actors.actor_player.hex == target, "large seeded move completes after reload")
	finish(radius, {"source_ms": source_ms, "admission_ms": admission_ms, "reload_ms": reload_ms, "cell_count": state.hexes.size(), "reachable_start_cells": adapter.gameplay_admission.navigation.reachable_start_cells, "request_bytes": request_bytes, "save_bytes": exact.to_utf8_buffer().size()})
func finish(radius: int, metrics: Dictionary) -> void:
	var file := FileAccess.open("res://artifacts/seeded_adventure_20261003/scale%d_report.json" % radius, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "radius": radius, "metrics": metrics, "scope": "One representative seed, exact navigation geometry and assessed local move; headless, not native large-map visual/GPU performance or all-seed proof."}, "\t")); file.close()
	print("SEEDED SCALE ", radius, " ", checks - failures.size(), "/", checks, " ", JSON.stringify(metrics))
	quit(0 if failures.is_empty() else 1)
