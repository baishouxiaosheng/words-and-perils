extends RefCounted
## JSON-safe canonical bytes are independent of dictionary insertion order.
const LIMIT := 9007199254740991
const MAX_DEPTH := 64

static func safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH: return false
	if value == null or value is bool or value is String or value is StringName: return true
	if value is int: return value >= -LIMIT and value <= LIMIT
	if value is float: return is_finite(value) and absf(value) <= LIMIT
	if value is Array:
		for item in value:
			if not safe(item, depth + 1): return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not safe(value[key], depth + 1): return false
		return true
	return false

static func normalized(value: Variant, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH: return null
	if value is StringName: return String(value)
	if value is float and is_finite(value) and value == floorf(value) and absf(value) <= LIMIT: return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys(); keys.sort()
		for key in keys: result[String(key)] = normalized(value[key], depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(normalized(item, depth + 1))
		return result
	return value

static func bytes(value: Variant) -> String: return JSON.stringify(normalized(value), "", true, true) if safe(value) else ""
static func digest(value: Variant) -> String: return bytes(value).sha256_text() if safe(value) else ""
static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= LIMIT and float(value) == floorf(float(value))

static func exact_fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key in fields: return false
	for key in fields:
		if not value.has(key): return false
	return true

static func pointer(value: Dictionary, path: String) -> Dictionary:
	if not path.begins_with("/"): return {"ok": false}
	var current: Variant = value
	for token in path.substr(1).split("/"):
		var key: String = token.replace("~1", "/").replace("~0", "~")
		if not current is Dictionary or not current.has(key): return {"ok": false}
		current = current[key]
	return {"ok": true, "value": current}

static func int64_string(value: Variant) -> bool:
	if not value is String or value.is_empty(): return false
	var start := 1 if value.begins_with("-") else 0
	if start == value.length(): return false
	for character in value.substr(start):
		if not character in "0123456789": return false
	return str(int(value)) == value

static func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "errors": [message]}
