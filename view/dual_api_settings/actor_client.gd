extends "res://view/dual_api_settings/client.gd"
## The same configured client/credential/HTTP transport, with opt-in intention
## dispatch and receipt-bound narration. Legacy requests still use super.
signal intention_ready(proposal_id: String, reply: Dictionary)
const ActorCodec = preload("res://view/actor_status_entry_v1/runtime/intention_codec.gd")

func request_intention(scope: RefCounted, proposal_id: String, trusted_instructions: String = "") -> Dictionary:
	return _begin(scope, proposal_id, "intention", trusted_instructions)

func _begin(engine: RefCounted, action_id: String, phase: String, trusted_instructions: String) -> Dictionary:
	var selected: Dictionary = select_phase(phase)
	if not selected.ok: return selected
	if phase == "assessment" or engine == null or not engine.has_method("intention_request"):
		return super._begin(engine, action_id, phase, trusted_instructions)
	if phase not in ["intention", "narration"]: return C.fail("INVALID_PHASE", "Unsupported actor transport phase.")
	if _transitioning: return C.fail("CONTEXT_CHANGING", "Connection context is changing; no request was sent.")
	if busy(): return C.fail("BUSY", "One shared transport operation is already pending.")
	if not configured(): return C.fail("NOT_CONFIGURED", "Configure the existing connection or import manual JSON; no model has run.")
	if not is_inside_tree() or _timer == null or not is_instance_valid(_transport): return C.fail("NOT_READY", "The shared HTTP client must be in the scene.")
	var request: Dictionary = engine.intention_request(action_id) if phase == "intention" else engine.narration_request(action_id)
	if request.is_empty(): return C.fail("NO_REQUEST", "No current bounded actor proposal or committed receipt request.")
	if phase == "intention" and (not ActorCodec.valid_proposal(request) or request.get("proposal_id") != action_id): return C.fail("NO_REQUEST", "The proposal identity is invalid.")
	if phase == "narration" and (request.get("schema_version") != "ai_gm_rebuilt/v1" or request.get("phase") != phase): return C.fail("NO_REQUEST", "The narration contract is invalid.")
	var public_bytes := C.bytes(request).to_utf8_buffer().size()
	var public_cap: int = _config.public_request_budget_bytes
	if public_bytes > public_cap: return Budget.exceeded(public_bytes, public_cap)
	var info: Dictionary = _transport.info()
	var provenance := {"provider": info.id, "live": info.live, "kind": "model_reply"}
	var envelope: Dictionary = ActorCodec.encode(request, _config, provenance, trusted_instructions)
	if envelope.is_empty(): return C.fail("ACTOR_PUBLIC_REQUEST", "Unknown or mismatched actor proposal schema and marker.")
	envelope = Presets.apply_wire(envelope, _config)
	var body := C.bytes(envelope)
	if contains_current_credential(body): return C.fail("SENSITIVE_REQUEST", "The public body contains the current credential; it was not sent.")
	if body.to_utf8_buffer().size() > 4194304: return C.fail("REQUEST_TOO_LARGE", "The HTTP body exceeds the existing 4 MiB limit.")
	_sequence += 1
	var token := _sequence
	# action_id is the inherited transport correlation slot only. An intention
	# stores a proposal ID here; no Engine pending action is fabricated.
	_active = {"request_id": token, "engine": engine, "request": request, "request_hash": C.digest(request), "phase": phase, "action_id": action_id, "provenance": provenance, "world_version": request.state_version, "request_bytes": body.to_utf8_buffer().size(), "public_request_bytes": public_bytes, "public_request_budget_bytes": public_cap}
	busy_changed.emit(true)
	if not busy() or _active.request_id != token: return C.fail("CANCELLED", "Cancelled before any network send.")
	var timeout_seconds: float = _config.timeout_seconds
	var request_bytes := body.to_utf8_buffer().size()
	_timer.start(timeout_seconds)
	var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + _api_key])
	var error: Error = _transport.send(token, _config.endpoint, headers, body, timeout_seconds)
	if error != OK:
		if busy() and _active.request_id == token: _finish_error("REQUEST_START_FAILED", "The request could not start; no automatic retry.")
		return C.fail("REQUEST_START_FAILED", "The request could not start; no automatic retry.")
	return {"ok": true, "request_id": token, "request_bytes": request_bytes, "timeout_seconds": timeout_seconds}

func _on_transport_completed(token: int, status: int, body: String, error_code: String) -> void:
	if not busy() or token != _active.request_id or _active.get("cancelled", false): return
	if _active.phase == "assessment" or not _active.engine.has_method("intention_request"):
		super._on_transport_completed(token, status, body, error_code); return
	if not error_code.is_empty():
		_finish_error(error_code if error_code in ["TIMEOUT", "RESPONSE_TOO_LARGE"] else "NETWORK_ERROR", "Network request failed; no automatic retry or gameplay cost."); return
	if status < 200 or status >= 300:
		var failed := C.fail("HTTP_ERROR", "Provider returned HTTP %d; response text is withheld to avoid credential disclosure." % status)
		failed["http_status"] = status; _finish(failed); return
	if contains_current_credential(body):
		_finish_error("SENSITIVE_RESPONSE", "The response contains a credential and was discarded."); return
	var decoded := ActorCodec.decode(body)
	if not decoded.ok: _finish(decoded); return
	if contains_current_credential(C.bytes(decoded.reply)):
		_finish_error("SENSITIVE_RESPONSE", "The decoded response contains a credential and was discarded."); return
	var scope: RefCounted = _active.engine
	var id: String = _active.action_id
	var phase: String = _active.phase
	var current: Dictionary = scope.intention_request(id) if phase == "intention" else scope.narration_request(id)
	# For narration, the scope verifies immutable receipt/context. A later world
	# version or a newer pending action is intentionally not a rejection reason.
	if current.is_empty() or C.digest(current) != _active.request_hash:
		_finish_error("STALE_CONTEXT", "The frozen request no longer owns this context."); return
	var request: Dictionary = _active.request
	var reply: Dictionary = decoded.reply
	var id_field := "proposal_id" if phase == "intention" else "action_id"
	if reply.get(id_field) != id or reply.get("state_version") != request.state_version or reply.get("context_hash") != request.context_hash:
		_finish_error("STALE_CONTEXT", "The reply does not match the exact proposal or receipt binding."); return
	var checked: Dictionary = scope.accept_intention(reply) if phase == "intention" else scope.validate_narration_reply(reply)
	if not checked.ok: _finish(checked); return
	var outcome := checked.duplicate(true)
	outcome["reply"] = reply.duplicate(true)
	_finish(outcome)
	if _sequence != token: return
	if phase == "intention": intention_ready.emit(id, reply)
	else: narration_ready.emit(id, String(checked.narration))
