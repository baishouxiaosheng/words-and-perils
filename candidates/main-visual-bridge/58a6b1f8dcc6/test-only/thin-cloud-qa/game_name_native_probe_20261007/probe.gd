extends SceneTree
func _initialize()->void:
	var result={"schema":"isolated_native_user_path/v1","pid":OS.get_process_id(),"platform":OS.get_name(),"name":ProjectSettings.get_setting("application/config/name"),"custom_user_dir":ProjectSettings.get_setting("application/config/use_custom_user_dir",false),"configured_custom_name":ProjectSettings.get_setting("application/config/custom_user_dir_name",""),"features":{"linuxbsd":OS.has_feature("linuxbsd"),"linux":OS.has_feature("linux"),"windows":OS.has_feature("windows")},"user_data_dir":OS.get_user_data_dir(),"globalized_user_path":ProjectSettings.globalize_path("user://"),"project_sha256":FileAccess.get_sha256("res://project.godot"),"scope":"Only isolated ProjectSettings/OS path reads; no Main, no existing save content, no migration"}
	var f=FileAccess.open(OS.get_environment("NAME_PROBE_REPORT"),FileAccess.WRITE)
	if f==null:push_error("Cannot save isolated path probe");quit(2);return
	f.store_string(JSON.stringify(result,"\t"));f.close();print("ISOLATED_NATIVE_NAME_PATH ",JSON.stringify(result));quit()
