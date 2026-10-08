extends RefCounted
## Test-only in-memory file backend for an exact source-extracted save_file.
const WRITE := 2
static var scenario: Dictionary = {}
static var files: Dictionary = {}
static var calls: Array = []

class Handle:
	extends RefCounted
	var path: String
	var options: Dictionary
	var contents: Dictionary
	var log_calls: Array
	func _init(next_path: String, next_options: Dictionary, next_contents: Dictionary, next_calls: Array) -> void:
		path = next_path; options = next_options; contents = next_contents; log_calls = next_calls
	func store_string(encoded: String) -> bool:
		log_calls.append("store")
		var stored: bool = options.get("stored", true)
		contents[path] = encoded if stored else encoded.left(7)
		return stored
	func flush() -> void: log_calls.append("flush")
	func get_error() -> Error:
		log_calls.append("get_error")
		return options.get("write_error", OK)
	func close() -> void: log_calls.append("close")

static func reset(options: Dictionary, path: String, destination: String) -> void:
	scenario = options.duplicate(true)
	files = {path: destination, path + ".tmp": "PREEXISTING_TMP"}
	calls = []

static func open(path: String, mode: int) -> RefCounted:
	calls.append("open")
	if mode != WRITE or scenario.get("open_failed", false): return null
	files[path] = ""
	return Handle.new(path, scenario, files, calls)

static func rename_absolute(temporary: String, destination: String) -> Error:
	calls.append("rename")
	var error: Error = scenario.get("rename_error", OK)
	if error != OK: return error
	files[destination] = files[temporary]
	files.erase(temporary)
	return OK
