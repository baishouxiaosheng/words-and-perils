extends RefCounted
## Only the new saved, upstream-bound PL drainage candidate format is admitted.
const Terrain := preload("res://view/recovered_terrain_loader.gd")
const FORMAT := "EXPERIMENTAL_REBUILT_HEX_DRAINAGE_CANDIDATES"
const VERSION := "hex-finite-drainage-candidate-rebuilt-0.2.0"
const DERIVED_FORMAT := "EXPERIMENTAL_REBUILT_HEX_LAKE_PORTS_DRAINAGE"
const DERIVED_VERSION := "hex-rebuilt-lake-ports-drainage-0.3.0"
const MAX_BYTES := 64 * 1024 * 1024
const MAX_BODIES := 4096
const MAX_FOOTPRINTS := 180000

static func load_file(path: String, world: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path): return Terrain.fail("Water input not found")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return Terrain.fail("Cannot open water input")
	if file.get_length() <= 0 or file.get_length() > MAX_BYTES: return Terrain.fail("Water byte budget exceeded")
	var bytes := file.get_buffer(file.get_length()); file.close()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return Terrain.fail("Malformed water JSON")
	var result := decode(parser.data, world)
	if result.ok:
		var hashing := HashingContext.new(); hashing.start(HashingContext.HASH_SHA256); hashing.update(bytes)
		result.water.file_sha256 = hashing.finish().hex_encode()
		result.water.source_path = path
	return result

static func decode(raw: Variant, world: Dictionary) -> Dictionary:
	if world.is_empty() or not raw is Dictionary: return Terrain.fail("Terrain must be loaded before water")
	var basic: bool = raw.get("format") == FORMAT and raw.get("snapshot_version") == VERSION
	var derived: bool = raw.get("format") == DERIVED_FORMAT and raw.get("snapshot_version") == DERIVED_VERSION
	if not basic and not derived: return Terrain.fail("Unsupported water schema/version")
	if basic and world.format != Terrain.FORMAT: return Terrain.fail("Basic water requires basic mesh schema")
	if derived and world.format != Terrain.DERIVED_FORMAT: return Terrain.fail("Derived water requires derived mesh schema")
	if raw.get("production_compatible", true) != false: return Terrain.fail("Water must not claim production compatibility")
	if basic and raw.get("recovery_status") != "RECOMPUTED_NEW_RECONSTRUCTED_INPUT_NO_HISTORICAL_PASS": return Terrain.fail("Unsupported basic water status")
	if derived and raw.get("recovery_status") != "NEW_DERIVED_FULL_WORLD_NO_HISTORICAL_PASS": return Terrain.fail("Unsupported derived water status")
	if not Terrain.hash_string(raw.get("semantic_hash")): return Terrain.fail("Invalid water semantic hash")
	if not raw.get("upstream") is Dictionary or raw.upstream.get("mesh_semantic_hash") != world.semantic_hash or raw.upstream.get("mesh_sha256") != world.file_sha256: return Terrain.fail("Water/terrain upstream hash mismatch")
	if raw.get("seed") != world.seed or raw.get("playable_radius") != world.radius: return Terrain.fail("Water/terrain seed/radius mismatch")
	if not raw.get("stages") is Dictionary or raw.stages.get("climate") != "NOT_DONE" or raw.stages.get("rivers") != "NOT_DONE" or raw.stages.get("final_dry") != "NOT_DONE": return Terrain.fail("Unsupported water stage contract")
	for field in ["bodies", "footprints", "failures_80"]:
		if not raw.get(field) is Array: return Terrain.fail("Missing water " + field)
	if raw.bodies.size() > MAX_BODIES or raw.footprints.size() > MAX_FOOTPRINTS: return Terrain.fail("Water resource budget exceeded")
	var bodies := {}
	var ocean_count := 0
	var lake_count := 0
	for row in raw.bodies:
		if not row is Dictionary or not Terrain.short_id(row.get("id")) or bodies.has(row.id): return Terrain.fail("Invalid/duplicate water body")
		if not row.get("kind") in ["ocean", "lake_candidate"] or not Terrain.finite_number(row.get("surface_level"), Terrain.MAX_HEIGHT): return Terrain.fail("Invalid water type/level")
		if not Terrain.finite_number(row.get("area_xz"), 20000.0) or row.area_xz <= 0: return Terrain.fail("Invalid water body area")
		if row.kind == "ocean":
			if row.surface_level != 0.0 or row.get("status") != "CONFIRMED_BOUNDARY_CONNECTED_NEGATIVE_PL" or not row.id.begins_with("ocean:"): return Terrain.fail("Invalid confirmed ocean contract")
			ocean_count += 1
		else:
			if row.get("status") != "FULL_RESERVOIR_CANDIDATE_NO_CLIMATE" or not row.id.begins_with("lake:"): return Terrain.fail("Invalid full-reservoir candidate contract")
			lake_count += 1
		bodies[row.id] = {"id": row.id, "kind": row.kind, "surface_level": float(row.surface_level), "area_xz": float(row.area_xz), "status": row.status}
	var footprints := []
	var by_face := {}
	var body_area := {}
	var unique := {}
	var triangles := 0
	for row in raw.footprints:
		if not row is Dictionary or not bodies.has(row.get("body_id", "")) or not Terrain.integer(row.get("face"), 0, world.face_ids.size() - 1): return Terrain.fail("Invalid footprint body/face")
		var key: String = row.body_id + "/" + str(int(row.face))
		if unique.has(key): return Terrain.fail("Duplicate footprint")
		unique[key] = true
		if not row.get("polygon_xz") is Array or not row.polygon_xz.size() in [3, 4]: return Terrain.fail("PL footprint must have 3 or 4 vertices")
		var polygon := PackedVector2Array()
		var fi := int(row.face)
		var level: float = bodies[row.body_id].surface_level
		var a: Vector3 = world.positions[world.indices[fi * 3]]
		var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
		var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
		var u := Vector2(b.x - a.x, b.z - a.z)
		var v := Vector2(c.x - a.x, c.z - a.z)
		var det := u.cross(v)
		for pp in row.polygon_xz:
			if not pp is Array or pp.size() != 2 or not Terrain.finite_number(pp[0]) or not Terrain.finite_number(pp[1]): return Terrain.fail("Invalid/nonfinite water polygon")
			var p := Vector2(float(pp[0]), float(pp[1]))
			var rel := p - Vector2(a.x, a.z)
			var wb := rel.cross(v) / det
			var wc := u.cross(rel) / det
			if wb < -0.0002 or wc < -0.0002 or wb + wc > 1.0002: return Terrain.fail("Water polygon escapes its stored source triangle")
			var height := a.y * (1.0 - wb - wc) + b.y * wb + c.y * wc
			if height > level + 0.00004: return Terrain.fail("Water footprint includes above-level terrain")
			polygon.append(p)
		var area := polygon_area(polygon)
		if area <= 0.0 or not Terrain.finite_number(row.get("area_xz"), 1.0) or absf(area - float(row.area_xz)) > 0.00001: return Terrain.fail("Invalid/negative water footprint area")
		# All admitted source footprint polygons are convex triangle halfspace clips.
		for j in range(polygon.size()):
			if (polygon[(j + 1) % polygon.size()] - polygon[j]).cross(polygon[(j + 2) % polygon.size()] - polygon[(j + 1) % polygon.size()]) < -0.000001: return Terrain.fail("Nonconvex water footprint")
		var record := {"body_id": row.body_id, "face": fi, "polygon": polygon, "level": level, "kind": bodies[row.body_id].kind}
		var idx := footprints.size()
		footprints.append(record)
		if not by_face.has(fi): by_face[fi] = PackedInt32Array()
		by_face[fi].append(idx)
		body_area[row.body_id] = body_area.get(row.body_id, 0.0) + float(row.area_xz)
		triangles += polygon.size() - 2
	if triangles > 240000: return Terrain.fail("Water triangle resource budget exceeded")
	for id in bodies:
		if absf(body_area.get(id, 0.0) - bodies[id].area_xz) > 0.00002: return Terrain.fail("Water body/footprint area mismatch")
	var policy_stats := {}
	if derived:
		if world.declared_policy.is_empty() or not raw.get("per_hex") is Array: return Terrain.fail("Missing derived policy fractions")
		var seen := {}
		var land_count := 0
		var main_count := 0
		var land_min := 1.0
		var main_min := 1.0
		var policy_failures := 0
		for row in raw.per_hex:
			if not row is Dictionary or not world.cells.has(row.get("hex", "")) or seen.has(row.hex) or not world.cells[row.hex].playable: return Terrain.fail("Invalid policy hex row")
			seen[row.hex] = true
			for field in ["stage_dry_fraction", "lake_fraction", "ocean_fraction"]:
				if not Terrain.finite_number(row.get(field), 1.000001) or row[field] < -0.000001: return Terrain.fail("Invalid policy fraction")
			if world.declared_policy.main_cells.has(row.hex):
				main_count += 1
				main_min = minf(main_min, float(row.lake_fraction))
				if row.lake_fraction < world.declared_policy.main_water_minimum - 0.000001: policy_failures += 1
			elif world.cells[row.hex].domain == "land":
				land_count += 1
				land_min = minf(land_min, float(row.stage_dry_fraction))
				if row.stage_dry_fraction < world.declared_policy.land_minimum - 0.000001: policy_failures += 1
			elif row.ocean_fraction < world.declared_policy.ocean_minimum - 0.000001: policy_failures += 1
		if main_count != world.declared_policy.main_cells.size(): return Terrain.fail("Incomplete declared main lake fractions")
		policy_stats = {"land_hexes": land_count, "main_hexes": main_count, "land_minimum_actual": land_min, "main_lake_minimum_actual": main_min, "failures": policy_failures, "raw_original_domain_failures": raw.failures_80.size()}
	return {"ok": true, "water": {"format": raw.format, "version": raw.snapshot_version, "declared_policy_stats": policy_stats, "semantic_hash": raw.semantic_hash, "file_sha256": "", "source_path": "", "bodies": bodies, "footprints": footprints, "by_face": by_face, "triangles": triangles, "oceans": ocean_count, "lake_candidates": lake_count, "failed_land_80": raw.failures_80.size(), "stages": raw.stages}}

static func polygon_area(polygon: PackedVector2Array) -> float:
	var first := polygon[0]
	var area := 0.0
	for j in range(1, polygon.size() - 1):
		var a := polygon[j] - first
		var b := polygon[j + 1] - first
		area += float(a.x) * float(b.y) - float(a.y) * float(b.x)
	return area * 0.5

static func surface_at(water: Dictionary, fi: int, p: Vector2) -> Dictionary:
	for idx in water.get("by_face", {}).get(fi, PackedInt32Array()):
		var footprint: Dictionary = water.footprints[idx]
		if Geometry2D.is_point_in_polygon(p, footprint.polygon):
			return {"ok": true, "height": footprint.level, "body_id": footprint.body_id, "kind": footprint.kind}
	return {"ok": false}
