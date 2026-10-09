extends RefCounted
## Presentation residency only. Admitted world/source/nav JSON is never changed.
## Native geometry is reproducible and may be rebuilt when a parked view returns.
const Geometry=preload("res://view/generated_v3_runtime/geometry.gd")
static func matches(source:RefCounted,built:Dictionary) -> bool:
	return built.get("ok",false) and built.get("source_hash")==source.identity.content_hash and built.get("geometry_hash")==source.identity.geometry_hash and built.get("renderer_profile")==source.identity.renderer_profile and native_mesh_hash(built.get("ground_mesh"))==source.identity.geometry_hash
static func ensure(source:RefCounted) -> Dictionary:
	if not source.renderer_bundle.is_empty():return {"ok":matches(source,source.renderer_bundle),"rebuilt":false}
	var built:Dictionary=Geometry.build(source.data,source.identity.renderer_profile)
	if not built.get("ok",false) or not matches(source,built):return {"ok":false,"errors":["地图显示不能按原来源精确恢复，当前旅程保留。"]}
	# Preserve all aliases inside the composed Source chain.
	source.renderer_bundle.merge(built,true)
	return {"ok":true,"rebuilt":true,"geometry_hash":built.geometry_hash}
static func reuse(previous:RefCounted,next:RefCounted) -> bool:
	if previous==null or next==null or previous==next or previous.renderer_bundle.is_empty():return false
	if not next.renderer_bundle.is_empty() and not matches(next,next.renderer_bundle):return false
	if not matches(previous,previous.renderer_bundle) or not matches(next,previous.renderer_bundle):return false
	var shared:Dictionary=previous.renderer_bundle.duplicate(false)
	next.renderer_bundle.clear();next.renderer_bundle.merge(shared,true)
	return true
static func suspend(source:RefCounted) -> bool:
	if source==null or source.renderer_bundle.is_empty():return false
	if not matches(source,source.renderer_bundle):return false
	source.renderer_bundle.clear()
	return true

static func native_mesh_hash(mesh:Variant) -> String:
	if not mesh is ArrayMesh or mesh.get_surface_count()!=1:return ""
	var arrays:Array=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty() or indices.size()%3!=0:return ""
	var expanded=PackedVector3Array()
	for index in indices:
		if index<0 or index>=vertices.size():return ""
		expanded.append(vertices[index])
	var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(expanded.to_byte_array());return hash_.finish().hex_encode()
