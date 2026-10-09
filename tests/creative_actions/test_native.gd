extends SceneTree
## Actual main UI and unchanged seeded Release test adapter. Independent sessions
## intentionally choose reproducible RNG seeds, never injected outcomes/world edits.
## Run only in the root's serialized, memory-bounded native test queue.
const Main = preload("res://main.tscn")
const Adapter = preload("res://view/playable_build/adapter.gd")
const Content = preload("res://view/playable_build/creative_content.gd")
const Effects = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const NORTH := "passage:coast_brace:north"
const SOUTH := "passage:coast_brace:south"
var scene
var checks := 0
var failures: Array = []
var captures: Array = []
var sessions: Array = []
var base_output_dir := "/tmp/creative_native/"
var output_dir := ""
var test_case := "full"
var checkpoint_case := "full"
var checkpoint: Dictionary = {}
var watchdog: Timer
var progress_file: FileAccess
var progress_rows: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): base_output_dir = argument.trim_prefix("--out=").trim_suffix("/") + "/"
		if argument.begins_with("--case="): test_case = argument.trim_prefix("--case=")
		if argument.begins_with("--checkpoint-dir="): checkpoint_case = argument.trim_prefix("--checkpoint-dir=")
	output_dir = base_output_dir + test_case + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	progress_file = FileAccess.open(output_dir + "native_progress.jsonl", FileAccess.WRITE)
	mark("initialize")
	watchdog = Timer.new(); watchdog.wait_time = 240; watchdog.one_shot = true
	root.add_child(watchdog); watchdog.timeout.connect(func(): printerr("CREATIVE_NATIVE_TIMEOUT"); quit(2))
	call_deferred("run")

func mark(stage: String, extra: Dictionary = {}) -> void:
	var row := {"stage": stage, "ticks_ms": Time.get_ticks_msec(), "checks": checks, "failures": failures.size(), "engine_heap_bytes": OS.get_static_memory_usage(), "engine_peak_heap_bytes": OS.get_static_memory_peak_usage(), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	if FileAccess.file_exists("/proc/self/status"):
		for line in FileAccess.get_file_as_string("/proc/self/status").split("\n"):
			if line.begins_with("VmRSS:") or line.begins_with("VmSize:") or line.begins_with("VmHWM:"): row[line.get_slice(":", 0)] = line.get_slice(":", 1).strip_edges()
	row.merge(extra); progress_rows.append(row)
	var encoded := JSON.stringify(row)
	print("CREATIVE_PROGRESS ", encoded)
	if progress_file != null: progress_file.store_line(encoded); progress_file.flush()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("CREATIVE_NATIVE_FAIL ", label)
	return value
func frames(n := 4) -> void:
	for _i in range(n): await process_frame
func capture(name_: String) -> void:
	await frames(); await RenderingServer.frame_post_draw
	var path := output_dir + name_ + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "save actual viewport " + name_)
	captures.append(path)
	mark("capture_complete", {"capture": name_, "path": path})
func camera(target_id := NORTH, size_ := 4.8) -> void:
	var frame := Content.pose(target_id, "braced")
	scene.board.world_view.overview = false; scene.board.world_view.target = frame.origin + Vector3(0, 0.12, 0)
	scene.board.world_view.distance = 12; scene.board.world_view.pitch = 0.65; scene.board.world_view.yaw = -0.28
	scene.board.camera.size = size_; scene.board.world_view._update_camera()

func seed_for(placement_pass: bool, stability_pass: bool) -> int:
	# The authored assessment uses A=2,D=2,P=0 for both
	# placement and stability. Fresh player has F=0. This independent probe never touches
	# the real engine RNG, and the report discloses all selected seeds/rolls.
	for seed_ in range(1, 10000):
		var probe := RandomNumberGenerator.new(); probe.seed = seed_
		if (probe.randi_range(1, 10000) <= 5000) == placement_pass and (probe.randi_range(1, 10000) <= 5000) == stability_pass: return seed_
	return -1

func new_session(seed_: int, load_checkpoint := false) -> bool:
	mark("session_begin", {"seed": seed_, "load_checkpoint": load_checkpoint})
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	mark("before_seeded_adapter")
	var candidate := Adapter.new(seed_, true); mark("after_seeded_adapter")
	if load_checkpoint:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(base_output_dir + checkpoint_case + "/checkpoint.json"))
		if not check(raw is Dictionary, "fresh process finds exact saved checkpoint from " + checkpoint_case): return false
		checkpoint = raw
		if not check(FileAccess.get_sha256(Adapter.COAST_SAVE) == checkpoint.get("core_save_sha256"), "fresh process core save hash matches full-case save"): return false
		mark("before_pre_renderer_load")
		var loaded: Dictionary = candidate.load_file()
		mark("after_pre_renderer_load", {"load_ok": loaded.get("ok", false)})
		if not check(loaded.get("ok", false), "exact saved game validates before heavy renderer construction"): return false
		if not check(C.digest(candidate.state_copy()) == checkpoint.get("world_sha256"), "fresh process restores exact full-case world"): return false
	mark("before_main_instantiate")
	scene = Main.instantiate(); mark("after_main_instantiate")
	scene.coast_adventure = candidate
	root.add_child(scene); mark("after_main_add_child")
	for frame in range(12):
		await process_frame; mark("initial_frame", {"frame": frame})
	check(scene.playtest.engine.ready().ok, "explicit seeded release-test session ready")
	check(scene.playtest.engine.save_data().rule_id == "ai_gm_test_coast_release/v1", "test-labelled fixed Release rule")
	check(Content.active(scene.playtest.state_copy()), "session retains exact authored physical catalog")
	camera(); mark("session_ready", {"seed": seed_})
	return true

func pick_subject(id: String) -> bool:
	mark("pick_begin", {"subject_id": id})
	for subject in scene.board.creative_view.selection_nodes():
		if subject.id != id: continue
		for node in subject.node.find_children("*", "MeshInstance3D", true, false):
			if node.mesh == null or node.name == "SelectedEdgeGlow": continue
			mark("pick_mesh_begin", {"subject_id": id, "mesh": str(node.name)})
			var faces_: PackedVector3Array = node.mesh.get_faces()
			mark("pick_mesh_faces", {"subject_id": id, "vertices": faces_.size()})
			for i in range(0, faces_.size(), 3):
				if i + 2 >= faces_.size(): break
				var point: Vector2 = scene.board.camera.unproject_position(node.global_transform * ((faces_[i] + faces_[i + 1] + faces_[i + 2]) / 3.0))
				mark("before_source_ray", {"subject_id": id, "triangle": i / 3})
				var candidates: Array = scene.board.pick_focus(point)
				mark("after_source_ray", {"subject_id": id, "candidates": candidates.size()})
				if candidates.is_empty() or candidates[0].reference.id != id: continue
				var before := C.bytes(scene.playtest.state_copy())
				scene.on_focus_candidates(candidates, point)
				check(C.bytes(scene.playtest.state_copy()) == before, "native exact mesh selection is read-only " + id)
				check(scene.board.creative_view.report().visible_subject_labels == 1, "only selected creative subject name visible")
				mark("pick_selected", {"subject_id": id})
				return scene.selected_focus.get("id") == id
	return false

func authored(kind: String, distractor := false) -> bool:
	mark("action_begin", {"sample": kind})
	var before: Dictionary = scene.playtest.state_copy(); var turn: int = before.turn
	scene._apply_focus(Content.make_reference(NORTH, before)); scene.fill_coast_sample(kind)
	if not check(not scene.goal.text.is_empty(), "native sample fills " + kind): return false
	var explicit_text: String = scene.submitted_player_intent()
	if distractor: scene._apply_focus(Content.make_reference(SOUTH, before))
	check(scene.submitted_player_intent() == explicit_text and C.bytes(scene.playtest.state_copy()) == C.bytes(before), "focus cannot rewrite explicit intent or world")
	mark("before_submit", {"sample": kind})
	scene.submit_button.pressed.emit()
	mark("after_submit", {"sample": kind})
	if not check(scene.playtest.phase() == "awaiting_assessment" and C.bytes(scene.playtest.state_copy()) == C.bytes(before), "End Turn freezes intent without mutation"): return false
	var frozen := C.bytes(scene.playtest.request()); var frozen_focus := C.bytes(scene.playtest.action_copy().focus)
	scene._apply_focus(Content.make_reference("item_brace_oar", before))
	check(C.bytes(scene.playtest.request()) == frozen and C.bytes(scene.playtest.action_copy().focus) == frozen_focus, "later source selection preserves frozen pending request")
	mark("before_fixture", {"sample": kind})
	scene.playtest_fixture()
	mark("after_fixture", {"sample": kind})
	if not check(scene.playtest.phase() == "idle" and scene.playtest.state_copy().turn == turn + 1, "actual UI callback accepts and commits " + kind):
		printerr(scene.status_label.text); return false
	var receipt: Dictionary = scene.playtest.engine.save_data().receipts[scene.playtest.last_action]
	if kind != "remove_brace":
		check(receipt.rolls.size() == 2, "exactly two actual program draws")
		for roll in receipt.rolls: check(roll.source == "program_rng" and roll.test_seeded, "honest seeded program RNG provenance")
	sessions.append({"seed": scene.playtest.engine.save_data().rng.seed, "sample": kind, "goal": explicit_text, "frozen_focus": JSON.parse_string(frozen_focus), "outcomes": receipt.outcomes, "rolls": receipt.rolls, "patches": receipt.patches})
	return true

func local_item_dimensions(id: String) -> Vector3:
	var row: Dictionary = scene.board.creative_view.item_nodes[id]; var found := false; var box := AABB()
	for node in row.node.get_children():
		if not node is MeshInstance3D or node.mesh == null or node.name == "SelectedEdgeGlow": continue
		for point in node.mesh.get_faces():
			var p: Vector3 = node.transform * point
			if not found: box = AABB(p, Vector3.ZERO); found = true
			else: box = box.expand(p)
	return box.size

func verify_pose(id: String, posture: String) -> void:
	var state: Dictionary = scene.playtest.state_copy(); var row: Dictionary = scene.board.creative_view.item_nodes[id]
	check(state.creative_placements.get(id, {}).get("posture") == posture, "canonical source posture " + posture)
	check(row.node.transform.is_equal_approx(Content.pose(NORTH, posture)), "native source matches deterministic " + posture + " frame")
	check(not state.items[id].has("owner_actor_id") and not id in state.actors.actor_player.inventory, "deployed source is same unowned singleton")
	check(state.items[id].hex == state.passage_targets[NORTH].support_hex, "deployed source custody matches support cell")

func verify_carried_motion() -> void:
	mark("carried_motion_begin")
	var before: Dictionary = scene.playtest.state_copy()
	var hex := [-2, 14]; var cell: Dictionary = before.hexes["-2,14"]
	scene._apply_focus({"world_id": before.world_id, "kind": "tile", "id": cell.id, "hex": hex})
	scene.fill_coast_sample("move"); scene.submit_button.pressed.emit(); scene.playtest_fixture()
	if not check(scene.playtest.phase() == "idle" and scene.playtest.state_copy().actors.actor_player.hex == hex, "actual assessed move for carried presentation check"): return
	var frozen := C.bytes(scene.playtest.state_copy()); var samples := 0; var maximum_error := 0.0
	var deadline := Time.get_ticks_msec() + 15000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec() < deadline:
		await process_frame
		for id in ["item_brace_oar", "item_brace_bar"]:
			var row: Dictionary = scene.board.creative_view.item_nodes[id]
			var actual_origin: Vector3 = scene.board.creative_view.to_local(scene.board.token_nodes.actor_player.global_position)
			maximum_error = maxf(maximum_error, row.node.position.distance_to(actual_origin + row.carry_offset))
			check(row.node.basis.get_scale().is_equal_approx(Vector3.ONE), "carried prop never inherits actor miniature scale")
		samples += 1
	check(samples > 0 and maximum_error < 0.00001, "carried props follow actual animated actor origin on every sampled frame")
	check(not scene.board.presentation.actors.actor_player.moving, "assessed movement presentation finishes within deadline")
	check(C.bytes(scene.playtest.state_copy()) == frozen, "carried motion display never mutates committed state")
	mark("carried_motion_finished", {"samples": samples, "maximum_error_world": maximum_error})

func run() -> void:
	mark("run_begin", {"case": test_case})
	watchdog.start()
	match test_case:
		"full", "same_process_load": await run_full_case()
		"resume": await run_resume_case()
		"partial": await run_partial_case()
		"failure": await run_failure_case()
		_: check(false, "unknown native test case")
	await finish()

func run_full_case() -> void:
	if not await new_session(seed_for(true, true)): return
	if not check(is_instance_valid(scene.board.creative_view) and scene.board.creative_view.report().passages == 2, "two genuine native passage instances"): return
	check(scene.board.creative_view.report().carried_items == 3, "three initial objects visibly carried")
	check(scene.board.creative_view.report().visible_subject_labels == 0, "unselected carried props do not crowd actor labels")
	for id in Content.ITEM_IDS:
		var size_ := local_item_dimensions(id); var physical: Dictionary = scene.playtest.state_copy().items[id].physical_traits
		check(is_equal_approx(size_.x, physical.length_mm * Content.WORLD_UNITS_PER_MM) and is_equal_approx(size_.z, physical.section_mm * Content.WORLD_UNITS_PER_MM), "actual mesh dimensions match authored physical traits " + id)
		check(pick_subject(id), "actual carried source mesh selectable " + id)
	check(pick_subject(NORTH), "actual north passage mesh selectable")
	camera(SOUTH); await frames(); check(pick_subject(SOUTH), "actual second passage independently selectable")
	await capture("creative_00_second_passage"); camera(); await capture("creative_01_before")
	if not authored("brace_plank", true): return
	check(Effects.active_target(scene.playtest.state_copy(), NORTH) and not Effects.active_target(scene.playtest.state_copy(), SOUTH), "explicit text north wins over selected south distractor")
	verify_pose("item_brace_plank", "braced"); check(pick_subject("item_brace_plank"), "actual braced source mesh selectable")
	var current: Dictionary = scene.playtest.state_copy(); var target: Dictionary = current.passage_targets[NORTH]
	check(not Effects.edge_allowed(current, current.actors.actor_player, target.endpoints[0], target.endpoints[1]), "full success truly obstructs registered ground edge")
	var path: Dictionary = scene.playtest.movement_preview(target.endpoints[0])
	check(path.get("ok", false) and path.get("route", []).size() > 2, "native route preview detours around active brace")
	await capture("creative_02_full_braced")
	mark("before_menu_save")
	scene.save_game(); mark("after_menu_save")
	if not check(scene.last_save_result.get("ok", false), "native menu saves active brace"): return
	var ids: Array = current.items.keys(); ids.sort()
	checkpoint = {"core_save_sha256": FileAccess.get_sha256(Adapter.COAST_SAVE), "world_sha256": C.digest(current), "item_ids": ids, "source_id": "item_brace_plank", "target_id": NORTH}
	var file := FileAccess.open(output_dir + "checkpoint.json", FileAccess.WRITE)
	if not check(file != null, "full case writes restart checkpoint"): return
	file.store_string(C.bytes(checkpoint)); file.flush(); file.close()
	mark("checkpoint_saved")
	# Explicit diagnostic only. The normal four-case runner never exercises this
	# same-process path; its observed OOM remains documented, not hidden.
	if test_case == "same_process_load":
		mark("before_same_process_menu_load")
		scene.load_game(); mark("after_same_process_menu_load")
		check(scene.last_load_result.get("ok", false) and C.digest(scene.playtest.state_copy()) == checkpoint.world_sha256, "diagnostic same-process load preserves exact world")
		verify_pose("item_brace_plank", "braced"); camera()
		check(pick_subject("item_brace_plank"), "same-process restored brace stays selectable")
		await capture("creative_03_same_process_loaded")

func run_resume_case() -> void:
	if not await new_session(1, true): return
	check(C.digest(scene.playtest.state_copy()) == checkpoint.world_sha256, "actual main presents exact restored world without content injection")
	verify_pose("item_brace_plank", "braced")
	check(pick_subject("item_brace_plank"), "fresh-process restored brace selectable")
	await capture("creative_03_loaded_braced")
	if not authored("remove_brace"): return
	verify_pose("item_brace_plank", "loose")
	var current: Dictionary = scene.playtest.state_copy(); var target: Dictionary = current.passage_targets[NORTH]
	check(not Effects.active_target(current, NORTH), "assessed removal deactivates only brace relation")
	check(scene.playtest.movement_preview(target.endpoints[0]).get("route", []).size() == 2, "removal restores direct dry route")
	check(pick_subject("item_brace_plank"), "actual removed loose source remains selectable")
	await capture("creative_04_removed_loose")
	var ids: Array = current.items.keys(); ids.sort(); check(ids == checkpoint.item_ids, "true-restart removal preserves all item IDs and count")
	await verify_carried_motion()

func run_partial_case() -> void:
	if not await new_session(seed_for(true, false)): return
	if not authored("brace_oar"): return
	verify_pose("item_brace_oar", "loose"); check(not Effects.active_target(scene.playtest.state_copy(), NORTH), "partial placement never blocks passage")
	check(pick_subject("item_brace_oar"), "actual partial loose oar selectable")
	await capture("creative_05_partial_oar")

func run_failure_case() -> void:
	if not await new_session(seed_for(false, true)): return
	var before: Dictionary = scene.playtest.state_copy().items.item_brace_bar.duplicate(true)
	if not authored("brace_bar"): return
	var current: Dictionary = scene.playtest.state_copy()
	check(C.bytes(current.items.item_brace_bar) == C.bytes(before) and current.creative_placements.is_empty() and not Effects.active_target(current, NORTH), "placement failure suppresses stability and preserves exact source custody")
	check(scene.board.creative_view.report().carried_items == 3, "failed bar stays visibly carried")
	check(pick_subject("item_brace_bar"), "failed bar remains actually selectable on actor")
	await capture("creative_06_failed_bar")

func finish() -> void:
	mark("finish")
	if is_instance_valid(watchdog): watchdog.stop()
	var report := {"case": test_case, "checks": checks, "failures": failures, "passed": failures.is_empty(), "display_server": DisplayServer.get_name(), "live_api": false, "no_world_mutation_harness": true, "seeded_release_test": true, "sessions": sessions, "captures": captures, "progress": progress_rows}
	if is_instance_valid(scene): report.renderer = scene.board.creative_view.report()
	var file := FileAccess.open(output_dir + "native_report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("CREATIVE_NATIVE ", checks, " checks; failures=", failures, "; output=", output_dir)
	if is_instance_valid(scene): scene.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
