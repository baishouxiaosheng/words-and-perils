extends "res://tests/resource_lifecycle/profile_native1080.gd"
func sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
func measure(label_: String) -> void:
	await super.measure(label_)
	var view = app.board.world_view
	var hits: Array = []
	for y in [0.25,0.5,0.75]:
		for x in [0.2,0.4,0.6,0.8]:
			var point := Vector2(x*app.viewport.size.x,y*app.viewport.size.y)
			hits.append(view.inspect_original_surfaces(point))
	report["source_picks_"+label_] = hits
	var layer = view.natural_shorelines
	var contexts: Array = []
	for pos in [Vector2(0,0),Vector2(10.240750399750986,20.4125),Vector2(9.280905577223233,22.075),Vector2(-15,12),Vector2(20,-15)]:
		contexts.append(layer.source_context_at_xz(pos))
	report["source_contexts_"+label_] = contexts
	if label_ == "focus":
		var geometry: Array = []
		for mi in layer.get_children():
			if mi is MeshInstance3D:
				geometry.append({"name":str(mi.name),"transform":str(mi.transform),"mesh_sha256":sha(var_to_bytes(mi.mesh.surface_get_arrays(0))),"shader_sha256":sha(mi.material_override.shader.code.to_utf8_buffer())})
		report["active_geometry_and_shaders"] = geometry
		report["lifecycle_counts"] = {"old_ground_meshes":view.ground_root.get_child_count(),"old_water_meshes":view.water_root.get_child_count(),"old_vegetation_meshes":view.vegetation_root.get_child_count(),"old_tree_groups":view.tree_groups.size(),"compact_meshes":view.compact_root.get_child_count(),"active_v03_meshes":layer.get_child_count(),"old_pick_chunks":layer.old_picks.size(),"new_pick_chunks":layer.new_picks.size(),"whole_canopy_groups":view.whole_canopies.groups.size()}
	save()
