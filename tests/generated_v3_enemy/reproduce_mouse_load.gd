extends SceneTree
const Adapter = preload("res://view/generated_v3_enemy/adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var a: RefCounted = Adapter.new()
	var path: String = a.default_save_path()
	var raw: String = FileAccess.get_file_as_string(path)
	var result: Dictionary = a.load_file(path)
	var report: Dictionary = {"path":ProjectSettings.globalize_path(path), "exists":FileAccess.file_exists(path), "bytes":raw.to_utf8_buffer().size(), "load_result":result}
	FileAccess.open("res://artifacts/generated_v3_enemy/native_mouse/load_error.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if not raw.is_empty(): FileAccess.open("res://artifacts/generated_v3_enemy/native_mouse/actual_saved_core.json",FileAccess.WRITE).store_string(raw)
	print("MOUSE_LOAD_REPRODUCTION ",JSON.stringify(report))
	quit(0 if result.ok else 1)
