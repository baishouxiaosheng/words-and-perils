extends RefCounted
## Geometry observations only. No movement result, traversal rule or path search.
## Existing lake water is deliberately absent and must be queried by its owner.
const CANDIDATE_SHA := "67846dad7766df69850fd16651231da07d783a271f3734f292a7f613a1b96b1a"
const QUERY_SHA := "31a99c53bd4fa5e2e93fa0ef2760aca8ce173c2b852a3f3f1c41753a79943a00"
# Input world vectors/cache are f32. This is a boundary contact tolerance, not width.
const CONTACT_TOLERANCE_WORLD := 0.000002
var last_error := ""
var polygons: Array = []
var water_bodies: Dictionary = {}
var ready := false
var bounds: Array = []

func load_file(path: String, expected_sha: String = QUERY_SHA) -> bool:
	ready = false
	last_error = ""
	polygons.clear()
	bounds.clear()
	if not FileAccess.file_exists(path):
		last_error = "Missing readonly river-water query summary"
		return false
	if not expected_sha.is_empty() and FileAccess.get_sha256(path) != expected_sha:
		last_error = "River-water query summary SHA mismatch"
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema","") != "actual-new-river-water-query-1" or data.get("candidate_sha256","") != CANDIDATE_SHA:
		last_error = "River-water query candidate/schema mismatch"
		return false
	polygons.clear()
	for row in data["polygons"]:
		var points: Array = row["polygon_xz"]
		if points.size() < 3:
			last_error = "Degenerate river-water query polygon"
			return false
		var signed_area := 0.0
		var p0: Array = points[0]
		for i in range(1,points.size()-1):
			signed_area += (points[i][0]-p0[0])*(points[i+1][1]-p0[1])-(points[i][1]-p0[1])*(points[i+1][0]-p0[0])
		if absf(signed_area) < 1e-20: continue
		for p in points:
			if bounds.is_empty(): bounds = [p[0],p[1],p[0],p[1]]
			else:
				bounds[0] = minf(bounds[0],p[0])
				bounds[1] = minf(bounds[1],p[1])
				bounds[2] = maxf(bounds[2],p[0])
				bounds[3] = maxf(bounds[3],p[1])
		var record: Dictionary = row.duplicate(true)
		record["orientation"] = 1.0 if signed_area > 0 else -1.0
		polygons.append(record)
	water_bodies = {"source":data["source_body"],"receiver":data["receiver_body"]}
	ready = true
	return true

func _overlaps_bounds(a: Vector2, b: Vector2) -> bool:
	return not bounds.is_empty() and maxf(a.x,b.x)>=bounds[0]-CONTACT_TOLERANCE_WORLD and minf(a.x,b.x)<=bounds[2]+CONTACT_TOLERANCE_WORLD and maxf(a.y,b.y)>=bounds[1]-CONTACT_TOLERANCE_WORLD and minf(a.y,b.y)<=bounds[3]+CONTACT_TOLERANCE_WORLD

func _segment_interval(from_xz: Vector2, to_xz: Vector2, row: Dictionary) -> Array:
	# Convex half-plane clipping keeps real saved polygon vertices as doubles.
	var lo := 0.0
	var hi := 1.0
	var points: Array = row["polygon_xz"]
	var orientation: float = row["orientation"]
	for i in range(points.size()):
		var a: Array = points[i]
		var b: Array = points[(i+1)%points.size()]
		var dx: float = b[0]-a[0]
		var dz: float = b[1]-a[1]
		var length := sqrt(dx*dx+dz*dz)
		if length < 1e-14: continue
		var v0: float = orientation*(dx*(from_xz.y-a[1])-dz*(from_xz.x-a[0]))/length
		var v1: float = orientation*(dx*(to_xz.y-a[1])-dz*(to_xz.x-a[0]))/length
		var t0 := v0+CONTACT_TOLERANCE_WORLD
		var t1 := v1+CONTACT_TOLERANCE_WORLD
		if t0 < 0 and t1 < 0: return []
		if t0 < 0: lo = maxf(lo,t0/(t0-t1))
		if t1 < 0: hi = minf(hi,t0/(t0-t1))
		if lo > hi: return []
	return [lo,hi]

func water_endpoint_context(xz: Vector2) -> Dictionary:
	if not ready: return {"ok":false,"error":last_error,"is_new_river_water":false}
	var hits: Array = []
	var candidate_rows: Array = polygons if _overlaps_bounds(xz,xz) else []
	for row in candidate_rows:
		if not _segment_interval(xz,xz,row).is_empty():
			hits.append({"original_face":row["original_face"],"original_hex_id":row["original_hex_id"]})
	return {"ok":true,"is_new_river_water":not hits.is_empty(),"requires_separate_adjudication":not hits.is_empty(),"position_xz":xz,"source_faces":hits,"water_bodies":water_bodies.duplicate(true),"scope":"NEW_RIVER_ONLY_EXISTING_LAKES_CHECKED_SEPARATELY","boundary_contact_tolerance_world":CONTACT_TOLERANCE_WORLD,"movement_result_decided":false}

func segment_intersects_water(from_xz: Vector2, to_xz: Vector2) -> Dictionary:
	if not ready: return {"ok":false,"error":last_error,"intersects":false}
	var hits: Array = []
	var intervals: Array = []
	var source_faces: Array = []
	var candidate_rows: Array = polygons if _overlaps_bounds(from_xz,to_xz) else []
	for row in candidate_rows:
		var interval := _segment_interval(from_xz,to_xz,row)
		if interval.is_empty(): continue
		intervals.append(interval)
		var fi := int(row["original_face"])
		if not source_faces.has(fi): source_faces.append(fi)
		hits.append({"from_t":interval[0],"to_t":interval[1],"original_face":fi,"original_hex_id":row["original_hex_id"]})
	intervals.sort_custom(func(a,b): return a[0]<b[0])
	var merged: Array = []
	for interval in intervals:
		if merged.is_empty() or interval[0] > merged[-1][1]+1e-9:
			merged.append(interval.duplicate())
		else: merged[-1][1] = maxf(merged[-1][1],interval[1])
	var length_inside := 0.0
	for interval in merged: length_inside += (interval[1]-interval[0])*from_xz.distance_to(to_xz)
	var start_context := water_endpoint_context(from_xz)
	var end_context := water_endpoint_context(to_xz)
	return {"ok":true,"intersects":not hits.is_empty(),"requires_separate_adjudication":not hits.is_empty(),"start_in_new_water":start_context["is_new_river_water"],"end_in_new_water":end_context["is_new_river_water"],"parameter_intervals":merged,"contact_length_world":length_inside,"original_faces":source_faces,"contacts":hits,"water_bodies":water_bodies.duplicate(true),"scope":"NEW_RIVER_ONLY_EXISTING_LAKES_CHECKED_SEPARATELY","boundary_contact_tolerance_world":CONTACT_TOLERANCE_WORLD,"movement_result_decided":false}

func nearest_dry_candidate(origin_xz: Vector2, prevalidated_candidates: Array) -> Dictionary:
	# Caller must already validate terrain, old lakes and its own movement rules.
	# This chooses among supplied candidates only and never invents a new anchor.
	if not ready: return {"ok":false,"error":last_error,"found":false}
	var best_index := -1
	var best_distance := INF
	var best := Vector2.ZERO
	for i in range(prevalidated_candidates.size()):
		var value = prevalidated_candidates[i]
		var p: Vector2
		if value is Vector2: p = value
		elif value is Array and value.size() == 2: p = Vector2(value[0],value[1])
		else: continue
		if water_endpoint_context(p)["is_new_river_water"]: continue
		var distance := origin_xz.distance_to(p)
		if distance < best_distance:
			best_index = i
			best_distance = distance
			best = p
	return {"ok":true,"found":best_index>=0,"candidate_index":best_index,"position_xz":best,"distance_world":best_distance if best_index>=0 else null,"scope":"ONLY_FILTERS_NEW_RIVER_FROM_CALLER_PREVALIDATED_CANDIDATES","movement_result_decided":false}
