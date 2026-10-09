extends RefCounted
## Physical observations from the exact visible sea + river water triangles.
## This is not a crossing capability. Navigation decides how contacts are used.
const ID = "generated_v3_actual_water_contacts/v1"
const CONTACT_EPS = 0.000004
const MAX_TRIANGLES = 65536
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var ready: bool = false
var water_hash: String = ""
var faces: Array = []
var bins: Dictionary = {}
var diagnostics: Dictionary = {}

func build(mesh: ArrayMesh, expected_hash: String) -> Dictionary:
	ready = false; water_hash = ""; faces.clear(); bins.clear(); diagnostics.clear()
	if mesh == null or mesh.get_surface_count() != 1:
		return C.fail("RIVER_WATER_MESH", "Physical water requires one exact visible triangle surface.")
	var arrays: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if ids.is_empty():
		for index in range(vs.size()): ids.append(index)
	if ids.is_empty() or ids.size() % 3 != 0 or ids.size() / 3 > MAX_TRIANGLES:
		return C.fail("RIVER_WATER_BOUNDS", "Physical water triangle count is invalid.")
	var expanded := PackedVector3Array()
	for index in ids:
		if index < 0 or index >= vs.size() or not vs[index].is_finite():
			return C.fail("RIVER_WATER_VERTEX", "Physical water has an invalid vertex or index.")
		expanded.append(vs[index])
	var hashing := HashingContext.new(); hashing.start(HashingContext.HASH_SHA256); hashing.update(expanded.to_byte_array())
	water_hash = hashing.finish().hex_encode()
	if water_hash != expected_hash:
		return C.fail("RIVER_WATER_HASH", "Visible water differs from its exact geometry identity.")
	for i in range(0, ids.size(), 3):
		var face: Array = [vs[ids[i]], vs[ids[i + 1]], vs[ids[i + 2]]]
		var signed: float = cross2(xz(face[1]) - xz(face[0]), xz(face[2]) - xz(face[0]))
		if signed <= 0.00000000000001:
			return C.fail("RIVER_WATER_TRIANGLE", "Visible water has an inverted or degenerate projected triangle.")
		for p: Vector3 in face:
			if p.y < -CONTACT_EPS:
				return C.fail("RIVER_WATER_LEVEL", "This river profile does not admit below-sea water surfaces.")
		var id: int = faces.size(); faces.append(face)
		for key in bucket_keys([xz(face[0]), xz(face[1]), xz(face[2])], CONTACT_EPS):
			if not bins.has(key): bins[key] = []
			bins[key].append(id)
	ready = true
	diagnostics = {"query_id":ID, "water_hash":water_hash, "water_triangles":faces.size(), "bins":bins.size(), "contact_epsilon":CONTACT_EPS, "authority":"exact visible projected sea and elevated river triangles", "crossing_capability":false}
	return {"ok":true, "diagnostics":diagnostics.duplicate(true)}

static func xz(p: Vector3) -> Vector2: return Vector2(p.x, p.z)
static func cross2(a: Vector2, b: Vector2) -> float: return float(a.x) * float(b.y) - float(a.y) * float(b.x)

static func bucket_keys(points: Array, margin: float = 0.0) -> Array:
	var low: Vector2 = points[0]; var high: Vector2 = points[0]
	for point: Vector2 in points: low = low.min(point); high = high.max(point)
	var result: Array = []
	for x in range(floori(low.x - margin), floori(high.x + margin) + 1):
		for z in range(floori(low.y - margin), floori(high.y + margin) + 1): result.append("%d,%d" % [x,z])
	return result

func candidates(points: Array, margin: float) -> Array:
	var found: Dictionary = {}
	for key in bucket_keys(points, margin + CONTACT_EPS):
		for id in bins.get(key, []): found[id] = true
	var result: Array = found.keys(); result.sort(); return result

static func inside(point: Vector2, face: Array) -> bool:
	for i in range(3):
		var a: Vector2 = xz(face[i]); var edge: Vector2 = xz(face[(i + 1) % 3]) - a
		if cross2(edge, point - a) < -CONTACT_EPS * edge.length(): return false
	return true

static func height(point: Vector2, face: Array) -> float:
	var a: Vector2 = xz(face[0]); var b: Vector2 = xz(face[1]); var c: Vector2 = xz(face[2])
	var determinant: float = cross2(b - a, c - a)
	var v: float = cross2(point - a, c - a) / determinant
	var w: float = cross2(b - a, point - a) / determinant
	return float(face[0].y) * (1.0 - v - w) + float(face[1].y) * v + float(face[2].y) * w

static func point_segment_distance_squared(p: Vector2, a: Vector2, b: Vector2) -> float:
	var dx: float = float(b.x) - float(a.x); var dz: float = float(b.y) - float(a.y)
	var length_squared: float = dx * dx + dz * dz
	if length_squared <= 0.0000000000000001: return p.distance_squared_to(a)
	var t: float = clampf(((float(p.x)-float(a.x))*dx + (float(p.y)-float(a.y))*dz)/length_squared, 0.0, 1.0)
	var px: float = float(p.x) - float(a.x) - t * dx; var pz: float = float(p.y) - float(a.y) - t * dz
	return px * px + pz * pz

static func point_triangle_distance_squared(p: Vector2, face: Array) -> float:
	if inside(p, face): return 0.0
	var best: float = INF
	for i in range(3): best = minf(best, point_segment_distance_squared(p, xz(face[i]), xz(face[(i+1)%3])))
	return best

static func triangle_interval(start: Vector2, finish: Vector2, face: Array) -> Array:
	var low: float = 0.0; var high: float = 1.0
	for i in range(3):
		var a: Vector2 = xz(face[i]); var edge: Vector2 = xz(face[(i+1)%3]) - a
		var epsilon: float = CONTACT_EPS * edge.length()
		var f0: float = cross2(edge, start-a) + epsilon
		var f1: float = cross2(edge, finish-a) + epsilon
		if f0 < 0.0 and f1 < 0.0: return []
		if absf(f1-f0) <= 0.000000000001: continue
		var t: float = -f0/(f1-f0)
		if f1 > f0: low = maxf(low,t)
		else: high = minf(high,t)
		if low > high: return []
	return [clampf(low,0.0,1.0),clampf(high,0.0,1.0)]

static func segment_triangle_distance_squared(start: Vector2, finish: Vector2, face: Array) -> float:
	if not triangle_interval(start,finish,face).is_empty(): return 0.0
	var best: float = minf(point_triangle_distance_squared(start,face),point_triangle_distance_squared(finish,face))
	for p: Vector3 in face: best = minf(best,point_segment_distance_squared(xz(p),start,finish))
	return best

func point_contact(point: Vector2, radius: float = 0.0) -> Dictionary:
	if not ready: return C.fail("WATER_QUERY_FAILED", "Physical water is not admitted.")
	if not point.is_finite() or not is_finite(radius) or radius < 0.0 or radius > 2.0:
		return C.fail("WATER_QUERY_FAILED", "Invalid physical water point or clearance.")
	var limit: float = (radius+CONTACT_EPS)*(radius+CONTACT_EPS)
	for id in candidates([point],radius):
		var distance_squared: float = point_triangle_distance_squared(point,faces[id])
		if distance_squared <= limit:
			return {"ok":true,"intersects":true,"triangle_id":id,"distance":sqrt(maxf(0.0,distance_squared)),"radius":radius,"water_hash":water_hash,"crossing_capability":false}
	return {"ok":true,"intersects":false,"radius":radius,"water_hash":water_hash,"crossing_capability":false}

func segment_contact(start: Vector2, finish: Vector2, radius: float = 0.0) -> Dictionary:
	if not ready: return C.fail("WATER_QUERY_FAILED", "Physical water is not admitted.")
	if not start.is_finite() or not finish.is_finite() or not is_finite(radius) or radius < 0.0 or radius > 2.0:
		return C.fail("WATER_QUERY_FAILED", "Invalid physical water segment or clearance.")
	var limit: float = (radius+CONTACT_EPS)*(radius+CONTACT_EPS)
	for id in candidates([start,finish],radius):
		var distance_squared: float = segment_triangle_distance_squared(start,finish,faces[id])
		if distance_squared <= limit:
			return {"ok":true,"intersects":true,"triangle_id":id,"distance":sqrt(maxf(0.0,distance_squared)),"radius":radius,"water_hash":water_hash,"crossing_capability":false}
	return {"ok":true,"intersects":false,"radius":radius,"water_hash":water_hash,"crossing_capability":false}

func water_height_at(point: Vector2) -> Dictionary:
	if not ready or not point.is_finite(): return C.fail("WATER_QUERY_FAILED", "Physical water is not admitted or point is invalid.")
	var level: float = -INF; var face_id: int = -1
	for id in candidates([point],0.0):
		if not inside(point,faces[id]): continue
		var value: float = height(point,faces[id])
		if value > level: level = value; face_id = id
	return {"ok":true,"wet":face_id>=0,"height":level if face_id>=0 else null,"triangle_id":face_id,"water_hash":water_hash}
