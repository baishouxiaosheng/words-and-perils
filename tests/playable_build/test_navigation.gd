extends SceneTree
const Nav = preload("res://view/playable_build/navigation.gd")
const World = preload("res://view/playable_build/world.gd")
const River = preload("res://view/river_overlay_preview/river_water_queries.gd")
var n := 0
var failures: Array[String] = []
func check(v: bool, label_: String) -> void:
	n+=1
	if not v: failures.append(label_); printerr("FAIL: "+label_)
func _initialize() -> void:
	check(Nav.ready(),"pinned navigation and actual water query data load")
	var state := World.world()
	var land_count := 0; var mixed_open := 0
	for row in World.catalog().cells:
		if not row.land: continue
		land_count += 1
		check(not state.hexes["%d,%d"%[row.q,row.r]].ground_blocked,"land with dry anchor not banned "+row.source_id)
		if row.dry_fraction < 0.999999:
			for b in Nav.cache.allowed_neighbors.get("%d,%d"%[row.q,row.r],[]):
				var pair := String(b).split(",")
				if Nav.step([row.q,row.r],[int(pair[0]),int(pair[1])]).ok: mixed_open += 1; break
	check(land_count==1584,"all accepted land represented")
	check(mixed_open>0,"minor-water land retains legal same-bank moves")
	check(Nav.step([-1,14],[-2,15]).ok,"opening legal move clear of real water")
	for pair in Nav.cache.water_contact_pairs:
		var a := String(pair[0]).split(","); var b := String(pair[1]).split(",")
		check(not Nav.step([int(a[0]),int(a[1])],[int(b[0]),int(b[1])]).ok,"original water contact waits for assessment")
	var q := River.new(); check(q.load_file(Nav.RIVER_WATER_PATH),"independent actual new-water summary loads")
	# River worker supplies dedicated crossing/boundary tests; verify our shared
	# helper is called against precisely the gameplay positions for every edge.
	var extra_contacts := 0
	for a in Nav.cache.allowed_neighbors:
		for b in Nav.cache.allowed_neighbors[a]:
			var hit: Dictionary = q.segment_intersects_water(Nav.positions[a],Nav.positions[b])
			if hit.intersects:
				extra_contacts += 1
				var ah := String(a).split(","); var bh := String(b).split(",")
				check(not Nav.step([int(ah[0]),int(ah[1])],[int(bh[0]),int(bh[1])]).ok,"new river contact waits for crossing assessment")
	print("PLAYABLE NAV ",n-failures.size(),"/",n," mixed_land_with_open_edge=",mixed_open," new_river_directed_edges=",extra_contacts)
	quit(0 if failures.is_empty() else 1)
