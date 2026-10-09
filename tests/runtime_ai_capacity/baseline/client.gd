extends Node
## Explicit-click client for the frozen engine. Never rolls, stages or commits.
## Secret exists only in memory. No FileAccess, exported secret, or save integration.
signal completed(result: Dictionary)
signal assessment_ready(action_id: String, reply: Dictionary)
signal narration_ready(action_id: String, text: String)
signal busy_changed(value: bool)
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Codec = preload("res://core/ai_gm_http/openai_chat_codec.gd")
const HttpTransport = preload("res://core/ai_gm_http/http_transport.gd")
var _config: Dictionary = {}
var _api_key := ""
var _transport: Node
var _active: Dictionary = {}
var _sequence := 0
var _timer: Timer
var _transitioning := false

func _ready() -> void:
	_timer = Timer.new(); _timer.one_shot = true; add_child(_timer)
	_timer.timeout.connect(_on_timeout)
	if _transport == null: set_transport(HttpTransport.new())

func contains_current_credential(text: String) -> bool: return not _api_key.is_empty() and text.contains(_api_key)
func busy() -> bool: return not _active.is_empty()
func public_configuration() -> Dictionary: return _config.duplicate(true)
func request_summary() -> Dictionary:
	if not busy(): return {}
	return {"request_id": _active.request_id, "phase": _active.phase, "action_id": _active.action_id, "request_bytes": _active.request_bytes, "timeout_seconds": _config.timeout_seconds, "transport_live": _active.provenance.live}
func configured() -> bool: return not _config.is_empty() and not _api_key.is_empty()
func provider_info() -> Dictionary:
	var live := false
	if is_instance_valid(_transport): live = bool(_transport.info().get("live", false))
	return {"id": "openai_compatible_json", "configured": configured(), "live": live and configured(), "label": "API已配置，尚未验证服务可用" if configured() else "未配置API · 人工JSON仍可用"}

func configure(config: Dictionary, api_key: String) -> Dictionary:
	if busy(): return C.fail("BUSY", "请先取消当前API请求，再修改连接设置。")
	var endpoint: Variant = config.get("endpoint", "")
	var model: Variant = config.get("model", "")
	var effort: Variant = config.get("reasoning_effort", "")
	var localhost: Variant = config.get("allow_localhost_http", false)
	var timeout: Variant = config.get("timeout_seconds", 30.0)
	var output_tokens: Variant = config.get("max_completion_tokens", 2048)
	if not C.integer(output_tokens) or output_tokens < 128 or output_tokens > 4096: return C.fail("INVALID_CONFIG", "输出token上限应为128至4096之间的整数。")
	if not endpoint is String or not model is String or not effort is String or not localhost is bool or not (timeout is float or timeout is int) or not is_finite(float(timeout)): return C.fail("INVALID_CONFIG", "连接设置的字段类型不正确。")
	endpoint = endpoint.strip_edges(); model = model.strip_edges(); effort = effort.strip_edges()
	if endpoint.is_empty() or model.is_empty() or api_key.strip_edges().is_empty(): return C.fail("NOT_CONFIGURED", "请填写完整API地址、提供商实际model ID，并仅在此本地面板输入API密钥。")
	if api_key.contains("\n") or api_key.contains("\r") or api_key.contains("\t") or api_key.contains(" "): return C.fail("INVALID_KEY", "密钥不能包含空白或换行；请重新检查输入。")
	if model.length() > 200 or effort.length() > 40 or model.contains("\n") or effort.contains("\n"): return C.fail("INVALID_CONFIG", "model ID或reasoning配置格式不正确。")
	if endpoint.contains(api_key) or model.contains(api_key) or effort.contains(api_key): return C.fail("SENSITIVE_CONFIG", "密钥不能放在地址、model或reasoning字段；请只填写独立密钥框。")
	var checked := _validate_endpoint(endpoint, localhost)
	if not checked.ok: return checked
	_config = {"endpoint": endpoint, "model": model, "reasoning_effort": effort, "timeout_seconds": clampf(float(timeout), 1.0, 120.0), "allow_localhost_http": localhost, "max_completion_tokens": int(output_tokens)}
	_api_key = api_key
	return {"ok": true, "message": "已保留在本次运行内存中；未联网验证，未保存密钥。"}

static func _validate_endpoint(endpoint: String, allow_localhost: bool) -> Dictionary:
	if endpoint.contains("?") or endpoint.contains("#") or endpoint.contains("@") or endpoint.contains("\\") or endpoint.contains("%") or endpoint.contains("\n") or endpoint.contains("\r") or endpoint.contains(" ") or endpoint.contains("\t"): return C.fail("INVALID_ENDPOINT", "地址不得含账号、查询参数、片段或转义字符；密钥仅用Authorization发送。")
	var regex := RegEx.new()
	regex.compile("^(https?)://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[^\\s]*)$")
	var matched := regex.search(endpoint)
	if matched == null: return C.fail("INVALID_ENDPOINT", "请填写提供商完整的HTTPS Chat Completions请求地址，包含路径。")
	var scheme := matched.get_string(1); var host := matched.get_string(2).to_lower()
	var port := matched.get_string(3)
	if not port.is_empty() and (int(port.substr(1)) < 1 or int(port.substr(1)) > 65535): return C.fail("INVALID_ENDPOINT", "端口应在1至65535之间。")
	if scheme != "https" and not (allow_localhost and host in ["localhost", "127.0.0.1", "[::1]"]): return C.fail("HTTPS_REQUIRED", "API必须使用HTTPS；仅勾选开发选项后允许localhost/127.0.0.1/[::1]的HTTP。")
	return {"ok": true}

func clear_configuration() -> void:
	_transitioning = true
	cancel(); _api_key = ""; _config.clear()
	_transitioning = false

func set_transport(custom: Node) -> Dictionary:
	if busy(): return C.fail("BUSY", "有请求进行中，不能替换transport。")
	if custom == _transport and is_instance_valid(custom): return {"ok": true}
	if custom == null or not custom.has_signal("completed") or not custom.has_method("send") or not custom.has_method("cancel") or not custom.has_method("info"): return C.fail("INVALID_TRANSPORT", "Transport必须实现send/cancel/info及completed信号。")
	var information: Variant = custom.info()
	if not information is Dictionary or not information.get("id") is String or not information.get("live") is bool: return C.fail("INVALID_TRANSPORT", "Transport必须明确标注来源与是否真实联网。")
	if is_instance_valid(_transport):
		if _transport.completed.is_connected(_on_transport_completed): _transport.completed.disconnect(_on_transport_completed)
		if _transport.get_parent() == self: remove_child(_transport); _transport.queue_free()
	_transport = custom
	if _transport.get_parent() == null: add_child(_transport)
	_transport.completed.connect(_on_transport_completed)
	return {"ok": true}

func request_assessment(engine: RefCounted, action_id: String, trusted_instructions: String = "") -> Dictionary:
	return _begin(engine, action_id, "assessment", trusted_instructions)
func request_narration(engine: RefCounted, action_id: String, trusted_instructions: String = "") -> Dictionary:
	return _begin(engine, action_id, "narration", trusted_instructions)

func _begin(engine: RefCounted, action_id: String, phase: String, trusted_instructions: String) -> Dictionary:
	if _transitioning: return C.fail("CONTEXT_CHANGING", "正在清除连接或切换上下文，未发送请求。")
	if busy(): return C.fail("BUSY", "正在等待本次API响应，请勿重复提交。")
	if not configured(): return C.fail("NOT_CONFIGURED", "未配置API；请设置连接，或继续人工JSON/署名样例。")
	if not is_inside_tree() or _timer == null or not is_instance_valid(_transport): return C.fail("NOT_READY", "请先把AI客户端加入场景。")
	if engine == null or not engine.has_method("model_request") or not engine.has_method("narration_request"): return C.fail("INVALID_ENGINE", "需要冻结AI-GM engine。")
	if phase == "assessment" and engine.action_copy(action_id).get("status") != "awaiting_assessment": return C.fail("INVALID_PHASE", "只有等待评估的当前意图可以请求AI；已锁定结果不能重评或重骰。")
	var request: Dictionary = engine.model_request(action_id) if phase == "assessment" else engine.narration_request(action_id)
	if request.is_empty() or request.get("schema_version") != "ai_gm_rebuilt/v1" or request.get("phase") != phase: return C.fail("NO_REQUEST", "没有可发送的公开ModelView请求。")
	var info: Dictionary = _transport.info()
	var provenance := {"provider": info.id, "live": info.live, "kind": "model_reply"}
	var body := C.bytes(Codec.encode(request, _config, provenance, trusted_instructions))
	if body.contains(_api_key): return C.fail("SENSITIVE_REQUEST", "公开请求中含有密钥内容，已阻止发送。请从意图或上下文中移除凭据。")
	if body.to_utf8_buffer().size() > 4194304: return C.fail("REQUEST_TOO_LARGE", "公开请求超过4 MiB，未发送；请缩小公开上下文。")
	_sequence += 1
	var token := _sequence
	_active = {"request_id": token, "engine": engine, "request": request, "request_hash": C.digest(request), "phase": phase, "action_id": action_id, "provenance": provenance, "world_version": engine.state_copy().state_version, "request_bytes": body.to_utf8_buffer().size()}
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

func cancel() -> Dictionary:
	if not busy(): return {"ok": true, "cancelled": false}
	var token: int = _active.request_id
	_active["cancelled"] = true
	_transport.cancel(token)
	_finish_error("CANCELLED", "已取消等待；不自动重试。服务端可能仍会处理并计费；游戏事实未因取消改变。")
	return {"ok": true, "cancelled": true}
func invalidate_context() -> void:
	_transitioning = true
	cancel(); _sequence += 1
	_transitioning = false

func _on_timeout() -> void:
	if not busy(): return
	_active["cancelled"] = true
	_transport.cancel(_active.request_id)
	_finish_error("TIMEOUT", "API等待超时；不自动重试。服务端可能仍会计费。已确定的数值结果保留。")

func _on_transport_completed(token: int, status: int, body: String, error_code: String) -> void:
	if not busy() or token != _active.request_id or _active.get("cancelled", false): return # Cancelled, duplicate or out-of-order response.
	if not error_code.is_empty():
		_finish_error(error_code if error_code in ["TIMEOUT", "RESPONSE_TOO_LARGE"] else "NETWORK_ERROR", "网络请求失败；没有自动重试。请检查连接，已确定的数值结果保留。")
		return
	if status < 200 or status >= 300:
		var message := "API返回HTTP %d；请检查服务配置。未显示服务端原文，以免泄露密钥。" % status
		if status in [401, 403]: message = "API认证或权限失败（HTTP %d）；请在本地设置面板检查密钥与模型权限。" % status
		elif status == 429: message = "API额度或限流（HTTP 429）；没有自动重试，请稍后手动尝试。"
		elif status >= 300 and status < 400: message = "API要求跳转，已拒绝转发Authorization。请核对并配置最终HTTPS地址。"
		var failure := C.fail("HTTP_ERROR", message)
		failure["http_status"] = status
		_finish(failure); return
	# Some servers reflect credentials in their body. Never store or display it.
	if not _api_key.is_empty() and body.contains(_api_key):
		_finish_error("SENSITIVE_RESPONSE", "API响应包含凭据内容，已整体丢弃；没有显示、保存或应用。")
		return
	var decoded := Codec.decode(body)
	if not decoded.ok: _finish(decoded); return
	if C.bytes(decoded.reply).contains(_api_key):
		_finish_error("SENSITIVE_RESPONSE", "模型JSON解码后包含凭据内容，已整体丢弃；没有显示、保存或应用。")
		return
	var engine: RefCounted = _active.engine
	var action_id: String = _active.action_id
	var phase: String = _active.phase
	var current: Dictionary = engine.model_request(action_id) if phase == "assessment" else engine.narration_request(action_id)
	if current.is_empty() or C.digest(current) != _active.request_hash or engine.state_copy().state_version != _active.world_version or (phase == "assessment" and engine.action_copy(action_id).get("status") != "awaiting_assessment"):
		_finish_error("STALE_CONTEXT", "响应对应的行动或公开状态已过期，已拒绝；请使用当前请求。")
		return
	var reply: Dictionary = decoded.reply
	var request: Dictionary = _active.request
	if reply.get("action_id") != action_id or reply.get("state_version") != request.state_version or reply.get("context_hash") != request.context_hash:
		_finish_error("STALE_CONTEXT", "模型响应没有精确匹配当前action_id/state_version/context_hash，未应用。")
		return
	if phase == "assessment" and C.bytes(reply.get("provenance")) != C.bytes(_active.provenance):
		_finish_error("INVALID_PROVENANCE", "模型来源声明不匹配实际transport，未应用。")
		return
	# Raw structured reply enters the existing strict engine; no repair or patching.
	var checked: Dictionary = engine.prepare_assessment(reply) if phase == "assessment" else engine.validate_narration_reply(reply)
	if not checked.ok: _finish(checked); return
	var outcome := checked.duplicate(true)
	outcome["reply"] = reply.duplicate(true)
	_finish(outcome)
	if _sequence != token: return # A completed handler replaced/cancelled the displayed context.
	if phase == "assessment": assessment_ready.emit(action_id, reply)
	else: narration_ready.emit(action_id, String(checked.narration))

func _finish_error(code: String, message: String) -> void: _finish(C.fail(code, message))
func _finish(result: Dictionary) -> void:
	if not busy(): return
	var final := result.duplicate(true)
	final["phase"] = _active.phase; final["action_id"] = _active.action_id; final["request_id"] = _active.request_id
	final["transport"] = {"provider": _active.provenance.provider, "live": _active.provenance.live}
	_active.clear()
	if _timer != null: _timer.stop()
	busy_changed.emit(false)
	completed.emit(final)

func _exit_tree() -> void:
	_transitioning = true
	var token: int = _active.get("request_id", -1)
	_sequence += 1; _active.clear(); _api_key = ""
	if _timer != null: _timer.stop()
	if token >= 0 and is_instance_valid(_transport): _transport.cancel(token)
