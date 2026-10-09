extends "res://core/gm_provider.gd"
## Genuine offline relay: export complete context, import an external model reply.
## Never pretends to be connected to a live model or generates gameplay locally.

const Transport = preload("res://core/json_file_transport.gd")
var transport: RefCounted

func _init(custom_transport: RefCounted = null) -> void:
	transport = custom_transport if custom_transport != null else Transport.new()

func provider_info() -> Dictionary:
	return {"id": "external_json_relay", "label": "离线 JSON 模型中继 · 等待外部 GM", "live": false, "description": "导出完整请求给外部模型，再导入它的 JSON 决定。当前没有连接模型 API。"}

func request_decision(request: Dictionary) -> Dictionary:
	return {"ok": true, "status": "awaiting_external_gm", "request": request.duplicate(true), "provider": provider_info()}

func export_request(request: Dictionary, path: String) -> Dictionary:
	return transport.write_json(path, request)

func import_decision(path: String) -> Dictionary:
	var result: Dictionary = transport.read_json(path)
	if not result.ok:
		return result
	var decision: Dictionary = result.data
	if decision.get("recorded_example", false):
		return {"ok": false, "errors": ["Recorded examples require an explicit matching action via recorded_example_for()."]}
	return {"ok": true, "decision": decision}

func recorded_example_for(request: Dictionary, path: String) -> Dictionary:
	var result: Dictionary = transport.read_json(path)
	if not result.ok:
		return result
	var example: Dictionary = result.data
	if not example.get("recorded_example", false) or not example.get("decision") is Dictionary:
		return {"ok": false, "errors": ["This file is not a labelled recorded GM example."]}
	if not example.get("expected_snapshot") is Dictionary:
		return {"ok": false, "errors": ["Recorded examples must include the exact expected_snapshot."]}
	if example.get("phase") != request.get("phase") or not example.get("goal") is String or example.goal != request.get("goal"):
		return {"ok": false, "errors": ["Recorded example does not match this goal and phase. Use the external relay."]}
	if example.get("expected_state_version") != request.get("state_version"):
		return {"ok": false, "errors": ["Recorded example state version does not match."]}
	if _normalized_json(example.get("expected_target_hex")) != _normalized_json(request.get("target_hex")):
		return {"ok": false, "errors": ["Recorded example target hex does not match."]}
	if example.has("expected_roll"):
		var player_roll = request.get("context", {}).get("player_roll")
		if not player_roll is Dictionary or example.expected_roll != player_roll.get("value"):
			return {"ok": false, "errors": ["Recorded resolution only matches its recorded player roll. Use the external relay for this roll."]}
	var expected: Dictionary = example.expected_snapshot.duplicate(true)
	var actual: Dictionary = request.get("snapshot", {}).duplicate(true)
	# A new session may have a different world ID, but all game facts must match.
	expected.erase("world_id")
	actual.erase("world_id")
	if _normalized_json(expected) != _normalized_json(actual):
		return {"ok": false, "errors": ["Recorded example does not match the exact numerical world snapshot."]}
	var decision: Dictionary = example.decision.duplicate(true)
	decision.action_id = request.action_id
	decision.state_version = request.state_version
	decision.schema_version = request.schema_version
	decision.phase = request.phase
	decision["provenance"] = {"provider": "recorded_external_gm_example", "live": false, "label": example.get("label", "预先录制的模型 GM 决定"), "source": example.get("source", "Recorded during prototype authoring")}
	return {"ok": true, "decision": decision, "recorded_example": true, "label": decision.provenance.label}

func _normalized_json(value: Variant) -> Variant:
	# JSON.parse represents numbers as doubles; world state restores whole values
	# to ints. Compare facts with normalized types, never by lossy string coercion.
	if value is StringName:
		return String(value)
	if value is float and is_finite(value) and absf(value) <= 9007199254740991 and value == floorf(value):
		return int(value)
	if value is Dictionary:
		var result := {}
		for key in value:
			result[String(key)] = _normalized_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_normalized_json(entry))
		return result
	return value
