extends "res://core/ai_gm_http/client.gd"
signal connection_changed
## Two independent memory-only role configurations; one existing serial HTTP owner.
## No persistent credentials, provider inference, automatic test call or retry.
const ROLES := ["narration", "decision"]
const Presets = preload("res://view/dual_api_settings/provider_presets.gd")
const ValidationClient = preload("res://core/ai_gm_http/client.gd")
var _roles: Dictionary = {}
var _selected_role := "decision"
var _role_status: Dictionary = {}

static func role_for_phase(phase: String) -> String:
	return "narration" if phase == "narration" else "decision"

func role_configured(role: String) -> bool:
	return role in ROLES and _roles.has(role) and not String(_roles[role].key).is_empty()

func role_configuration(role: String) -> Dictionary:
	return _roles[role].config.duplicate(true) if role_configured(role) else {}

func role_status(role: String) -> String:
	return String(_role_status.get(role, "已配置 · 尚未联网验证" if role_configured(role) else "未配置 · 使用离线路径"))

func any_role_configured() -> bool:
	return role_configured("narration") or role_configured("decision")

func contains_current_credential(text: String) -> bool:
	for role in _roles:
		if not String(_roles[role].key).is_empty() and text.contains(String(_roles[role].key)): return true
	return super.contains_current_credential(text)

func configure(config: Dictionary, api_key: String) -> Dictionary:
	# Compatibility migration of the previous one-config public API. The exact
	# supplied configuration and key are retained for each independently editable role.
	var revision := _configuration_revision
	var result: Dictionary = configure_roles({"narration": {"config": config, "key": api_key}, "decision": {"config": config, "key": api_key}})
	# Legacy callers use an explicit re-apply to retire consent/tickets, even if
	# the bytes are unchanged; ordinary modal no-op saves remain non-destructive.
	if result.get("ok", false) and _configuration_revision == revision: connection_changed.emit()
	return result

func configure_roles(edits: Dictionary) -> Dictionary:
	if busy() or _transitioning: return C.fail("BUSY", "请先取消当前请求，再保存API设置；现有配置保留。")
	for role in edits:
		if role not in ROLES: return C.fail("INVALID_ROLE", "无法识别此API用途；现有配置保留。")
	var candidate: Dictionary = _roles.duplicate(true)
	# Admit a legacy configuration already present in this same client instance,
	# without exposing its credential through a getter, UI, file or diagnostic.
	if candidate.is_empty() and not _config.is_empty() and not _api_key.is_empty():
		for role in ROLES: candidate[role] = {"config": _config.duplicate(true), "key": _api_key}
	for role in ROLES:
		if not edits.has(role): continue
		var edit: Variant = edits[role]
		if not edit is Dictionary or not edit.get("config", {}) is Dictionary or not edit.get("key", "") is String:
			return C.fail("INVALID_CONFIG", "API设置格式无效；两项原配置均保留。")
		var old: Dictionary = candidate.get(role, {})
		var config: Dictionary = edit.get("config", {}).duplicate(true)
		var key: String = edit.get("key", "")
		var supplied_key: bool = not key.is_empty()
		if key.is_empty(): key = String(old.get("key", ""))
		# Bearer tokens must be safe header/text atoms; unsupported control or JSON
		# escape characters are rejected before any public encoding.
		for ch in key:
			if ch.unicode_at(0) < 33 or ch.unicode_at(0) > 126 or ch in ["\\", "\""]:
				return C.fail("INVALID_KEY", "API密钥包含不支持的空白、控制或转义字符；原配置保留。")
		if config.is_empty() and not old.is_empty(): config = old.config.duplicate(true)
		if config.is_empty() and key.is_empty(): continue
		if String(config.get("endpoint", "")).strip_edges().is_empty() and String(config.get("model", "")).strip_edges().is_empty() and key.is_empty() and old.is_empty(): continue
		if config.get("provider", "openai_compatible_json") != "openai_compatible_json":
			return C.fail("UNSUPPORTED_PROVIDER", "当前仅支持Chat Completions JSON兼容接口；两项原配置均保留。")
		for field in ["model", "reasoning_effort"]:
			if not config.get(field, "") is String: return C.fail("INVALID_CONFIG", "模型设置须为文字；原配置保留。")
			for invalid in ["\n", "\r", "\t"]:
				if String(config.get(field, "")).contains(invalid): return C.fail("INVALID_CONFIG", "模型设置不能包含控制字符；原配置保留。")
		var validator = ValidationClient.new()
		var checked: Dictionary = validator.configure(config, key)
		var normalized: Dictionary = validator.public_configuration() if checked.get("ok", false) else {}
		validator.free()
		if not checked.get("ok", false): return checked
		# Blank keeps a key only for the same validated full endpoint. A provider/region
		# change cannot silently carry a retained secret to a different endpoint.
		if not old.is_empty() and not supplied_key and Presets.endpoint_binding(String(normalized.endpoint))!=Presets.endpoint_binding(String(old.config.get("endpoint",""))):
			return C.fail("NEW_ENDPOINT_REQUIRES_KEY", "服务地址或区域已更换，请重新输入该用途的密钥；两项原配置均保留，未发送请求。")
		if config.has("service_preset"):
			var preset: Variant=config.get("service_preset")
			if not preset is String or preset not in Presets.IDS:
				return C.fail("INVALID_PRESET", "服务商选项无效；两项原配置均保留。")
			var json_mode: Variant=config.get("json_object_mode",false)
			var token_field: Variant=config.get("token_parameter",Presets.token_parameter(preset))
			if not json_mode is bool or not token_field is String or token_field not in ["max_tokens","max_completion_tokens"]:
				return C.fail("INVALID_PRESET", "服务商或兼容参数无效；两项原配置均保留。")
			if preset!="custom" and Presets.endpoint_binding(normalized.endpoint)!=Presets.endpoint_binding(Presets.ENDPOINTS[preset]):
				return C.fail("PRESET_ENDPOINT_MISMATCH", "地址与所选服务商或区域不一致；中转地址请选自定义，原配置保留。")
			if preset!="custom" and token_field!=Presets.token_parameter(preset):
				return C.fail("INVALID_PRESET", "此服务商的输出上限参数不匹配；原配置保留。")
			normalized["service_preset"]=preset
			normalized["json_object_mode"]=json_mode
			normalized["token_parameter"]=token_field
		normalized["provider"] = "openai_compatible_json"
		candidate[role] = {"config": normalized, "key": key}
	# Neither role's secret can be placed in either public configuration.
	# Also validate the untouched roles admitted by the legacy fallback.
	for role in candidate:
		for ch in String(candidate[role].key):
			if ch.unicode_at(0) < 33 or ch.unicode_at(0) > 126 or ch in ["\\", "\""]:
				return C.fail("INVALID_KEY", "旧密钥含不支持的字符；未迁移、未清除原值，请在本地更换。")
	var protected_keys: Array = []
	for entries in [_roles, candidate]:
		for role in entries: protected_keys.append(String(entries[role].key))
	if not _api_key.is_empty(): protected_keys.append(_api_key)
	for role in candidate:
		for protected_key in protected_keys:
			if not protected_key.is_empty() and C.bytes(candidate[role].config).contains(protected_key):
				return C.fail("SENSITIVE_CONFIG", "密钥只能填写独立密钥框，不能放入任一接口地址或模型字段；原配置保留。")
	if candidate == _roles: return {"ok": true, "message": "设置未改变；空白密钥保留原值。未联网。"}
	_roles = candidate
	_configuration_revision += 1
	for role in ROLES: _role_status.erase(role)
	_activate(_selected_role)
	connection_changed.emit()
	return {"ok": true, "message": "已保存到本次运行内存；关闭游戏后需重输。未联网验证，空白密钥保留原值。"}

func _activate(role: String) -> void:
	_selected_role = role
	_config = role_configuration(role)
	_api_key = String(_roles[role].key) if role_configured(role) else ""

func select_phase(phase: String) -> Dictionary:
	if phase not in ["narration", "assessment", "intention"]: return C.fail("INVALID_PHASE", "未知请求用途。")
	var role := role_for_phase(phase)
	if busy(): return C.fail("BUSY", "当前请求尚未结束，未切换API用途。")
	if _selected_role != role:
		_activate(role); _configuration_revision += 1
	if not role_configured(role): return C.fail("NOT_CONFIGURED", ("叙事API" if role == "narration" else "快速决策模型API") + "尚未配置；未发送请求。")
	return {"ok": true}

func _begin(engine: RefCounted, action_id: String, phase: String, trusted_instructions: String) -> Dictionary:
	var selected: Dictionary = select_phase(phase)
	if not selected.ok: return selected
	if _transitioning: return C.fail("CONTEXT_CHANGING", "正在清除连接或切换上下文，未发送请求。")
	if busy(): return C.fail("BUSY", "正在等待本次API响应，请勿重复提交。")
	if not configured(): return C.fail("NOT_CONFIGURED", "未配置API；请设置连接，或继续人工JSON/署名样例。")
	if not is_inside_tree() or _timer == null or not is_instance_valid(_transport): return C.fail("NOT_READY", "请先把AI客户端加入场景。")
	if engine == null or not engine.has_method("model_request") or not engine.has_method("narration_request"): return C.fail("INVALID_ENGINE", "需要冻结AI-GM engine。")
	if phase == "assessment" and engine.action_copy(action_id).get("status") != "awaiting_assessment": return C.fail("INVALID_PHASE", "只有等待评估的当前意图可以请求AI；已锁定结果不能重评或重骰。")
	var request: Dictionary = engine.model_request(action_id) if phase == "assessment" else engine.narration_request(action_id)
	if request.is_empty() or request.get("schema_version") != "ai_gm_rebuilt/v1" or request.get("phase") != phase: return C.fail("NO_REQUEST", "没有可发送的公开ModelView请求。")
	if contains_current_credential(C.bytes(request)) or contains_current_credential(trusted_instructions):
		return C.fail("SENSITIVE_REQUEST", "公开请求含会话密钥，未发送。")
	var public_bytes := C.bytes(request).to_utf8_buffer().size()
	var public_cap: int = _config.public_request_budget_bytes
	if public_bytes > public_cap: return Budget.exceeded(public_bytes, public_cap)
	var info: Dictionary = _transport.info()
	var provenance := {"provider": info.id, "live": info.live, "kind": "model_reply"}
	var body := C.bytes(Presets.encode(request, _config, provenance, trusted_instructions))
	if contains_current_credential(body): return C.fail("SENSITIVE_REQUEST", "公开请求中含有密钥内容，已阻止发送。请从意图或上下文中移除凭据。")
	if body.to_utf8_buffer().size() > 4194304: return C.fail("REQUEST_TOO_LARGE", "公开请求超过4 MiB，未发送；请缩小公开上下文。")
	_sequence += 1
	var token := _sequence
	_active = {"request_id": token, "engine": engine, "request": request, "request_hash": C.digest(request), "phase": phase, "action_id": action_id, "provenance": provenance, "world_version": engine.state_copy().state_version, "request_bytes": body.to_utf8_buffer().size(), "public_request_bytes":public_bytes, "public_request_budget_bytes":public_cap}
	busy_changed.emit(true)
	if not busy() or _active.request_id != token: return C.fail("CANCELLED", "发送前已取消请求；未发送网络数据。")
	var timeout_seconds: float = _config.timeout_seconds
	var request_bytes := body.to_utf8_buffer().size()
	_timer.start(timeout_seconds)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _api_key])
	var error: Error = _transport.send(token, _config.endpoint, headers, body, timeout_seconds)
	if error != OK:
		if busy() and _active.request_id == token: _finish_error("REQUEST_START_FAILED", "API请求无法启动；未自动重试，请检查连接设置。")
		return C.fail("REQUEST_START_FAILED", "API请求无法启动；未自动重试。")
	return {"ok": true, "request_id": token, "request_bytes": request_bytes, "timeout_seconds": timeout_seconds}

func _on_transport_completed(token: int, status: int, body: String, error_code: String) -> void:
	if not busy() or token != _active.request_id or _active.get("cancelled", false): return
	# Scan both credentials, including JSON-escaped reflection, before inherited
	# decode/engine/history/UI handling. Never put the raw provider body in errors.
	var sensitive := contains_current_credential(body)
	if not sensitive and status >= 200 and status < 300 and error_code.is_empty():
		var decoded: Dictionary = Codec.decode(body)
		sensitive = decoded.get("ok", false) and contains_current_credential(C.bytes(decoded.get("reply", {})))
	if sensitive:
		_finish_error("SENSITIVE_RESPONSE", "响应包含API凭据，已丢弃且未显示、保存或应用。")
		return
	super._on_transport_completed(token, status, body, error_code)

func _finish(result: Dictionary) -> void:
	if busy():
		var role := role_for_phase(String(_active.phase))
		_role_status[role] = ("真实响应已校验" if _active.provenance.live else "离线mock响应已校验（非联网）") if result.get("ok", false) else "最近请求失败 · 请查看连接状态"
	super._finish(result)

func set_transport(custom: Node) -> Dictionary:
	var previous: Node = _transport
	var result: Dictionary = super.set_transport(custom)
	if result.get("ok", false) and previous != _transport: connection_changed.emit()
	return result

func clear_configuration() -> void:
	super.clear_configuration()
	_roles.clear(); _role_status.clear()
	connection_changed.emit()

func _exit_tree() -> void:
	super._exit_tree()
	_roles.clear(); _role_status.clear()
