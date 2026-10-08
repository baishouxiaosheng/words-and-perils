extends SceneTree
func _initialize() -> void:
	var root := OS.get_cmdline_user_args()[0].replace("\\", "/").simplify_path().trim_suffix("/")
	var os_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	var global_dir := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path().trim_suffix("/")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		if str(p.name).begins_with("autoload/"): autoloads.append(p.name)
	var isolated := os_dir.to_lower().begins_with((root+"/appdata/Godot/app_userdata/").to_lower()) and os_dir.to_lower()==global_dir.to_lower() and autoloads.is_empty()
	print("LOCAL_SUITE_ISOLATION ",JSON.stringify({"isolated":isolated,"os_user_dir":os_dir,"globalized_user_dir":global_dir,"autoloads":autoloads,"run_id":"task002-parse-01"}))
	if not isolated:
		quit(3)
		return
	OS.set_environment("FOGBANK_STAGING_TEST_USER_DIR",os_dir)
	OS.set_environment("COAST_PLAY_RECIPE","")
	OS.set_environment("COAST_PLAY_RUN_ID","task002-parse-01")
	OS.set_environment("COAST_PLAY_OUTPUT","E:/WordsAndPerils-Tasks/local-queue-bootstrap-20261008/run-01a1b40-02/runs/task002-parse-01/output")
	var candidate: Script = load("res://view/generated_natural_coast_basic/adapter.gd")
	var valid := candidate != null and candidate.can_instantiate()
	print("CANDIDATE_PARSE ",JSON.stringify({"ok":valid,"pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"adapter_sha256":FileAccess.get_sha256("res://view/generated_natural_coast_basic/adapter.gd")}))
	quit(0 if valid else 1)
