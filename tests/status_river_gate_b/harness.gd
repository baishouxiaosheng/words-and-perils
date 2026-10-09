extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const F = preload("res://tests/status_river_gate_b/fixture.gd")
var checks := 0
var failures: Array = []
var report: Dictionary = {"model_calls":0, "live_model_quality_verified":false, "seed_search":false}
var case_name := "unset"
var completed := false

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("GATE_B_FAIL ", label)
	return value

func argument(name: String, fallback := "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name + "="):
			return value.substr(name.length() + 1)
	return fallback

func storage_safe() -> bool:
	# Parent must isolate HOME/XDG outside the original player's save profile.
	return check(OS.get_user_data_dir().contains("/status_river_integration_20261006/gate_b_tests/"), "user-data output is confined to the explicit Gate B scratch subtree")

func write_json(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return check(false, "write artifact " + path)
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.flush()
	file.close()
	return true

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		check(false, "required prior artifact exists: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > F.Save.MAX_SAVE_BYTES:
		check(false, "prior artifact fits declared 32 MiB budget")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		check(false, "prior artifact is valid JSON object")
		return {}
	return parsed

func witness(adapter_: RefCounted, path: String, extra: Dictionary = {}) -> bool:
	var data := {"producer_pid":OS.get_process_id(), "engine_digest":C.digest(adapter_.engine.save_data()), "file_sha256":FileAccess.get_sha256(path), "phase":adapter_.phase(), "source_identity":F.identity(adapter_.state_copy()), "extra":extra}
	return write_json(path + ".witness.json", data)

func verify_reopen(adapter_: RefCounted, path: String) -> bool:
	var prior := read_json(path + ".witness.json")
	if prior.is_empty():
		return false
	var ok := check(int(prior.producer_pid) != OS.get_process_id(), "save producer and reader are separate OS processes")
	ok = check(FileAccess.get_sha256(path) == prior.file_sha256, "saved file matches its retained writer hash") and ok
	ok = check(C.digest(adapter_.engine.save_data()) == prior.engine_digest, "entire engine state/RNG/pending/receipts/history reopens exactly") and ok
	ok = check(adapter_.phase() == prior.phase, "saved transaction phase reopens exactly") and ok
	report["reopen_witness"] = prior
	return ok

func verify_adapter(adapter_: RefCounted) -> bool:
	if not check(adapter_.engine.ready().get("ok", false), "actual Coast engine validates"):
		return false
	var world: Dictionary = F.world_check(adapter_.state_copy())
	report["world_check"] = world
	if not check(world.ok, "full1801 source identity/world/bundle/catalog/mesh/drainage checks pass"):
		return false
	if not check(adapter_.status_gameplay_mode and F.source_check(adapter_.state_copy()), "explicit new mode retains exact trusted poison/feather/antidote/land profiles"):
		return false
	return check(adapter_.engine.rule_id() == "ai_gm_test_coast_release/v1", "deterministic fixture uses fixed release calculator, never legacy disposition authority")

func fixed_checks(adapter_: RefCounted, direct := false) -> bool:
	var action: Dictionary = adapter_.action_copy()
	var rows: Array = action.get("checks", [])
	var expected_method := "direct_success" if direct else "random"
	var ok := check(rows.size() == 2 and rows.all(func(row): return row.method == expected_method), "trusted source release policy owns both checks despite model certain disposition")
	if not direct:
		ok = check(rows.all(func(row): return row.roll_min == 1 and row.roll_max == 10000 and row.derived_facts.rule_version == "coast_release/v1"), "source dice retain the fixed release-v1 domain and derivation") and ok
	report["last_checks"] = rows
	return ok

func finish() -> void:
	report["source_request_budget_probes"] = F.budget_observations.duplicate(true)
	var worst_public: Variant = null
	var worst_admitted: Variant = null
	var warning_count := 0
	for probe in F.budget_observations:
		var margin: int = probe.get("public_headroom_bytes",65536)
		worst_public = margin if worst_public == null else mini(int(worst_public),margin)
		if probe.get("transport_admitted",false):
			worst_admitted = margin if worst_admitted == null else mini(int(worst_admitted),margin)
		if probe.get("wrapper_exceeds_65536_observation",false): warning_count += 1
	report["source_request_budget_summary"] = {"probes":F.budget_observations.size(),"public_limit_bytes":65536,"complete_wrapper_limit_bytes":4194304,"worst_candidate_public_headroom_bytes":worst_public,"worst_admitted_public_headroom_bytes":worst_admitted,"wrapper_over65536_observation_count":warning_count,"native_measurement_only_not_model_cost_or_quality":true}
	if not completed and failures.is_empty():
		failures.append("Required gate stages did not complete")
	report.merge({"case":case_name, "completed":completed, "checks":checks, "passed":checks-failures.size(), "failures":failures, "pid":OS.get_process_id(), "engine":Engine.get_version_info().string}, true)
	if OS.get_user_data_dir().contains("/status_river_integration_20261006/gate_b_tests/"):
		write_json("user://" + case_name + "_report.json", report)
	print("STATUS_RIVER_GATE_B ", case_name, " ", checks-failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
