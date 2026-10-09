extends RefCounted
## Static selection is contextual evidence only, independent of item custody.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Catalog = preload("res://core/source_entities/static_catalog.gd")
const PublicProjection = preload("res://core/source_entities/static_projection.gd")
const VERSION := "source-static-focus/v1"
const REF_FIELDS := ["world_id", "kind", "id", "hex", "scene_id", "catalog_version", "catalog_id", "entity_revision"]
const FACT_FIELDS := ["scene_id", "source_identity", "catalog_identity", "placement_identity", "descriptor", "supporting_cell", "location_witness", "selection_is_action"]
const LOCATION_FIELDS := ["kind", "scene_id", "hex", "primary_hex", "supported_hexes"]

static func reference_for(focus: Dictionary) -> Dictionary: return PublicProjection.pick(focus, REF_FIELDS)
static func valid_hex(value: Variant) -> bool: return Catalog.valid_hex(value)

static func cell(state: Dictionary, scene_id: String, hex: Variant) -> Dictionary:
	if not valid_hex(hex) or not state.get("scenes", {}).has(scene_id): return {}
	var found: Dictionary = Cells.cell(state, scene_id, hex)
	return found if found.get("scene_id") == scene_id and found.get("q") == hex[0] and found.get("r") == hex[1] else {}

static func source_identity(state: Dictionary) -> Dictionary:
	if not Catalog.validate_world(state).ok: return {}
	return state.generated_world.static_entity_catalog.source_identity.duplicate(true)

static func make_reference(id: String, state: Dictionary, clicked_hex: Array = []) -> Dictionary:
	if not Catalog.valid_id(id) or not Catalog.validate_world(state).ok: return {}
	var catalog: Dictionary = state.generated_world.static_entity_catalog
	var descriptor: Dictionary = C.normalized(catalog.entries.get(id, {}))
	if descriptor.is_empty(): return {}
	var hex: Array = descriptor.primary_hex if clicked_hex.is_empty() else C.normalized(clicked_hex)
	if not valid_hex(hex) or not hex in descriptor.supported_hexes: return {}
	var scene_id := Catalog.scene_for(descriptor, state)
	if scene_id.is_empty() or cell(state, scene_id, hex).is_empty(): return {}
	return C.normalized({"world_id":state.world_id,"kind":descriptor.kind,"id":id,"hex":hex,"scene_id":scene_id,"catalog_version":VERSION,"catalog_id":catalog.catalog_hash,"entity_revision":0})

static func _location(reference: Dictionary, descriptor: Dictionary) -> Dictionary:
	return C.normalized({"kind":"static","scene_id":reference.scene_id,"hex":reference.hex,"primary_hex":descriptor.primary_hex,"supported_hexes":descriptor.supported_hexes})

static func resolve(reference: Dictionary, state: Dictionary) -> Dictionary:
	if not C.exact_fields(reference, REF_FIELDS) or not C.safe(reference) or not reference.id is String or not valid_hex(reference.hex): return C.fail("STATIC_FOCUS", "静态目标需要完整身份、支持地格和版本，请重新选择。")
	var current := make_reference(reference.id, state, reference.hex)
	if current.is_empty() or C.bytes(reference) != C.bytes(current): return C.fail("STATIC_FOCUS", "静态目标的目录、位置或版本无效，请重新选择。")
	var catalog: Dictionary = state.generated_world.static_entity_catalog
	var descriptor: Dictionary = catalog.entries[current.id]
	var focus := current.duplicate(true)
	focus.schema_version = 1
	focus.facts = {"scene_id":current.scene_id,"source_identity":catalog.source_identity.duplicate(true),"catalog_identity":{"schema_version":Catalog.ID,"profile_id":catalog.profile_id,"catalog_hash":catalog.catalog_hash},"placement_identity":catalog.placement_identity.duplicate(true),"descriptor":descriptor.duplicate(true),"supporting_cell":cell(state, current.scene_id, current.hex).duplicate(true),"location_witness":_location(current, descriptor),"selection_is_action":false}
	return {"ok":true,"focus":C.normalized(focus)}

static func validate_historical(value: Dictionary, state: Dictionary) -> Array:
	if not Catalog.validate_world(state).ok or not C.exact_fields(value, REF_FIELDS + ["schema_version", "facts"]) or not C.safe(value): return ["Historical static focus requires its exact immutable catalog and frozen witness."]
	if value.schema_version != 1 or not value.id is String or not valid_hex(value.hex) or not C.integer(value.entity_revision) or value.entity_revision != 0: return ["Historical static identity or revision is invalid."]
	var expected := make_reference(value.id, state, value.hex)
	if expected.is_empty() or C.bytes(reference_for(value)) != C.bytes(expected): return ["Historical static identity differs from the world's frozen catalog."]
	var facts: Variant = value.facts
	var catalog: Dictionary = state.generated_world.static_entity_catalog
	var descriptor: Dictionary = catalog.entries[value.id]
	if not C.exact_fields(facts, FACT_FIELDS) or facts.scene_id != value.scene_id or not facts.selection_is_action is bool or facts.selection_is_action: return ["Historical static facts are malformed or treated as an action."]
	if C.bytes(facts.source_identity) != C.bytes(catalog.source_identity) or C.bytes(facts.catalog_identity) != C.bytes(Catalog.identity(state)) or C.bytes(facts.placement_identity) != C.bytes(catalog.placement_identity) or C.bytes(facts.descriptor) != C.bytes(descriptor): return ["Historical static source, placement or descriptor changed."]
	if not C.exact_fields(facts.location_witness, LOCATION_FIELDS) or C.bytes(facts.location_witness) != C.bytes(_location(expected, descriptor)) or C.bytes(facts.supporting_cell) != C.bytes(cell(state, value.scene_id, value.hex)): return ["Historical static supporting cell or location witness changed."]
	return []
