extends RefCounted
## Original faceted vegetation. Broadleaf cylinder/crown recipe adapted from v9.
## One exact regular-heptagon projected crown. No gameplay entity identities.
static func _tri(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for p in [a,b,c]:
		data.vertices.append(p);data.normals.append(normal);data.colors.append(color)
static func _ring(data: Dictionary, low: Array, high: Array, color: Color) -> void:
	for i in range(7):
		var j := (i + 1) % 7
		var tint := color * (0.95 if i % 3 == 0 else 1.04 if i % 3 == 1 else 1.0)
		_tri(data, low[i], low[j], high[i], tint)
		_tri(data, low[j], high[j], high[i], tint)
static func _points(radius: float, y: float) -> Array:
	var points := []
	for i in range(7): points.append(Vector3(cos(TAU * i / 7.0) * radius, y, sin(TAU * i / 7.0) * radius))
	return points
static func make(kind: String) -> ArrayMesh:
	var data := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}
	var woody := kind in ["temperate", "tropical", "sapling", "shrub"]
	var trunk_top := 0.69 if kind == "tropical" else 0.57
	var bark := Color("73503a").srgb_to_linear() if kind == "tropical" else Color("886348").srgb_to_linear()
	if woody:
		_ring(data,_points(0.12,0.0),_points(0.055,trunk_top),bark)
		if kind == "tropical": _ring(data,_points(.23,.0),_points(.10,.19),bark * .86)
	var greens := {"temperate": Color("66854b"), "tropical": Color("3f765b"), "sapling":Color("a1ac56"), "shrub": Color("a48b55"), "tuft":Color("8c9987"), "reed":Color("668b65")}
	var base: Color = greens[kind].srgb_to_linear()
	var rings: Array
	if kind == "tropical": rings = [[.35,.52],[.70,.65],[1.0,.81],[.87,.93],[.30,1.0]]
	elif kind in ["temperate", "sapling"]: rings = [[.35,.36],[.82,.49],[1.0,.69],[.66,.89],[.12,1.0]]
	else: rings = [[.25,.05],[1.0,.40],[.82,.68],[.20,1.0]]
	var previous: Array = _points(rings[0][0],rings[0][1])
	for i in range(1,rings.size()):
		var next := _points(rings[i][0],rings[i][1])
		_ring(data,previous,next,base*(.79+float(i)*.085))
		previous=next
	for i in range(7): _tri(data,previous[i],previous[(i+1)%7],Vector3(0,1.01,0),base*1.15)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_COLOR]=data.colors
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
