extends RefCounted
## File transport only. It does not evaluate actions or manufacture GM replies.

func write_json(path: String, payload: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["Cannot write JSON: " + error_string(FileAccess.get_open_error())]}
	file.store_string(JSON.stringify(payload, "\t", true, true))
	file.close()
	return {"ok": true, "path": path}

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": ["JSON file does not exist: " + path]}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		return {"ok": false, "errors": ["Invalid JSON object at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]}
	return {"ok": true, "data": parser.data}
