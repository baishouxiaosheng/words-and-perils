extends RefCounted
## Saplings whose crown overlaps a full-size tree crown read as a spike growing
## out of the big tree. Those rows are retired from display and selection; the
## catalog still knows their identities so a save that felled one stays valid.
## Rows are the 10-float canopy stride: x, y, z, radius, height, yaw, factor, kind.
const BIG := ["temperate", "tropical"]
## Row 1148 stands beside the spawn on the only walk out (hex -1,13); the felling
## and detour journey is built on it and no full-size tree lies on any spawn route.
## Its crown only grazes a big crown edge, so it is kept.
const KEEP := {1148: true}

static func rows(instance_rows: PackedFloat32Array, kinds: Array) -> Dictionary:
	var grid := {}; var saplings: Array[int] = []
	var big_r := 0.0; var sap_r := 0.0
	for i in range(instance_rows.size()/10):
		var kind: String = kinds[int(instance_rows[i*10+7])]
		if kind == "sapling": saplings.append(i); sap_r = maxf(sap_r, instance_rows[i*10+3])
		elif kind in BIG: big_r = maxf(big_r, instance_rows[i*10+3])
	var cell := maxf(big_r+sap_r, 0.01)
	for i in range(instance_rows.size()/10):
		if kinds[int(instance_rows[i*10+7])] not in BIG: continue
		var key := Vector2i(floori(instance_rows[i*10]/cell), floori(instance_rows[i*10+2]/cell))
		if not grid.has(key): grid[key] = []
		grid[key].append(i)
	var retired := {}
	for s in saplings:
		if KEEP.has(s): continue
		var at := Vector2(instance_rows[s*10], instance_rows[s*10+2]); var r: float = instance_rows[s*10+3]
		var home := Vector2i(floori(at.x/cell), floori(at.y/cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for b in grid.get(home+Vector2i(dx, dz), []):
					if at.distance_to(Vector2(instance_rows[b*10], instance_rows[b*10+2])) < instance_rows[b*10+3]+r: retired[s] = true
	return retired
