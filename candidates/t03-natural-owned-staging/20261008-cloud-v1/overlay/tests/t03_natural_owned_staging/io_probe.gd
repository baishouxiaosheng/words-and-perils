extends RefCounted
## Deterministic in-memory I/O only. Never scans or mutates real staging/user files.
const WRITE := 2
static var options: Dictionary = {}
static var files: Dictionary = {}
static var directories: Dictionary = {}
static var calls: Array = []
static var staging_calls: Array = []
static var counters: Dictionary = {}
static var created: Array = []
static var attempted: Array = []
static var serial := 0
class WriteHandle:
	extends RefCounted
	var path: String
	var settings: Dictionary
	var contents: Dictionary
	var order: Array
	var counts: Dictionary
	var flushed := false
	func _init(p: String, s: Dictionary, f: Dictionary, c: Array, n: Dictionary) -> void:
		path = p; settings = s; contents = f; order = c; counts = n
	func store_string(encoded: String) -> bool:
		order.append("store")
		var data: PackedByteArray = encoded.to_utf8_buffer()
		var stored: bool = settings.get("stored",true)
		contents[path] = data if stored else data.slice(0,7)
		return stored
	func flush() -> void: order.append("flush"); flushed = true
	func get_error() -> Error:
		order.append("get_error")
		var error: Error = settings.get("flush_error",settings.get("write_error",OK)) if flushed else settings.get("write_error",OK)
		counts.error_reads.append({"after_flush":flushed,"error":error})
		return error
	func close() -> void: order.append("close"); counts.closed += 1
class ReadHandle:
	extends RefCounted
	var path: String
	var settings: Dictionary
	var contents: Dictionary
	var order: Array
	var counts: Dictionary
	func _init(p: String, s: Dictionary, f: Dictionary, c: Array, n: Dictionary) -> void:
		path = p; settings = s; contents = f; order = c; counts = n
	func get_length() -> int: return contents[path].size()
	func get_buffer(length: int) -> PackedByteArray:
		order.append("read_buffer")
		var data: PackedByteArray = contents[path].slice(0,length)
		if settings.get("readback_corrupt",false) and not data.is_empty(): data[0] = data[0] ^ 1
		return data
	func get_error() -> Error: return settings.get("read_error",OK)
	func close() -> void: order.append("read_close"); counts.read_closed += 1
static func reset(settings: Dictionary, destination: String, original: PackedByteArray) -> void:
	options = settings.duplicate(true)
	files = {destination:original.duplicate(),destination+".tmp":"PREEXISTING_TEST_TMP".to_utf8_buffer()}
	directories = {}; calls = []; staging_calls = []; created = []; attempted = []; serial = 0
	counters = {"opened":0,"closed":0,"read_opened":0,"read_closed":0,"renames":0,"error_reads":[]}
static func nonce() -> PackedByteArray:
	staging_calls.append("nonce")
	if options.get("nonce_queue",[]).size() > 0: return options.nonce_queue.pop_front()
	serial += 1
	var bytes := PackedByteArray(); bytes.resize(32); bytes.fill(serial)
	return bytes
static func make_directory(path: String) -> Error:
	staging_calls.append({"mkdir":path}); attempted.append(path)
	if directories.has(path) or files.has(path): return ERR_ALREADY_EXISTS
	if options.get("mkdir_failed",false): return ERR_CANT_CREATE
	directories[path] = true; created.append(path)
	return OK
static func open(path: String, mode: int) -> RefCounted:
	calls.append("open")
	if mode != WRITE or options.get("open_failed",false): return null
	counters.opened += 1; files[path] = PackedByteArray()
	return WriteHandle.new(path,options,files,calls,counters)
static func readback(path: String) -> RefCounted:
	staging_calls.append({"read_open":path})
	if options.get("read_open_failed",false) or not files.has(path): return null
	counters.read_opened += 1
	return ReadHandle.new(path,options,files,staging_calls,counters)
static func rename_absolute(temporary: String, destination: String) -> Error:
	calls.append("rename"); counters.renames += 1
	var hook: Callable = options.get("before_rename",Callable())
	if hook.is_valid():
		options.erase("before_rename"); hook.call()
	var error: Error = options.get("rename_error",OK)
	if error != OK:
		if options.get("drop_destination_on_rename_failure",false): files.erase(destination)
		return error
	if not files.has(temporary): return ERR_FILE_NOT_FOUND
	files[destination] = files[temporary].duplicate(); files.erase(temporary)
	return OK
static func remove_fixed(path: String) -> Error:
	staging_calls.append({"remove":path})
	if files.has(path):
		if options.get("payload_remove_failed",false): return ERR_CANT_CREATE
		files.erase(path); return OK
	if directories.has(path):
		if options.get("directory_remove_failed",false): return ERR_CANT_CREATE
		# Models native rmdir nonempty refusal; this is a memory model, not a disk scan.
		for file_path in files:
			if String(file_path).begins_with(path+"/"): return ERR_CANT_CREATE
		directories.erase(path); return OK
	return ERR_DOES_NOT_EXIST
