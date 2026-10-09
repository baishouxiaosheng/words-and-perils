extends "res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd"
## Saplings are left out of the map. At their source scale (about 0.04 wide and
## 0.16 tall) they read as stray spikes beside full-size trees, and their thin
## crowns cast detached triangle shadows. The pinned recipe and cache stay
## unchanged; remaining groups keep their source row indices and total_count.
var removed_saplings := 0

func load_cache(base: Dictionary, variant: String = "v1") -> bool:
	if not super.load_cache(base, variant): return false
	var kept: Array = []
	for group: Dictionary in groups:
		if str(group.near.name).begins_with("sapling_"):
			removed_saplings += int(group.count)
			group.near.free(); group.far.free()
		else:
			kept.append(group)
	groups = kept
	return true
