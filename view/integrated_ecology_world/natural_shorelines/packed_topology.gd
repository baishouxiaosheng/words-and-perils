extends RefCounted
## Read-only, lossless runtime representation of the v03 JSON topology.
## Coordinates stay Float64. Full source-face records are materialized only for
## an actual hit, retaining the JSON number types and every provenance field.
## An unfamiliar schema remains intact rather than silently dropping metadata.
var positions := PackedFloat64Array()
var indices := PackedInt32Array()
var ids := PackedStringArray()
var owners := PackedStringArray()
var legacy_parents := PackedInt32Array()
var fallback: Dictionary = {}
var vertex_count := 0
var face_count := 0
var packed := false

func load_data(data: Dictionary) -> void:
	packed = false
	positions.clear()
	indices.clear()
	ids.clear()
	owners.clear()
	legacy_parents.clear()
	fallback = data
	vertex_count = data.get("vertices", []).size()
	face_count = data.get("faces", []).size()
	if data.size() != 2 or not data.has("vertices") or not data.has("faces"):
		return
	for vertex in data.vertices:
		if not vertex is Dictionary or vertex.size() != 1 or not vertex.has("position"):
			return
		if not vertex.position is Array or vertex.position.size() != 3:
			return
		for value in vertex.position:
			if typeof(value) != TYPE_FLOAT:
				return
	for face in data.faces:
		if not face is Dictionary or face.size() != 4:
			return
		for key in ["id", "vertices", "owner", "legacy_parent_face_index"]:
			if not face.has(key):
				return
		if not face.id is String or not face.owner is String or not face.vertices is Array or face.vertices.size() != 3:
			return
		for vi in face.vertices:
			if typeof(vi) != TYPE_FLOAT or not is_finite(vi) or vi < 0.0 or vi > 2147483647.0 or vi != floor(vi) or int(vi) >= vertex_count:
				return
		if typeof(face.legacy_parent_face_index) != TYPE_FLOAT or not is_finite(face.legacy_parent_face_index) or face.legacy_parent_face_index < -2147483648.0 or face.legacy_parent_face_index > 2147483647.0 or face.legacy_parent_face_index != floor(face.legacy_parent_face_index):
			return
	positions.resize(vertex_count * 3)
	indices.resize(face_count * 3)
	ids.resize(face_count)
	owners.resize(face_count)
	legacy_parents.resize(face_count)
	for vi in range(vertex_count):
		for axis in range(3):
			positions[vi * 3 + axis] = data.vertices[vi].position[axis]
	for fi in range(face_count):
		var row: Dictionary = data.faces[fi]
		ids[fi] = row.id
		owners[fi] = row.owner
		legacy_parents[fi] = int(row.legacy_parent_face_index)
		for corner in range(3):
			indices[fi * 3 + corner] = int(row.vertices[corner])
	fallback = {}
	packed = true

func vertex_index(fi: int, corner: int) -> int:
	return indices[fi * 3 + corner] if packed else int(fallback.faces[fi].vertices[corner])

func vertex_position(vi: int) -> Vector3:
	if packed:
		return Vector3(positions[vi * 3], positions[vi * 3 + 1], positions[vi * 3 + 2])
	var p: Array = fallback.vertices[vi].position
	return Vector3(p[0], p[1], p[2])

func vertex_height(vi: int) -> float:
	return positions[vi * 3 + 1] if packed else float(fallback.vertices[vi].position[1])

func face(fi: int) -> Dictionary:
	if not packed:
		return fallback.faces[fi]
	# JSON.parse supplies all source numbers as floats; preserve that contract.
	return {"id": ids[fi], "vertices": [float(indices[fi * 3]), float(indices[fi * 3 + 1]), float(indices[fi * 3 + 2])], "owner": owners[fi], "legacy_parent_face_index": float(legacy_parents[fi])}
