extends RefCounted
## Research-only native port of the frozen Python structured-hex producer.
## MIT-derived fan/strip/corner construction: David Pruitt (2024).
## See ../ATTRIBUTION.md and ../provenance/upstream/LICENSE.md.txt.
## No I/O, Python, GEOS, seed generation or shared mutable globals.

const VERSION = "v3_structured_hex_gd/1"
const REFERENCE_VERSION = "v3_structured_hex/1"

## Fresh per-call worker; usable by preload without an editor class-name cache.
## Returns {ok, mesh:ArrayMesh, data:Dictionary} or a structured error.
static func build(source: Variant, original: Variant = null) -> Dictionary:
	return BuildWorker.new()._build(source, original)

class BuildWorker:
	extends RefCounted
	const VERSION = "v3_structured_hex_gd/1"
	const REFERENCE_VERSION = "v3_structured_hex/1"
	const MAX_RADIUS = 12
	const MAX_CELLS = 469
	const MAX_ABS_HEIGHT = 16.0
	const MIN_NONZERO_HEIGHT = 0.0000001
	const MAX_TRIANGLES = 65536
	const SOLID = 0.8
	const DIRECTIONS = [[1,0],[0,1],[-1,1],[-1,0],[0,-1],[1,-1]]

	var _vertices: Array = []
	var _indices: Array = []
	var _kinds: Array = []
	var _owners: Array = []
	var _shore: Array = []
	var _lookup: Dictionary = {}
	var _failure: String = ""

	static func _error(code: String, message: String) -> Dictionary:
		return {"ok":false, "error_code":code, "message":message}

	static func _number(value: Variant) -> bool:
		return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

	static func _integer(value: Variant) -> bool:
		return _number(value) and float(value) == floor(float(value))

	static func _center(q: int, r: int) -> Array:
		return [sqrt(3.0) * (float(q) + float(r) / 2.0), 1.5 * float(r)]

	static func _polygon(q: int, r: int) -> Array:
		var center = _center(q,r)
		var result: Array = []
		for i in range(6):
			var angle = float(30+60*i) * (PI/180.0)
			result.append([center[0]+cos(angle),center[1]+sin(angle)])
		return result

	# Seven decimal places, ties-to-even, matching the reference's logical-key scale.
	# Coordinates remain unrounded in the geometry. Integer keys only weld ownership.
	static func _quantize(value: float) -> int:
		var scaled = value * 10000000.0
		var low = floor(scaled)
		var fraction = scaled-low
		if fraction > 0.5 or (fraction == 0.5 and int(low)%2 != 0):
			low += 1.0
		return int(low)

	static func _order(point: Array) -> Array:
		var result: Array = []
		for value in point: result.append(_quantize(value))
		return result

	static func _key(point: Array) -> String:
		var parts = PackedStringArray()
		for value in point: parts.append(str(_quantize(value)))
		return ",".join(parts)

	static func _less(a: Array, b: Array) -> bool:
		for i in range(a.size()):
			if a[i] != b[i]: return a[i] < b[i]
		return false

	static func _lerp(a: Array, b: Array, t: float) -> Array:
		var result: Array = []
		for i in range(a.size()): result.append(a[i]+(b[i]-a[i])*t)
		return result

	static func _edge(a: Array, b: Array) -> Array:
		var result: Array = []
		for t in [0.0,0.25,0.5,0.75,1.0]: result.append(_lerp(a,b,t))
		return result

	static func _zero_mid(a: Array, b: Array) -> Array:
		var result = _lerp(a,b,0.5)
		result[1] = 0.0
		return result

	func _vertex(point: Array) -> int:
		var key = _key(point)
		if not _lookup.has(key):
			_lookup[key] = _vertices.size()
			var packed = Vector3(point[0],point[1],point[2])
			# Add zero to canonicalize negative zero, as in Python f32().
			_vertices.append([float(packed.x)+0.0,float(packed.y)+0.0,float(packed.z)+0.0])
		return _lookup[key]

	func _emit(a: Array,b: Array,c: Array,kind: String,owner: Array) -> void:
		if not _failure.is_empty(): return
		if _kinds.size() >= MAX_TRIANGLES:
			_failure = "construction exceeds MAX_TRIANGLES"
			return
		var ids = [_vertex(a),_vertex(b),_vertex(c)]
		var v0: Array = _vertices[ids[0]]
		var v1: Array = _vertices[ids[1]]
		var v2: Array = _vertices[ids[2]]
		var cross_xz = (v1[0]-v0[0])*(v2[2]-v0[2])-(v1[2]-v0[2])*(v2[0]-v0[0])
		if absf(cross_xz) < 0.00000000000001:
			_failure = "degenerate construction "+kind
			return
		if cross_xz < 0.0:
			var swap = ids[1]
			ids[1] = ids[2]
			ids[2] = swap
		_indices.append_array(ids)
		_kinds.append(kind)
		_owners.append(owner.duplicate())

	func _quad(a: Array,b: Array,c: Array,d: Array,kind: String,owner: Array) -> void:
		_emit(a,b,c,kind,owner)
		_emit(b,d,c,kind,owner)

	func _strip(a: Array,b: Array,kind: String,owner: Array) -> void:
		for j in range(4): _quad(a[j],a[j+1],b[j],b[j+1],kind,owner)

	func _build(source: Variant, original: Variant) -> Dictionary:
		var started = Time.get_ticks_usec()
		if not source is Dictionary: return _error("SOURCE_TYPE","source must be a Dictionary")
		if source.get("schema_version") not in ["coastal_source_v3/prototype1","structured_hex_fixture/v1"]:
			return _error("SCHEMA","unsupported source schema")
		var radius = source.get("board_radius")
		if not _integer(radius) or radius < 0 or radius > MAX_RADIUS:
			return _error("RADIUS","board_radius must be an integer from 0 to 12")
		var supplied = source.get("cells")
		if not supplied is Dictionary: return _error("CELLS_TYPE","cells must be a Dictionary")
		if supplied.is_empty() or supplied.size() > MAX_CELLS:
			return _error("CELL_LIMIT","cells must contain 1 to 469 entries")
		if supplied.size() != 1+3*int(radius)*(int(radius)+1):
			return _error("DOMAIN","this bounded port requires a complete axial disk")
		var recipe = source.get("recipe")
		if not recipe is Dictionary or not recipe.get("id") is String or recipe.id.is_empty() or recipe.id.length() > 128:
			return _error("RECIPE","recipe.id must be a nonempty String of at most 128 characters")
		if source.has("seed") and (not _integer(source.seed) or absf(float(source.seed)) > 2147483647.0):
			return _error("SEED","optional seed must be a finite signed 31-bit integer")
		for field in ["seed_token","content_hash"]:
			if source.has(field) and (not source[field] is String or source[field].length() > 128):
				return _error("METADATA",field+" must be a String of at most 128 characters")
		var cells: Dictionary = {}
		for key in supplied:
			if not key is String or key.length() > 16: return _error("CELL_KEY","cell key must be a bounded q,r string")
			var c = supplied[key]
			if not c is Dictionary: return _error("CELL_TYPE","cell "+key+" must be a Dictionary")
			var q = c.get("q")
			var r = c.get("r")
			if not _integer(q) or not _integer(r): return _error("COORDINATE","cell "+key+" q,r must be finite integers")
			if maxf(absf(float(q)),maxf(absf(float(r)),absf(float(q)+float(r)))) > radius:
				return _error("COORDINATE","cell "+key+" lies outside the declared disk")
			if key != "%d,%d" % [int(q),int(r)]: return _error("CELL_KEY","cell key disagrees with q,r at "+key)
			var elevation = c.get("elevation")
			if not _number(elevation) or absf(float(elevation)) > MAX_ABS_HEIGHT:
				return _error("HEIGHT","cell "+key+" elevation must be finite and within +/-16")
			if elevation != 0.0 and absf(float(elevation)) < MIN_NONZERO_HEIGHT:
				return _error("HEIGHT_PRECISION","nonzero elevations must have magnitude at least 1e-7")
			if not c.get("ocean") is bool: return _error("CLASS_TYPE","cell "+key+" ocean must be bool")
			if c.ocean != (elevation <= 0.0): return _error("CLASS","source class and elevation disagree at "+key)
			cells[key] = {"q":int(q),"r":int(r),"elevation":float(elevation),"sign":-1 if elevation<=0.0 else 1,"center":_center(q,r),"polygon":_polygon(q,r),"neighbors":[]}
		for key in cells:
			var c: Dictionary = cells[key]
			for direction in DIRECTIONS:
				var neighbor = "%d,%d" % [c.q+direction[0],c.r+direction[1]]
				if cells.has(neighbor): c.neighbors.append(neighbor)
		var hexes: Dictionary = {}
		if original != null:
			if not original is Dictionary or original.size() != cells.size():
				return _error("ORIGINAL_DOMAIN","original hexes must match the complete cell domain")
			for key in cells:
				if not original.has(key): return _error("ORIGINAL_DOMAIN","original missing cell "+key)
				var value = original[key]
				var c: Dictionary = cells[key]
				if not value is Dictionary: return _error("ORIGINAL_TYPE","original hex must be a Dictionary at "+key)
				if not _integer(value.get("q")) or not _integer(value.get("r")) or value.q != c.q or value.r != c.r:
					return _error("ORIGINAL_COORDINATE","original coordinates disagree at "+key)
				var expected_class = "water" if c.sign < 0 else "land"
				if value.get("declared_class") != expected_class or not value.get("crop_boundary") is bool:
					return _error("ORIGINAL_CLASS","original class or crop boundary invalid at "+key)
				var polygon = value.get("polygon")
				if not polygon is Array or polygon.size() != 6: return _error("ORIGINAL_POLYGON","original polygon must have 6 points at "+key)
				for i in range(6):
					if not polygon[i] is Array or polygon[i].size() != 2: return _error("ORIGINAL_POLYGON","original point must have 2 coordinates at "+key)
					for j in range(2):
						if not _number(polygon[i][j]) or absf(polygon[i][j]-c.polygon[i][j]) > 0.000002:
							return _error("ORIGINAL_POLYGON","original full-hex coordinate invalid at "+key)
				# Preserve the supplied denominator literals, copying only bounded known fields.
				hexes[key] = {"q":c.q,"r":c.r,"polygon":polygon.duplicate(true),"declared_class":expected_class,"crop_boundary":value.crop_boundary}
		else:
			for key in cells:
				var c: Dictionary = cells[key]
				hexes[key] = {"q":c.q,"r":c.r,"polygon":c.polygon.duplicate(true),"declared_class":"water" if c.sign<0 else "land","crop_boundary":c.neighbors.size()<6}
		# Continuous same-class least-squares gradient and the unchanged local amplitude cap.
		for key in cells:
			var c: Dictionary = cells[key]
			var xx = 0.0
			var xz = 0.0
			var zz = 0.0
			var xy = 0.0
			var zy = 0.0
			for neighbor in c.neighbors:
				var other: Dictionary = cells[neighbor]
				if other.sign != c.sign: continue
				var dx = other.center[0]-c.center[0]
				var dz = other.center[1]-c.center[1]
				var dy = other.elevation-c.elevation
				xx += dx*dx
				xz += dx*dz
				zz += dz*dz
				xy += dx*dy
				zy += dz*dy
			var det = xx*zz-xz*xz
			if absf(det)<0.0000000001:
				xx += 1.0
				zz += 1.0
				det = xx*zz-xz*xz
			var gx = (xy*zz-zy*xz)/det
			var gz = (zy*xx-xy*xz)/det
			var magnitude = sqrt(gx*gx+gz*gz)
			var limit = 0.7*maxf(absf(c.elevation),0.01)/SOLID
			var factor = minf(1.0,limit/magnitude) if magnitude != 0.0 else 1.0
			c["gradient"] = [gx*factor,gz*factor]
		var corners: Dictionary = {}
		var edges: Dictionary = {}
		var keys = cells.keys()
		keys.sort()
		for key in keys:
			var c: Dictionary = cells[key]
			for i in range(6):
				var p: Array = c.polygon[i]
				var next: Array = c.polygon[(i+1)%6]
				var point_key = _key(p)
				if not corners.has(point_key): corners[point_key] = {"order":_order(p),"owners":[]}
				corners[point_key].owners.append([key,i])
				var a = _order(p)
				var b = _order(next)
				if _less(b,a):
					var swap = a
					a = b
					b = swap
				var edge_key = "%d,%d|%d,%d" % [a[0],a[1],b[0],b[1]]
				if not edges.has(edge_key): edges[edge_key] = {"order":a+b,"owners":[]}
				edges[edge_key].owners.append([key,i])
		var core: Dictionary = {}
		for key in cells:
			var c: Dictionary = cells[key]
			var cx = c.center[0]
			var cz = c.center[1]
			core[key] = []
			for point in c.polygon:
				var x = cx+SOLID*(point[0]-cx)
				var z = cz+SOLID*(point[1]-cz)
				var y = c.elevation+c.gradient[0]*(x-cx)+c.gradient[1]*(z-cz)
				y = c.sign*maxf(c.sign*y,0.003)
				core[key].append([x,y,z])
		for key in keys:
			var c: Dictionary = cells[key]
			var center = [c.center[0],c.elevation,c.center[1]]
			for i in range(6):
				var edge = _edge(core[key][i],core[key][(i+1)%6])
				for j in range(4): _emit(center,edge[j],edge[j+1],"cell_fan",[key])
		var edge_rows = edges.values()
		edge_rows.sort_custom(func(a,b): return _less(a.order,b.order))
		for edge_row in edge_rows:
			var own: Array = edge_row.owners
			var key: String = own[0][0]
			var i: int = own[0][1]
			var a = _edge(core[key][i],core[key][(i+1)%6])
			if own.size() == 2:
				var other: String = own[1][0]
				var j: int = own[1][1]
				var b = _edge(core[other][j],core[other][(j+1)%6])
				if _key(cells[other].polygon[j]) != _key(cells[key].polygon[i]): b.reverse()
				if cells[key].sign != cells[other].sign:
					var mid: Array = []
					for n in range(5): mid.append(_zero_mid(a[n],b[n]))
					_strip(a,mid,"mixed_edge_land" if cells[key].sign>0 else "mixed_edge_water",[key,other])
					_strip(mid,b,"mixed_edge_land" if cells[other].sign>0 else "mixed_edge_water",[key,other])
					for n in range(4): _shore.append([_vertex(mid[n]),_vertex(mid[n+1])])
				else: _strip(a,b,"same_class_edge",[key,other])
			else:
				var rim: Array = []
				for p in [cells[key].polygon[i],cells[key].polygon[(i+1)%6]]:
					var incident: Array = corners[_key(p)].owners
					var signs: Dictionary = {}
					var sum_y = 0.0
					for pair in incident:
						signs[cells[pair[0]].sign] = true
						sum_y += core[pair[0]][pair[1]][1]
					var y = 0.0 if signs.size()>1 else sum_y/incident.size()
					rim.append([p[0],y,p[1]])
				_strip(a,_edge(rim[0],rim[1]),"full_hex_rim_cap",[key])
		var corner_rows = corners.values()
		corner_rows.sort_custom(func(a,b): return _less(a.order,b.order))
		for row in corner_rows:
			var own: Array = row.owners
			var ps: Array = []
			var ss: Array = []
			var owner: Array = []
			for pair in own:
				ps.append(core[pair[0]][pair[1]])
				ss.append(cells[pair[0]].sign)
				owner.append(pair[0])
			if own.size()==3:
				if ss[0]==ss[1] and ss[1]==ss[2]: _emit(ps[0],ps[1],ps[2],"same_class_corner",owner)
				else:
					var odd = 0
					for n in range(3):
						if ss.count(ss[n])==1:
							odd = n
							break
					var a: Array = ps[odd]
					var b: Array = ps[(odd+1)%3]
					var c: Array = ps[(odd+2)%3]
					var ab = _zero_mid(a,b)
					var ac = _zero_mid(a,c)
					_emit(a,ab,ac,"mixed_corner_minority",owner)
					_quad(ab,b,ac,c,"mixed_corner_majority",owner)
					_shore.append([_vertex(ab),_vertex(ac)])
			elif own.size()==2:
				var a: Array = ps[0]
				var b: Array = ps[1]
				var y = 0.0 if ss[0]!=ss[1] else (a[1]+b[1])*0.5
				# Reference corner uses the seven-decimal logical key for rim position.
				var v = [row.order[0]/10000000.0,y,row.order[1]/10000000.0]
				if ss[0]!=ss[1]:
					var mid = _zero_mid(a,b)
					_emit(a,mid,v,"mixed_rim_corner",owner)
					_emit(mid,b,v,"mixed_rim_corner",owner)
					_shore.append([_vertex(mid),_vertex(v)])
				else: _emit(a,b,v,"same_class_rim_corner",owner)
		if not _failure.is_empty(): return _error("CONSTRUCTION",_failure)
		var vs = PackedVector3Array()
		var normals = PackedVector3Array()
		for v in _vertices:
			vs.append(Vector3(v[0],v[1],v[2]))
			normals.append(Vector3.ZERO)
		var indices = PackedInt32Array(_indices)
		var triangles: Array = []
		var flat = PackedVector3Array()
		var classes: Array = []
		for i in range(0,indices.size(),3):
			var a = indices[i]
			var b = indices[i+1]
			var c = indices[i+2]
			var normal = (vs[c]-vs[a]).cross(vs[b]-vs[a])
			normals[a] += normal
			normals[b] += normal
			normals[c] += normal
			var triangle: Array = []
			var positive = false
			var negative = false
			for j in range(3):
				var point = vs[indices[i+j]]
				flat.append(point)
				triangle.append([point.x,point.y,point.z])
				positive = positive or point.y>0.0
				negative = negative or point.y<0.0
			triangles.append(triangle)
			classes.append("mixed" if positive and negative else "land" if positive else "water" if negative else "zero")
		for i in range(normals.size()): normals[i] = normals[i].normalized()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vs
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var hash = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(flat.to_byte_array())
		var geometry_hash = hash.finish().hex_encode()
		var low = [_vertices[0][0],_vertices[0][1],_vertices[0][2]]
		var high = low.duplicate()
		for v in _vertices:
			for i in range(3):
				low[i] = minf(low[i],v[i])
				high[i] = maxf(high[i],v[i])
		var samples: Dictionary = {}
		var focus = [0.0,0.0]
		var best = INF
		for key in cells:
			var c: Dictionary = cells[key]
			var label = "water" if c.sign<0 else "land"
			samples[key] = {"center_xz":c.center.duplicate(),"before_elevation":c.elevation,"elevation":c.elevation,"gradient":c.gradient.duplicate(),"class_before":label,"class_after":label}
			if c.sign>0:
				for neighbor in c.neighbors:
					if cells[neighbor].sign<0:
						var distance = c.center[0]*c.center[0]+c.center[1]*c.center[1]
						if distance<best:
							best = distance
							focus = c.center.duplicate()
						break
		var counts: Dictionary = {}
		for kind in _kinds: counts[kind] = counts.get(kind,0)+1
		var data = {"schema_version":"v3_actual_arraymesh/v1","geometry_version":VERSION,"reference_geometry_version":REFERENCE_VERSION,"water_level":0.0,"seed":source.get("seed",726381),"seed_token":source.get("seed_token","726381"),"board_radius":int(radius),"recipe_id":recipe.id,"source_hash":source.get("content_hash",""),"source_hash_kind":"supplied_unverified_content_hash","canonical_geometry_hash":geometry_hash,"hexes":hexes,"original_hexes":hexes.duplicate(true),"vertices":_vertices,"indices":_indices,"triangles":triangles,"face_kinds":_kinds,"face_owners":_owners,"face_classes":classes,"intended_shore_edges":_shore,"center_samples":samples,"bounds":{"min":low,"max":high},"camera_focus":[focus[0],0.2,focus[1]],"parameters":{"solid_radius_fraction":SOLID,"edge_segments":4,"candidate_parameter_sets":1,"core_gradient_amplitude_fraction":0.7,"source_triangle_intersections":false,"global_slope_limit":null},"construction":{"vertices":vs.size(),"triangles":triangles.size(),"face_kinds":counts,"build_ms":(Time.get_ticks_usec()-started)/1000.0},"scope":{"production_default":false,"gameplay_admitted":false,"navigation_migrated":false,"derived_fields_recomputed":false,"continuous_routes_verified":false}}
		return {"ok":true,"mesh":mesh,"data":data}
