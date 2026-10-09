extends RefCounted
## API settings remembered on this machine, outside every project folder, so all
## builds and updates read the same file: %APPDATA%/WordsAndPerils/api_settings.cfg.
## Encrypted with a per-machine pass. Keys never enter saves, logs or the repo.
## Scripted runs (-s/--script, i.e. tests) ignore the file unless WP_USE_SAVED_API=1.
const FILE := "WordsAndPerils/api_settings.cfg"
const PREFS := ["connection_enabled", "automatic_assessment", "automatic_narration"]

static func path() -> String:
	var base := OS.get_environment("APPDATA")
	return (base if not base.is_empty() else OS.get_data_dir()).replace("\\", "/") + "/" + FILE

static func enabled() -> bool:
	var scripted := false
	for arg in OS.get_cmdline_args(): scripted = scripted or arg in ["-s", "--script"]
	return not scripted or OS.get_environment("WP_USE_SAVED_API") == "1"

static func _pass() -> String: return "words-and-perils-api/" + OS.get_unique_id()

## {"roles": {role: {"config": {...}, "key": "..."}}, "prefs": {...}} or {} when absent/unreadable.
static func read() -> Dictionary:
	if not enabled() or not FileAccess.file_exists(path()): return {}
	var file := ConfigFile.new()
	if file.load_encrypted_pass(path(), _pass()) != OK: return {}
	var roles := {}
	for role in file.get_sections():
		if role == "prefs": continue
		var config: Variant = file.get_value(role, "config", {}); var key: Variant = file.get_value(role, "key", "")
		if config is Dictionary and key is String: roles[role] = {"config": config, "key": key}
	var prefs := {}
	for name in PREFS:
		var value: Variant = file.get_value("prefs", name, null)
		if value is bool: prefs[name] = value
	return {"roles": roles, "prefs": prefs}

static func write(roles: Dictionary, prefs: Dictionary) -> bool:
	if not enabled(): return false
	DirAccess.make_dir_recursive_absolute(path().get_base_dir())
	var file := ConfigFile.new()
	for role in roles:
		file.set_value(role, "config", roles[role].config); file.set_value(role, "key", roles[role].key)
	for name in PREFS:
		if prefs.has(name): file.set_value("prefs", name, bool(prefs[name]))
	return file.save_encrypted_pass(path(), _pass()) == OK

static func forget() -> void:
	if enabled() and FileAccess.file_exists(path()): DirAccess.remove_absolute(path())
