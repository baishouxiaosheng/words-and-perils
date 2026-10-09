extends SceneTree
## One full scene, no same-process reload. Native framebuffer captures only.
## Baseline changes only MSAA and the new water filter, not source/game state.
const Main = preload("res://main.tscn")
const Canonical = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Quality = preload("res://view/render_quality.gd")
var scene
var target := Vector2i(1920, 1080)
var out := "res://artifacts/render_quality_20261003/native"
var report := {"captures": [], "timings": [], "checks": [], "target_hardware_tested": false}
var failures := 0
var seconds := 5.0
func _initialize() -> void: call_deferred("run")
func settle(frames: int = 12) -> void:
	for i in range(frames): await process_frame
func check(value: bool, label_: String) -> void:
	report.checks.append({"passed": value, "name": label_})
	if not value: failures += 1; printerr("QUALITY FAIL: ", label_)
func save_report() -> void:
	report["failures"] = failures
	var f := FileAccess.open(out + "/comparison.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t")); f.close()
func ripple_filter(enabled: bool) -> void:
	for mat in scene.board.world_view.clear_daylight_profile.water_shaders:
		mat.set_shader_parameter("ripple_antialiasing", enabled)
func capture(tag: String, expected_camera: Transform3D) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	var image_: Image = root.get_texture().get_image()
	var path := out + "/" + tag + ".png"
	check(image_.get_size() == target, tag + ": native PNG dimensions")
	check(image_.save_png(path) == OK, tag + ": saved framebuffer")
	check(scene.viewport.size == target and scene.viewport.scaling_3d_scale == 1.0 and scene.board_container.stretch_shrink == 1, tag + ": 1:1 world raster")
	check(scene.board.camera.global_transform == expected_camera, tag + ": exact same camera transform")
	report.captures.append({"tag": tag, "path": path, "pixels": [image_.get_width(), image_.get_height()], "camera_transform": str(expected_camera), "camera_size": scene.board.camera.size, "msaa_enum": scene.viewport.msaa_3d, "preset": scene.viewport.get_meta(&"render_quality"), "no_resampling": true, "source_sha256": FileAccess.get_sha256(path)})
	image_ = null
	save_report()
func profile(tag: String, repetition: int) -> void:
	await settle(16)
	var samples: Array[float] = []
	var start := Time.get_ticks_usec(); var previous := start
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		await process_frame
		var now := Time.get_ticks_usec(); samples.append(float(now - previous) / 1000.0); previous = now
	var elapsed := float(Time.get_ticks_usec() - start) / 1000.0
	samples.sort()
	var row := {"tag": tag, "repetition": repetition, "frames": samples.size(), "mean_frame_ms": elapsed / maxi(samples.size(), 1), "p50_frame_ms": samples[samples.size()/2], "p95_frame_ms": samples[mini(samples.size()-1, int(samples.size()*.95))], "observed_fps": samples.size() * 1000.0 / elapsed, "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "viewport": [scene.viewport.size.x, scene.viewport.size.y], "msaa_enum": scene.viewport.msaa_3d, "process_enabled": true, "vsync_disable_requested": true, "vsync_effective_verified": false, "engine_max_fps": Engine.max_fps}
	report.timings.append(row); print("AA TIMING ", JSON.stringify(row)); save_report()
func run() -> void:
	if DisplayServer.get_name() == "headless": printerr("Native renderer is required for AA image/performance evidence"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var pair := arg.trim_prefix("--size=").split("x"); target = Vector2i(int(pair[0]), int(pair[1]))
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seconds="): seconds = maxf(1.0, float(arg.trim_prefix("--seconds=")))
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	root.mode = Window.MODE_WINDOWED; root.size = target
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	report.merge({"display": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "requested_pixels": [target.x, target.y], "engine_version": Engine.get_version_info(), "sample_seconds": seconds, "sampling": "Live idle scene; warm-up 16 frames each; order 2x,4x,off then off,4x,2x to expose order drift. Engine FPS cap removed; VSync disable is requested but this cloud driver reports unsupported changes, so effective VSync is not verified. Not target laptop proof"})
	scene = Main.instantiate(); root.add_child(scene); await settle(24)
	root.mode = Window.MODE_WINDOWED; root.size = target; await settle()
	check(scene.coast_mode, "actual coast scene active")
	check(scene.board.world_view.clear_daylight_profile.enabled, "faceted unshaded daylight profile active")
	var state_before := Canonical.bytes(scene.playtest.state_copy())
	var camera: Transform3D = scene.board.camera.global_transform
	# Identical camera, original shader at old hardware 2x versus new 4x and filter.
	scene.set_quality(Quality.Preset.BALANCED); ripple_filter(false)
	await capture("01_before_hardware_2x", camera)
	scene.set_quality(Quality.Preset.LOW_LOAD); ripple_filter(false)
	await capture("02_before_software_off", camera)
	scene.set_quality(Quality.Preset.FINE); ripple_filter(true)
	await capture("03_after_fine_4x", camera)
	scene.set_quality(Quality.Preset.BALANCED)
	await capture("04_after_balanced_2x", camera)
	# Matched repeated samples vary only AA; water filter stays enabled.
	for order in [[2,1,0], [0,1,2]]:
		for index in order:
			scene.set_quality(index)
			await profile(Quality.LABELS[index], 0 if order[0] == 2 else 1)
	# Distant silhouettes and water at the very same overview camera.
	scene.toggle_overview(); await settle(20); camera = scene.board.camera.global_transform
	scene.set_quality(Quality.Preset.BALANCED); ripple_filter(false)
	await capture("05_overview_before_2x", camera)
	scene.set_quality(Quality.Preset.FINE); ripple_filter(true)
	await capture("06_overview_after_4x", camera)
	# A close water view isolates shader aliasing from silhouette AA.
	scene.view_trial_river(); await settle(20); camera = scene.board.camera.global_transform
	scene.set_quality(Quality.Preset.FINE); ripple_filter(false)
	await capture("07_water_before_4x", camera)
	ripple_filter(true); await capture("08_water_after_4x", camera)
	for index in [0,2,1,0,1]:
		scene.on_tool_selected(Quality.MENU_IDS[index])
		check(scene.quality_choice.selected == index, "menu preset selects " + str(index))
		for other in range(3): check(scene.display_menu.is_item_checked(scene.display_menu.get_item_index(Quality.MENU_IDS[other])) == (index == other), "only current quality radio checked")
	check(Canonical.bytes(scene.playtest.state_copy()) == state_before, "quality/camera changes leave authoritative state byte-identical")
	save_report(); print("RENDER QUALITY NATIVE COMPLETE failures=", failures)
	scene.queue_free(); await process_frame; quit(0 if failures == 0 else 1)
