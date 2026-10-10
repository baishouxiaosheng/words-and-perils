extends RefCounted
## Per-model light frame for the palette gradients. Each face still decides lit
## or shade on its own in the shader; this measures, once per mesh, where the
## model's terminator falls along the sun direction and how far its lit and
## shaded parts reach, so both sides grade outward from the terminator.
## The shade colour depends only on position on the model, never on how many
## shadows cover a pixel, so overlapping shadows keep one colour.
const SUN := Vector3(-.55, .74, .39)
static var _cache: Dictionary = {}

## form_frame = local centre + local radius; form_span = (terminator, lit end,
## shade end) in units of that radius along the sun direction.
static func apply(node: GeometryInstance3D, threshold: float) -> void:
	var mesh: Mesh = null
	if node is MultiMeshInstance3D and node.multimesh != null: mesh = node.multimesh.mesh
	elif node is MeshInstance3D: mesh = node.mesh
	if mesh == null: return
	# MultiMesh instances are mostly yaw-rotated copies; the node basis stands in for all.
	var basis := node.global_basis
	var key := "%d|%s" % [mesh.get_instance_id(), basis]
	if not _cache.has(key): _cache[key] = measure(mesh, basis, threshold)
	var frame: Dictionary = _cache[key]
	if frame.is_empty(): return
	node.set_instance_shader_parameter("form_frame", frame.frame)
	node.set_instance_shader_parameter("form_span", frame.span)

## Mountains hold several peaks per node, so they grade by height instead.
static func apply_height(node: GeometryInstance3D) -> void:
	var box := node.global_transform * node.get_aabb()
	node.set_instance_shader_parameter("form_height", Vector2(box.position.y, box.end.y))

static func measure(mesh: Mesh, basis: Basis, threshold: float) -> Dictionary:
	var box := mesh.get_aabb()
	var centre := box.get_center()
	var radius := box.size.length() * .5
	var scale := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
	if radius * scale <= .0001: return {}
	var sun := SUN.normalized()
	var rotation := basis.orthonormalized()
	var lit: Array = []
	var shade: Array = []
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		# Large batched meshes are sampled; a few thousand faces fix the percentiles.
		var stride: int = maxi(1, count / 3 / 3000) * 3
		for i in range(0, count - 2, stride):
			var ia: int = indices[i] if not indices.is_empty() else i
			var ib: int = indices[i + 1] if not indices.is_empty() else i + 1
			var ic: int = indices[i + 2] if not indices.is_empty() else i + 2
			var a := basis * (vertices[ia] - centre)
			var b := basis * (vertices[ib] - centre)
			var c := basis * (vertices[ic] - centre)
			var area := (b - a).cross(c - a).length() * .5
			if area <= .0000001: continue
			# Authored normals, not winding: the palette shaders draw both sides.
			var n: Vector3 = (rotation * (normals[ia] + normals[ib] + normals[ic])).normalized() if not normals.is_empty() else (b - a).cross(c - a).normalized()
			var u := (a + b + c).dot(sun) / (3.0 * radius * scale)
			(lit if n.dot(sun) > threshold else shade).append(Vector2(u, area))
	var by_u := func(p: Vector2, q: Vector2) -> bool: return p.x < q.x
	lit.sort_custom(by_u)
	shade.sort_custom(by_u)
	var terminator := 0.0
	if lit.is_empty(): terminator = 1.0
	elif shade.is_empty(): terminator = -1.0
	else: terminator = (_percentile(lit, .12) + _percentile(shade, .88)) * .5
	var lit_end: float = maxf(_percentile(lit, .97) if not lit.is_empty() else 1.0, terminator + .05)
	var shade_end: float = minf(_percentile(shade, .03) if not shade.is_empty() else -1.0, terminator - .05)
	return {"frame": Vector4(centre.x, centre.y, centre.z, radius), "span": Vector3(terminator, lit_end, shade_end)}

## Area-weighted percentile of rows already sorted by u.
static func _percentile(rows: Array, fraction: float) -> float:
	var total := 0.0
	for row: Vector2 in rows: total += row.y
	var walked := 0.0
	for row: Vector2 in rows:
		walked += row.y
		if walked >= total * fraction: return row.x
	return rows[-1].x
