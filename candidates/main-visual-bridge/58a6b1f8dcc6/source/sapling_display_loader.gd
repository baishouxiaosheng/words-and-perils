extends "res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd"
## Private display-only policy. Parent meshes/rows/cache identity stay unchanged.
var saplings_hidden := false
var sapling_visibility_snapshots: Array = []
var policy_visible_count := 0
var policy_visible_triangles := 0

func sapling_nodes() -> Array:
	var nodes: Array = []
	for group: Dictionary in groups:
		# Pinned original bucket constructor names every kind_<x>_<z> pair.
		if str(group.near.name).begins_with("sapling_"):
			nodes.append(group.near); nodes.append(group.far)
	return nodes

func set_saplings_hidden(value: bool) -> void:
	if value == saplings_hidden: return
	if value:
		policy_visible_count = visible_count; policy_visible_triangles = visible_triangles
		for node: MultiMeshInstance3D in sapling_nodes():
			sapling_visibility_snapshots.append({"node": node, "visible": node.visible})
		saplings_hidden = true
		_apply_sapling_policy()
	else:
		saplings_hidden = false
		for row: Dictionary in sapling_visibility_snapshots:
			if is_instance_valid(row.node): row.node.visible = row.visible
		sapling_visibility_snapshots.clear()
		visible_count = policy_visible_count; visible_triangles = policy_visible_triangles

func _apply_sapling_policy() -> void:
	if not saplings_hidden: return
	for node: MultiMeshInstance3D in sapling_nodes(): node.visible = false
	# Display counters reflect hidden presentation; original active source counts
	# and all original constructor/cache fields remain intact.
	visible_count = 0; visible_triangles = 0
	if not visible: return
	for group: Dictionary in groups:
		if group.near.visible:
			visible_count += int(group.active_count)
			visible_triangles += int(group.active_count) * int(group.near_triangles)
		elif group.far.visible:
			visible_count += int(group.active_count)
			visible_triangles += int(group.active_count) * 7

func update_lod(camera: Camera3D, target: Vector3, overview: bool, enabled: bool) -> void:
	super.update_lod(camera, target, overview, enabled)
	_apply_sapling_policy()

func uninstall_sapling_policy() -> void:
	set_saplings_hidden(false)
