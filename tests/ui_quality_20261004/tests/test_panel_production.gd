extends SceneTree
const Baseline = preload("baseline_panel.gd")
const Candidate = preload("../candidate/view/playable_build/panel.gd")
const Adapter = preload("counting_coast_adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var baseline: Control
var candidate: Control
var report: Dictionary = {"checks": [], "profiles": [], "phases": [], "production_rule": true, "live_provider": false, "fps_claim": false}
var failures := 0
var out := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	call_deferred("run")
func check(ok: bool, name_: String) -> void:
	report.checks.append({"passed": ok, "name": name_})
	if not ok: failures += 1; printerr("PANEL_PRODUCTION_FAIL ", name_)
func props(panel: Control) -> Dictionary:
	var rows: Array = []
	for b in panel.sample_buttons: rows.append({"kind": b.get_meta("sample_kind"), "text": b.text, "visible": b.visible, "visible_in_tree": b.is_visible_in_tree(), "disabled": b.disabled, "tooltip": b.tooltip_text})
	return {"authority": panel.authority.text, "fixture_text": panel.fixture_button.text, "fixture_disabled": panel.fixture_button.disabled, "reset_disabled": panel.reset_button.disabled, "buttons": rows}
func compare(adapter: RefCounted, name_: String) -> void:
	var original := C.bytes(adapter.engine.save_data())
	for shown in [false, true, false, true]:
		baseline.visible = shown; candidate.visible = shown
		baseline.update_adapter(adapter); candidate.update_adapter(adapter)
		check(props(baseline) == props(candidate), name_ + "/visible" + str(shown) + " exact UI state")
	check(C.bytes(adapter.engine.save_data()) == original, name_ + " no authority/RNG/pending/receipt change")
	report.phases.append({"name": name_, "phase": adapter.phase(), "buttons": props(candidate), "authority_sha256": original.sha256_text()})
func profile(adapter: RefCounted) -> void:
	for round_ in range(4):
		for panel in ([baseline, candidate] if round_ % 2 == 0 else [candidate, baseline]):
			adapter.reset_copy_counts()
			var retained_before := OS.get_static_memory_usage()
			var start := Time.get_ticks_usec()
			for iteration in range(4): panel.update_adapter(adapter)
			var elapsed := Time.get_ticks_usec() - start
			report.profiles.append({"variant": "baseline" if panel == baseline else "candidate", "round": round_, "iterations": 4, "elapsed_us": elapsed, "counts": adapter.copy_counts.duplicate(true), "retained_static_delta_bytes": OS.get_static_memory_usage() - retained_before})
func run() -> void:
	if out.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	baseline = Baseline.new(); candidate = Candidate.new()
	root.add_child(baseline); root.add_child(candidate); await process_frame
	var adapter: RefCounted = Adapter.new()
	check(adapter.engine.ready().ok, "production adapter ready")
	check(adapter.engine.rule_id() == "coast_release/v1" and adapter.engine.save_data().rng.mode == "runtime_random", "no seeded/test-rule mode")
	check(adapter.state_copy().hexes.size() == 1801, "actual full coast state")
	compare(adapter, "idle_new")
	check(adapter.begin_intent(adapter.sample_goal("observe")).ok, "begin real signed observation")
	compare(adapter, "awaiting_assessment")
	profile(adapter)
	check(adapter.prepare_fixture().ok, "actual signed fixture assessment")
	compare(adapter, "ready_roll")
	check(adapter.roll_once().ok, "actual program lock")
	compare(adapter, "rolled")
	var locked_path := out.path_join("locked.json")
	check(adapter.save_file(locked_path).ok, "save actual locked action")
	var resumed: RefCounted = Adapter.new()
	check(resumed.load_file(locked_path).ok, "new adapter accepts same locked save")
	check(C.bytes(resumed.engine.save_data()) == C.bytes(adapter.engine.save_data()), "locked save exact core/RNG/branch identity")
	compare(resumed, "rolled_reload")
	check(adapter.stage().ok, "stage actual action")
	compare(adapter, "staged")
	check(adapter.commit().ok, "commit actual action")
	compare(adapter, "committed_idle")
	check(adapter.state_copy().turn == 1 and adapter.state_copy().flags.coast_observed, "observation commits exactly once")
	check(adapter.begin_intent("看看海风吹来的方向。").ok, "free text can await valid assessment")
	compare(adapter, "awaiting_free_text")
	check(candidate.fixture_button.disabled, "free text cannot apply a signed fixture")
	check(adapter.cancel().ok, "cancel unlocked waiting action")
	compare(adapter, "cancelled_idle")
	report["failures"] = failures
	report["scope"] = "Actual production coast adapter and standalone real panel controls; no full-scene raster or game-FPS measurement"
	var file := FileAccess.open(out.path_join("panel_production_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	baseline.queue_free(); candidate.queue_free(); await process_frame
	print("PANEL_PRODUCTION_COMPLETE checks=", report.checks.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
