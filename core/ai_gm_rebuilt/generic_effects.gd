extends RefCounted
## Bounded authored effect vocabulary. No executable model data or JSON pointers.
## Catalog IDs resolve back to verified scene sources; sparse records are factual overrides.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const SOURCE_SCHEMA := "coast_condition_source/v1"
const MAX_DURATION := 3
const MAX_MAGNITUDE := 3
const STARTER_SOURCES := {"item_poison_vial": "poison", "item_feather_vial": "flight"}

static func source_profile(kind: String) -> Dictionary:
	return {"schema_version": SOURCE_SCHEMA, "kind": kind, "units_per_use": 1, "max_duration": MAX_DURATION, "max_magnitude": MAX_MAGNITUDE if kind == "poison" else 1, "target_scope": "self_or_adjacent_actor" if kind == "poison" else "self"}

static func install_starting_supplies(state: Dictionary) -> void:
	# Called for NEW games only. Loading/upgrading a save never awards supplies.
	for id in STARTER_SOURCES:
		var kind: String = STARTER_SOURCES[id]
		state.items[id] = {"id": id, "name": "苦叶毒剂（原型补给）" if kind == "poison" else "轻羽药剂（原型补给）", "description": "明示规则补给：消耗一瓶和一点体力，经递送与效果两项评估，给自己或相邻存活角色施加1至3回合、每回合1至3伤害的毒。不是完整战斗系统。" if kind == "poison" else "明示规则补给：消耗一瓶和一点体力，经递送与效果两项评估，给自己1至3回合飞行；只绕过地面阻挡，不绕过空中、全域和未实现的跨水限制。", "quantity": 2 if kind == "poison" else 1, "owner_actor_id": "actor_player", "condition_source": source_profile(kind), "interaction_profile": BasicEffects.interaction()}
		state.actors.actor_player.inventory.append(id)

static func validate_source(_item_id: String, item: Dictionary) -> bool:
	if not item.has("condition_source"): return true
	# Capability profiles are authored world content; item identity/name never chooses an effect.
	# No model-accessible operation may create or modify these profiles.
	var p: Variant = item.condition_source
	if not C.exact_fields(p, ["schema_version", "kind", "units_per_use", "max_duration", "max_magnitude", "target_scope"]) or p.schema_version != SOURCE_SCHEMA or not p.kind is String or not p.kind in ["poison", "flight"]: return false
	for field in ["units_per_use", "max_duration", "max_magnitude"]:
		if not C.integer(p[field]) or p[field] < 1 or p[field] > 3: return false
	if not p.target_scope is String or not p.target_scope in ["self", "self_or_adjacent_actor"]: return false
	return p.kind != "flight" or (p.max_magnitude == 1 and p.target_scope == "self")

static func validate_environment(state: Dictionary) -> Dictionary:
	if not state.has("environment_entities"): return {"ok": true} # Legacy worlds have none.
	if not state.environment_entities is Dictionary: return C.fail("ENVIRONMENT_STATE", "Environment overrides must be a typed sparse object.")
	for id in state.environment_entities:
		if not id is String or not _valid_record(id, state.environment_entities[id]): return C.fail("ENVIRONMENT_STATE", "Unknown source entity or malformed immutable fallen record.")
		var entity: Dictionary = Catalog.entity(id, state)
		if entity.is_empty(): return C.fail("ENVIRONMENT_STATE", "Environment source bundle or catalog identity differs.")
		var key := Traversal.key(entity.hex)
		if not state.hexes.has(key) or state.hexes[key].scene_id != entity.scene_id or not state.hexes[key].ground_blocked: return C.fail("ENVIRONMENT_STATE", "A fallen source entity must block its own authoritative ground cell.")
	return {"ok": true}

static func _valid_record(id: String, record: Variant) -> bool:
	if not C.exact_fields(record, ["id", "state"]) or not record.id is String or record.id != id or not C.exact_fields(record.state, ["posture", "revision", "ground_blocking"]): return false
	if not record.state.posture is String or not C.integer(record.state.revision) or not record.state.ground_blocking is bool: return false
	return Catalog.validate_record(id, record)

static func stable_environment(before: Dictionary, after: Dictionary) -> bool:
	var old: Dictionary = before.get("environment_entities", {})
	var current: Dictionary = after.get("environment_entities", {})
	for id in old:
		if not current.has(id) or C.bytes(old[id]) != C.bytes(current[id]): return false
	# First version supports monotonic standing -> fallen only; no restoration patches.
	return validate_environment(after).ok

static func apply_fell(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch, ["type", "entity_id", "expected_revision", "cell_id"]) or not patch.entity_id is String or not C.integer(patch.expected_revision) or patch.expected_revision != 0 or not patch.cell_id is String: return C.fail("ENVIRONMENT_EFFECT", "Felling requires a stable source ID, expected revision and owning cell.")
	if not state.has("environment_entities") or not state.environment_entities is Dictionary: return C.fail("ENVIRONMENT_UNAVAILABLE", "This world has not enabled source-bound environment effects.")
	var entity: Dictionary = Catalog.entity(patch.entity_id, state)
	if entity.is_empty() or entity.kind != "tree" or entity.state.posture != "standing" or entity.state.revision != patch.expected_revision: return C.fail("ENVIRONMENT_PRECONDITION", "Target is not a current standing source tree.")
	var key := Traversal.key(entity.hex)
	if not state.hexes.has(key): return C.fail("ENVIRONMENT_TARGET", "The tree has no valid supporting cell.")
	var cell: Dictionary = state.hexes[key]
	if cell.id != patch.cell_id or cell.scene_id != entity.scene_id or cell.ground_blocked or cell.all_blocked: return C.fail("ENVIRONMENT_PRECONDITION", "Target ownership changed or its ground is already blocked.")
	# One typed operation changes object and owner ground together after all checks.
	state.environment_entities[patch.entity_id] = {"id": patch.entity_id, "state": {"posture": "fallen", "revision": 1, "ground_blocking": true}}
	cell.ground_blocked = true
	return {"ok": true}

static func distance(a: Array, b: Array) -> int:
	var dq: int = int(a[0]) - int(b[0]); var dr: int = int(a[1]) - int(b[1])
	return maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))
