extends RefCounted
## Opt-in, single-slot orchestration facade over the existing authoritative Engine.
## No resolver, action-choice AI, random draw, world mutation, status tick or save schema.
## Bind only an Engine already admitted/loaded by its owning profile adapter.
const PENDING_PHASES := ["awaiting_assessment", "ready_roll", "rolled", "staged"]
var _engine: RefCounted
var _active_id := ""
var _epoch := 0
var _request_sequence := 0
var _ticket: Dictionary = {}

func bind_validated_engine(engine: RefCounted, validated_pending: Dictionary = {}) -> Dictionary:
	# The caller takes pending from the SAME already validated engine save envelope.
	# No second authoritative queue is persisted, and network tickets never survive load.
	if engine == null: return _fail("NO_ENGINE", "An admitted Engine is required.")
	for method in ["ready", "save_data", "state_copy", "action_copy", "model_request", "begin_intent", "prepare_assessment", "roll_once", "stage", "commit", "cancel_intent", "committed_receipt_hash"]:
		if not engine.has_method(method): return _fail("ENGINE_CONTRACT", "Missing Engine method: " + method)
	var checked: Dictionary = engine.ready()
	if not checked.get("ok", false): return checked
	var actual_pending: Variant = engine.save_data().get("pending")
	if not actual_pending is Dictionary or actual_pending != validated_pending: return _fail("PENDING_BINDING", "Bind with the complete pending map from this admitted Engine; omission is not idle.")
	if validated_pending.size() > 1: return _fail("PENDING_CAPACITY", "This compatibility facade preserves the Engine's single pending slot.")
	var candidate_id := ""
	for id in validated_pending:
		if not id is String or not validated_pending[id] is Dictionary: return _fail("PENDING_BINDING", "Malformed pending identity.")
		var actual: Dictionary = engine.action_copy(id)
		if actual.is_empty() or actual != validated_pending[id] or actual.get("status") not in PENDING_PHASES: return _fail("PENDING_BINDING", "Pending must exactly match the admitted Engine.")
		candidate_id = id
	_engine = engine
	_active_id = candidate_id
	invalidate_transport()
	return {"ok": true, "resume": resume()}

func invalidate_transport() -> void:
	_epoch += 1
	_ticket.clear()

func active_action_id() -> String:
	return _active_id

func phase() -> String:
	if _engine == null: return "unbound"
	if _active_id.is_empty(): return "idle"
	return str(_engine.action_copy(_active_id).get("status", "missing"))

func next_slot() -> Dictionary:
	if _engine == null: return _fail("NO_ENGINE", "Bind an admitted Engine first.")
	if not _active_id.is_empty():
		var pending: Dictionary = _engine.action_copy(_active_id)
		if pending.is_empty(): return _fail("PENDING_DIVERGED", "The owning adapter changed the Engine; rebind explicitly.")
		return {"ok": true, "actor_id": pending.actor_id, "action_id": _active_id, "phase": pending.status, "source": "frozen_pending", "needs_intent": false}
	var state: Dictionary = _engine.state_copy()
	var actor_id := "actor_player"
	if state.has("combat_turn"):
		var turn: Variant = state.combat_turn
		if not turn is Dictionary or turn.get("phase") not in ["player", "enemy"]: return _fail("TURN_CONTRACT", "Unknown authoritative phase; no queue order is invented.")
		actor_id = str(turn.get("enemy_actor_id", "")) if turn.phase == "enemy" else "actor_player"
	var actor: Variant = state.get("actors", {}).get(actor_id)
	if not actor is Dictionary or not actor.get("health") is Dictionary: return _fail("TURN_ACTOR", "The authoritative phase owner is absent.")
	if int(actor.health.get("current", 0)) <= 0: return _fail("ACTOR_DOWNED", "No intention for a downed actor; only registered atomic rules may reschedule.")
	return {"ok": true, "actor_id": actor_id, "action_id": "", "phase": "idle", "source": "authoritative_phase", "needs_intent": true}

func begin_intent(actor_id: String, goal: String, focus: Dictionary = {}) -> Dictionary:
	var slot := next_slot()
	if not slot.get("ok", false): return slot
	if not slot.needs_intent: return _fail("ACTION_IN_PROGRESS", "Finish or cancel the frozen intention first.")
	if slot.actor_id != actor_id: return _fail("TURN_ACTOR", "The authoritative phase belongs to another actor.")
	# goal/focus come from a human or a separately approved model intent proposer.
	# In particular there is no enemy_attack template or fallback action here.
	var result: Dictionary = _engine.begin_intent(goal, focus, actor_id)
	if result.get("ok", false):
		_active_id = str(result.request.action_id)
		invalidate_transport()
	return result

func resume() -> Dictionary:
	var slot := next_slot()
	if not slot.get("ok", false): return slot
	if slot.needs_intent: return {"ok": true, "phase": "idle", "next": "obtain_intent", "slot": slot}
	var result := {"ok": true, "action_id": _active_id, "actor_id": slot.actor_id, "phase": slot.phase}
	match slot.phase:
		"awaiting_assessment":
			result["next"] = "request_assessment"
			result["request"] = _engine.model_request(_active_id)
		"ready_roll": result["next"] = "roll_once"
		"rolled": result["next"] = "stage"
		"staged":
			result["next"] = "commit"
			result["stage_hash"] = _engine.action_copy(_active_id).stage_hash
	return result

func issue_assessment_ticket(now_ms: int, ttl_ms: int = 0) -> Dictionary:
	if phase() != "awaiting_assessment": return _fail("ASSESSMENT_PHASE", "Only an unresolved intention may request assessment.")
	if now_ms < 0 or ttl_ms < 0: return _fail("CLOCK_ARGUMENT", "Monotonic time and optional TTL must be nonnegative.")
	if not _ticket.is_empty(): return _fail("REQUEST_IN_PROGRESS", "Invalidate or finish the current request before retrying.")
	var request: Dictionary = _engine.model_request(_active_id)
	if request.is_empty(): return _fail("NO_REQUEST", "The admitted Engine has no request for this intention.")
	_request_sequence += 1
	_ticket = {"scheduler_instance": get_instance_id(), "epoch": _epoch, "request_sequence": _request_sequence, "action_id": _active_id,
		"actor_id": str(request.context.actor_id), "state_version": request.state_version, "context_hash": request.context_hash,
		"issued_at_ms": now_ms, "expires_at_ms": now_ms + ttl_ms if ttl_ms > 0 else -1}
	return {"ok": true, "ticket": _ticket.duplicate(true), "request": request}

func accept_assessment(reply: Variant, ticket: Dictionary, now_ms: int) -> Dictionary:
	if _ticket.is_empty() or ticket != _ticket: return _fail("STALE_REQUEST", "The response no longer owns this request.")
	if now_ms < int(ticket.issued_at_ms): return _fail("CLOCK_ARGUMENT", "Monotonic time moved backwards.")
	if int(ticket.expires_at_ms) >= 0 and now_ms >= int(ticket.expires_at_ms):
		_ticket.clear()
		return _fail("EXPIRED_REQUEST", "The response expired; the same intention remains pending without cost.")
	if phase() != "awaiting_assessment" or _active_id != ticket.action_id: return _fail("STALE_ACTION", "The frozen intention changed.")
	var action: Dictionary = _engine.action_copy(_active_id)
	var state: Dictionary = _engine.state_copy()
	if action.actor_id != ticket.actor_id or action.state_version != ticket.state_version or state.state_version != ticket.state_version or action.context_hash != ticket.context_hash:
		return _fail("STALE_ACTION", "The action actor, snapshot or public-context identity changed.")
	if not reply is Dictionary or reply.get("action_id") != ticket.action_id or reply.get("state_version") != ticket.state_version or reply.get("context_hash") != ticket.context_hash:
		return _fail("REPLY_BINDING", "Assessment must match the frozen action, version and context.")
	# The trusted Engine owns all schema, numeric, resolver and actor checks.
	# Engine-level acceptance/rejection consumes this ticket, never an extra turn.
	# Earlier binding/clock rejection preserves the ticket; retry must invalidate it.
	_ticket.clear()
	return _engine.prepare_assessment(reply)

func roll_once(action_id: String) -> Dictionary:
	var checked := _check_active(action_id)
	if not checked.ok: return checked
	return _engine.roll_once(action_id)

func stage(action_id: String) -> Dictionary:
	var checked := _check_active(action_id)
	if not checked.ok: return checked
	return _engine.stage(action_id)

func commit(action_id: String, stage_hash: String) -> Dictionary:
	if _engine == null: return _fail("NO_ENGINE", "Bind an admitted Engine first.")
	# Duplicate commits stay with Engine's receipt/stage token validator. A previous
	# receipt must never clear a newer active action or issue another clock event.
	if action_id != _active_id and _engine.committed_receipt_hash(action_id).is_empty(): return _fail("UNKNOWN_ACTION", "No active action or committed receipt has this identity.")
	var result: Dictionary = _engine.commit(action_id, stage_hash)
	if result.get("ok", false) and action_id == _active_id:
		_active_id = ""
		invalidate_transport()
	return result

func cancel() -> Dictionary:
	if _engine == null or _active_id.is_empty(): return _fail("UNKNOWN_ACTION", "There is no pending intention to cancel.")
	invalidate_transport()
	var result: Dictionary = _engine.cancel_intent(_active_id)
	if result.get("ok", false): _active_id = ""
	# An enemy cancellation leaves the authoritative enemy phase in place.
	return result

static func clock_contract() -> Dictionary:
	return {"owner_action_end": "Engine frozen atomic hooks only; acting actor; sequence=before.state_version+1",
		"world_step": "Only an explicit registered status_v2_world_step patch; no per-enemy or wall-time advance",
		"legacy_status": "Retain the saved profile's existing committed-action hook clock",
		"patrol": "Authorized legacy hook, at most one legal configured step per committed action; never enqueue a second actor action",
		"preview_rejection_cancel_narration": "No gameplay time, status tick, patrol step, RNG or payment"}

func _check_active(action_id: String) -> Dictionary:
	if _engine == null or action_id.is_empty() or action_id != _active_id: return _fail("UNKNOWN_ACTION", "This is not the current frozen intention.")
	return {"ok": true}

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "errors": [message]}
