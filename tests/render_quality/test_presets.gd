extends SceneTree
const Quality = preload("res://view/render_quality.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("QUALITY FAIL: ", message)
func run() -> void:
	check(Quality.default_preset("NVIDIA GeForce GTX 1660 Ti") == Quality.Preset.FINE, "hardware default requests fine, not a hardware performance claim")
	check(Quality.default_preset("llvmpipe (LLVM 15)") == Quality.Preset.LOW_LOAD, "software preview is explicit low load")
	check(Quality.default_preset("softpipe") == Quality.Preset.LOW_LOAD, "softpipe is explicit low load")
	var holder := SubViewportContainer.new(); root.add_child(holder)
	var world := SubViewport.new(); holder.add_child(world)
	world.size = Vector2i(800, 600)
	for index in [0, 2, 1, 0, 1]:
		holder.stretch_shrink = 2
		world.scaling_3d_scale = 0.75
		var result := Quality.apply(world, root, holder, index)
		check(world.msaa_3d == [Viewport.MSAA_DISABLED, Viewport.MSAA_4X, Viewport.MSAA_2X][index], "requested world MSAA: " + str(index))
		check(root.msaa_3d == Viewport.MSAA_DISABLED, "HUD does not allocate 3D AA")
		check(world.scaling_3d_scale == 1.0 and holder.stretch_shrink == 1, "native 1:1 raster: " + str(index))
		check(world.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not world.use_taa, "no unsupported temporal or screen AA")
		check(int(result.samples) == [0, 4, 2][index], "sample metadata reflects actual setting")
		check(world.get_meta(&"render_quality").index == index, "runtime metadata identifies preset")
	check(Quality.status(0).contains("关闭抗锯齿"), "low-load status discloses jagged edges")
	check(Quality.status(1).contains("实机验证"), "fine status does not claim target GPU benchmark")
	var out := {"checks": checks, "failures": failures, "display_server": DisplayServer.get_name(), "headless_is_configuration_only": true}
	DirAccess.make_dir_recursive_absolute("res://artifacts/render_quality_20261003")
	var f := FileAccess.open("res://artifacts/render_quality_20261003/preset_unit.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t")); f.close()
	print("RENDER QUALITY UNIT ", JSON.stringify(out))
	holder.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
