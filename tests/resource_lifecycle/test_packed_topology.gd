extends SceneTree
const PackedTopology = preload("res://view/integrated_ecology_world/natural_shorelines/packed_topology.gd")
const Shore = preload("res://view/integrated_ecology_world/natural_shorelines/shore_layer.gd")
const ROOT = "res://artifacts/natural_shorelines_v03_20261002/cache/"
var checks: Array = []
var failures := 0
var report: Dictionary = {}
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks.append({"name": label_, "passed": ok})
	if not ok:
		failures += 1
		printerr("TOPOLOGY_FAIL ", label_)
func old_bary(raw: Dictionary, fi: int, p: Vector3) -> Vector3:
	var ps: Array = []
	for vi in raw.faces[fi].vertices:
		var v: Array = raw.vertices[vi].position
		ps.append(Vector2(v[0], v[2]))
	var u: Vector2 = ps[1] - ps[0]
	var v: Vector2 = ps[2] - ps[0]
	var rel: Vector2 = Vector2(p.x, p.z) - ps[0]
	var det := u.cross(v)
	var b: float = rel.cross(v) / det
	var c: float = u.cross(rel) / det
	return Vector3(1-b-c,b,c)
func run() -> void:
	var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	var info: Dictionary = manifest.files["source_topology_v03.json.gz"]
	check(FileAccess.get_sha256(ROOT + "source_topology_v03.json.gz") == info.sha256, "unchanged source topology checksum")
	var parser := JSON.new()
	check(parser.parse(FileAccess.get_file_as_bytes(ROOT + "source_topology_v03.json.gz").decompress(int(info.decoded_bytes), FileAccess.COMPRESSION_GZIP).get_string_from_utf8()) == OK, "authoritative JSON parses")
	var raw: Dictionary = parser.data
	var json_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var compact = PackedTopology.new()
	compact.load_data(raw)
	check(compact.packed and compact.fallback.is_empty(), "known schema uses packed representation without retained JSON")
	check(compact.vertex_count == 67289 and compact.face_count == 133352, "complete vertices and source faces retained")
	var positions_exact := true
	var vectors_exact := true
	for vi in range(compact.vertex_count):
		var p: Array = raw.vertices[vi].position
		for axis in range(3):
			positions_exact = positions_exact and compact.positions[vi*3+axis] == float(p[axis])
		vectors_exact = vectors_exact and compact.vertex_position(vi) == Vector3(p[0],p[1],p[2]) and compact.vertex_height(vi) == float(p[1])
	check(positions_exact, "all 201867 source coordinate values preserve full JSON Float64 precision")
	check(vectors_exact, "all position vectors and interpolated-height operands equal baseline")
	var faces_exact := true
	var indices_exact := true
	for fi in range(compact.face_count):
		faces_exact = faces_exact and var_to_bytes(compact.face(fi)) == var_to_bytes(raw.faces[fi])
		for corner in range(3):
			indices_exact = indices_exact and compact.vertex_index(fi,corner) == int(raw.faces[fi].vertices[corner])
	check(faces_exact, "all 133352 full source-face payloads are Variant-byte-identical including JSON number types")
	check(indices_exact, "all 400056 triangle indices preserve identity and order")
	var layer = Shore.new()
	layer.topology = compact
	var bary_exact := true
	var height_exact := true
	var count := 0
	for fi in range(0, compact.face_count, 23):
		var p := Vector3.ZERO
		for corner in range(3):
			p += compact.vertex_position(compact.vertex_index(fi,corner))/3.0
		var old := old_bary(raw,fi,p)
		var current: Vector3 = layer._source_bary(fi,p)
		bary_exact = bary_exact and current == old
		var old_height := 0.0
		var new_height := 0.0
		for corner in range(3):
			old_height += float(raw.vertices[raw.faces[fi].vertices[corner]].position[1]) * old[corner]
			new_height += compact.vertex_height(compact.vertex_index(fi,corner)) * current[corner]
		height_exact = height_exact and old_height == new_height
		count += 1
	check(bary_exact and height_exact, "stratified source barycentrics and heights exactly match baseline")
	report["barycentric_samples"] = count
	layer.free()
	var unknown := {"vertices":[{"position":[1.0,2.0,3.0]}],"faces":[{"id":"sample","vertices":[0.0,0.0,0.0],"owner":"hex:0,0","legacy_parent_face_index":0.0,"extra_provenance":{"keep":"all"}}]}
	var future = PackedTopology.new()
	future.load_data(unknown)
	check(not future.packed and var_to_bytes(future.face(0)) == var_to_bytes(unknown.faces[0]), "future face fields preserve exact fallback instead of dropping provenance")
	unknown["source_revision"] = "future"
	future = PackedTopology.new()
	future.load_data(unknown)
	check(not future.packed and future.fallback == unknown, "future top-level fields preserve complete fallback")
	var small := {"vertices":[{"position":[1.0,2.0,3.0]}],"faces":[{"id":"sample","vertices":[0.0,0.0,0.0],"owner":"hex:0,0","legacy_parent_face_index":0.0}]}
	future = PackedTopology.new()
	future.load_data(small)
	check(future.packed, "ordinary small JSON schema packs")
	small.faces[0].legacy_parent_face_index = 2147483648.0
	future.load_data(small)
	check(not future.packed and var_to_bytes(future.face(0)) == var_to_bytes(small.faces[0]), "int32 overflow and repeated load preserve complete fallback")
	small.faces[0].legacy_parent_face_index = 1
	future.load_data(small)
	check(not future.packed and var_to_bytes(future.face(0)) == var_to_bytes(small.faces[0]), "non-JSON integral Variant type is retained in fallback")
	raw = {}
	parser.data = null
	parser = null
	var retained := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	report.merge({"checks":checks,"failures":failures,"source_mesh_sha256":manifest.source_mesh_sha256,"source_file_sha256":info.sha256,"memory_before_bytes":before,"json_loaded_bytes":json_memory,"packed_retained_bytes":retained,"json_delta_bytes":json_memory-before,"packed_delta_bytes":retained-before,"estimated_static_reduction_bytes":json_memory-retained,"vertex_count":compact.vertex_count,"face_count":compact.face_count})
	var out := OS.get_environment("FOGBANK_PERF_OUT")
	var f := FileAccess.open(out + "/packed_topology.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	f.close()
	print("PACKED_TOPOLOGY_COMPLETE failures=",failures," reduction_bytes=",json_memory-retained)
	quit(0 if failures==0 else 1)
