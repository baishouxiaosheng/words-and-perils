extends RefCounted
## Read-only static identities, detached from already-admitted physical placement.
## Admission must validate placement against its source before calling build().
## This module checks the exact transport/binding shape; it never loads terrain,
## renders geometry, grants custody, or claims to re-run physical admission.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const IDs = preload("res://core/source_entities/catalog.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const ID := "static_source_entity_catalog/v1"
const MAX_ENTITIES := 64
const MAX_BYTES := 128 * 1024
const MAX_DESCRIPTOR_BYTES := 16 * 1024
const MAX_MANIFEST_BYTES := 4 * 1024 * 1024
const KINDS := ["settlement", "building", "road"]
const FIELDS := ["schema_version", "profile_id", "source_identity", "placement_identity", "entries", "catalog_hash"]
const SOURCE_FIELDS := ["source_contract", "content_hash", "geometry_hash", "source_runtime_hash"]
const PLACEMENT_FIELDS := ["schema_version", "profile_id", "placement_hash", "context_hash"]
const DESCRIPTOR_FIELDS := ["id", "kind", "name", "description", "primary_hex", "supported_hexes", "physical_witness"]
const CONTEXT_FIELDS := ["schema_version", "profile_id", "source_hash", "geometry_hash", "renderer_profile", "asset_catalog_hash", "river_reservation", "origin_hex"]
const MANIFEST_FIELDS := ["schema_version", "profile_id", "source_hash", "geometry_hash", "renderer_profile", "asset_catalog_hash", "river_reservation", "origin_hex", "context_hash", "placement_hash", "asset_clearance_contract", "actor_sole_radius", "actor_clearance_radius", "settlements", "buildings", "roads", "plaza", "entry_anchors", "blocked_edges", "base_allowed_neighbors", "allowed_neighbors", "origin_component", "scope"]
const SETTLEMENT_FIELDS := ["id", "name", "kind", "center_hex", "footprint_hexes", "entry_hex", "building_ids", "road_ids", "walled"]
const BUILDING_FIELDS := ["id", "settlement_id", "asset_id", "asset_sha256", "lod1_sha256", "hex", "position", "yaw_radians", "scale", "footprint", "clearance_envelope", "clearance_radius", "foundation_plane", "support_limits", "support"]
const ROAD_FIELDS := ["id", "settlement_id", "hex", "route_hexes", "centerline_q40", "centerline_scale", "width", "clearance_radius", "footprint", "clearance_envelope", "visual_lift", "terrain_cost_modifier", "support_limits", "support"]
const SUPPORT_FIELDS := ["ok", "area", "height_spread", "intersected_triangles", "max_gradient", "max_height", "min_height", "uncovered_area_upper_bound"]
const SETTLEMENT_WITNESS_FIELDS := ["settlement_kind", "entry_hex", "building_ids", "road_ids", "walled", "plaza"]
const BUILDING_WITNESS_FIELDS := ["settlement_id", "asset_id", "asset_sha256", "lod1_sha256", "position", "yaw_radians", "scale", "footprint", "clearance_envelope", "clearance_radius", "foundation_plane", "support_limits", "support"]
const ROAD_WITNESS_FIELDS := ["settlement_id", "centerline_q40", "centerline_scale", "width", "clearance_radius", "footprint", "clearance_envelope", "visual_lift", "terrain_cost_modifier", "support_limits", "support"]

static func pick(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field in fields:
		if value.has(field): result[field] = C.normalized(value[field])
	return result

static func valid_id(value: Variant) -> bool: return IDs.valid_id(value)
static func valid_hash(value: Variant) -> bool: return IDs.valid_hash(value)
static func valid_hex(value: Variant) -> bool:
	return value is Array and value.size() == 2 and C.integer(value[0]) and C.integer(value[1]) and absf(float(value[0])) <= 1000 and absf(float(value[1])) <= 1000

static func valid_hexes(value: Variant, maximum: int = 16) -> bool:
	if not value is Array or value.is_empty() or value.size() > maximum: return false
	var seen: Dictionary = {}
	for hex in value:
		if not valid_hex(hex) or seen.has(C.bytes(hex)): return false
		seen[C.bytes(hex)] = true
	return true

static func _number(value: Variant, minimum: float = -1000000.0, maximum: float = 1000000.0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _row(value: Variant, dimensions: int, exact_integer: bool = false) -> bool:
	if not value is Array or value.size() != dimensions: return false
	for part in value:
		if exact_integer:
			if not C.integer(part): return false
		elif not _number(part): return false
	return true

static func _polygon(value: Variant) -> bool:
	if not value is Array or value.size() < 3 or value.size() > 64: return false
	var seen: Dictionary = {}; var area := 0.0; var direction := 0
	for row in value:
		if not _row(row, 2) or seen.has(C.bytes(row)): return false
		seen[C.bytes(row)] = true
	for i in value.size():
		var a: Array = value[i]; var b: Array = value[(i + 1) % value.size()]; var c: Array = value[(i + 2) % value.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
		var turn: float = (float(b[0]) - float(a[0])) * (float(c[1]) - float(b[1])) - (float(b[1]) - float(a[1])) * (float(c[0]) - float(b[0]))
		if absf(turn) > 0.000000000001:
			var next_direction := 1 if turn > 0.0 else -1
			if direction != 0 and direction != next_direction: return false
			direction = next_direction
	if direction == 0 or absf(area) <= 0.000000000001: return false
	# Every vertex must lie in the same half-plane of every convex hull edge.
	# Local turning signs alone can admit a self-intersecting star polygon.
	for i in value.size():
		var a: Array = value[i]; var b: Array = value[(i + 1) % value.size()]
		for point in value:
			var cross: float = (float(b[0]) - float(a[0])) * (float(point[1]) - float(a[1])) - (float(b[1]) - float(a[1])) * (float(point[0]) - float(a[0]))
			if cross * direction < -0.000000000001: return false
	return true

static func _ids(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > MAX_ENTITIES: return false
	var seen: Dictionary = {}
	for id in value:
		if not valid_id(id) or seen.has(id): return false
		seen[id] = true
	return true

static func _support(value: Variant) -> bool:
	if not C.exact_fields(value, SUPPORT_FIELDS) or not value.ok is bool or not value.ok: return false
	for field in SUPPORT_FIELDS:
		if field == "ok": continue
		if not _number(value[field]): return false
	if not C.integer(value.intersected_triangles) or value.intersected_triangles < 1: return false
	return value.area > 0 and value.height_spread >= 0 and value.max_gradient >= 0 and value.uncovered_area_upper_bound >= 0 and value.max_height >= value.min_height

static func _limits(value: Variant, kind: String) -> bool:
	var fields: Array = ["dry_clearance", "max_gradient"]
	if kind != "road": fields.append("max_height_spread")
	if kind == "building": fields.append("max_foundation_gap")
	if not C.exact_fields(value, fields): return false
	for field in fields:
		if not _number(value[field], 0.0): return false
	return true

static func _plaza(value: Variant) -> bool:
	return C.exact_fields(value, ["footprint", "support_limits", "support"]) and _polygon(value.footprint) and _limits(value.support_limits, "plaza") and _support(value.support)

static func _building_witness(value: Variant) -> bool:
	if not C.exact_fields(value, BUILDING_WITNESS_FIELDS): return false
	if not valid_id(value.settlement_id) or not valid_id(value.asset_id) or not valid_hash(value.asset_sha256) or not valid_hash(value.lod1_sha256): return false
	if not _row(value.position, 3) or not _row(value.foundation_plane, 3) or not _number(value.yaw_radians) or not _number(value.scale, 0.000000001) or not _number(value.clearance_radius, 0.0): return false
	return _polygon(value.footprint) and _polygon(value.clearance_envelope) and _limits(value.support_limits, "building") and _support(value.support)

static func _road_witness(value: Variant) -> bool:
	if not C.exact_fields(value, ROAD_WITNESS_FIELDS) or not valid_id(value.settlement_id): return false
	if not value.centerline_q40 is Array or value.centerline_q40.size() < 2 or value.centerline_q40.size() > 64 or value.centerline_scale != 1099511627776: return false
	for row in value.centerline_q40:
		if not _row(row, 3, true): return false
	if not _number(value.width, 0.000000001) or not _number(value.clearance_radius, 0.0) or not _number(value.visual_lift, 0.0) or value.terrain_cost_modifier != 1: return false
	return _polygon(value.footprint) and _polygon(value.clearance_envelope) and _limits(value.support_limits, "road") and _support(value.support)

static func valid_descriptor(value: Variant) -> bool:
	if not C.exact_fields(value, DESCRIPTOR_FIELDS) or not C.safe(value) or not valid_id(value.id) or not value.kind in KINDS: return false
	if not IDs.valid_text(value.name, 256) or not IDs.valid_text(value.description, 4096) or not valid_hex(value.primary_hex) or not valid_hexes(value.supported_hexes) or not value.primary_hex in value.supported_hexes: return false
	if C.bytes(value).to_utf8_buffer().size() > MAX_DESCRIPTOR_BYTES: return false
	var witness: Variant = value.physical_witness
	match value.kind:
		"settlement":
			return C.exact_fields(witness, SETTLEMENT_WITNESS_FIELDS) and witness.settlement_kind == "village" and valid_hex(witness.entry_hex) and _ids(witness.building_ids) and _ids(witness.road_ids) and witness.walled is bool and not witness.walled and _plaza(witness.plaza) and value.supported_hexes == [value.primary_hex]
		"building": return value.supported_hexes == [value.primary_hex] and _building_witness(witness)
		"road": return value.supported_hexes.size() == 2 and value.supported_hexes[0] == value.primary_hex and _adjacent(value.supported_hexes[0], value.supported_hexes[1]) and _road_witness(witness)
	return false

static func _adjacent(a: Array, b: Array) -> bool:
	var q: int = int(a[0]) - int(b[0]); var r: int = int(a[1]) - int(b[1])
	return maxi(absi(q), maxi(absi(r), absi(q + r))) == 1

static func _cell_key(value: Variant) -> bool:
	if not value is String: return false
	var parts: PackedStringArray = value.split(",")
	if parts.size() != 2 or not C.int64_string(parts[0]) or not C.int64_string(parts[1]): return false
	return valid_hex([int(parts[0]), int(parts[1])])

static func _graph(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty() or value.size() > 10000: return false
	for key in value:
		if not _cell_key(key) or not value[key] is Array or value[key].size() > 6: return false
		var seen: Dictionary = {}
		for neighbor in value[key]:
			if not _cell_key(neighbor) or neighbor == key or seen.has(neighbor) or not value.has(neighbor): return false
			seen[neighbor] = true
	for key in value:
		for neighbor in value[key]:
			if not key in value[neighbor]: return false
	return true

static func _manifest_shape(value: Dictionary, inventory_identity: Dictionary) -> bool:
	if not C.exact_fields(value, MANIFEST_FIELDS) or not C.safe(value) or C.bytes(value).to_utf8_buffer().size() > MAX_MANIFEST_BYTES: return false
	if value.schema_version != "generated_v3_placement/v1" or value.profile_id != "dry_village/v1" or value.renderer_profile != "structured_v1" or value.river_reservation != "source_site_and_entry_cells/v1": return false
	if not valid_hash(value.source_hash) or not valid_hash(value.geometry_hash) or not valid_hash(value.asset_catalog_hash) or not valid_hash(value.context_hash) or not valid_hash(value.placement_hash) or not valid_hex(value.origin_hex): return false
	if value.source_hash != inventory_identity.get("content_hash") or value.geometry_hash != inventory_identity.get("geometry_hash") or C.digest(pick(value, CONTEXT_FIELDS)) != value.context_hash: return false
	var payload: Dictionary = value.duplicate(true); payload.erase("placement_hash")
	if C.digest(payload) != value.placement_hash: return false
	if value.asset_clearance_contract != "full_asset_projected_aabb_plus_circumscribed_disk/v1" or not _number(value.actor_sole_radius, 0.0) or not _number(value.actor_clearance_radius, float(value.actor_sole_radius)): return false
	if not value.settlements is Array or value.settlements.size() != 1 or not value.buildings is Array or value.buildings.size() != 3 or not value.roads is Array or value.roads.size() != 1 or not _plaza(value.plaza): return false
	if not _graph(value.base_allowed_neighbors) or not _graph(value.allowed_neighbors) or value.base_allowed_neighbors.keys().size() != value.allowed_neighbors.keys().size(): return false
	for key in value.base_allowed_neighbors:
		if not value.allowed_neighbors.has(key): return false
		for neighbor in value.allowed_neighbors[key]:
			if not neighbor in value.base_allowed_neighbors[key]: return false
	if not value.origin_component is Array or value.origin_component.is_empty() or value.origin_component.size() > 10000: return false
	var component: Dictionary = {}
	for key in value.origin_component:
		if not _cell_key(key) or component.has(key) or not value.base_allowed_neighbors.has(key): return false
		component[key] = true
	if not value.entry_anchors is Array or value.entry_anchors.size() != 2: return false
	var roles: Dictionary = {}
	for anchor in value.entry_anchors:
		if not C.exact_fields(anchor, ["role", "hex", "position_q40", "position_scale"]) or not anchor.role in ["plaza", "entry"] or roles.has(anchor.role) or not valid_hex(anchor.hex) or not _row(anchor.position_q40, 3, true) or anchor.position_scale != 1099511627776: return false
		roles[anchor.role] = anchor
	if not value.blocked_edges is Array or value.blocked_edges.is_empty() or value.blocked_edges.size() > 128: return false
	for edge in value.blocked_edges:
		if not C.exact_fields(edge, ["from", "to", "building_ids", "reason"]) or not valid_hex(edge.from) or not valid_hex(edge.to) or not _adjacent(edge.from, edge.to) or not _ids(edge.building_ids) or edge.reason != "building_clearance": return false
	var expected_scope := {"one_hex_village":true,"gate":false,"river_geometry":false,"source_river_cells_reserved":true,"river_corridor_geometry_verified":false,"rooms":false,"npc_behavior":false,"road_cost_bonus":false}
	return C.bytes(value.scope) == C.bytes(expected_scope)

static func _descriptor(id: String, kind: String, name_: String, description: String, primary: Array, supported: Array, witness: Dictionary) -> Dictionary:
	return C.normalized({"id":id,"kind":kind,"name":name_,"description":description,"primary_hex":primary,"supported_hexes":supported,"physical_witness":witness})

static func build(profile_id: String, inventory_identity: Dictionary, placement_manifest: Dictionary) -> Dictionary:
	if not IDs.valid_text(profile_id, 128) or not _manifest_shape(placement_manifest, inventory_identity): return C.fail("STATIC_PLACEMENT", "静态实体需要来源一致、已验证且未改动的有限安放清单。")
	var source := {"source_contract":inventory_identity.get("source_contract"),"content_hash":inventory_identity.get("content_hash"),"geometry_hash":inventory_identity.get("geometry_hash"),"source_runtime_hash":inventory_identity.get("runtime_hash")}
	var entries: Dictionary = {}; var manifest: Dictionary = C.normalized(placement_manifest)
	for site in manifest.settlements:
		if not C.exact_fields(site, SETTLEMENT_FIELDS) or not valid_id(site.id) or not IDs.valid_text(site.name, 256) or site.kind != "village" or not valid_hex(site.center_hex) or not valid_hexes(site.footprint_hexes): return C.fail("STATIC_PLACEMENT", "聚落安放描述无效。")
		entries[site.id] = _descriptor(site.id, "settlement", site.name, "已安放的一格村落。此选择只提供静态位置和建筑背景，不代表行动。", site.center_hex, site.footprint_hexes, {"settlement_kind":site.kind,"entry_hex":site.entry_hex,"building_ids":site.building_ids,"road_ids":site.road_ids,"walled":site.walled,"plaza":manifest.plaza})
	for building in manifest.buildings:
		if not C.exact_fields(building, BUILDING_FIELDS) or not valid_id(building.id) or not valid_id(building.asset_id) or not valid_hex(building.hex) or entries.has(building.id): return C.fail("STATIC_PLACEMENT", "建筑身份重复或安放描述无效。")
		var name_: String = {"village_cottage_a":"村舍一", "village_cottage_b":"村舍二", "village_barn":"村落谷仓"}.get(building.asset_id, "村落建筑")
		entries[building.id] = _descriptor(building.id, "building", name_, "村落中的固定建筑。可查看已验证安放位置与外部轮廓；此版本没有室内、入口或物品归属。", building.hex, [building.hex], pick(building, BUILDING_WITNESS_FIELDS))
	for road in manifest.roads:
		if not C.exact_fields(road, ROAD_FIELDS) or not valid_id(road.id) or not valid_hex(road.hex) or not valid_hexes(road.route_hexes) or entries.has(road.id): return C.fail("STATIC_PLACEMENT", "道路身份重复或安放描述无效。")
		entries[road.id] = _descriptor(road.id, "road", "村落入口道路", "连接村落广场与相邻干地的固定道路。选择保留实际点击的支持地格，不授予移动、渡河或地形消耗加成。", road.hex, road.route_hexes, pick(road, ROAD_WITNESS_FIELDS))
	var old_catalog: Variant = inventory_identity.get("entity_catalog", {})
	if not old_catalog is Dictionary or not old_catalog.get("entries", {}) is Dictionary: return C.fail("STATIC_COLLISION", "原有物品目录结构无效。")
	for id in entries:
		if old_catalog.get("entries", {}).has(id): return C.fail("STATIC_COLLISION", "静态实体不能与原有物品共用身份。")
	var catalog: Dictionary = C.normalized({"schema_version":ID,"profile_id":profile_id,"source_identity":source,"placement_identity":pick(manifest, PLACEMENT_FIELDS),"entries":entries})
	catalog.catalog_hash = C.digest(catalog)
	var checked := validate(catalog)
	if not checked.ok: return checked
	for anchor in manifest.entry_anchors:
		var site: Dictionary = entries[manifest.settlements[0].id]
		if anchor.hex != (site.primary_hex if anchor.role == "plaza" else site.physical_witness.entry_hex): return C.fail("STATIC_PLACEMENT", "安放锚点与静态实体不一致。")
	for edge in manifest.blocked_edges:
		for id in edge.building_ids:
			if not entries.has(id) or entries[id].kind != "building": return C.fail("STATIC_PLACEMENT", "阻挡边引用了未登记建筑。")
	return {"ok":true,"catalog":catalog}

static func validate(value: Variant) -> Dictionary:
	if not C.exact_fields(value, FIELDS) or not C.safe(value) or value.schema_version != ID or not IDs.valid_text(value.profile_id, 128) or not valid_hash(value.catalog_hash) or not value.entries is Dictionary or value.entries.is_empty() or value.entries.size() > MAX_ENTITIES: return C.fail("STATIC_CATALOG", "静态实体目录结构无效。")
	if not C.exact_fields(value.source_identity, SOURCE_FIELDS) or not IDs.valid_text(value.source_identity.source_contract, 128): return C.fail("STATIC_SOURCE", "静态实体缺少不可变来源身份。")
	for field in ["content_hash", "geometry_hash", "source_runtime_hash"]:
		if not valid_hash(value.source_identity[field]): return C.fail("STATIC_SOURCE", "静态实体来源哈希无效。")
	if not C.exact_fields(value.placement_identity, PLACEMENT_FIELDS) or value.placement_identity.schema_version != "generated_v3_placement/v1" or value.placement_identity.profile_id != "dry_village/v1" or not valid_hash(value.placement_identity.placement_hash) or not valid_hash(value.placement_identity.context_hash): return C.fail("STATIC_SOURCE", "静态实体安放身份无效。")
	for id in value.entries:
		if not valid_descriptor(value.entries[id]) or value.entries[id].id != id: return C.fail("STATIC_CATALOG", "静态实体ID、类型或物理描述无效。")
	if not _relations(value.entries): return C.fail("STATIC_RELATION", "静态实体关联或支持位置不一致。")
	var payload: Dictionary = value.duplicate(true); payload.erase("catalog_hash")
	if C.digest(payload) != value.catalog_hash or C.bytes(value).to_utf8_buffer().size() > MAX_BYTES: return C.fail("STATIC_CATALOG", "静态实体目录哈希或大小不匹配。")
	return {"ok":true}

static func _relations(entries: Dictionary) -> bool:
	var parents: Dictionary = {}
	for id in entries:
		var descriptor_: Dictionary = entries[id]; var witness: Dictionary = descriptor_.physical_witness
		if descriptor_.kind != "settlement": continue
		for kind in ["building", "road"]:
			for child_id in witness[kind + "_ids"]:
				if not entries.has(child_id) or parents.has(child_id): return false
				var child: Dictionary = entries[child_id]
				if child.kind != kind or child.physical_witness.settlement_id != id or child.primary_hex != descriptor_.primary_hex: return false
				if kind == "road" and child.supported_hexes != [descriptor_.primary_hex, witness.entry_hex]: return false
				parents[child_id] = id
	for id in entries:
		if entries[id].kind != "settlement" and not parents.has(id): return false
	return true

static func scene_for(descriptor_: Dictionary, state: Dictionary) -> String:
	if not state.get("scenes") is Dictionary: return ""
	var found := ""
	for scene_id in state.scenes:
		if not scene_id is String: return ""
		var complete := true
		for hex in descriptor_.supported_hexes:
			var supporting: Dictionary = Cells.cell(state, scene_id, hex)
			if supporting.is_empty() or supporting.get("scene_id") != scene_id or supporting.get("q") != hex[0] or supporting.get("r") != hex[1]: complete = false; break
		if complete:
			if not found.is_empty(): return ""
			found = scene_id
	return found

static func validate_world(state: Dictionary) -> Dictionary:
	var metadata: Variant = state.get("generated_world")
	if not metadata is Dictionary: return C.fail("STATIC_SOURCE", "当前世界没有静态实体目录。")
	var catalog: Variant = metadata.get("static_entity_catalog")
	var checked := validate(catalog)
	if not checked.ok: return checked
	if not IDs.valid_text(state.get("world_id"), 256) or metadata.get("static_entity_profile") != catalog.profile_id or metadata.get("static_entity_catalog_hash") != catalog.catalog_hash: return C.fail("STATIC_SOURCE", "静态目录不属于当前世界版本。")
	for field in ["source_contract", "content_hash", "geometry_hash"]:
		if metadata.get(field) != catalog.source_identity[field]: return C.fail("STATIC_SOURCE", "静态目录与地图来源不一致。")
	if metadata.get("inventory_runtime_hash") != catalog.source_identity.source_runtime_hash or metadata.get("placement_hash") != catalog.placement_identity.placement_hash or metadata.get("placement_profile") != catalog.placement_identity.profile_id or metadata.get("placement_context_hash") != catalog.placement_identity.context_hash: return C.fail("STATIC_SOURCE", "静态目录与物品版本或安放身份不一致。")
	for field in ["items", "actors", "scenes", "hexes"]:
		if not state.get(field) is Dictionary: return C.fail("STATIC_WORLD", "静态实体所在世界结构无效。")
	for scene_id in state.scenes:
		if not valid_id(scene_id) or not state.scenes[scene_id] is Dictionary: return C.fail("STATIC_WORLD", "场景身份结构无效。")
	if state.has("scene_hexes"):
		if not state.scene_hexes is Dictionary: return C.fail("STATIC_WORLD", "场景地格结构无效。")
		for scene_id in state.scene_hexes:
			if not valid_id(scene_id) or not state.scenes.has(scene_id) or not state.scene_hexes[scene_id] is Dictionary: return C.fail("STATIC_WORLD", "场景地格结构无效。")
	# Guard cell containers before using the backwards-compatible Cells helpers.
	var cell_maps: Array = [state.hexes]
	for scene_map in state.get("scene_hexes", {}).values(): cell_maps.append(scene_map)
	for cell_map in cell_maps:
		for supporting in cell_map.values():
			if not supporting is Dictionary or not C.safe(supporting) or C.bytes(supporting).to_utf8_buffer().size() > 65536: return C.fail("STATIC_WORLD", "支持地格不是有限的冻结资料。")
	var collision_ids: Dictionary = {}
	var old_catalog: Variant = metadata.get("entity_catalog", {})
	if not old_catalog is Dictionary or not old_catalog.get("entries", {}) is Dictionary: return C.fail("STATIC_WORLD", "原有物品目录结构无效。")
	for id in old_catalog.get("entries", {}): collision_ids[id] = true
	for field in ["items", "actors", "scenes"]:
		for id in state[field]: collision_ids[id] = true
	for scene_id in state.scenes:
		for supporting in Cells.cells(state, scene_id).values():
			if not supporting is Dictionary: return C.fail("STATIC_WORLD", "支持地格结构无效。")
			collision_ids[supporting.get("id", "")] = true
	for id in catalog.entries:
		if collision_ids.has(id) or scene_for(catalog.entries[id], state).is_empty(): return C.fail("STATIC_COLLISION", "静态实体身份冲突，或没有唯一的支持场景。")
	return {"ok":true}

static func descriptor(id: String, state: Dictionary) -> Dictionary:
	if not validate_world(state).ok: return {}
	return state.generated_world.static_entity_catalog.entries.get(id, {}).duplicate(true)

static func identity(state: Dictionary) -> Dictionary:
	if not validate_world(state).ok: return {}
	var catalog: Dictionary = state.generated_world.static_entity_catalog
	return {"schema_version":ID,"profile_id":catalog.profile_id,"catalog_hash":catalog.catalog_hash}
