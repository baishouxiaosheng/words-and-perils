extends RefCounted
## Immutable, bundle-bound identities for ACTUAL shipped render objects.
## Sparse world overrides preserve consequences without copying 7k meshes/facts into saves.
const Settlement = preload("res://view/playable_build/settlement_content.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const VERSION := "active-scene-entities/v1"
const SCENE := "scene_coast"
const PUBLIC_FIELDS := ["id", "kind", "name", "hex", "scene_id", "catalog_version", "bundle_id", "source", "public_facts", "state"]
static var _entities: Dictionary = {}
static var _tree_rows: Dictionary = {}
static var _regions: Dictionary = {}
static var _tree_transforms: Dictionary = {}
static var _bundle := ""
static var last_error := ""

static func _decode(path: String, row: Dictionary) -> PackedByteArray:
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != row.get("sha256", ""): return PackedByteArray()
	var size_: int = int(row.get("decoded_bytes", 0))
	if size_ <= 0 or size_ > 24000000: return PackedByteArray()
	var bytes_ := FileAccess.get_file_as_bytes(path).decompress(size_, FileAccess.COMPRESSION_GZIP)
	return bytes_ if bytes_.size() == size_ else PackedByteArray()

static func ready() -> bool:
	if not Bundle.ready(): last_error = Bundle.last_error; return false
	var bundle: Dictionary = Bundle.manifest()
	if _bundle == bundle.bundle_id and not _entities.is_empty(): return true
	_entities.clear(); _tree_rows.clear(); _regions.clear(); _tree_transforms.clear(); _bundle = ""
	var catalog: Dictionary = Bundle.document("catalog")
	var render: Dictionary = Bundle.document("render_manifest")
	var canopy_path: String = bundle.runtime.legacy_canopy_manifest.path
	var canopy: Variant = JSON.parse_string(FileAccess.get_file_as_string(canopy_path))
	if not canopy is Dictionary: last_error = "Missing bundle canopy catalog"; return false
	var rows := _decode(canopy_path.get_base_dir()+"/"+str(canopy.runtime.file), canopy.runtime).to_float32_array()
	var support_path: String = str(bundle.runtime.render_manifest.path).get_base_dir()+"/canopy_support_v03.json.gz"
	var support_bytes := _decode(support_path, render.files.get("canopy_support_v03.json.gz", {}))
	var bindings: Variant = JSON.parse_string(support_bytes.get_string_from_utf8())
	if rows.size() != int(canopy.instances)*10 or not bindings is Dictionary or bindings.get("source_mesh_sha256") != bundle.source_identity.mesh_sha256 or bindings.get("legacy_anchor_manifest_sha256") != bundle.runtime.legacy_canopy_manifest.sha256 or bindings.get("updates", []).size() != int(canopy.instances):
		last_error = "Scene entity source/instance binding mismatch"; return false
	var river_manifest_path: String = bundle.runtime.retained_river_manifest.path
	var river_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(river_manifest_path))
	var river_contract_path: String = river_manifest_path.get_base_dir()+"/"+str(river_manifest.overlay_contract_file)
	if FileAccess.get_sha256(river_contract_path) != river_manifest.overlay_contract_sha256: last_error = "River exclusion source mismatch"; return false
	var river_contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(river_contract_path))
	var river_polygon := PackedVector2Array()
	for point in river_contract.footprint_polygon_xz: river_polygon.append(Vector2(point[0],point[1]))
	var river_box: Array = river_contract.footprint_bounds_xz
	var cells: Dictionary = {}
	for cell in catalog.cells: cells["%d,%d" % [cell.q, cell.r]] = cell
	var identity := str(bundle.bundle_id).trim_prefix("natural-shore-v03-")
	for i in range(int(canopy.instances)):
		var update: Dictionary = bindings.updates[i]
		if update.get("hide", true) or update.get("row") != i: continue
		var j := i*10
		var x: float = rows[j]; var z: float = rows[j+2]; var radius: float = rows[j+3]
		if x+radius >= river_box[0] and x-radius <= river_box[2] and z+radius >= river_box[1] and z-radius <= river_box[3]:
			var crown := PackedVector2Array()
			for n in range(7): crown.append(Vector2(x+radius*cos(rows[j+5]+TAU*n/7.0), z+radius*sin(rows[j+5]+TAU*n/7.0)))
			if not Geometry2D.intersect_polygons(crown,river_polygon).is_empty(): continue
		var hex := hex_at(Vector3(rows[j], rows[j+1], rows[j+2]))
		var key := "%d,%d" % hex
		if not cells.has(key): continue # Halo artwork has no playable cell or gameplay identity.
		var kind: String = canopy.runtime.kinds[int(rows[j+7])]
		var id := "tree:"+identity+":"+str(i)
		var rendered_root := Vector3(rows[j], float(update.height), rows[j+2])
		var position := [rendered_root.x, rendered_root.y, rendered_root.z]
		_entities[id] = {"id": id, "kind": "tree", "name": {"temperate": "林木", "tropical": "热带树", "sapling": "幼树", "shrub": "灌木"}.get(kind, "树"), "hex": hex, "scene_id": SCENE, "catalog_version": VERSION, "bundle_id": bundle.bundle_id,
			"source": {"instance_row": i, "instance_sha256": canopy.runtime.sha256, "source_mesh_sha256": bundle.source_identity.mesh_sha256, "new_source_face_index": int(update.new_source_face_index), "legacy_parent_face_index": int(rows[j+8])},
			"public_facts": {"vegetation_type": kind, "position": position, "height": rows[j+4], "crown_radius": rows[j+3], "visible_form": "standing_vegetation"}}
		_tree_rows[i] = id
		_tree_transforms[i] = Transform3D(Basis(Vector3.UP,-rows[j+5]).scaled(Vector3(rows[j+3],rows[j+4],rows[j+3])),rendered_root)
	var mountain_manifest: Dictionary = Bundle.document("mountain_manifest")
	var mountain_path: String = str(bundle.runtime.mountain_manifest.path).get_base_dir()+"/"+str(mountain_manifest.binary)
	var mountain_rows := _decode(mountain_path, {"sha256": mountain_manifest.binary_sha256, "decoded_bytes": int(mountain_manifest.vertices)*8*4}).to_float32_array()
	if mountain_rows.size() != int(mountain_manifest.vertices)*8: last_error = "Mountain entity geometry binding mismatch"; return false
	for group in mountain_manifest.groups:
		var region: String = str(group.region)
		# A cell's centre relief label is NOT a complete footprint. Small visible
		# groups may contain no cell centre, and large groups straddle cell owners.
		var support_hexes := _mountain_support(group, mountain_rows, cells)
		if support_hexes.is_empty(): continue
		var id := "mountain:"+identity+":"+region
		_entities[id] = {"id": id, "kind": "mountain", "name": "山群", "hex": support_hexes[0], "scene_id": SCENE, "catalog_version": VERSION, "bundle_id": bundle.bundle_id,
			"source": {"source_region": region, "mountain_manifest_sha256": bundle.runtime.mountain_manifest.sha256, "source_mesh_sha256": bundle.source_identity.mesh_sha256},
			"public_facts": {"visible_form": "faceted_mountain_group", "support_hexes": support_hexes, "bounds_xz": Array(PackedFloat32Array(group.bounds_xz))}}
		_regions[region] = id
	var lamp_id := "prop:"+identity+":old_lamp"
	_entities[lamp_id] = {"id": lamp_id, "kind": "prop", "name": "旧灯", "hex": catalog.spawn.keeper.duplicate(), "scene_id": SCENE, "catalog_version": VERSION, "bundle_id": bundle.bundle_id,
		"source": {"authored_prop": "old_lamp", "source_mesh_sha256": bundle.source_identity.mesh_sha256}, "public_facts": {"visible_form": "shore_lantern", "description": "守灯人身旁的旧灯。灯罩歪斜，灯芯受潮。"}}
	for descriptor_ in Settlement.descriptors(): _entities[descriptor_.id] = descriptor_
	_bundle = str(bundle.bundle_id); last_error = ""
	return true

static func descriptor(id: String) -> Dictionary:
	return _entities.get(id, {}).duplicate(true) if ready() else {}
static func instance_transform(row: int) -> Transform3D:
	return _tree_transforms.get(row, Transform3D.IDENTITY) if not _bundle.is_empty() or ready() else Transform3D.IDENTITY
static func tree_id(row: int) -> String: return str(_tree_rows.get(row, "")) if not _bundle.is_empty() or ready() else ""
static func mountain_id(region: String) -> String: return str(_regions.get(region, "")) if not _bundle.is_empty() or ready() else ""
static func lamp_id() -> String:
	return "prop:"+_bundle.trim_prefix("natural-shore-v03-")+":old_lamp" if ready() else ""
static func initial_state(id: String) -> Dictionary:
	var value := descriptor(id)
	return {"posture": "standing" if value.get("kind") == "tree" else "fixed", "revision": 0, "ground_blocking": false} if not value.is_empty() else {}
static func validate_record(id: String, record: Variant) -> bool:
	if not record is Dictionary or record.size() != 2 or record.get("id") != id or not record.get("state") is Dictionary: return false
	var state_: Dictionary = record.state
	return descriptor(id).get("kind") == "tree" and state_.size() == 3 and state_.get("posture") == "fallen" and exact_integer(state_.get("revision")) and state_.get("revision") == 1 and state_.get("ground_blocking") is bool and state_.get("ground_blocking") == true
static func state_for(id: String, world: Dictionary) -> Dictionary:
	if descriptor(id).get("kind") in ["settlement","district"]: return Settlement.entity_state(world,id)
	var overrides: Dictionary = world.get("environment_entities", {})
	return overrides[id].state.duplicate(true) if overrides.has(id) and validate_record(id, overrides[id]) else initial_state(id)
static func entity(id: String, world: Dictionary) -> Dictionary:
	var value := descriptor(id)
	if value.is_empty() or world.get("generated_world", {}).get("bundle_id") != value.bundle_id or not world.get("hexes", {}).has("%d,%d" % value.hex): return {}
	if world.get("environment_entities", {}).has(id) and not validate_record(id, world.environment_entities[id]): return {}
	if value.kind in ["settlement","district"] and not Settlement.active(world): return {}
	value.state = state_for(id, world)
	if value.kind == "tree" and value.state.posture == "fallen": value.public_facts.visible_form = "fallen_vegetation"
	if value.kind == "prop" and value.source.authored_prop == "old_lamp":
		value.public_facts["lit"] = world.get("flags", {}).get("lamp_restored", false)
		if value.public_facts.lit: value.public_facts.description = "旧灯已经修复并重燃。"
	return value
static func make_reference(id: String, world: Dictionary, clicked_hex: Array = []) -> Dictionary:
	var value := entity(id, world)
	if value.is_empty(): return {}
	return {"world_id": world.world_id, "kind": value.kind, "id": id, "hex": value.hex.duplicate() if clicked_hex.is_empty() else clicked_hex.duplicate(), "catalog_version": VERSION, "entity_revision": value.state.revision}
static func supports_hex(value: Dictionary, hex: Array) -> bool:
	if value.get("kind") in ["mountain","settlement","district"]:
		for candidate in value.public_facts.get("support_hexes", []):
			if same_hex(hex, candidate): return true
		return false
	return same_hex(hex, value.get("hex"))
static func coverage(world: Dictionary = {}) -> Dictionary:
	if not ready(): return {"ok": false, "error": last_error}
	return {"ok": true, "trees": _tree_rows.size(), "mountain_groups": _regions.size(), "props": 1, "settlements": Settlement.all_settlements().size() if Settlement.active(world) else 0, "cities": "source_bound_village_citystate_city_1_1_3_when_installed", "identity": VERSION, "sparse_state": true}
static func hex_at(point: Vector3) -> Array:
	var qf := point.x/sqrt(3.0)-point.z/3.0; var rf := point.z*2.0/3.0; var sf := -qf-rf
	var q := roundi(qf); var r := roundi(rf); var s := roundi(sf)
	var dq := absf(q-qf); var dr := absf(r-rf); var ds := absf(s-sf)
	if dq > dr and dq > ds: q = -r-s
	elif dr > ds: r = -q-s
	return [q,r]

static func _mountain_support(group: Dictionary, values: PackedFloat32Array, cells: Dictionary) -> Array:
	var found: Dictionary = {}
	var polygons: Dictionary = {}
	for vertex_index in range(int(group.first_vertex), int(group.first_vertex)+int(group.vertices), 3):
		var triangle := PackedVector2Array()
		for offset in range(3):
			var j := (vertex_index+offset)*8
			triangle.append(Vector2(values[j], values[j+2]))
		if absf((triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])) < 0.000000001: continue
		var lo := triangle[0]; var hi := triangle[0]
		for point in triangle: lo=lo.min(point); hi=hi.max(point)
		for r in range(floori((lo.y-1.0)/1.5), ceili((hi.y+1.0)/1.5)+1):
			for q in range(floori(lo.x/sqrt(3.0)-r*0.5-0.5), ceili(hi.x/sqrt(3.0)-r*0.5+0.5)+1):
				var key := "%d,%d" % [q,r]
				if found.has(key) or not cells.has(key): continue
				if not polygons.has(key):
					var polygon := PackedVector2Array(); var center := Vector2(sqrt(3.0)*(q+r*0.5),1.5*r)
					for i in range(6): polygon.append(center+Vector2(cos(PI/6.0+TAU*i/6.0),sin(PI/6.0+TAU*i/6.0)))
					polygons[key]=polygon
				for intersection in Geometry2D.intersect_polygons(triangle, polygons[key]):
					var twice_area := 0.0
					for i in range(intersection.size()): twice_area += intersection[i].cross(intersection[(i+1)%intersection.size()])
					if absf(twice_area) > 0.000000001: found[key]=[q,r]; break
	var keys := found.keys(); keys.sort()
	var result: Array=[]
	for key in keys: result.append(found[key])
	return result

static func exact_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0 and float(value) == floorf(float(value))
static func same_hex(a: Variant, b: Variant) -> bool:
	if not a is Array or not b is Array or a.size() != 2 or b.size() != 2: return false
	for i in range(2):
		if not exact_integer(a[i]) or not exact_integer(b[i]) or int(a[i]) != int(b[i]): return false
	return true
