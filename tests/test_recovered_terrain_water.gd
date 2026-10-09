extends SceneTree
const Terrain := preload("res://view/recovered_terrain_loader.gd")
const Water := preload("res://view/recovered_terrain_water_loader.gd")
const View := preload("res://view/recovered_terrain_view.gd")
var checks := 0
var failures := []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAILED " + label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var terrain := Terrain.load_file("res://artifacts/hex_world_rebuilt_20261002/mesh_12_r24.json")
	check(terrain.ok, "real r24 upstream loads")
	if not terrain.ok: quit(2); return
	var path := "res://artifacts/hex_world_hydrology_rebuilt_20261002/drainage_12_r24.json"
	var parsed := Water.load_file(path, terrain.world)
	check(parsed.ok, "real saved PL water loads")
	if not parsed.ok: printerr(parsed); quit(2); return
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var bad := raw.duplicate(true); bad.snapshot_version = "hex-finite-drainage-candidate-0.1.0"
	check(not Water.decode(bad, terrain.world).ok, "historical water format refused")
	bad = raw.duplicate(true); bad.upstream.mesh_semantic_hash = "0".repeat(64)
	check(not Water.decode(bad, terrain.world).ok, "wrong semantic source refused")
	bad = raw.duplicate(true); bad.upstream.mesh_sha256 = "0".repeat(64)
	check(not Water.decode(bad, terrain.world).ok, "wrong byte source refused")
	bad = raw.duplicate(true); bad.bodies[0].surface_level = NAN
	check(not Water.decode(bad, terrain.world).ok, "NaN water refused")
	bad = raw.duplicate(true); bad.bodies[0].surface_level = true
	check(not Water.decode(bad, terrain.world).ok, "boolean water level refused")
	bad = raw.duplicate(true); bad.footprints[0].face = -1
	check(not Water.decode(bad, terrain.world).ok, "negative footprint index refused")
	bad = raw.duplicate(true); bad.footprints[0].polygon_xz[0][0] = INF
	check(not Water.decode(bad, terrain.world).ok, "nonfinite polygon refused")
	bad = raw.duplicate(true); bad.footprints[0].polygon_xz[0][0] += 5.0
	check(not Water.decode(bad, terrain.world).ok, "polygon outside source face refused")
	bad = raw.duplicate(true); bad.bodies[0].area_xz = -1.0
	check(not Water.decode(bad, terrain.world).ok, "negative body area refused")
	bad = raw.duplicate(true); bad.production_compatible = true
	check(not Water.decode(bad, terrain.world).ok, "water production claim refused")
	bad = raw.duplicate(true); bad.footprints.append(bad.footprints[0].duplicate(true))
	check(not Water.decode(bad, terrain.world).ok, "duplicate footprint refused")
	var water: Dictionary = parsed.water
	check(water.oceans == 3 and water.lake_candidates == 279 and water.failed_land_80 == 232, "candidate/policy limitations preserved")
	check(water.triangles == 15951 and water.footprints.size() == 14232, "explicit clipped polygon counts")
	var view := View.new(); root.add_child(view); await process_frame
	view.show_world(terrain.world, water)
	check(view.water_root.get_child_count() > 0, "actual explicit water mesh nodes")
	view.set_grid_visible(false); check(not view.grid_root.visible, "water grid off is real visibility")
	view.set_grid_visible(true); check(view.grid_root.visible, "water grid on is real visibility")
	for kind in ["ocean", "lake_candidate"]:
		var footprint: Dictionary = {}
		for row in water.footprints:
			if row.kind == kind: footprint = row; break
		var center := Vector2.ZERO
		for p in footprint.polygon: center += p
		center /= footprint.polygon.size()
		view.fit_overview()
		var source_point := Vector3(center.x, footprint.level, center.y)
		var hit := view.inspect(view.camera.unproject_position(source_point))
		check(hit.ok and hit.get("body_id", "") == footprint.body_id and absf(hit.height - footprint.level) < 0.00005, "explicit front water pick " + kind)
		view.set_height_scale(2.0); view.fit_overview()
		hit = view.inspect(view.camera.unproject_position(view.content_root.global_transform * source_point))
		check(hit.ok and hit.get("body_id", "") == footprint.body_id and absf(hit.height - footprint.level) < 0.00005 and absf(hit.display_height - 2.0 * footprint.level) < 0.0001, "2x water inverse pick " + kind)
		view.set_height_scale(1.0)
	view.clear_world(); await process_frame
	check(view.water.is_empty() and view.water_root == null, "water clear releases view state")
	view.queue_free(); await process_frame
	var report := {"checks": checks, "failures": failures, "terrain_hash": terrain.world.semantic_hash, "water_hash": water.semantic_hash, "scope": "new read-only PL water adapter; saved upstream hashes, geometry, candidate labels, visibility, inverse-transform picks; not climate/rivers/gameplay acceptance"}
	var file := FileAccess.open("res://artifacts/recovered_terrain_viewer_20261002/water_adapter_test_report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("RECOVERED_WATER_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
