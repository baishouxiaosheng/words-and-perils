extends "res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd"
## Saplings stay on the map except those whose crown overlaps a full-size tree
## crown (see sapling_clash.gd); those instances are dropped from their group's
## MultiMesh and rows, so no unexplained zero-scale slot is left for the palette
## exclusion contract to reject. total_count keeps the source anchor count.
## Saplings never cast (transaction.gd _tiny_detail).
const SaplingClash = preload("res://view/playable_build/sapling_clash.gd")
var removed_saplings := 0

func load_cache(base: Dictionary, variant: String = "v1") -> bool:
	if not super.load_cache(base, variant): return false
	var clashing := SaplingClash.rows(instance_rows, manifest.runtime.kinds)
	for group: Dictionary in groups:
		if not str(group.near.name).begins_with("sapling_"): continue
		var kept: Array = []
		for k in range(group.rows.size()):
			if not clashing.has(int(group.rows[k])): kept.append(k)
		if kept.size() == group.rows.size(): continue
		for mi: MultiMeshInstance3D in [group.near, group.far]:
			var mm := mi.multimesh
			var transforms: Array = []
			var colors: Array = []
			for k: int in kept:
				transforms.append(mm.get_instance_transform(k))
				colors.append(mm.get_instance_color(k))
			mm.instance_count = kept.size()
			for n in range(kept.size()):
				mm.set_instance_transform(n, transforms[n])
				mm.set_instance_color(n, colors[n])
		var rows: Array = []
		for k: int in kept: rows.append(group.rows[k])
		removed_saplings += group.rows.size() - kept.size()
		group.rows = rows
		group.count = rows.size()
		group.active_count = rows.size()
	return true

## A perspective view picks tree detail per group from the visible height at
## that group's depth instead of one zoom threshold, so widening the view
## trades full trees for crowns from the far edge inward. Groups switch with a
## little hysteresis so a slow lift never flickers. Orthographic views keep the
## single threshold. Every styled group also gets the view for plant thinning.
const VEGETATION := preload("res://private_main_visual/vegetation.gdshader")
const LOD_HEIGHT := 22.0
const LOD_BAND := .75
var _low_groups: Dictionary = {}

func update_lod(camera: Camera3D, target: Vector3, overview: bool, enabled: bool) -> void:
	super.update_lod(camera, target, overview, enabled)
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	var perspective := camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not overview
	var height_per_depth := 2.0 * tan(deg_to_rad(camera.fov) * .5)
	var eye := camera.global_position
	var thin := Vector4(eye.x, eye.y, eye.z, viewport_height / height_per_depth if perspective else -viewport_height / maxf(camera.size, .01))
	if perspective:
		var forward := -camera.global_basis.z
		var low_count := 0
		var shown := 0
		visible_triangles = 0
		for i in range(groups.size()):
			var group: Dictionary = groups[i]
			if not (group.near.visible or group.far.visible): continue
			shown += 1
			var height: float = (group.center - eye).dot(forward) * height_per_depth
			var low: bool = height >= LOD_HEIGHT - (LOD_BAND if _low_groups.has(i) else -LOD_BAND)
			if low: _low_groups[i] = true; low_count += 1
			else: _low_groups.erase(i)
			group.near.visible = not low; group.far.visible = low
			if enabled: visible_triangles += int(group.active_count) * (7 if low else int(group.near_triangles))
		lod_mode = "FAR_ALL_SOURCE_CROWNS_7_TRIANGLES" if low_count == shown else "NEAR_FULL_TREE_GEOMETRY" if low_count == 0 else "DEPTH_BANDED_NEAR_AND_FAR"
	else:
		_low_groups.clear()
	for group: Dictionary in groups:
		for node: MultiMeshInstance3D in [group.near, group.far]:
			if node.visible and node.material_override is ShaderMaterial and node.material_override.shader == VEGETATION:
				node.set_instance_shader_parameter("view_thin", thin)
