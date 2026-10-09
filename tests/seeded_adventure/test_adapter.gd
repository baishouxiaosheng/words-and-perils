extends SceneTree
const Adapter = preload("res://view/generated_adventure/seeded_adapter.gd")
const Legacy = preload("res://view/generated_adventure/adapter.gd")
const Contract = preload("res://core/world_generation_contract.gd")
const Validation = preload("res://core/world_generation_validation.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT := "res://artifacts/seeded_adventure_20261003/"
class Disconnected:
	extends "res://view/generated_adventure/seeded_adapter.gd"
	func _check_gameplay(candidate: RefCounted) -> Dictionary:
		var graph: Dictionary = candidate.source.navigation.allowed.duplicate(true)
		for key in graph: graph[key] = []
		return SeedValidation.validate_navigation(candidate.source.data, graph, candidate.source.navigation.supported, candidate.source.world.actors.actor_player.hex)
var checks := 0
var failures: Array = []
var cases: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
	return ok
func resign(metadata: Dictionary) -> void:
	metadata.erase("metadata_hash"); metadata.metadata_hash = C.digest(metadata)
func json_copy(value: Dictionary) -> Dictionary: return JSON.parse_string(C.bytes(value))
func roundtrip(adapter: RefCounted, label: String) -> void:
	var exact: String = C.bytes(adapter.save_data())
	var restored := Adapter.new()
	check(restored.load_data(JSON.parse_string(exact)).ok, label + " re-admits v2 from JSON")
	check(C.bytes(restored.save_data()) == exact, label + " preserves complete source/metadata/context/plan/RNG/stage/memory")
func run() -> void:
	var envelope := Contract.generate("雪岸-playable", "compact_coast", 4)
	if not check(envelope.ok, "text seed produces validated source envelope"): finish(); return
	var adapter := Adapter.new()
	if not check(adapter.start_seeded(envelope).ok, "text seed and exact starting component admit gameplay"): finish(); return
	check(adapter.gameplay_admission.navigation.reachable_start_cells >= 4 and not adapter.gameplay_admission.visual_quality_checked, "honest exact dry component evidence, no visual-quality claim")
	check(C.bytes(adapter.source.data) == C.bytes(envelope.source) and adapter.source.identity.content_hash == envelope.metadata.source_content_hash, "closed source is unchanged and identity remains authoritative")
	check(adapter.save_data().schema_version == Adapter.SEEDED_SAVE_SCHEMA and not adapter.save_data().source.has("generation_metadata"), "v2 stores provenance only as sibling")
	check(adapter.default_save_path() == Adapter.SEEDED_SAVE and Adapter.SEEDED_SAVE != Legacy.GENERATED_SAVE, "new save namespace cannot overwrite old v1 by default")
	var detached: Dictionary = adapter.generation_envelope(); detached.metadata.request.seed_token = "changed"; detached.source.seed = 99
	check(C.bytes(adapter.generation_envelope()) == C.bytes({"source": envelope.source, "metadata": envelope.metadata}), "exported provenance and source are detached")
	var initial := C.bytes(adapter.save_data())
	check(not adapter.start_seeded(envelope).ok and C.bytes(adapter.save_data()) == initial, "already started wrapper cannot replace its authority")
	roundtrip(adapter, "idle")
	var state: Dictionary = adapter.state_copy()
	var start: Array = state.actors.actor_player.hex
	var neighbor: String = adapter.source.navigation.allowed["%d,%d" % start][0]
	var cell: Dictionary = state.hexes[neighbor]
	var target := [cell.q, cell.r]
	var focus: Dictionary = adapter.tile_reference(target)
	check(adapter.attention(focus).ok and C.bytes(adapter.save_data()) == initial, "selection remains attention-only and consumes no RNG")
	check(adapter.begin_intent(adapter.sample_goal("move", focus), focus).ok and adapter.phase() == "awaiting_assessment", "seeded movement still waits for assessment")
	check(C.bytes(adapter.state_copy()) == C.bytes(state) and not adapter.roll_once().ok, "unassessed intention cannot move or roll")
	check(adapter.request().contract.resolver_ids == ["generated_move_v1", "generated_observe_v1", "generated_rest_v1"], "no invented action support or abilities")
	roundtrip(adapter, "awaiting_assessment")
	check(adapter.prepare_fixture().ok, "signed offline assessment follows unchanged trusted rules")
	roundtrip(adapter, "ready_roll")
	check(adapter.roll_once().ok, "assessed result locks")
	var locked := C.bytes(adapter.save_data()); var locked_rng := C.bytes(adapter.engine.save_data().rng)
	check(adapter.roll_once().ok and C.bytes(adapter.save_data()) == locked, "repeated roll is exact no-op")
	roundtrip(adapter, "rolled")
	check(adapter.save_file("user://seeded_locked.json").ok, "locked v2 file writes atomically")
	var restored := Adapter.new()
	check(restored.load_file("user://seeded_locked.json").ok and C.bytes(restored.save_data()) == locked, "file roundtrip preserves locked engine and metadata")
	check(restored.stage().ok, "restored roll stages without reroll")
	roundtrip(restored, "staged")
	check(restored.commit().ok and restored.state_copy().actors.actor_player.hex == target, "new seeded adventure commits assessed move")
	check(C.bytes(restored.engine.save_data().rng) == locked_rng and restored.state_copy().turn == 1, "commit advances one turn without consuming extra RNG")
	var receipt_id: String = restored.last_action
	var receipt: Dictionary = restored.engine.save_data().receipts[receipt_id]
	var committed := C.bytes(restored.save_data())
	check(restored.engine.commit(receipt_id, receipt.stage_hash).already_committed and C.bytes(restored.save_data()) == committed, "duplicate commit cannot change seed metadata or engine")
	for kind in ["observe", "rest"]:
		var current_focus: Dictionary = restored.tile_reference(target)
		check(restored.begin_intent(restored.sample_goal(kind, current_focus), current_focus).ok and restored.prepare_fixture().ok and restored.roll_once().ok and restored.stage().ok and restored.commit().ok, "seeded assessed " + kind + " completes")
	check(restored.state_copy().flags.observations == 1 and restored.state_copy().actors.actor_player.stamina.current == 8, "observation and rest retain existing program consequences")
	roundtrip(restored, "committed")
	var restarted: RefCounted = restored.restarted()
	check(restarted.ready().ok and restarted.state_copy().turn == 0 and C.bytes(restarted.generation_metadata) == C.bytes(envelope.metadata), "explicit reset keeps original seed/preset identity")
	check(C.bytes(restored.save_data()) != C.bytes(restarted.save_data()) and restored.state_copy().turn == 3, "reset candidate does not mutate previous adventure")
	var whole := C.bytes(restored.save_data())
	var bad := restored.save_data(); bad.generation_metadata.request.seed_token = "forged"
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "metadata tamper rejected atomically")
	bad = restored.save_data(); bad.generation_metadata.request.seed_token = "forged"; resign(bad.generation_metadata)
	check(not Adapter.new().load_data(bad).ok, "resigned mismatched seed metadata rejected")
	bad = restored.save_data(); bad.generation_metadata.engine_version = "future-engine"; resign(bad.generation_metadata)
	check(not Adapter.new().load_data(bad).ok, "different engine provenance requires explicit migration")
	bad = restored.save_data(); bad.source.seed = 99
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "source mismatch preserves prior adventure")
	bad = restored.save_data(); bad.engine.state.generated_world.runtime_hash = "forged"
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "runtime identity tamper rejected atomically after provenance validation")
	bad = restored.save_data(); bad.engine.rule_id = "coast_release/v1"
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "unsupported rules rejected without migration")
	bad = json_copy(JSON.parse_string(locked)); bad.engine.pending[adapter.active_action].context_hash = "forged"
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "pending context tamper cannot publish partial load")
	bad = restored.save_data(); bad.extra = true
	check(not restored.load_data(bad).ok and C.bytes(restored.save_data()) == whole, "closed v2 save rejects extra fields atomically")
	var denied := Disconnected.new()
	check(denied.start_seeded(envelope).get("code") == "SEED_NAV_COMPONENT" and denied.source == null and denied.engine == null, "injected disconnected graph fails actual component validator before authority publication")
	check(not denied.ready().ok and denied.save_data().is_empty(), "failed new candidate cannot claim readiness or save an empty success")
	check(not Disconnected.new().load_data(restored.save_data()).ok, "v2 reload also reruns exact start gate")
	# Legacy wrapper path is deliberately delegated to the unchanged v1 adapter.
	var legacy := Legacy.new(envelope.source)
	check(legacy.begin_intent(legacy.sample_goal("rest")).ok, "legacy v1 starts pending action")
	for phase in ["awaiting_assessment", "ready_roll", "rolled", "staged", "idle"]:
		var legacy_saved := legacy.save_data(); var compat := Adapter.new()
		check(compat.load_data(json_copy(legacy_saved)).ok and C.bytes(compat.save_data()) == C.bytes(legacy_saved), "v1 " + phase + " stays exact v1 without invented provenance")
		check(compat.generation_metadata.is_empty() and compat.default_save_path() == Legacy.GENERATED_SAVE, "v1 " + phase + " keeps original save namespace")
		if phase == "awaiting_assessment": legacy.prepare_fixture()
		elif phase == "ready_roll": legacy.roll_once()
		elif phase == "rolled": legacy.stage()
		elif phase == "staged": legacy.commit()
	var old_saved := legacy.save_data()
	check(not restored.load_data(old_saved).ok and C.bytes(restored.save_data()) == whole, "seeded v2 cannot silently downgrade to v1")
	var compat := Adapter.new(); compat.load_data(old_saved)
	check(not compat.load_data(restored.save_data()).ok and C.bytes(compat.save_data()) == C.bytes(old_saved), "loaded v1 cannot silently become v2")
	check(compat.restarted().save_data().schema_version == Legacy.SAVE_SCHEMA, "legacy reset remains v1")
	check(compat.save_file().ok, "v1 saves to its original path")
	var old_hash := FileAccess.get_sha256(Legacy.GENERATED_SAVE)
	check(restored.save_file().ok and FileAccess.get_sha256(Legacy.GENERATED_SAVE) == old_hash, "saving v2 never overwrites preserved v1 file")
	var continued := Adapter.new()
	check(continued.load_file().ok and C.bytes(continued.save_data()) == whole, "fresh Continue selects existing v2 exactly")
	var valid_v2 := FileAccess.get_file_as_string(Adapter.SEEDED_SAVE)
	var corrupt_file := FileAccess.open(Adapter.SEEDED_SAVE, FileAccess.WRITE); corrupt_file.store_string("{}"); corrupt_file.close()
	check(not Adapter.new().load_file().ok and FileAccess.get_sha256(Legacy.GENERATED_SAVE) == old_hash, "invalid v2 is reported without silent fallback to older progress")
	corrupt_file = FileAccess.open(Adapter.SEEDED_SAVE, FileAccess.WRITE); corrupt_file.store_string(valid_v2); corrupt_file.close()
	check(compat.load_file().ok and C.bytes(compat.save_data()) == C.bytes(old_saved), "already loaded v1 continues its own path even when v2 exists")
	for seed_value in ["9223372036854775807", "-2147483648", "2147483647", "001"]:
		var sample := Contract.generate(seed_value, "compact_coast", 4)
		var candidate := Adapter.new(); var admitted := candidate.start_seeded(sample)
		check(sample.ok and admitted.ok, "representative extreme/text seed exact admission: " + seed_value)
		if not admitted.ok: continue
		check(candidate.generation_metadata.request.seed_token == seed_value and candidate.source.data.seed == sample.metadata.effective_seed, "seed identity retained: " + seed_value)
		var reloaded := Adapter.new()
		check(reloaded.load_data(json_copy(candidate.save_data())).ok and C.bytes(reloaded.save_data()) == C.bytes(candidate.save_data()), "extreme seed JSON roundtrip: " + seed_value)
		cases.append({"input": seed_value, "effective_seed": sample.metadata.effective_seed, "radius": 4, "reachable_start_cells": candidate.gameplay_admission.navigation.reachable_start_cells})
	finish()
func finish() -> void:
	var file := FileAccess.open(OUT + "adapter_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "representative_cases": cases, "scope": "Finite radius4 exact-navigation samples; disconnected graph is an injected rejection fixture; no visual, all-seed, large-native, or live-model claim."}, "\t")); file.close()
	print("SEEDED ADVENTURE ADAPTER ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
