extends SceneTree
const Prototype0 = preload("res://view/playable_build/player_details.gd")
const Prototype1 = preload("res://tests/focused/baseline_player_details.gd")
const Prototype2 = preload("res://tests/focused/test_focus_location.gd")
const Prototype3 = preload("res://tests/focused/local_isolated.gd")
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
	var loaded: Array = []
	var valid := true
	var loaded_script0: Script = load("res://view/playable_build/player_details.gd")
	valid = valid and loaded_script0 != null and loaded_script0.can_instantiate()
	loaded.append({"path":"view/playable_build/player_details.gd","sha256":FileAccess.get_sha256("res://view/playable_build/player_details.gd")})
	var loaded_script1: Script = load("res://tests/focused/baseline_player_details.gd")
	valid = valid and loaded_script1 != null and loaded_script1.can_instantiate()
	loaded.append({"path":"tests/focused/baseline_player_details.gd","sha256":FileAccess.get_sha256("res://tests/focused/baseline_player_details.gd")})
	var loaded_script2: Script = load("res://tests/focused/test_focus_location.gd")
	valid = valid and loaded_script2 != null and loaded_script2.can_instantiate()
	loaded.append({"path":"tests/focused/test_focus_location.gd","sha256":FileAccess.get_sha256("res://tests/focused/test_focus_location.gd")})
	var loaded_script3: Script = load("res://tests/focused/local_isolated.gd")
	valid = valid and loaded_script3 != null and loaded_script3.can_instantiate()
	loaded.append({"path":"tests/focused/local_isolated.gd","sha256":FileAccess.get_sha256("res://tests/focused/local_isolated.gd")})
	print("FOCUSED_PARSE_RESULT ",JSON.stringify({"ok":valid,"pid":OS.get_process_id(),"loaded":loaded,"entry_sha256":FileAccess.get_sha256(get_script().resource_path),"test_bodies_started":false}))
	quit(0 if valid else 1)
