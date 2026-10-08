extends RefCounted
## Test-only memory backend. No native flush/close failure is claimed.
const READ := 1
const WRITE := 2
static var scenario: Dictionary = {}
static var files: Dictionary = {}
static var calls: Array = []

class Handle:
	extends RefCounted
	var path: String
	var mode: int
	var options: Dictionary
	var contents: Dictionary
	var log_calls: Array
	var position: int = 0
	var closed: bool = false
	func _init(next_path: String, next_mode: int, next_options: Dictionary, next_contents: Dictionary, next_calls: Array) -> void:
		path = next_path; mode = next_mode; options = next_options; contents = next_contents; log_calls = next_calls
	func store_string(encoded: String) -> bool:
		log_calls.append("store")
		var stored: bool = options.get("stored", true)
		var bytes: PackedByteArray = encoded.to_utf8_buffer()
		contents[path] = bytes if stored else bytes.slice(0, mini(7, bytes.size()))
		return stored
	func flush() -> void:
		log_calls.append("flush")
		if options.get("late_flush_loss", false): _truncate()
	func get_error() -> Error:
		log_calls.append("write_error" if mode == WRITE else "read_error")
		if mode == WRITE: return options.get("write_error", OK)
		if options.get("length_error", false): return ERR_FILE_CANT_READ
		return options.get("read_error", OK) if position > 0 else OK
	func get_length() -> int:
		log_calls.append("length")
		return contents[path].size()
	func get_buffer(amount: int) -> PackedByteArray:
		log_calls.append("read_%d" % amount)
		var bytes: PackedByteArray = contents[path]
		var count: int = mini(amount, maxi(0, bytes.size() - position))
		if options.get("short_read", false): count = maxi(0, count - 1)
		var result: PackedByteArray = bytes.slice(position, position + count)
		position += count
		if options.get("append_during_read", false) and position > 0:
			bytes.append(0); contents[path] = bytes
		return result
	func close() -> void:
		log_calls.append("close_write" if mode == WRITE else "close_read")
		closed = true
		if mode == WRITE and options.get("late_close_loss", false): _truncate()
	func _truncate() -> void:
		var bytes: PackedByteArray = contents[path]
		contents[path] = bytes.slice(0, maxi(0, bytes.size() - 1))

static func reset(options: Dictionary, path: String, destination: String) -> void:
	scenario = options.duplicate(true)
	files = {path: destination.to_utf8_buffer(), path + ".tmp": "PREEXISTING_TMP".to_utf8_buffer()}
	calls = []

static func open(path: String, mode: int) -> RefCounted:
	calls.append("open_write" if mode == WRITE else "open_read")
	if mode == WRITE:
		if scenario.get("open_failed", false): return null
		files[path] = PackedByteArray()
	elif mode == READ:
		if scenario.get("read_open_failed", false) or not files.has(path): return null
		var bytes: PackedByteArray = files[path]
		if scenario.get("truncate_before_read", false): bytes = bytes.slice(0, maxi(0, bytes.size() - 1))
		if scenario.get("same_length_corruption", false) and not bytes.is_empty(): bytes[0] = bytes[0] ^ 1
		files[path] = bytes
	else:
		return null
	return Handle.new(path, mode, scenario, files, calls)

static func rename_absolute(temporary: String, destination: String) -> Error:
	calls.append("rename")
	var error: Error = scenario.get("rename_error", OK)
	if error != OK: return error
	files[destination] = files[temporary]
	files.erase(temporary)
	return OK
