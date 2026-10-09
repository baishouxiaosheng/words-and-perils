extends SceneTree
## Complete Main selection CPU boundary after real raw geometry picking.
## Two AB + two BA pairs per kind. Startup, raw pick, and validation are untimed.
const Main = preload("res://main.tscn")
const Support = preload("res://tests/lazy_typed_attention/support.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PAIRS = 4
var suite = Support.new()
var app
var samples: Array = []
var picks: Array = []
var started_us: int

func _initialize() -> void: call_deferred("run")

func frames(count: int = 2) -> void:
	for _frame in range(count): await process_frame

func camera_at(hex: Array, yaw: float = 0.0) -> void:
	app.board.view_focus = app.playtest.source.navigation.cell_center(hex)
	app.board.camera_distance = 7.5
	app.board.overview_mode = false
	app.board.orbit_camera(yaw, 0)

func visible_screen(point: Vector3) -> Vector2:
	if app.board.camera.is_position_behind(point): return Vector2(-1, -1)
	return app.board.camera.unproject_position(point)

func raw_hit_at(point: Vector3, catalog_version: String) -> Dictionary:
	var screen: Vector2 = visible_screen(point)
	if screen.x < 0 or screen.y < 0 or screen.x >= app.viewport.size.x or screen.y >= app.viewport.size.y: return {}
	var candidates: Array = app.board.pick_focus(screen)
	# Retain the entire actual ordered raw result. Do not promote an occluded hit.
	if candidates.is_empty() or candidates[0].reference.get("catalog_version") != catalog_version: return {}
	return {"candidates": candidates.duplicate(true), "screen": screen}

func raw_npc() -> Dictionary:
	var id: String = app.playtest.source.npc_id
	var token: Node3D = app.board.token_nodes[id]
	var hex: Array = app.playtest.state_copy().actors[id].hex
	for turn in [0.0, 0.8, 0.8, 0.8]:
		camera_at(hex, turn); await frames()
		for offset in [0.16, 0.11, 0.22]:
			var found: Dictionary = raw_hit_at(token.global_position + Vector3(0, offset, 0), "source-npc-focus/v1")
			if not found.is_empty(): return found
	return {}

func raw_vegetation() -> Dictionary:
	# Bounded deterministic search over genuine visible plant meshes, never proxies.
	var plants: Array = app.playtest.source.vegetation_result.manifest.plants.duplicate()
	plants.sort_custom(func(a, b): return float(a.height) > float(b.height) if a.height != b.height else str(a.id) < str(b.id))
	for index in range(mini(24, plants.size())):
		var plant: Dictionary = plants[index]
		camera_at(plant.hex); await frames()
		var p: Array = plant.position
		for fraction in [0.55, 0.75, 0.35]:
			var found: Dictionary = raw_hit_at(Vector3(p[0], p[1] + float(plant.height) * fraction, p[2]), "source-vegetation-focus/v1")
			if not found.is_empty(): return found
	return {}

func ui_identity() -> Dictionary:
	return {"selected_focus": app.selected_focus.duplicate(true), "resolved_focus": app.resolved_focus.duplicate(true), "selected_hex": [app.selected.x, app.selected.y], "board_selected_hex": [app.board.selected_hex.x, app.board.selected_hex.y], "board_selected_actor": app.board.selected_actor_id, "board_selected_static": app.board.selected_static_id, "board_selected_vegetation": app.board.vegetation_view._selected_id, "target_label": app.target_label.text, "target_tooltip": app.target_label.tooltip_text, "target_visible": app.target_row.visible, "clear_enabled": not app.clear_target_button.disabled, "route_preview": app.movement_preview.duplicate(true), "choice_count": app.focus_choices.size(), "choice_visible": app.focus_choice_button.visible, "popup_visible": app.focus_choice_popup.visible, "goal": app.goal.text}

func benchmark(label: String, hit: Dictionary) -> void:
	var adapter: RefCounted = app.playtest
	var reference: Dictionary = hit.candidates[0].reference
	var input: Dictionary = {"reference": reference, "screen": [hit.screen.x, hit.screen.y], "candidates": []}
	for candidate in hit.candidates:
		input.candidates.append({"reference": candidate.reference, "label": candidate.label, "distance": candidate.distance})
	var input_hash: String = C.digest(input)
	picks.append({"label": label, "input": input, "sha256": input_hash, "raw_picker": "board.pick_focus", "first_visible_subject_only": true})
	var expected_ui: Dictionary = {}
	# Warm both implementations equally through the exact measured operation.
	for variant in ["old", "new"]:
		adapter.engine = suite.pair[variant]
		app.clear_target(); await frames()
		var before: Dictionary = Support.identity(adapter)
		adapter.engine.facts_calls = 0
		app.on_focus_candidates(hit.candidates.duplicate(true), hit.screen)
		suite.check(Support.identity(adapter) == before, label + " " + variant + " warmup read-only")
		suite.check(adapter.engine.facts_calls == (1 if variant == "old" else 0), label + " " + variant + " warmup actual facts calls")
		suite.check(C.bytes(app.selected_focus) == C.bytes(reference), label + " " + variant + " real raw subject selected")
		if expected_ui.is_empty(): expected_ui = ui_identity()
		else: suite.check(C.bytes(ui_identity()) == C.bytes(expected_ui), label + " warmup exact Main UI parity")
	for pair_index in range(PAIRS):
		var order: Array = ["old", "new"] if pair_index % 2 == 0 else ["new", "old"]
		var pair_baseline: Dictionary = {}
		for order_index in range(order.size()):
			var variant: String = order[order_index]
			adapter.engine = suite.pair[variant]
			app.clear_target(); await frames()
			var before: Dictionary = Support.identity(adapter)
			if pair_baseline.is_empty(): pair_baseline = before
			else: suite.check(before == pair_baseline, label + " pair" + str(pair_index) + " identical authoritative inputs")
			adapter.engine.facts_calls = 0
			var candidates: Array = hit.candidates.duplicate(true)
			var started: int = Time.get_ticks_usec()
			app.on_focus_candidates(candidates, hit.screen)
			var elapsed: int = Time.get_ticks_usec() - started
			var facts_calls: int = adapter.engine.facts_calls
			var output: Dictionary = ui_identity()
			suite.check(Support.identity(adapter) == before, label + " " + variant + " measured save/RNG/request/pending read-only")
			suite.check(C.bytes(output) == C.bytes(expected_ui), label + " " + variant + " measured exact Main output")
			suite.check(facts_calls == (1 if variant == "old" else 0), label + " " + variant + " measured actual facts calls")
			samples.append({"label": label, "pair": pair_index, "order": order, "order_index": order_index, "variant": variant, "elapsed_us": elapsed, "facts_calls": facts_calls, "input_sha256": input_hash, "save_sha256": before.save.sha256_text(), "request_sha256": before.request.sha256_text(), "world_sha256": before.world.sha256_text(), "rng_sha256": before.rng.sha256_text(), "pending_target_sha256": before.pending_target.sha256_text(), "active_action": before.active_action, "phase": before.phase, "ui_sha256": C.digest(output)})
		suite.check(order == (["old", "new"] if pair_index % 2 == 0 else ["new", "old"]), label + " reversed pairing retained")
	suite.restore(adapter)

func summarize() -> Dictionary:
	var result: Dictionary = {}
	for label in ["npc", "vegetation"]:
		var entry: Dictionary = {}
		for variant in ["old", "new"]:
			var times: Array = []; var facts_calls: int = 0
			for row in samples:
				if row.label == label and row.variant == variant:
					times.append(row.elapsed_us); facts_calls += int(row.facts_calls)
			times.sort()
			if times.is_empty(): continue
			var total: float = 0.0
			for elapsed in times: total += float(elapsed)
			entry[variant] = {"repetitions": times.size(), "facts_calls": facts_calls, "min_us": times[0], "max_us": times[-1], "mean_us": total / times.size(), "median_us": (float(times[(times.size() - 1) / 2]) + float(times[times.size() / 2])) / 2.0}
		if entry.has("old") and entry.has("new"):
			entry["old_over_new_median_ratio"] = entry.old.median_us / maxf(1.0, entry.new.median_us)
			entry["median_reduction_fraction"] = 1.0 - entry.new.median_us / maxf(1.0, entry.old.median_us)
		result[label] = entry
	return result

func finish() -> void:
	suite.write_report("res://artifacts/lazy_typed_attention/main_benchmark_report.json", {"elapsed_us": Time.get_ticks_usec() - started_us, "boundary": "synchronous Main.on_focus_candidates after genuine board.pick_focus; production strict focus validation and selection/UI refresh included; raw picker, render-frame latency and test assertions/serialization excluded; details dialog not opened", "fixture": {"seed": 726381, "radius": 12, "recipe": "coastal_range", "vegetation": true}, "source_admissions": 1, "main_instances": 1, "display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "warmups_per_variant_per_kind": 1, "pairs_per_kind": PAIRS, "raw_picks": picks, "samples": samples, "summary": summarize()})
	print("LAZY_ATTENTION_MAIN ", suite.checks, " ", suite.failures, " ", JSON.stringify(summarize()))
	quit(0 if suite.failures.is_empty() else 1)

func run() -> void:
	started_us = Time.get_ticks_usec(); root.size = Vector2i(1280, 720)
	var adapter = suite.admit()
	if adapter == null or not suite.engines_for(adapter): finish(); return
	app = Main.instantiate(); app.startup_legacy = true; root.add_child(app); await frames()
	app._switch_mode_to("generated_v3_npc", adapter); await frames(3)
	if not suite.check(app.playtest == adapter and app.generated_v3_npc_mode and app.board.load_error.is_empty(), "one admitted real source installed in actual Main"): finish(); return
	app.set_map_dialogue_hidden(true)
	var npc_hit: Dictionary = await raw_npc()
	if not suite.check(not npc_hit.is_empty(), "raw visible NPC foreground hit exists"): finish(); return
	await benchmark("npc", npc_hit)
	app.clear_target(); await frames()
	var vegetation_hit: Dictionary = await raw_vegetation()
	if not suite.check(not vegetation_hit.is_empty(), "raw visible vegetation foreground hit exists"): finish(); return
	await benchmark("vegetation", vegetation_hit)
	# Main pending-target semantics use the same actual raw plant click.
	var begun: Dictionary = adapter.begin_intent("查看守路村民，保留当前目标等待评估。", adapter.npc_reference())
	if suite.check(begun.ok, "real pending NPC intent before later UI click") and suite.engines_for(adapter):
		var expected: Dictionary = {}
		for variant in ["old", "new"]:
			adapter.engine = suite.pair[variant]
			var before: Dictionary = Support.identity(adapter)
			app.on_focus_candidates(vegetation_hit.candidates.duplicate(true), vegetation_hit.screen)
			suite.check(Support.identity(adapter) == before, variant + " pending Main click preserves exact frozen target/request/RNG/save")
			suite.check(app.selected_focus.catalog_version == "source-vegetation-focus/v1" and adapter.action_copy().focus.catalog_version == "source-npc-focus/v1", variant + " pending NPC target distinct from subsequent plant selection")
			if expected.is_empty(): expected = ui_identity()
			else: suite.check(C.bytes(ui_identity()) == C.bytes(expected), "pending Main output exact old/new parity")
		suite.restore(adapter)
		suite.check(adapter.cancel().ok, "pending Main test action canceled")
	finish()
