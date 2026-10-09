extends RefCounted
## Immutable transport for already-admitted vegetation. PRECONDITION: a fresh
## Planner.build result, or external input accepted by Planner.validate, is required.
## Digest/shape checks here do not authenticate physical placement. Source must
## rebuild this catalog at admission and preserve its immutable world binding.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const IDs = preload("res://core/source_entities/catalog.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const ID := "source_vegetation_catalog/v1"
const PROFILE := "sparse_biomes/v1"
const MAX_ENTITIES := 1024
const MAX_BYTES := 1536 * 1024
const MAX_DESCRIPTOR_BYTES := 1024
const MANIFEST_ID := "generated_v3_vegetation/v1"
const ASSET_ID := "v3_vegetation_assets/v1"
const KINDS := ["temperate", "tropical", "sapling", "shrub", "tuft", "reed"]
const BIOMES := {"temperate_forest":"temperate", "jungle":"tropical", "grassland":"sapling", "dry_steppe":"shrub", "desert":"shrub", "alpine":"tuft", "wetland":"reed"}
const FIELDS := ["schema_version", "profile_id", "source_identity", "vegetation_identity", "entries", "catalog_hash"]
const SOURCE_FIELDS := ["source_contract", "content_hash", "geometry_hash", "source_runtime_hash", "placement_hash", "navigation_hash"]
const VEGETATION_FIELDS := ["schema_version", "profile_id", "vegetation_hash", "context_hash", "asset_catalog_hash", "reservation_hash"]
const DESCRIPTOR_FIELDS := ["id", "kind", "hex", "biome", "asset_id", "habit", "position", "radius", "height", "yaw", "tint", "row_hash", "full_sha256", "far_sha256", "root_support"]
const ROOT_SUPPORT_FIELDS := ["area", "height_spread", "max_gradient", "max_height", "min_height"]
const SUPPORT_FIELDS := ["ok", "area", "height_spread", "intersected_triangles", "max_gradient", "max_height", "min_height", "uncovered_area_upper_bound"]
const CONTEXT_FIELDS := ["schema_version", "profile_id", "source_hash", "geometry_hash", "renderer_profile", "placement_hash", "navigation_hash", "asset_catalog_hash", "reservation_hash", "origin_hex", "river_reservation"]
const MANIFEST_FIELDS := ["schema_version", "profile_id", "source_hash", "geometry_hash", "renderer_profile", "placement_hash", "navigation_hash", "asset_catalog_hash", "reservation_hash", "origin_hex", "river_reservation", "context_hash", "plants", "solid_clearance_radius", "limits", "statistics", "scope", "vegetation_hash"]
const ROW_FIELDS := ["id", "hex", "biome", "asset_id", "position", "radius", "height", "yaw", "tint", "root_footprint", "solid_footprint", "canopy_footprint", "solid_envelope", "support", "canopy_support", "solid_kind", "visual_bounds", "far_bounds", "root_bounds", "canopy_ground_gap", "row_hash"]
const ASSET_FIELDS := ["id", "habit", "full_sha256", "far_sha256", "triangles", "far_triangles", "visual_bounds", "root_bounds", "solid_bounds", "canopy_bounds", "source_minimum_y_q40", "minimum_y_scale", "same_projected_footprint"]
const PIN_PATHS := ["res://view/ecology_preview/vegetation_meshes.gd", "res://view/ecology_preview/vegetation_surface.gdshader", "res://view/ecology_preview/LICENSE.txt", "res://view/integrated_ecology_world/performance_variant/whole_canopies.gd"]

static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result
static func valid_id(value: Variant) -> bool: return IDs.valid_id(value)
static func valid_hash(value: Variant) -> bool: return IDs.valid_hash(value)
static func valid_hex(value: Variant) -> bool:
	return value is Array and value.size() == 2 and C.integer(value[0]) and C.integer(value[1]) and absf(float(value[0])) <= 1000 and absf(float(value[1])) <= 1000
static func _number(value: Variant, minimum: float = -1000000.0, maximum: float = 1000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func _q12(value: Variant, minimum: float = -1000000.0, maximum: float = 1000000.0) -> bool:
	return _number(value, minimum, maximum) and C.integer(float(value) * 4096.0)
static func _vector(value: Variant, dimensions: int) -> bool:
	if not value is Array or value.size() != dimensions: return false
	for coordinate in value:
		if not _q12(coordinate): return false
	return true
static func _bounds(value: Variant) -> bool:
	if not C.exact_fields(value, ["min", "max"]) or not _vector(value.min, 3) or not _vector(value.max, 3): return false
	for i in 3:
		if value.min[i] > value.max[i]: return false
	return true
static func _polygon(value: Variant) -> bool:
	if not value is Array or value.size() < 3 or value.size() > 128: return false
	var area := 0.0
	var seen: Dictionary = {}
	for point in value:
		if not _vector(point, 2) or seen.has(C.bytes(point)): return false
		seen[C.bytes(point)] = true
	for i in value.size():
		var a: Array = value[i]; var b: Array = value[(i + 1) % value.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
		for point in value:
			if (float(b[0]) - float(a[0])) * (float(point[1]) - float(a[1])) - (float(b[1]) - float(a[1])) * (float(point[0]) - float(a[0])) < -0.0000001: return false
	return area > 0.0000000001
static func _support(value: Variant) -> bool:
	if not C.exact_fields(value, SUPPORT_FIELDS) or not value.ok is bool or not value.ok: return false
	for field in ROOT_SUPPORT_FIELDS + ["uncovered_area_upper_bound"]:
		if not _q12(value[field], 0.0): return false
	return C.integer(value.intersected_triangles) and value.intersected_triangles > 0 and value.intersected_triangles <= 1000000 and value.max_height >= value.min_height
static func _root_support(value: Variant, asset: String) -> bool:
	if not C.exact_fields(value, ROOT_SUPPORT_FIELDS): return false
	for field in ROOT_SUPPORT_FIELDS:
		if not _q12(value[field], 0.0): return false
	var woody: bool = asset in ["temperate", "tropical", "sapling"]
	# Native support rounds outward by one q12 quantum; never tighten the
	# physical limits by interpreting the already-rounded summary as raw data.
	return value.min_height >= 0.009765625 and value.max_height >= value.min_height and value.max_gradient <= (0.55 if woody else 0.30) + 1.0 / 4096.0 and value.height_spread <= (0.04 if woody else 0.016) + 1.0 / 4096.0
static func habit(asset: String) -> String:
	return "tree" if asset in ["temperate", "tropical", "sapling"] else "shrub" if asset == "shrub" else "herbaceous"
static func _stable_id(id: Variant, hex: Array, context_hash: String) -> bool:
	if not valid_id(id): return false
	var prefix := "vegetation:v3:" + context_hash.substr(0, 16) + ":%d_%d:" % [int(hex[0]), int(hex[1])]
	return id.begins_with(prefix) and id.substr(prefix.length()) in ["0", "1", "2", "3", "4", "5"]
static func valid_descriptor(value: Variant) -> bool:
	if not C.exact_fields(value, DESCRIPTOR_FIELDS) or not C.safe(value) or not valid_id(value.id) or value.kind != "vegetation" or not valid_hex(value.hex): return false
	if not value.biome is String or not BIOMES.has(value.biome) or value.asset_id != BIOMES[value.biome] or value.habit != habit(value.asset_id): return false
	if not _vector(value.position, 3) or not _q12(value.radius, 1.0 / 4096.0, 1.0) or not _q12(value.height, 1.0 / 4096.0, 1.0) or not _q12(value.yaw, 0.0, 7.0) or not _q12(value.tint, 0.0, 2.0): return false
	for field in ["row_hash", "full_sha256", "far_sha256"]:
		if not valid_hash(value[field]): return false
	return _root_support(value.root_support, value.asset_id) and C.bytes(value).to_utf8_buffer().size() <= MAX_DESCRIPTOR_BYTES
static func _assets(value: Variant) -> bool:
	if not C.exact_fields(value, ["schema_version", "pins", "assets", "license", "catalog_hash"]) or not C.safe(value) or value.schema_version != ASSET_ID or not C.exact_fields(value.pins, PIN_PATHS) or not C.exact_fields(value.assets, KINDS) or not IDs.valid_text(value.license, 256): return false
	for path in PIN_PATHS:
		if not valid_hash(value.pins[path]): return false
	for asset in KINDS:
		var row: Variant = value.assets[asset]
		if not C.exact_fields(row, ASSET_FIELDS) or row.id != asset or row.habit != habit(asset) or not valid_hash(row.full_sha256) or not valid_hash(row.far_sha256): return false
		if not C.integer(row.triangles) or row.triangles < 1 or row.triangles > 1024 or not C.integer(row.far_triangles) or row.far_triangles < 1 or row.far_triangles > row.triangles: return false
		if not C.integer(row.source_minimum_y_q40) or not C.integer(row.minimum_y_scale) or row.minimum_y_scale != 1099511627776 or not row.same_projected_footprint is bool or not row.same_projected_footprint: return false
		for field in ["visual_bounds", "root_bounds", "solid_bounds", "canopy_bounds"]:
			if not _bounds(row[field]): return false
	var unsigned: Dictionary = value.duplicate(true); unsigned.erase("catalog_hash")
	return valid_hash(value.catalog_hash) and C.digest(unsigned) == value.catalog_hash and C.bytes(value).to_utf8_buffer().size() <= 32768
static func _descriptor(row: Dictionary, assets: Dictionary) -> Dictionary:
	var result := pick(row, ["id", "hex", "biome", "asset_id", "position", "radius", "height", "yaw", "tint", "row_hash"])
	result.merge({"kind":"vegetation", "habit":assets[row.asset_id].habit, "full_sha256":assets[row.asset_id].full_sha256, "far_sha256":assets[row.asset_id].far_sha256, "root_support":pick(row.support, ROOT_SUPPORT_FIELDS)})
	return C.normalized(result)
static func _manifest(value: Variant, source: Dictionary, assets: Dictionary) -> bool:
	if not C.exact_fields(value, MANIFEST_FIELDS) or not C.safe(value) or value.schema_version != MANIFEST_ID or value.profile_id != PROFILE or value.renderer_profile != "structured_v1" or value.river_reservation != "full_source_river_cells/v1": return false
	if not valid_hex(value.origin_hex) or not value.plants is Array or value.plants.size() > MAX_ENTITIES or C.bytes(value).to_utf8_buffer().size() > 4 * 1024 * 1024: return false
	for field in ["source_hash", "geometry_hash", "placement_hash", "navigation_hash", "asset_catalog_hash", "reservation_hash", "context_hash", "vegetation_hash"]:
		if not valid_hash(value[field]): return false
	if value.source_hash != source.get("content_hash") or value.geometry_hash != source.get("geometry_hash") or value.placement_hash != source.get("placement_hash") or value.navigation_hash != source.get("effective_navigation_hash") or value.asset_catalog_hash != assets.catalog_hash: return false
	if C.digest(pick(value, CONTEXT_FIELDS)) != value.context_hash: return false
	var unsigned: Dictionary = value.duplicate(true); unsigned.erase("vegetation_hash")
	if C.digest(unsigned) != value.vegetation_hash or not _number(value.solid_clearance_radius) or value.solid_clearance_radius != 0.38: return false
	var limits := {"max_plants":1024, "max_full_triangles":80000, "max_active_batches":64, "dry_clearance":0.01, "root_max_gradient":0.55, "root_max_spread":0.04, "low_max_gradient":0.30, "low_max_spread":0.016, "root_embed":0.003}
	var scope := {"source_biomes_unchanged":true, "navigation_unchanged":true, "solid_policy":"stem_or_low_foliage_outside_existing_corridors/v1", "canopy_is_navigation_wall":false, "cover_or_harvest_gameplay":false, "selection_is_action":false}
	if C.bytes(value.limits) != C.bytes(limits) or C.bytes(value.scope) != C.bytes(scope): return false
	var previous := ""; var triangles := 0; var biomes: Dictionary = {}; var species: Dictionary = {}
	for row in value.plants:
		if not C.exact_fields(row, ROW_FIELDS) or not valid_hex(row.hex) or not _stable_id(row.id, row.hex, value.context_hash) or row.id <= previous or not row.asset_id in KINDS or not _support(row.support) or not _support(row.canopy_support): return false
		if not valid_descriptor(_descriptor(row, assets.assets)): return false
		for field in ["root_footprint", "solid_footprint", "canopy_footprint", "solid_envelope"]:
			if not _polygon(row[field]): return false
		for field in ["visual_bounds", "far_bounds", "root_bounds"]:
			if not _bounds(row[field]): return false
		if row.solid_kind != ("stem" if row.asset_id in ["temperate", "tropical", "sapling"] else "low_foliage") or not _q12(row.canopy_ground_gap): return false
		var row_unsigned: Dictionary = row.duplicate(true); row_unsigned.erase("row_hash")
		if C.digest(row_unsigned) != row.row_hash: return false
		previous = row.id; triangles += int(assets.assets[row.asset_id].triangles)
		biomes[row.biome] = biomes.get(row.biome, 0) + 1; species[row.asset_id] = species.get(row.asset_id, 0) + 1
	return triangles <= 80000 and C.bytes(value.statistics) == C.bytes({"instances":value.plants.size(), "full_triangles":triangles, "biomes":biomes, "assets":species})

static func build(profile_id: String, source_identity: Dictionary, manifest: Dictionary, asset_catalog: Dictionary) -> Dictionary:
	if not IDs.valid_text(profile_id, 128) or not _assets(asset_catalog) or not _manifest(manifest, source_identity, asset_catalog): return C.fail("VEGETATION_CATALOG_INPUT", "Vegetation requires an exact source-bound admitted manifest and native asset catalog.")
	var source := pick(source_identity, ["source_contract", "content_hash", "geometry_hash", "placement_hash"])
	source["source_runtime_hash"] = source_identity.get("runtime_hash")
	source["navigation_hash"] = source_identity.get("effective_navigation_hash")
	var entries: Dictionary = {}
	for row in manifest.plants:
		for field in ["entity_catalog", "static_entity_catalog", "npc_catalog"]:
			var old: Variant = source_identity.get(field, {})
			if not old is Dictionary or not old.get("entries", {}) is Dictionary or old.get("entries", {}).has(row.id): return C.fail("VEGETATION_COLLISION", "Vegetation cannot take another registered identity.")
		entries[row.id] = _descriptor(row, asset_catalog.assets)
	var catalog: Dictionary = C.normalized({"schema_version":ID, "profile_id":profile_id, "source_identity":source, "vegetation_identity":pick(manifest, VEGETATION_FIELDS), "entries":entries})
	catalog["catalog_hash"] = C.digest(catalog)
	var checked := validate(catalog)
	return {"ok":true, "catalog":catalog} if checked.ok else checked
static func validate(value: Variant) -> Dictionary:
	if not C.exact_fields(value, FIELDS) or not C.safe(value) or value.schema_version != ID or not IDs.valid_text(value.profile_id, 128) or not valid_hash(value.catalog_hash) or not value.entries is Dictionary or value.entries.size() > MAX_ENTITIES: return C.fail("VEGETATION_CATALOG", "Vegetation catalog shape or bounded count is invalid.")
	if not C.exact_fields(value.source_identity, SOURCE_FIELDS) or not IDs.valid_text(value.source_identity.source_contract, 128): return C.fail("VEGETATION_SOURCE", "Vegetation has no exact immutable source binding.")
	for field in SOURCE_FIELDS:
		if field != "source_contract" and not valid_hash(value.source_identity[field]): return C.fail("VEGETATION_SOURCE", "Vegetation source digest is invalid.")
	if not C.exact_fields(value.vegetation_identity, VEGETATION_FIELDS) or value.vegetation_identity.schema_version != MANIFEST_ID or value.vegetation_identity.profile_id != PROFILE: return C.fail("VEGETATION_SOURCE", "Vegetation placement binding is invalid.")
	for field in ["vegetation_hash", "context_hash", "asset_catalog_hash", "reservation_hash"]:
		if not valid_hash(value.vegetation_identity[field]): return C.fail("VEGETATION_SOURCE", "Vegetation placement digest is invalid.")
	for id in value.entries:
		var descriptor_: Variant = value.entries[id]
		if not valid_descriptor(descriptor_) or descriptor_.id != id or not _stable_id(id, descriptor_.hex, value.vegetation_identity.context_hash): return C.fail("VEGETATION_IDENTITY", "Vegetation identity, root cell or compact descriptor is invalid.")
	var unsigned: Dictionary = value.duplicate(true); unsigned.erase("catalog_hash")
	if C.digest(unsigned) != value.catalog_hash or C.bytes(value).to_utf8_buffer().size() > MAX_BYTES: return C.fail("VEGETATION_CATALOG", "Vegetation catalog digest or size changed.")
	return {"ok":true}
static func scene_for(descriptor_: Dictionary, state: Dictionary) -> String:
	var found := ""
	for scene_id in state.scenes:
		var supporting: Dictionary = Cells.cell(state, scene_id, descriptor_.hex)
		if supporting.get("scene_id") != scene_id or not C.integer(supporting.get("q")) or not C.integer(supporting.get("r")) or C.bytes([supporting.q, supporting.r]) != C.bytes(descriptor_.hex): continue
		if supporting.get("biome") != descriptor_.biome or not supporting.get("ocean") is bool or supporting.ocean or not supporting.get("river") is bool or supporting.river: continue
		if not found.is_empty(): return ""
		found = scene_id
	return found
static func validate_world(state: Dictionary) -> Dictionary:
	var metadata: Variant = state.get("generated_world")
	if not metadata is Dictionary: return C.fail("VEGETATION_WORLD", "World has no admitted vegetation catalog.")
	var checked := validate(metadata.get("vegetation_entity_catalog"))
	if not checked.ok: return checked
	var catalog: Dictionary = metadata.vegetation_entity_catalog
	if not IDs.valid_text(state.get("world_id"), 256) or metadata.get("profile") != catalog.profile_id or metadata.get("vegetation_profile") != PROFILE or metadata.get("vegetation_catalog_hash") != catalog.catalog_hash or metadata.get("vegetation_hash") != catalog.vegetation_identity.vegetation_hash or metadata.get("vegetation_base_runtime_hash") != catalog.source_identity.source_runtime_hash: return C.fail("VEGETATION_SOURCE", "Vegetation does not belong to this exact world version.")
	for field in ["source_contract", "content_hash", "geometry_hash", "placement_hash"]:
		if metadata.get(field) != catalog.source_identity[field]: return C.fail("VEGETATION_SOURCE", "Vegetation and world source or village differ.")
	if metadata.get("effective_navigation_hash") != catalog.source_identity.navigation_hash: return C.fail("VEGETATION_SOURCE", "Vegetation and effective navigation differ.")
	for field in ["scenes", "hexes", "actors", "items"]:
		if not state.get(field) is Dictionary: return C.fail("VEGETATION_WORLD", "Vegetation world containers are invalid.")
	for scene_id in state.scenes:
		if not valid_id(scene_id) or not state.scenes[scene_id] is Dictionary: return C.fail("VEGETATION_WORLD", "Vegetation scene identity is invalid.")
	if not state.get("scene_hexes", {}) is Dictionary: return C.fail("VEGETATION_WORLD", "Scene-local vegetation cells are invalid.")
	var maps: Array = [state.hexes]
	for scene_id in state.get("scene_hexes", {}):
		if not valid_id(scene_id) or not state.scenes.has(scene_id) or not state.scene_hexes[scene_id] is Dictionary: return C.fail("VEGETATION_WORLD", "Scene-local vegetation namespace is invalid.")
		maps.append(state.scene_hexes[scene_id])
	var occupied: Dictionary = {}
	for field in ["actors", "items", "scenes"]:
		for id in state[field]: occupied[id] = true
	for field in ["entity_catalog", "static_entity_catalog", "npc_catalog"]:
		var other: Variant = metadata.get(field, {})
		if not other is Dictionary or not other.get("entries", {}) is Dictionary: return C.fail("VEGETATION_WORLD", "Another source catalog is malformed.")
		for id in other.get("entries", {}): occupied[id] = true
	for cells in maps:
		for supporting in cells.values():
			if not supporting is Dictionary or not C.safe(supporting) or C.bytes(supporting).to_utf8_buffer().size() > 65536: return C.fail("VEGETATION_WORLD", "Vegetation supporting cells are not bounded frozen facts.")
			occupied[supporting.get("id", "")] = true
	for id in catalog.entries:
		if occupied.has(id) or scene_for(catalog.entries[id], state).is_empty(): return C.fail("VEGETATION_IDENTITY", "Vegetation has an identity collision or lacks unique matching dry root support.")
	return {"ok":true}
static func descriptor(id: String, state: Dictionary) -> Dictionary:
	if not validate_world(state).ok: return {}
	return state.generated_world.vegetation_entity_catalog.entries.get(id, {}).duplicate(true)
static func identity(state: Dictionary) -> Dictionary:
	if not validate_world(state).ok: return {}
	var catalog: Dictionary = state.generated_world.vegetation_entity_catalog
	return {"schema_version":ID, "profile_id":catalog.profile_id, "catalog_hash":catalog.catalog_hash}
