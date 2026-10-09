extends "res://view/runtime_ai/controller.gd"
## One existing connection panel and one shared client. Old profiles retain their
## existing controller path; new identity presence is checked before old metadata.
signal intention_ready(actor_id: String, goal: String)
const ActorClient = preload("res://view/actor_status_entry_v1/runtime/client.gd")
const StatusScope = preload("res://view/actor_status_entry_v1/runtime/status_scope.gd")
const ActorScope = preload("res://view/actor_action_entry/runtime/actor_scope.gd")
var intention_consent := false
var _receipt_target := ""

func _ready() -> void:
	client = ActorClient.new(); add_child(client)
	client.completed.connect(_on_completed)
	client.assessment_ready.connect(_on_assessment)
	client.narration_ready.connect(_on_narration)
	client.intention_ready.connect(_on_intention)
	client.busy_changed.connect(_on_client_busy_changed)
	client.connection_changed.connect(_on_connection_changed)

func bind_adapter(adapter: RefCounted) -> void:
	intention_consent = false
	super.bind_adapter(adapter)

func _on_connection_changed() -> void:
	intention_consent = false
	if _actor_mode(): invalidate_context()

func _actor_mode() -> bool:
	return _adapter != null and _adapter.engine != null and (_status_declared(_adapter.engine.state_copy()) or ActorScope.recognizes(_adapter.engine.state_copy()))

func _status_declared(state: Dictionary) -> bool:
	# Missing/corrupted state markers must not erase an already bound status
	# facade/rule declaration and route it to an old/global public projector.
	# This selects only the rejection boundary; _admitted stays fully strict.
	if StatusScope.recognizes_status(state): return true
	if _adapter == null: return false
	if _adapter.has_method("profile_id") and _adapter.profile_id() == StatusScope.StatusSource.PROFILE: return true
	return _adapter.engine != null and _adapter.engine.has_method("rule_id") and _adapter.engine.rule_id() == StatusScope.StatusRule.PROFILE_RULE

func authorize_intention_requests(enabled: bool) -> void:
	intention_consent = enabled
	if not enabled and _operation.get("phase") == "intention": cancel()
	changed.emit()

func intention_cost_notice() -> String:
	return "此独立模式的敌方回合需要一次意图提案与一次普通评估；可选叙事另加一次。沿用当前提供商及model，可能分别计费。默认不发送意图提案；没有自动重试。"

func request_intention() -> Dictionary: return _begin("intention")

func request_receipt_narration(action_id: String) -> Dictionary:
	if not _actor_mode(): return _report(C.fail("ACTOR_RUNTIME_PROFILE", "Historical receipt requests are scoped to actor profile."))
	_receipt_target = action_id
	var result := _begin("narration")
	_receipt_target = ""
	return result

func _begin(kind: String) -> Dictionary:
	if not _actor_mode():
		if kind == "intention": return _report(C.fail("ACTOR_RUNTIME_PROFILE", "No admitted actor profile profile; no intention request was sent."))
		return super._begin(kind)
	if kind not in ["intention", "assessment", "narration"]: return _report(C.fail("INVALID_PHASE", "Unknown transport phase."))
	# Required work owns the one shared transport. Optional calls cancelled here
	# are never queued for an automatic paid retry.
	if kind != "narration" and _operation.get("phase") == "narration": cancel()
	if _invalidating or busy(): return _report(C.fail("BUSY", "One transport operation is already pending."))
	if not is_instance_valid(client) or not client.configured(): return _report(C.fail("NOT_CONFIGURED", "Offline manual JSON remains available; no model has run."))
	if not connection_enabled: return _report(C.fail("CONSENT_REQUIRED", "Apply the existing connection consent first; no request was sent."))
	if kind == "intention" and not intention_consent: return _report(C.fail("INTENTION_CONSENT_REQUIRED", intention_cost_notice()))
	if cooldown_remaining() > 0.0: return _report(C.fail("BACKOFF", "Wait for the existing manual retry cooldown; there is no automatic retry."))
	var core: Variant = _adapter.get("core")
	if core == null: return _report(C.fail("ACTOR_RUNTIME_PROFILE", "New marker lacks an admitted actor facade; legacy fallback is forbidden."))
	var configuration_revision: int = client.configuration_revision()
	var generation := _epoch
	var receiver: RefCounted = _adapter
	var source: RefCounted = _adapter.engine
	var guard: Callable = func(): return is_inside_tree() and not _invalidating and _epoch == generation and _adapter == receiver and _adapter.engine == source
	var capacity: Variant = client.public_configuration().get("public_request_budget_bytes", 65536)
	var scope: RefCounted = StatusScope.new(_adapter, guard, capacity, clock) if _status_declared(source.state_copy()) else ActorScope.new(_adapter, guard, capacity, clock)
	_scope = scope
	var ttl_ms := int(float(client.public_configuration().timeout_seconds) * 1000.0)
	var prepared: Dictionary
	var id := ""
	if kind == "intention":
		prepared = scope.begin_intention(ttl_ms)
		if prepared.get("ok", false): id = prepared.request.proposal_id
	elif kind == "assessment":
		prepared = scope.begin_assessment(ttl_ms)
		if prepared.get("ok", false): id = prepared.request.action_id
	else:
		id = _receipt_target if not _receipt_target.is_empty() else str(_adapter.last_action)
		if _adapter.has_recorded_narration(id): return _report(C.fail("ALREADY_RECORDED", "This receipt already has optional narration; no duplicate request."))
		prepared = scope.bind_receipt(id)
	last_metrics = scope.last_metrics.duplicate(true)
	if not prepared.get("ok", false):
		_drop_actor_grants(); return _report(prepared)
	_operation_sequence += 1
	var operation_id := _operation_sequence
	_operation = {"epoch": generation, "action_id": id, "phase": kind, "operation_id": operation_id, "client_request_id": -1}
	changed.emit()
	var live: bool = client.provider_info().live
	status_changed.emit(("Waiting for provider " if live else "Waiting for offline test transport ") + kind + "; no numerical action has been committed by this request.")
	if _operation.get("operation_id", -1) != operation_id or _epoch != generation: return C.fail("STALE_CONTEXT", "Cancelled before send.")
	if not connection_enabled or (kind == "intention" and not intention_consent) or client.configuration_revision() != configuration_revision:
		_operation.clear(); _drop_actor_grants(); return _report(C.fail("CONFIG_CHANGED", "Connection or consent changed before send; review the existing panel."))
	var result: Dictionary
	if kind == "intention": result = client.request_intention(scope, id)
	elif kind == "assessment": result = client.request_assessment(scope, id, CONTRACT)
	else: result = client.request_narration(scope, id, CONTRACT)
	if not result.ok and _operation.get("operation_id", -1) == operation_id:
		_operation.clear(); _drop_actor_grants(); _report(result)
	return result

func _drop_actor_grants() -> void:
	if _adapter != null and _adapter.has_method("invalidate_transport"):
		_adapter.invalidate_transport()

func invalidate_context() -> void:
	_drop_actor_grants()
	_receipt_target = ""
	super.invalidate_context()

func cancel_transport_for_manual() -> void: before_manual_import()

func before_manual_import() -> void:
	# Retain the exact proposal grant for manual acceptance while retiring every
	# HTTP ownership token and scheduler ticket BEFORE any manual preparation.
	_invalidating = true; _epoch += 1; _operation.clear(); _scope = null
	if _actor_mode(): _adapter.core.scheduler.invalidate_transport()
	if is_instance_valid(client): client.invalidate_context()
	_invalidating = false; changed.emit()

func cancel() -> Dictionary:
	var actor_mode := _actor_mode()
	var result: Dictionary = super.cancel()
	if actor_mode: _drop_actor_grants()
	return result

func _on_completed(result: Dictionary) -> void:
	if _owns_result(result) and _actor_mode() and not result.get("ok", false): _drop_actor_grants()
	super._on_completed(result)

func _on_intention(id: String, reply: Dictionary) -> void:
	if not _matches(id, "intention") or not _actor_mode() or _adapter.phase() != "awaiting_assessment": return
	var generation := _epoch
	var operation_id: int = _operation.operation_id
	var receiver: RefCounted = _adapter
	var action_id: String = _adapter.active_action
	_operation.clear(); changed.emit()
	if not _same_completion(generation, operation_id) or _adapter != receiver or _adapter.active_action != action_id or _adapter.phase() != "awaiting_assessment": return
	intention_ready.emit(str(reply.actor_id), str(reply.goal))

func _on_narration(id: String, text: String) -> void:
	if not _actor_mode(): super._on_narration(id, text); return
	if not _matches(id, "narration") or _scope == null: return
	var receiver: RefCounted = _adapter
	var source: RefCounted = _adapter.engine
	var scope: RefCounted = _scope
	var hash_: String = source.committed_receipt_hash(id)
	if hash_.is_empty() or hash_ != scope.receipt_hash or scope.narration_request(id).is_empty(): return
	var generation := _epoch
	var operation_id: int = _operation.operation_id
	_operation.clear(); changed.emit()
	if not _same_completion(generation, operation_id) or _adapter != receiver or _adapter.engine != source or source.committed_receipt_hash(id) != hash_: return
	# Main remains the single display/sidecar recorder for this receipt.
	narration_received.emit(id, text)
