extends "res://view/tabletop_interaction/intent_transport.gd"
## Opt-in local host adapter, not yet the live UI route. No assessment/commit API.
## Only trusted composition code constructs this with an engine and ownership.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "tabletop_intent/v1"
const MAX_REQUESTS := 256
const FIELDS := ["schema", "session_id", "request_id", "sequence", "world_id", "expected_state_version", "ownership_version", "actor_id", "goal", "attention"]
var _engine: RefCounted
var _session_id: String
var _principal_id: String
var _owned_actor_ids: Array
var _ownership_version: int
var _last_sequence := 0
var _accepted: Dictionary = {}

func _init(engine: RefCounted, session_id: String, principal_id: String, owned_actor_ids: Array, ownership_version := 1) -> void:
	_engine = engine
	_session_id = session_id
	_principal_id = principal_id
	_owned_actor_ids = owned_actor_ids.duplicate(true)
	_ownership_version = ownership_version

func submit_intent(command: Dictionary) -> Dictionary:
	if _engine == null or _session_id.is_empty() or _principal_id.is_empty(): return _fail("HOST_NOT_CONFIGURED")
	if not C.safe(command) or not C.exact_fields(command, FIELDS): return _fail("COMMAND_SHAPE")
	if command.schema != SCHEMA or command.session_id != _session_id: return _fail("SESSION_MISMATCH")
	if not _text(command.request_id, 160) or not _text(command.actor_id, 160) or not _text(command.world_id, 240): return _fail("COMMAND_ID")
	if not _text(command.goal, 8192) or not command.attention is Dictionary: return _fail("EXPLICIT_INTENT_REQUIRED")
	for field in ["sequence", "expected_state_version", "ownership_version"]:
		if not C.integer(command[field]) or command[field] < 0: return _fail("COMMAND_VERSION")
	# Duplicates are answered before comparing the current world's version.
	# The same ID with changed text, attention, owner or sequence is never a retry.
	var fingerprint := C.digest(command)
	if _accepted.has(command.request_id):
		var previous: Dictionary = _accepted[command.request_id]
		if previous.fingerprint != fingerprint: return _fail("REQUEST_ID_CONFLICT")
		var duplicate: Dictionary = previous.ack.duplicate(true)
		duplicate.duplicate_request = true
		return duplicate
	if command.sequence != _last_sequence + 1: return _fail("SEQUENCE_MISMATCH")
	if command.ownership_version != _ownership_version: return _fail("OWNERSHIP_STALE")
	if not command.actor_id in _owned_actor_ids: return _fail("ACTOR_NOT_OWNED")
	if _accepted.size() >= MAX_REQUESTS: return _fail("SESSION_CAPACITY_REACHED")
	var state: Dictionary = _engine.state_copy()
	if command.world_id != state.get("world_id"): return _fail("WORLD_MISMATCH")
	if command.expected_state_version != state.get("state_version"): return _fail("STATE_STALE")
	# This is the existing mandatory assessment entry point. It freezes a request;
	# it cannot move, attack, roll, spend resources, stage or commit world facts.
	var admitted: Dictionary = _engine.begin_intent(command.goal, command.attention.duplicate(true), command.actor_id)
	if not admitted.get("ok", false): return _fail(str(admitted.get("code", "INTENT_REJECTED")))
	var ack := {"ok": true, "schema": "tabletop_intent_ack/v1", "session_id": _session_id,
		"request_id": command.request_id, "sequence": command.sequence,
		"action_id": admitted.request.action_id, "state_version": state.state_version,
		"phase": "awaiting_assessment", "duplicate_request": false}
	_last_sequence = int(command.sequence)
	_accepted[command.request_id] = {"fingerprint": fingerprint, "ack": ack.duplicate(true)}
	return ack

static func _text(value: Variant, limit: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}
