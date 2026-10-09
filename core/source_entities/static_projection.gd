extends RefCounted
## Projection reads frozen values only. No world, source, renderer or catalog lookup.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const FOCUS_FIELDS := ["schema_version", "world_id", "kind", "id", "hex", "scene_id", "catalog_version", "catalog_id", "entity_revision"]
const DESCRIPTOR_FIELDS := ["id", "kind", "name", "description", "primary_hex", "supported_hexes"]
const SOURCE_FIELDS := ["source_contract", "content_hash", "geometry_hash", "source_runtime_hash"]
const CATALOG_FIELDS := ["schema_version", "profile_id", "catalog_hash"]
const PLACEMENT_FIELDS := ["schema_version", "profile_id", "placement_hash", "context_hash"]
const SUPPORT_FIELDS := ["ok", "area", "height_spread", "intersected_triangles", "max_gradient", "max_height", "min_height", "uncovered_area_upper_bound"]

static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result

static func _dictionary(value: Variant) -> Dictionary: return value if value is Dictionary else {}

static func public_physical(witness: Dictionary, kind: String) -> Dictionary:
	var result: Dictionary = {}
	match kind:
		"settlement":
			result = pick(witness, ["settlement_kind", "entry_hex", "building_ids", "road_ids", "walled"])
			var plaza: Dictionary = _dictionary(witness.get("plaza", {}))
			result.plaza = pick(plaza, ["footprint"])
			result.plaza.support_limits = pick(_dictionary(plaza.get("support_limits", {})), ["dry_clearance", "max_gradient", "max_height_spread"])
			result.plaza.support = pick(_dictionary(plaza.get("support", {})), SUPPORT_FIELDS)
		"building":
			result = pick(witness, ["settlement_id", "asset_id", "asset_sha256", "lod1_sha256", "position", "yaw_radians", "scale", "footprint", "clearance_envelope", "clearance_radius", "foundation_plane"])
			result.support_limits = pick(_dictionary(witness.get("support_limits", {})), ["dry_clearance", "max_gradient", "max_height_spread", "max_foundation_gap"])
			result.support = pick(_dictionary(witness.get("support", {})), SUPPORT_FIELDS)
		"road":
			result = pick(witness, ["settlement_id", "centerline_q40", "centerline_scale", "width", "clearance_radius", "footprint", "clearance_envelope", "visual_lift", "terrain_cost_modifier"])
			result.support_limits = pick(_dictionary(witness.get("support_limits", {})), ["dry_clearance", "max_gradient"])
			result.support = pick(_dictionary(witness.get("support", {})), SUPPORT_FIELDS)
	return result

static func public_descriptor(descriptor: Dictionary) -> Dictionary:
	var result := pick(descriptor, DESCRIPTOR_FIELDS)
	result.physical_witness = public_physical(_dictionary(descriptor.get("physical_witness", {})), str(descriptor.get("kind", "")))
	return C.normalized(result)

static func frozen_focus(focus: Dictionary, cell_fields: Array) -> Dictionary:
	if focus.is_empty(): return {}
	var result := pick(focus, FOCUS_FIELDS)
	var facts: Dictionary = _dictionary(focus.get("facts", {}))
	result.facts = pick(facts, ["scene_id", "selection_is_action"])
	result.facts.source_identity = pick(_dictionary(facts.get("source_identity", {})), SOURCE_FIELDS)
	result.facts.catalog_identity = pick(_dictionary(facts.get("catalog_identity", {})), CATALOG_FIELDS)
	result.facts.placement_identity = pick(_dictionary(facts.get("placement_identity", {})), PLACEMENT_FIELDS)
	result.facts.descriptor = public_descriptor(_dictionary(facts.get("descriptor", {})))
	result.facts.supporting_cell = pick(_dictionary(facts.get("supporting_cell", {})), cell_fields)
	result.facts.location_witness = pick(_dictionary(facts.get("location_witness", {})), ["kind", "scene_id", "hex", "primary_hex", "supported_hexes"])
	return C.normalized(result)
