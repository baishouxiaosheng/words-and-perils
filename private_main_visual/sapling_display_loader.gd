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
