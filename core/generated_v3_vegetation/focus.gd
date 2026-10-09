extends RefCounted
## Selection is read-only evidence. Root identity never follows canopy overhang.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Catalog = preload("res://core/generated_v3_vegetation/catalog.gd")
const VERSION := "source-vegetation-focus/v1"
const REF_FIELDS := ["world_id", "kind", "id", "hex", "scene_id", "catalog_version", "catalog_id", "entity_revision"]
const FACT_FIELDS := ["scene_id", "source_identity", "catalog_identity", "vegetation_identity", "descriptor", "supporting_cell", "location_witness", "selection_is_action"]
const LOCATION_FIELDS := ["kind", "scene_id", "root_hex"]
static func reference_for(focus: Dictionary) -> Dictionary: return Catalog.pick(focus, REF_FIELDS)
static func cell(state: Dictionary, scene_id: String, hex: Variant) -> Dictionary:
	if not Catalog.valid_hex(hex) or not state.get("scenes", {}).has(scene_id): return {}
	var found: Dictionary = Cells.cell(state, scene_id, hex)
	return found if found.get("scene_id") == scene_id and C.integer(found.get("q")) and C.integer(found.get("r")) and C.bytes([found.q, found.r]) == C.bytes(hex) else {}
static func source_identity(state: Dictionary) -> Dictionary:
	return state.generated_world.vegetation_entity_catalog.source_identity.duplicate(true) if Catalog.validate_world(state).ok else {}
static func make_reference(id: String, state: Dictionary, clicked_hex: Array = []) -> Dictionary:
	if not Catalog.valid_id(id) or not Catalog.validate_world(state).ok or (not clicked_hex.is_empty() and not Catalog.valid_hex(clicked_hex)): return {}
	return _reference(id, state, state.generated_world.vegetation_entity_catalog)
static func _reference(id: String, state: Dictionary, catalog: Dictionary) -> Dictionary:
	var descriptor_: Dictionary = catalog.entries.get(id, {})
	if descriptor_.is_empty(): return {}
	# clicked_hex is only a picking hint. Even a neighboring dry canopy hit
	# resolves to the exact admitted root; the hint never enters the identity.
	var scene_id := Catalog.scene_for(descriptor_, state)
	if scene_id.is_empty(): return {}
	return C.normalized({"world_id":state.world_id, "kind":"vegetation", "id":id, "hex":descriptor_.hex, "scene_id":scene_id, "catalog_version":VERSION, "catalog_id":catalog.catalog_hash, "entity_revision":0})
static func references_for_admitted_world(state: Dictionary) -> Dictionary:
	# Validate once, then derive all compact renderer lookup headers without
	# N independent full-catalog validations. No caller-identity memoization.
	var checked := Catalog.validate_world(state)
	if not checked.ok: return checked
	var catalog: Dictionary = state.generated_world.vegetation_entity_catalog
	var references: Dictionary = {}
	for id in catalog.entries: references[id] = _reference(id, state, catalog)
	return {"ok":true, "references":references}
static func _location(reference: Dictionary) -> Dictionary:
	return C.normalized({"kind":"vegetation_root", "scene_id":reference.scene_id, "root_hex":reference.hex})
static func _reference_shape(reference: Dictionary) -> bool:
	return C.exact_fields(reference, REF_FIELDS) and C.safe(reference) and reference.id is String and Catalog.valid_hex(reference.hex) and C.integer(reference.entity_revision) and reference.entity_revision == 0
static func resolve(reference: Dictionary, state: Dictionary) -> Dictionary:
	if not _reference_shape(reference): return C.fail("VEGETATION_FOCUS", "Vegetation selection needs its complete immutable identity and root cell.")
	if not Catalog.validate_world(state).ok: return C.fail("VEGETATION_FOCUS", "Vegetation catalog, root, world or revision changed; select it again.")
	return _resolve_checked(reference, state, state.generated_world.vegetation_entity_catalog)
static func _resolve_checked(reference: Dictionary, state: Dictionary, catalog: Dictionary) -> Dictionary:
	# Private operation-local reuse only: caller just validated THIS world and
	# passes its exact catalog. Never retain a mutable caller identity as proof.
	if not _reference_shape(reference): return C.fail("VEGETATION_FOCUS", "Vegetation selection needs its complete immutable identity and root cell.")
	var current := _reference(reference.id, state, catalog)
	if current.is_empty() or C.bytes(reference) != C.bytes(current): return C.fail("VEGETATION_FOCUS", "Vegetation catalog, root, world or revision changed; select it again.")
	var focus := current.duplicate(true)
	focus["schema_version"] = 1
	focus["facts"] = {"scene_id":current.scene_id, "source_identity":catalog.source_identity.duplicate(true), "catalog_identity":{"schema_version":Catalog.ID, "profile_id":catalog.profile_id, "catalog_hash":catalog.catalog_hash}, "vegetation_identity":catalog.vegetation_identity.duplicate(true), "descriptor":catalog.entries[current.id].duplicate(true), "supporting_cell":cell(state, current.scene_id, current.hex).duplicate(true), "location_witness":_location(current), "selection_is_action":false}
	return {"ok":true, "focus":C.normalized(focus)}
static func _historical_shape(value: Dictionary) -> bool:
	return C.exact_fields(value, REF_FIELDS + ["schema_version", "facts"]) and C.safe(value) and C.integer(value.schema_version) and value.schema_version == 1
static func validate_historical(value: Dictionary, state: Dictionary) -> Array:
	if not _historical_shape(value): return ["Historical vegetation focus must retain its exact frozen schema."]
	if not Catalog.validate_world(state).ok: return ["Historical vegetation identity no longer matches the admitted root catalog."]
	return _validate_historical_checked(value, state, state.generated_world.vegetation_entity_catalog)
static func _validate_historical_checked(value: Dictionary, state: Dictionary, catalog: Dictionary) -> Array:
	# Same complete reference and frozen-fact checks as the public path; only
	# redundant catalog/world traversal is omitted inside one checked operation.
	if not _historical_shape(value): return ["Historical vegetation focus must retain its exact frozen schema."]
	var resolved := _resolve_checked(reference_for(value), state, catalog)
	if not resolved.ok: return ["Historical vegetation identity no longer matches the admitted root catalog."]
	if not C.exact_fields(value.facts, FACT_FIELDS) or C.bytes(value.facts) != C.bytes(resolved.focus.facts): return ["Historical vegetation source, descriptor, root support or read-only witness changed."]
	return []
