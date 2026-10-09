extends "res://tests/t03_raw_readback/test_save_file.gd"
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
func _init() -> void:
	if not verify_isolation():
		quit(3)
		return
	super._init()
