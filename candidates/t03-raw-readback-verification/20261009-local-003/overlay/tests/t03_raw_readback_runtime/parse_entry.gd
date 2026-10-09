extends SceneTree
func verify_isolation() -> bool:
	var root := OS.get_cmdline_user_args()[0].replace("\\", "/").simplify_path().trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	var global_dir := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		if str(p.name).begins_with("autoload/"): autoloads.append(p.name)
	var isolated := os_dir.to_lower().begins_with((root+"/appdata/Godot/app_userdata/").to_lower()) and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
	print("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads}))
	return isolated
func _initialize() -> void:
	if not verify_isolation():
		quit(3)
		return
	var loaded: Array = []
	var valid := true
	var resource_0: Script = load("res://core/ai_gm_rebuilt/engine.gd")
	valid = valid and resource_0 != null and resource_0.can_instantiate()
	loaded.append({"path":"core/ai_gm_rebuilt/engine.gd","sha256":FileAccess.get_sha256("res://core/ai_gm_rebuilt/engine.gd")})
	var resource_1: Script = load("res://core/ai_gm_rebuilt/canonical.gd")
	valid = valid and resource_1 != null and resource_1.can_instantiate()
	loaded.append({"path":"core/ai_gm_rebuilt/canonical.gd","sha256":FileAccess.get_sha256("res://core/ai_gm_rebuilt/canonical.gd")})
	var resource_2: Script = load("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
	valid = valid and resource_2 != null and resource_2.can_instantiate()
	loaded.append({"path":"tests/experimental/ai_gm_rebuilt/story_fixture.gd","sha256":FileAccess.get_sha256("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")})
	var resource_3: Script = load("res://tests/t03_raw_readback/io_probe.gd")
	valid = valid and resource_3 != null and resource_3.can_instantiate()
	loaded.append({"path":"tests/t03_raw_readback/io_probe.gd","sha256":FileAccess.get_sha256("res://tests/t03_raw_readback/io_probe.gd")})
	var resource_4: Script = load("res://tests/t03_raw_readback/test_save_file.gd")
	valid = valid and resource_4 != null and resource_4.can_instantiate()
	loaded.append({"path":"tests/t03_raw_readback/test_save_file.gd","sha256":FileAccess.get_sha256("res://tests/t03_raw_readback/test_save_file.gd")})
	print("RAW_PARSE_RESULT ",JSON.stringify({"ok":valid,"loaded":loaded,"pid":OS.get_process_id(),"entry_sha256":FileAccess.get_sha256(get_script().resource_path),"test_bodies_started":false}))
	quit(0 if valid else 1)
