extends RefCounted
## New, read-only PL geometry adapter. Never configures Game/TerrainField.
const FORMAT := "EXPERIMENTAL_HEX_HEIGHT_MESH"
const VERSION := "hex-conforming-height-mesh-reconstructed-0.3.0"
const DERIVED_FORMAT := "EXPERIMENTAL_REBUILT_HEX_LAKE_PORTS_HEIGHT_MESH"
const DERIVED_VERSION := "hex-rebuilt-lake-ports-height-mesh-0.3.0"
const MAX_BYTES := 128 * 1024 * 1024
const MAX_VERTICES := 90000
const MAX_FACES := 180000
const MAX_CELLS := 3000
const MAX_EDGES := 10000
const MAX_COORD := 512.0
const MAX_HEIGHT := 128.0

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
static func finite_number(value: Variant, bound: float = MAX_COORD) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= bound
static func integer(value: Variant, low: int, high: int) -> bool:
	return finite_number(value, float(maxi(absi(low), absi(high)))) and float(value) == floor(float(value)) and value >= low and value <= high
static func short_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 192
static func hash_string(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return fail("Input not found: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return fail("Cannot open input")
	if file.get_length() <= 0 or file.get_length() > MAX_BYTES: return fail("Input byte budget exceeded")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return fail("Invalid JSON: " + parser.get_error_message())
	var result := decode(parser.data)
	if result.ok:
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(bytes)
		result.world.file_sha256 = hashing.finish().hex_encode()
		result.world.source_path = path
	return result
static func decode(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return fail("Root must be an object")
	var basic: bool = raw.get("format") == FORMAT and raw.get("geometry_version") == VERSION
	var derived: bool = raw.get("format") == DERIVED_FORMAT and raw.get("geometry_version") == DERIVED_VERSION
	if not basic and not derived: return fail("Unsupported geometry schema/version")
	if raw.get("production_world", true) != false or raw.get("production_sampler_compatible", true) != false: return fail("Experimental data must not claim production compatibility")
	if basic and not raw.get("recovery_status") in ["REBUILT_NEW_DATA_NO_HISTORICAL_PASS", "VIEWER_TEST_FIXTURE"]: return fail("Unknown basic recovery status")
	if derived and raw.get("recovery_status") != "NEW_DERIVED_REAL_HEIGHT_NO_HISTORICAL_PASS": return fail("Unknown derived recovery status")
	if not hash_string(raw.get("semantic_hash")): return fail("Missing valid semantic hash")
	if not integer(raw.get("seed"), -2147483648, 2147483647): return fail("Invalid seed")
	if not integer(raw.get("playable_radius"), 0, 24) or not finite_number(raw.get("hex_radius"), 4.0) or float(raw.hex_radius) != 1.0: return fail("Unsupported hex scale/radius")
	for field in ["vertices", "faces", "cells", "canonical_edges", "boundary_loop"]:
		if not raw.get(field) is Array or raw[field].is_empty(): return fail("Missing nonempty " + field)
	if raw.vertices.size() > MAX_VERTICES or raw.faces.size() > MAX_FACES or raw.cells.size() > MAX_CELLS or raw.canonical_edges.size() > MAX_EDGES: return fail("Geometry resource budget exceeded")
	if raw.recovery_status != "VIEWER_TEST_FIXTURE" and raw.faces.size() != raw.cells.size() * 36: return fail("Incomplete finite-template face count")
	if not integer(raw.get("halo_radius"), 1, 25) or int(raw.halo_radius) != int(raw.playable_radius) + 1: return fail("Invalid halo extent")
	if raw.recovery_status != "VIEWER_TEST_FIXTURE" and raw.cells.size() != 1 + 3 * int(raw.halo_radius) * (int(raw.halo_radius) + 1): return fail("Incomplete canonical hex domain")
	var positions := PackedVector3Array()
	var vertex_ids := {}
	var index_ids := PackedStringArray()
	var bounds := AABB()
	for row in raw.vertices:
		if not row is Dictionary or not short_id(row.get("id")) or vertex_ids.has(row.id): return fail("Invalid/duplicate vertex ID")
		if not row.get("xz") is Array or row.xz.size() != 2 or not finite_number(row.xz[0]) or not finite_number(row.xz[1]) or not finite_number(row.get("designed_height"), MAX_HEIGHT): return fail("Invalid/nonfinite vertex")
		var p := Vector3(float(row.xz[0]), float(row.designed_height), float(row.xz[1]))
		vertex_ids[row.id] = positions.size()
		index_ids.append(row.id)
		positions.append(p)
		if positions.size() == 1: bounds = AABB(p, Vector3.ZERO)
		else: bounds = bounds.expand(p)
	var cells := {}
	for row in raw.cells:
		if not row is Dictionary or not integer(row.get("q"), -25, 25) or not integer(row.get("r"), -25, 25): return fail("Invalid hex coordinate")
		var cid := "hex:%d,%d" % [int(row.q), int(row.r)]
		if row.get("id") != cid or cells.has(cid) or not row.get("playable") is bool: return fail("Invalid/duplicate canonical hex")
		if not row.get("domain") in ["land", "water_candidate"]: return fail("Unknown geometry domain")
		if not row.get("original_hex") is Array or row.original_hex.size() != 6: return fail("Missing canonical hex polygon")
		var axial_radius := maxi(absi(int(row.q)), maxi(absi(int(row.r)), absi(int(row.q) + int(row.r))))
		if axial_radius > int(raw.halo_radius) or row.playable != (axial_radius <= int(raw.playable_radius)): return fail("Hex outside declared domain/playable extent")
		var offsets := [Vector2(1,1), Vector2(0,2), Vector2(-1,1), Vector2(-1,-1), Vector2(0,-2), Vector2(1,-1)]
		for j in range(6):
			var p: Variant = row.original_hex[j]
			if not p is Array or p.size() != 2 or not finite_number(p[0]) or not finite_number(p[1]): return fail("Invalid canonical hex polygon")
			var expected := Vector2((2.0 * row.q + row.r + offsets[j].x) * sqrt(3.0) / 2.0, (3.0 * row.r + offsets[j].y) / 2.0)
			if Vector2(float(p[0]), float(p[1])).distance_to(expected) > 0.00002: return fail("Canonical hex geometry disagrees with q/r")
		cells[cid] = {"id": cid, "q": int(row.q), "r": int(row.r), "playable": row.playable, "domain": row.domain, "original_hex": row.original_hex}
	var playable_count := 0
	for id in cells:
		if cells[id].playable: playable_count += 1
	var owner_counts := {}
	var indices := PackedInt32Array()
	var face_ids := PackedStringArray()
	var face_owners := PackedStringArray()
	var unique_faces := {}
	var buckets := {}
	for row in raw.faces:
		if not row is Dictionary or not short_id(row.get("id")) or unique_faces.has(row.id) or not cells.has(row.get("owner", "")): return fail("Invalid/duplicate face or owner")
		if not row.get("vertices") is Array or row.vertices.size() != 3: return fail("Face must have 3 indices")
		for idx in row.vertices:
			if not integer(idx, 0, positions.size() - 1): return fail("Face index out of bounds")
		var a: Vector3 = positions[int(row.vertices[0])]
		var b: Vector3 = positions[int(row.vertices[1])]
		var c: Vector3 = positions[int(row.vertices[2])]
		var owner: Dictionary = cells[row.owner]
		var center := Vector2(sqrt(3.0) * (owner.q + owner.r * 0.5), 1.5 * owner.r)
		for p in [a,b,c]:
			if Vector2(p.x,p.z).distance_to(center) > 1.00002: return fail("Face escapes its canonical owner neighborhood")
		owner_counts[row.owner] = owner_counts.get(row.owner, 0) + 1
		var area := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
		if area <= 0.00000001: return fail("Nonpositive/degenerate XZ triangle")
		var fi := face_ids.size()
		for idx in row.vertices: indices.append(int(idx))
		face_ids.append(row.id)
		face_owners.append(row.owner)
		unique_faces[row.id] = true
		var x0 := floori(minf(a.x, minf(b.x, c.x)) / 2.0)
		var x1 := floori(maxf(a.x, maxf(b.x, c.x)) / 2.0)
		var z0 := floori(minf(a.z, minf(b.z, c.z)) / 2.0)
		var z1 := floori(maxf(a.z, maxf(b.z, c.z)) / 2.0)
		if x1 - x0 > 3 or z1 - z0 > 3: return fail("Face spatial budget exceeded")
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var key := Vector2i(x, z)
				if not buckets.has(key): buckets[key] = PackedInt32Array()
				buckets[key].append(fi)
	if raw.recovery_status != "VIEWER_TEST_FIXTURE":
		for id in cells:
			if owner_counts.get(id,0) != 36: return fail("Incomplete finite-template face ownership")
	var edges := []
	var edge_ids := {}
	for row in raw.canonical_edges:
		if not row is Dictionary or not short_id(row.get("id")) or edge_ids.has(row.id): return fail("Invalid/duplicate canonical edge")
		if not row.get("path_vertices") is Array or row.path_vertices.size() != 5: return fail("Canonical edge must have 5 stored vertices")
		var edge := PackedInt32Array()
		for idx in row.path_vertices:
			if not integer(idx, 0, positions.size() - 1): return fail("Edge index out of bounds")
			edge.append(int(idx))
		edges.append(edge)
		edge_ids[row.id] = true
	for idx in raw.boundary_loop:
		if not integer(idx, 0, positions.size() - 1): return fail("Boundary index out of bounds")
	if bounds.size.x <= 0 or bounds.size.z <= 0: return fail("Empty geometry bounds")
	var policy := {}
	if derived:
		if not raw.get("lake_policy") is Dictionary or not raw.lake_policy.get("main_cells") is Dictionary or not raw.get("rebuilt_lake_ports") is Dictionary or not raw.rebuilt_lake_ports.get("config") is Dictionary: return fail("Missing explicit derived policy")
		var config: Dictionary = raw.rebuilt_lake_ports.config
		for field in ["minimum_stage_dry_fraction", "minimum_main_water_fraction", "minimum_ocean_fraction"]:
			if not finite_number(config.get(field), 1.0) or config[field] <= 0.0: return fail("Invalid declared policy threshold")
		for id in raw.lake_policy.main_cells:
			if not cells.has(id) or not cells[id].playable or not short_id(raw.lake_policy.main_cells[id]): return fail("Invalid declared main lake hex")
		policy = {"main_cells": raw.lake_policy.main_cells, "land_minimum": float(config.minimum_stage_dry_fraction), "main_water_minimum": float(config.minimum_main_water_fraction), "ocean_minimum": float(config.minimum_ocean_fraction), "source_acceptance": str(raw.rebuilt_lake_ports.get("acceptance_status", "PENDING"))}
	return {"ok": true, "world": {"format": raw.format, "version": raw.geometry_version, "declared_policy": policy, "semantic_hash": raw.semantic_hash, "seed": int(raw.seed), "radius": int(raw.playable_radius), "fixture": raw.recovery_status == "VIEWER_TEST_FIXTURE", "positions": positions, "vertex_ids": index_ids, "indices": indices, "face_ids": face_ids, "face_owners": face_owners, "cells": cells, "playable_count": playable_count, "halo_count": cells.size() - playable_count, "edges": edges, "boundary_loop": raw.boundary_loop, "bounds": bounds, "buckets": buckets, "hydrology_status": str(raw.get("hydrology_status", "NOT_DONE")), "climate_status": str(raw.get("climate_status", "NOT_DONE")), "material_status": str(raw.get("material_status", "NOT_DONE")), "file_sha256": "", "source_path": ""}}

static func height_at(world: Dictionary, point: Vector2) -> Dictionary:
	var key := Vector2i(floori(point.x / 2.0), floori(point.y / 2.0))
	for fi in world.buckets.get(key, PackedInt32Array()):
		var a: Vector3 = world.positions[world.indices[fi * 3]]
		var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
		var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
		var u := Vector2(b.x - a.x, b.z - a.z)
		var v := Vector2(c.x - a.x, c.z - a.z)
		var p := point - Vector2(a.x, a.z)
		var det := u.cross(v)
		var wb := p.cross(v) / det
		var wc := u.cross(p) / det
		if wb >= -0.000001 and wc >= -0.000001 and wb + wc <= 1.000001:
			return {"ok": true, "height": a.y * (1.0 - wb - wc) + b.y * wb + c.y * wc, "face": fi, "owner": world.face_owners[fi]}
	return {"ok": false}

static func ray_pick(world: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	# Face triangle is the source of truth, never the old continuous macro sampler.
	var nearest := INF
	var answer := {"ok": false}
	if world.is_empty(): return answer
	var bounds: AABB = world.bounds.grow(0.001)
	var intersect: Variant = bounds.intersects_ray(origin, direction)
	if intersect == null: return answer
	var candidates := {}
	# XZ traversal uses bounded 1-unit samples. Each 2-unit bucket contains all
	# triangles intersecting it. Include neighbors for boundary robustness.
	var end := origin + direction * 2048.0
	var ray_start: Vector3 = intersect
	var travel := minf(2048.0, bounds.size.length() * 2.0 + 4.0)
	var horizontal := Vector2(direction.x, direction.z).length()
	var steps := maxi(1, ceili(travel * horizontal))
	for i in range(steps + 1):
		var p := ray_start + direction * (travel * float(i) / float(steps))
		var k := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for fi in world.buckets.get(k + Vector2i(dx, dz), PackedInt32Array()): candidates[fi] = true
	for fi in candidates:
		var a: Vector3 = world.positions[world.indices[fi * 3]]
		var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
		var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
		var p: Variant = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
		if p != null:
			var distance := origin.distance_to(p)
			if distance < nearest:
				nearest = distance
				answer = {"ok": true, "position": p, "height": p.y, "distance": distance, "face": fi, "face_id": world.face_ids[fi], "owner": world.face_owners[fi]}
	return answer
