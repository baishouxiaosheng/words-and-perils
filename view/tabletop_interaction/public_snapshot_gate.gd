extends RefCounted
## Display-only, complete public snapshot admission. Never applies core patches.
## Caller supplies identity from a future authenticated transport, not payload.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const FIELDS := ["schema", "session_id", "audience_id", "world_id", "sequence", "state_version", "entities"]
const ENTITY_FIELDS := ["id", "kind", "scene_id", "hex", "label"]
var _authority_id: String
var _session_id: String
var _audience_id: String
var _world_id: String
var _last_sequence := -1
var _last_version := -1
var _last_digest := ""

func _init(authority_id: String, session_id: String, audience_id: String, world_id: String) -> void:
	_authority_id = authority_id
	_session_id = session_id
	_audience_id = audience_id
	_world_id = world_id

func accept_snapshot(sender_id: String, snapshot: Dictionary) -> Dictionary:
	if _authority_id.is_empty() or sender_id != _authority_id: return _fail("NOT_AUTHORITY")
	if not C.safe(snapshot) or not C.exact_fields(snapshot, FIELDS): return _fail("SNAPSHOT_SHAPE")
	if snapshot.schema != "tabletop_public_snapshot/v1" or snapshot.session_id != _session_id or snapshot.audience_id != _audience_id or snapshot.world_id != _world_id: return _fail("SNAPSHOT_SCOPE")
	if not C.integer(snapshot.sequence) or not C.integer(snapshot.state_version) or snapshot.sequence < 0 or snapshot.state_version < 0: return _fail("SNAPSHOT_VERSION")
	if not snapshot.entities is Array or snapshot.entities.size() > 4096: return _fail("SNAPSHOT_ENTITIES")
	var ids := {}
	for entity in snapshot.entities:
		if not C.exact_fields(entity, ENTITY_FIELDS): return _fail("PRIVATE_OR_UNSUPPORTED_FIELD")
		for key in ["id", "kind", "scene_id", "label"]:
			if not entity[key] is String or entity[key].is_empty() or entity[key].length() > 240: return _fail("ENTITY_ID")
		if ids.has(entity.id) or not entity.kind in ["actor", "tile", "item", "environment"]: return _fail("ENTITY_ID")
		if not entity.hex is Array or entity.hex.size() != 2 or not C.integer(entity.hex[0]) or not C.integer(entity.hex[1]): return _fail("ENTITY_HEX")
		ids[entity.id] = true
	var fingerprint := C.digest(snapshot)
	if snapshot.sequence == _last_sequence:
		if fingerprint != _last_digest: return _fail("SNAPSHOT_SEQUENCE_CONFLICT")
		return {"ok": true, "render": false, "duplicate_snapshot": true}
	if snapshot.sequence < _last_sequence or snapshot.state_version < _last_version: return _fail("SNAPSHOT_STALE")
	_last_sequence = int(snapshot.sequence)
	_last_version = int(snapshot.state_version)
	_last_digest = fingerprint
	return {"ok": true, "render": true, "duplicate_snapshot": false, "snapshot": snapshot.duplicate(true)}

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "render": false}
