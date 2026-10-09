extends "res://tests/focused/test_combined_player_details.gd"
func verify_isolation() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		print("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":false,"reason":"missing trusted data-root argument"}))
		return false
	var root := args[0].replace("\\", "/").simplify_path().trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	var global_dir := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/")
	var leaf := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var expected := root+"/appdata/"+leaf
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		if str(p.name).begins_with("autoload/"): autoloads.append(p.name)
	var isolated := not leaf.is_empty() and not leaf.contains("/") and not leaf.contains("\\") and os_dir.to_lower()==expected.to_lower() and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
	print("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"expected":expected,"autoloads":autoloads}))
	return isolated
func _initialize() -> void:
	if not verify_isolation():
		quit(3)
		return
	super._initialize()
