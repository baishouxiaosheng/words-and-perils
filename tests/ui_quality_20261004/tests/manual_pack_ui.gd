extends SceneTree
## Read-only actual-window QA. The caller supplies a verified idle checkpoint.
## F8 records UI evidence; F9 or normal window-close records final state and exits.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Inventory = preload("res://view/generated_inventory/adapter.gd")
var app: Control
var checkpoint := ""
var out := ""
var initial_authority := ""
var last_f8 := false
var last_f9 := false
var finishing := false
var capture_busy := false
var records: Array = []
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint="): checkpoint = arg.trim_prefix("--checkpoint=")
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	call_deferred("run")
func frames(n: int = 5) -> void:
	for i in range(n): await process_frame
func run() -> void:
	if checkpoint.is_empty() or out.is_empty() or DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("FOGBANK_QA_WINDOWED", "1")
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	app = load("res://main.tscn").instantiate(); root.add_child(app); await frames(12)
	var restored := Inventory.new()
	var loaded: Dictionary = restored.load_file(checkpoint)
	if not loaded.get("ok", false) or restored.phase() != "idle":
		printerr("MANUAL_PACK_CHECKPOINT_REJECTED ", loaded); app.queue_free(); await frames(); quit(2); return
	app.generated_adventure = restored
	app._switch_mode("generated"); await frames()
	root.mode = Window.MODE_WINDOWED; root.size = Vector2i(1280, 720); await frames()
	initial_authority = C.digest(app.playtest.save_data())
	auto_accept_quit = false
	root.close_requested.connect(finish)
	process_frame.connect(poll_keys)
	await record("ready")
	print("MANUAL_PACK_READY F8=capture F9=finish authority=", initial_authority)
func poll_keys() -> void:
	if finishing: return
	var f8 := Input.is_physical_key_pressed(KEY_F8)
	var f9 := Input.is_physical_key_pressed(KEY_F9)
	if f8 and not last_f8: record.call_deferred("manual_" + str(records.size()))
	if f9 and not last_f9: finish.call_deferred()
	last_f8 = f8; last_f9 = f9
func record(label_: String) -> void:
	if capture_busy or not is_instance_valid(app): return
	capture_busy = true
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path := out.path_join(label_ + ".png")
	var saved := image.save_png(path)
	var current := C.digest(app.playtest.save_data())
	records.append({"label": label_, "path": path, "png_saved": saved == OK, "native_root": [root.size.x, root.size.y], "world_raster": [app.viewport.size.x, app.viewport.size.y], "png_size": [image.get_width(), image.get_height()], "authority_unchanged": current == initial_authority, "selected_focus": app.selected_focus.duplicate(true), "target_caption": app.target_label.text, "details_visible": app.focus_details_dialog.visible, "details": app.focus_details_text.text, "inventory_visible": app.inventory_dialog.visible, "pack": app.board.inventory_pack.diagnostic()})
	write_report(false)
	capture_busy = false
func write_report(done: bool) -> void:
	var file := FileAccess.open(out.path_join("manual_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed": done, "scope": "Actual-window mouse/keyboard read-only UI QA; no new gameplay action or provider", "checkpoint": checkpoint, "initial_authority": initial_authority, "records": records, "all_recorded_authority_unchanged": records.all(func(row): return row.authority_unchanged)}, "\t")); file.close()
func finish() -> void:
	if finishing: return
	finishing = true
	while capture_busy: await process_frame
	await record("final")
	write_report(true)
	var good := records.all(func(row): return row.authority_unchanged)
	print("MANUAL_PACK_COMPLETE records=", records.size(), " readonly=", good)
	app.queue_free(); await frames(4); quit(0 if good else 1)
