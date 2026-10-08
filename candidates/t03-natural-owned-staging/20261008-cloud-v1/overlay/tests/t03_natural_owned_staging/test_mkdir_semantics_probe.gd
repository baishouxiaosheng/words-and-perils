extends SceneTree
## Runtime prerequisite on the existing target binary, not a save/gameplay suite.
var failures: Array = []
var checks := 0
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures.append(label_); printerr("FAIL: "+label_)
func _initialize() -> void:
	var expected: String = OS.get_environment("FOGBANK_STAGING_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/") != expected:
		printerr("MKDIR_PROBE_REFUSED: explicit isolated user directory required"); quit(2); return
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	check(bytes.size() == 32,"strong nonce returned exact size")
	if bytes.size() != 32: finish({}); return
	var parent: String = ProjectSettings.globalize_path("user://").path_join(".words-and-perils-natural-mkdir-probe-"+bytes.hex_encode())
	var owned: Error = DirAccess.make_dir_absolute(parent)
	check(owned == OK,"new private parent created")
	if owned != OK: finish({"parent_create":int(owned)}); return
	var directory: String = parent.path_join("exclusive")
	var first: Error = DirAccess.make_dir_absolute(directory)
	var second: Error = DirAccess.make_dir_absolute(directory)
	check(first == OK and DirAccess.dir_exists_absolute(directory),"new directory succeeds")
	check(second != OK,"existing directory must not return OK")
	var sentinel: String = parent.path_join("existing-file")
	var file := FileAccess.open(sentinel,FileAccess.WRITE)
	check(file != null,"private sentinel opened")
	var file_existing: Error = FAILED
	if file != null:
		var stored: bool = file.store_string("PRIVATE_MKDIR_SENTINEL"); file.flush()
		var write_error: Error = file.get_error(); file.close()
		check(stored and write_error == OK,"private sentinel fully written")
		file_existing = DirAccess.make_dir_absolute(sentinel)
		check(file_existing != OK,"existing regular file must not return OK")
		check(FileAccess.get_file_as_string(sentinel) == "PRIVATE_MKDIR_SENTINEL","existing regular file bytes unchanged")
		var removed_file: Error = DirAccess.remove_absolute(sentinel)
		check(removed_file == OK,"remove only own fixed sentinel")
	if first == OK:
		var removed_directory: Error = DirAccess.remove_absolute(directory)
		check(removed_directory == OK,"remove only own empty test directory")
	var removed_parent: Error = DirAccess.remove_absolute(parent)
	check(removed_parent == OK,"remove only own empty parent; no recursive cleanup")
	finish({"first":int(first),"existing_directory":int(second),"existing_file":int(file_existing),"cleanup_parent":int(removed_parent)})
func finish(results: Dictionary) -> void:
	print("NATURAL_STAGING_MKDIR_PROBE ",JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"mkdir_results":results,"version":Engine.get_version_info(),"pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"isolated actual mkdir semantics only; not source/binary provenance, save concurrency, target replacement or durability"}))
	quit(0 if failures.is_empty() else 1)
