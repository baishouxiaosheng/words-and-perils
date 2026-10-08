extends RefCounted
## Test-only deterministic in-memory backend; no real disk fault injection.
const WRITE := 2
static var options: Dictionary = {}
static var files: Dictionary = {}
static var calls: Array = []
static var counters: Dictionary = {}
class Handle:
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
		var bytes := encoded.to_utf8_buffer()
		var stored: bool = settings.get("stored",true)
		contents[path] = bytes if stored else bytes.slice(0,7)
		return stored
	func flush() -> void:
		order.append("flush"); flushed = true
	func get_error() -> Error:
		order.append("get_error")
		var error: Error = settings.get("flush_error",settings.get("write_error",OK)) if flushed else settings.get("write_error",OK)
		counts.error_reads.append({"after_flush":flushed,"error":error})
		return error
	func close() -> void:
		order.append("close"); counts.closed += 1
static func reset(s: Dictionary, destination: String, original: PackedByteArray) -> void:
	options = s.duplicate(true)
	files = {destination:original.duplicate(),destination+".tmp":"PREEXISTING_TEST_TMP".to_utf8_buffer()}
	calls = []
	counters = {"opened":0,"closed":0,"renames":0,"error_reads":[]}
static func open(path: String, mode: int) -> RefCounted:
	calls.append("open")
	if mode != WRITE or options.get("open_failed",false): return null
	counters.opened += 1
	files[path] = PackedByteArray()
	return Handle.new(path,options,files,calls,counters)
static func rename_absolute(temporary: String, destination: String) -> Error:
	calls.append("rename"); counters.renames += 1
	files[destination] = files[temporary].duplicate(); files.erase(temporary)
	return OK

