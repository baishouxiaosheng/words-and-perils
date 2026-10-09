extends SceneTree
## UI contract and bounded CPU-copy comparison. No scene generation or provider.
const Baseline = preload("baseline_panel.gd")
const Candidate = preload("../candidate/view/playable_build/panel.gd")
var report: Dictionary = {"checks": [], "scenario_count": 0, "profiles": [], "live_ai": false, "native_gameplay": false, "target_gpu": false}
var failures := 0
var out := ""

class CountingAdapter extends RefCounted:
	var current_phase := "idle"
	var state: Dictionary = {"turn": 0, "flags": {"lamp_restored": false}, "hexes": {}}
	var counters: Dictionary = {}
	var fixture := false
	var scene_goal := true
	func _init() -> void:
		for i in range(1801): state.hexes[str(i)] = {"id": "hex_" + str(i), "q": i % 43, "r": i / 43, "terrain": "plain", "scene_id": "scene_coast", "ground_blocked": false, "air_blocked": false, "all_blocked": false}
		reset_counts()
	func reset_counts() -> void:
		counters = {"phase_calls": 0, "state_copy_calls": 0, "action_copy_calls": 0, "copied_state_hex_entries": 0, "copied_action_snapshot_hex_entries": 0, "story_complete_calls": 0, "story_goal_calls": 0, "fixture_calls": 0, "sample_goal_calls": 0}
	func state_copy() -> Dictionary:
		counters.state_copy_calls += 1
		counters.copied_state_hex_entries += state.hexes.size()
		return state.duplicate(true)
	func action_copy() -> Dictionary:
		counters.action_copy_calls += 1
		if current_phase == "idle": return {}
		counters.copied_action_snapshot_hex_entries += state.hexes.size()
		return {"status": current_phase, "snapshot": state}.duplicate(true)
	func phase() -> String:
		counters.phase_calls += 1
		return str(action_copy().get("status", "idle"))
	func authority_text() -> String:
		return "authority:" + current_phase + ":" + str(state.turn)
	func fixture_available() -> bool:
		counters.fixture_calls += 1
		return fixture and current_phase == "awaiting_assessment"
	func story_complete() -> bool:
		counters.story_complete_calls += 1
		return state_copy().flags.lamp_restored
	func story_goal() -> String:
		counters.story_goal_calls += 1
		return "goal:" + str(state_copy().turn)
	func sample_goal(kind: String) -> String:
		counters.sample_goal_calls += 1
		return "sample:" + kind if scene_goal else ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	call_deferred("run")

func check(value: bool, label_: String) -> void:
	report.checks.append({"passed": value, "label": label_})
	if not value:
		failures += 1
		printerr("PANEL_REFRESH_FAIL ", label_)

func panel_state(panel: Control) -> Dictionary:
	var buttons: Array = []
	for b in panel.sample_buttons:
		buttons.append({"kind": b.get_meta("sample_kind"), "text": b.text, "disabled": b.disabled, "visible": b.visible, "in_tree": b.is_visible_in_tree(), "tooltip": b.tooltip_text})
	return {"authority": panel.authority.text, "fixture_text": panel.fixture_button.text, "fixture_disabled": panel.fixture_button.disabled, "reset_disabled": panel.reset_button.disabled, "buttons": buttons}

func run() -> void:
	if out.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	var before: Control = Baseline.new()
	var after: Control = Candidate.new()
	root.add_child(before); root.add_child(after)
	await process_frame
	var adapter := CountingAdapter.new()
	check(before.sample_buttons.size() == 24 and after.sample_buttons.size() == 24, "same24 sample buttons")
	for feature_mask in range(8):
		for key in ["scene_transitions", "physical_catalog", "settlement_state"]: adapter.state.erase(key)
		for bit in range(3):
			if feature_mask & (1 << bit): adapter.state[["scene_transitions", "physical_catalog", "settlement_state"][bit]] = {}
		for phase_ in ["idle", "awaiting_assessment", "ready_roll", "rolled", "staged", "idle"]:
			adapter.current_phase = phase_
			adapter.fixture = phase_ == "awaiting_assessment"
			adapter.state.turn += 1
			for completed in [false, true]:
				adapter.state.flags.lamp_restored = completed
				adapter.scene_goal = not completed
				for shown in [true, false, true]:
					before.visible = shown; after.visible = shown
					var unchanged := JSON.stringify(adapter.state)
					before.update_adapter(adapter); after.update_adapter(adapter)
					var name_ := "features%d/%s/complete%s/visible%s/turn%d" % [feature_mask, phase_, completed, shown, adapter.state.turn]
					check(panel_state(before) == panel_state(after), name_ + " exact UI properties")
					check(JSON.stringify(adapter.state) == unchanged, name_ + " authoritative fixture untouched")
					report.scenario_count += 1
	# Reversed repeated same-input blocks bound timer noise. This fixture models
	# the actual map-sized duplicate(true) API; it is not a gameplay/FPS benchmark.
	adapter.current_phase = "awaiting_assessment"
	adapter.state.flags.lamp_restored = false
	adapter.fixture = true
	for round_ in range(4):
		var order: Array = [before, after] if round_ % 2 == 0 else [after, before]
		for panel in order:
			adapter.reset_counts()
			var static_before := OS.get_static_memory_usage()
			var start := Time.get_ticks_usec()
			for iteration in range(8): panel.update_adapter(adapter)
			var elapsed := Time.get_ticks_usec() - start
			report.profiles.append({"variant": "baseline" if panel == before else "candidate", "round": round_, "iterations": 8, "elapsed_us": elapsed, "static_retained_delta_bytes": OS.get_static_memory_usage() - static_before, "counters": adapter.counters.duplicate(true)})
	var base_counts: Dictionary = report.profiles[0].counters
	var candidate_counts: Dictionary = report.profiles[1].counters
	check(candidate_counts.phase_calls < base_counts.phase_calls, "map-sized phase copies reduced")
	check(candidate_counts.state_copy_calls < base_counts.state_copy_calls, "state snapshot copies reduced")
	check(candidate_counts.copied_action_snapshot_hex_entries < base_counts.copied_action_snapshot_hex_entries, "fewer frozen-action hex dictionaries copied")
	check(candidate_counts.copied_state_hex_entries < base_counts.copied_state_hex_entries, "fewer world hex dictionaries copied")
	report["failures"] = failures
	report["scope"] = "Synthetic stateful panel contract plus CPU-copy benchmark; native full-scene and production adapter verification remain separate"
	var file := FileAccess.open(out.path_join("panel_refresh_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	before.queue_free(); after.queue_free(); await process_frame
	print("PANEL_REFRESH_COMPLETE scenarios=", report.scenario_count, " checks=", report.checks.size(), " failures=", failures)
	quit(0 if failures == 0 else 1)
