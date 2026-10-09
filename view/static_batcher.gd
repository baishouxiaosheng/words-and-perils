extends RefCounted
## Collapse immutable miniature parts by shared material; retains UV/normal data.
## Labels, dynamic actors, overlays and action effects remain separate.
static func merge_under(root: Node3D, include_root: bool = true) -> int:
	var groups: Dictionary={}
	var consumed: Array[MeshInstance3D]=[]
	var root_inverse:=root.global_transform.affine_inverse()
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh_node: MeshInstance3D=node
		if mesh_node.mesh==null or mesh_node.name.begins_with("Batched_"):continue
		var transform_=root_inverse*mesh_node.global_transform
		for surface_index in range(mesh_node.mesh.get_surface_count()):
			var material_:Material=mesh_node.material_override
			if material_==null:material_=mesh_node.get_surface_override_material(surface_index)
			if material_==null:material_=mesh_node.mesh.surface_get_material(surface_index)
			var key:=str(material_.get_instance_id()) if material_!=null else "unmaterialed"
			if not groups.has(key):
				var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key]={"builder":builder,"material":material_,"shadow":mesh_node.cast_shadow}
			groups[key].builder.append_from(mesh_node.mesh,surface_index,transform_)
		consumed.append(mesh_node)
	for key in groups:
		var combined:=MeshInstance3D.new();combined.name="Batched_"+key
		combined.mesh=groups[key].builder.commit()
		combined.material_override=groups[key].material
		combined.cast_shadow=groups[key].shadow
		root.add_child(combined)
	for node in consumed:
		node.hide()
		node.queue_free()
	return groups.size()
