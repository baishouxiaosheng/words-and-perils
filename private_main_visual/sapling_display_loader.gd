extends "res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd"
## Saplings stay on the map except those whose crown overlaps a full-size tree
## crown (see sapling_clash.gd); those instances are scaled to zero, the same way
## river exclusion hides rows. Saplings never cast (transaction.gd _tiny_detail).
## The pinned recipe and cache stay unchanged; groups keep their source rows.
const SaplingClash = preload("res://view/playable_build/sapling_clash.gd")
var removed_saplings := 0

func load_cache(base: Dictionary, variant: String = "v1") -> bool:
	if not super.load_cache(base, variant): return false
	var clashing := SaplingClash.rows(instance_rows, manifest.runtime.kinds)
	for group: Dictionary in groups:
		if not str(group.near.name).begins_with("sapling_"): continue
		for k in range(group.rows.size()):
			if not clashing.has(int(group.rows[k])): continue
			for mi: MultiMeshInstance3D in [group.near, group.far]:
				var tr: Transform3D = mi.multimesh.get_instance_transform(k); tr.basis = Basis().scaled(Vector3.ZERO); mi.multimesh.set_instance_transform(k, tr)
			group.active_count -= 1; removed_saplings += 1
	return true
