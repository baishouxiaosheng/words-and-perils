extends Node
## Optional actual-game runtime. It requests/validates data; the main controller
## alone performs its existing single roll -> stage -> atomic commit journey.
signal assessment_validated(action_id: String)
signal narration_received(action_id: String, text: String)
signal request_finished(result: Dictionary)
signal status_changed(text: String)
signal changed
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Client = preload("res://core/ai_gm_http/client.gd")
const ScopedEngine = preload("res://view/runtime_ai/scoped_engine.gd")
const CONTRACT := "The installed request.contract.action_schemas are the only supported action contracts. Respect their exact bindings, required_fact_paths, component IDs and numeric bounds; compound actions may require multiple components. Never invent an action family, code, raw patch, tool call, parameter or source item. All facts and bounds must be in the transmitted public context. Required references must be exact complete values. Omitted map geometry remains authoritative in the local engine; ask for narrower input instead of guessing omitted facts. Selection is read-only attention, never authority: explicit objects and destinations in player text win over focus. Questions about feasibility are not execution orders. Use generic physical traits and installed relation mechanisms, never item-name scripts or invented properties. When a single installed contract cannot faithfully represent the entire intent, use negotiated control_reply with NEEDS_CLARIFICATION, INFEASIBLE, NO_SUPPORTED_MECHANISM or NEEDS_PUBLIC_CONTEXT; older requests use UNSUPPORTED_INTENT. No action is executed for feedback. For optional narration, use only the committed authoritative_result and historical public context; no later or provisional state."
var client: Node
var connection_enabled := false
var automatic_assessment := false
var automatic_narration := false
var _adapter: RefCounted
var _epoch := 0
var _operation: Dictionary = {}
var _scope: RefCounted
var _invalidating := false
var _consecutive_transient := 0
var _retry_after_ms := 0
var _last_committed_narration := ""
var _public_expansions: Dictionary = {}
var clock: Callable = func(): return Time.get_ticks_msec()
var last_metrics: Dictionary = {}
var last_result: Dictionary = {}

func _ready() -> void:
	client = Client.new(); add_child(client)
	client.completed.connect(_on_completed)
	client.assessment_ready.connect(_on_assessment)
	client.narration_ready.connect(_on_narration)
	client.busy_changed.connect(func(_value: bool): changed.emit())
func _process(_delta: float) -> void:
	# Refresh retry buttons at expiry without issuing any network request.
	if _retry_after_ms > 0 and int(clock.call()) >= _retry_after_ms:
		_retry_after_ms = 0; changed.emit()
func bind_adapter(adapter: RefCounted) -> void:
	invalidate_context(); _adapter = adapter; _last_committed_narration = ""; changed.emit()
func busy() -> bool: return not _operation.is_empty() or (is_instance_valid(client) and client.busy())
func automatic_assessment_enabled() -> bool: return connection_enabled and automatic_assessment and is_instance_valid(client) and client.configured()
func phase() -> String:
	if _adapter == null: return "idle"
	return "committed" if _adapter.phase() == "idle" and not _adapter.last_action.is_empty() else _adapter.phase()
func set_transport(transport: Node) -> Dictionary: return client.set_transport(transport)
func configure(config: Dictionary, credential: String) -> Dictionary: return client.configure(config, credential)
func cooldown_remaining() -> float: return maxf(0.0, float(_retry_after_ms - int(clock.call())) / 1000.0)
func request_assessment() -> Dictionary: return _begin("assessment")
func request_narration() -> Dictionary: return _begin("narration")
func narration_recorded() -> bool:
	return _adapter!=null and _adapter.has_method("has_recorded_narration") and _adapter.has_recorded_narration(_adapter.last_action)
func _begin(kind: String) -> Dictionary:
	if _invalidating or busy(): return _report(C.fail("BUSY", "当前请求尚未结束，未重复发送。"))
	if _adapter == null or not is_instance_valid(client): return _report(C.fail("NOT_READY", "当前冒险尚未就绪。"))
	if not client.configured(): return _report(C.fail("NOT_CONFIGURED", "离线等待裁定。可配置自己的API接口，或导入人工评估；未运行AI。"))
	if not connection_enabled: return _report(C.fail("CONSENT_REQUIRED", "请在连接面板核对当前设置及可能计费说明后应用；未发送请求。"))
	if cooldown_remaining() > 0.0: return _report(C.fail("BACKOFF", "上次临时故障后请等待%.1f秒再手动请求；没有自动重试。" % cooldown_remaining()))
	var id: String = _adapter.active_action if kind == "assessment" else _adapter.last_action
	if (kind == "assessment" and _adapter.phase() != "awaiting_assessment") or (kind == "narration" and (_adapter.phase() != "idle" or id.is_empty())):
		return _report(C.fail("INVALID_PHASE", "评估只接受未裁定意图；可选叙事只接受已提交结果。"))
	if kind=="narration" and narration_recorded():return _report(C.fail("ALREADY_RECORDED","本回合可选叙事已记入历史；没有重复发送或产生新的API请求。"))
	var generation := _epoch
	var source: RefCounted = _adapter.engine
	_scope = ScopedEngine.new(source, func(): return is_inside_tree() and not _invalidating and _epoch == generation and _adapter != null and _adapter.engine == source)
	_scope.expanded_paths = _public_expansions.get(id,[]).duplicate()
	var request: Dictionary = _scope.model_request(id) if kind == "assessment" else _scope.narration_request(id)
	last_metrics = _scope.last_metrics.duplicate(true)
	if request.is_empty(): return _report(_scope.last_error if not _scope.last_error.is_empty() else C.fail("NO_REQUEST", "没有当前可发送的公开请求。"))
	_operation = {"epoch":generation, "action_id":id, "phase":kind}
	changed.emit()
	status_changed.emit("正在等待AI评估；未结算回合。" if kind == "assessment" else "数值已提交；正在请求可选叙事。")
	var result: Dictionary = client.request_assessment(_scope, id, CONTRACT) if kind == "assessment" else client.request_narration(_scope, id, CONTRACT)
	if not result.ok and not _operation.is_empty(): _operation.clear(); _report(result)
	return result
func cancel() -> Dictionary:
	if not is_instance_valid(client): return {"ok":true, "cancelled":false}
	return client.cancel()
func invalidate_context() -> void:
	_invalidating = true; _epoch += 1; _operation.clear(); _scope = null; last_result.clear(); _public_expansions.clear()
	if is_instance_valid(client): client.invalidate_context()
	_invalidating = false; changed.emit()
func committed() -> void:
	# Call after the main's commit/refresh. One optional narration attempt only.
	if not automatic_narration or _adapter == null or _adapter.phase() != "idle" or _adapter.last_action.is_empty(): return
	if narration_recorded():return
	if _last_committed_narration == _adapter.last_action: return
	_last_committed_narration = _adapter.last_action
	request_narration()
func _on_completed(result: Dictionary) -> void:
	if _invalidating or _operation.is_empty() or _operation.epoch != _epoch: return
	last_result = result.duplicate(true)
	if not result.ok:
		if result.get("code")=="NEEDS_PUBLIC_CONTEXT" and result.get("control_reply") is Dictionary:
			var control: Dictionary=result.control_reply
			var paths: Array=_public_expansions.get(control.action_id,[]).duplicate()
			for path in control.context_paths:
				if not path in paths: paths.append(path)
			_public_expansions[control.action_id]=paths
			result.errors=["已补入同一冻结快照中的公开事实；可再次点击请求评估。没有自动联网、扣费或推进回合。"]
		var transient: bool = result.get("code") in ["TIMEOUT", "NETWORK_ERROR", "REQUEST_START_FAILED"] or int(result.get("http_status",0)) == 429 or int(result.get("http_status",0)) >= 500
		if transient:
			_consecutive_transient = mini(_consecutive_transient + 1, 6)
			_retry_after_ms = int(clock.call()) + mini(30000, 1000 * (1 << (_consecutive_transient - 1)))
		_operation.clear()
		var fallback := " 已提交事实及原有回合结果保持不变。" if result.get("phase") == "narration" else " 意图仍可取消或导入有效人工评估；未重掷。"
		status_changed.emit("；".join(result.get("errors", ["请求失败。"]))+fallback)
		changed.emit()
	else:
		_consecutive_transient = 0; _retry_after_ms = 0
	request_finished.emit(result)
func _on_assessment(id: String, _reply: Dictionary) -> void:
	if not _matches(id, "assessment") or _adapter.active_action != id or _adapter.phase() != "ready_roll": return
	_operation.clear(); changed.emit(); assessment_validated.emit(id)
func _on_narration(id: String, text: String) -> void:
	if not _matches(id, "narration") or _adapter.last_action != id or _adapter.phase() != "idle": return
	_operation.clear(); _adapter.narration = text
	changed.emit(); narration_received.emit(id, text)
func _matches(id: String, kind: String) -> bool:
	return not _invalidating and not _operation.is_empty() and _operation.epoch == _epoch and _operation.action_id == id and _operation.phase == kind and _adapter != null
func _report(result: Dictionary) -> Dictionary:
	status_changed.emit("；".join(result.get("errors", []))); changed.emit(); return result
func _exit_tree() -> void:
	_invalidating = true; _epoch += 1; _operation.clear(); _scope = null; _adapter = null
	if is_instance_valid(client): client.clear_configuration()
