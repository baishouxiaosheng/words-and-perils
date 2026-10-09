extends RefCounted
## Current rendered body bounds, from raw native arrays; no world/state writes.
## Mesh resources are immutable in this profile; transforms/visibility stay live.
var meshes:Dictionary={}
func _local_bounds(mesh:Mesh) -> Dictionary:
	var id:int=mesh.get_instance_id()
	if meshes.has(id) and meshes[id].mesh.get_ref()==mesh:return meshes[id]
	var bounds=AABB();var found=false
	for surface_index in mesh.get_surface_count():
		var arrays:Array=mesh.surface_get_arrays(surface_index)
		if arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:return {"ok":false}
		for p in arrays[Mesh.ARRAY_VERTEX]:
			if not p.is_finite():return {"ok":false}
			bounds=bounds.expand(p) if found else AABB(p,Vector3.ZERO);found=true
	var value={"ok":found,"bounds":bounds,"mesh":weakref(mesh)};meshes[id]=value;return value
func collect(node:Node,result:Array[AABB]) -> bool:
	if node.is_queued_for_deletion() or str(node.name)=="SelectedEdgeGlow":return true
	if node is Node3D and not node.is_visible_in_tree():return true
	if node is MeshInstance3D and node.mesh!=null:
		var local:Dictionary=_local_bounds(node.mesh)
		if not local.ok or not node.global_transform.is_finite():return false
		result.append(node.global_transform*local.bounds)
	for child in node.get_children():
		if not collect(child,result):return false
	return true
static func merged(parts:Array[AABB]) -> AABB:
	var result:AABB=parts[0]
	for i in range(1,parts.size()):result=result.merge(parts[i])
	return result
