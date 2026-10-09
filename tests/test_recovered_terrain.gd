extends SceneTree
const Loader := preload("res://view/recovered_terrain_loader.gd")
const View := preload("res://view/recovered_terrain_view.gd")
var checks := 0
var failures := []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAILED: " + label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := "res://artifacts/hex_world_rebuilt_20261002/mesh_12_r2.json"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var parsed := Loader.decode(raw)
	check(parsed.ok, "actual new r2 schema accepted")
	if not parsed.ok: quit(2); return
	var bad := raw.duplicate(true)
	bad.geometry_version = "macro_hex_biomes_v2"
	check(not Loader.decode(bad).ok, "old schema refused")
	bad = raw.duplicate(true); bad.production_world = true
	check(not Loader.decode(bad).ok, "production claim refused")
	bad = raw.duplicate(true); bad.vertices[0].designed_height = NAN
	check(not Loader.decode(bad).ok, "NaN refused")
	bad = raw.duplicate(true); bad.vertices[0].xz[0] = INF
	check(not Loader.decode(bad).ok, "Infinity refused")
	bad = raw.duplicate(true); bad.vertices[0].designed_height = true
	check(not Loader.decode(bad).ok, "boolean not numeric")
	bad = raw.duplicate(true); bad.faces[0].vertices[0] = -1
	check(not Loader.decode(bad).ok, "negative index refused")
	bad = raw.duplicate(true); bad.faces[0].vertices[0] = raw.vertices.size()
	check(not Loader.decode(bad).ok, "out of bounds refused")
	bad = raw.duplicate(true); bad.faces[0].vertices[1] = bad.faces[0].vertices[0]
	check(not Loader.decode(bad).ok, "degenerate face refused")
	bad = raw.duplicate(true); bad.faces[0].owner = "hex:999,999"
	check(not Loader.decode(bad).ok, "unknown owner refused")
	bad = raw.duplicate(true); bad.vertices[1].id = bad.vertices[0].id
	check(not Loader.decode(bad).ok, "duplicate vertex refused")
	bad = raw.duplicate(true); bad.canonical_edges[0].path_vertices[0] = -1
	check(not Loader.decode(bad).ok, "bad grid edge refused")
	bad = raw.duplicate(true); bad.semantic_hash = "notahash"
	check(not Loader.decode(bad).ok, "bad hash refused")
	bad = raw.duplicate(true); bad.faces[0].owner = bad.faces[-1].owner
	check(not Loader.decode(bad).ok, "remote valid owner ID refused by canonical geometry")
	bad = raw.duplicate(true); bad.faces.pop_back()
	check(not Loader.decode(bad).ok, "incomplete finite face list refused")
	bad = raw.duplicate(true); bad.cells[0].original_hex[0][0] += 0.1
	check(not Loader.decode(bad).ok, "canonical polygon q/r mismatch refused")
	check(not Loader.load_file("res://missing.json").ok, "missing file refused")
	var malformed := "user://viewer_invalid.json"
	var file := FileAccess.open(malformed, FileAccess.WRITE); file.store_string("{bad]"); file.close()
	check(not Loader.load_file(malformed).ok, "malformed file refused")
	file = FileAccess.open("user://viewer_oversize.json", FileAccess.WRITE)
	file.seek(Loader.MAX_BYTES); file.store_8(0); file.close()
	check(not Loader.load_file("user://viewer_oversize.json").ok, "oversize file refused before JSON parse")
	var world: Dictionary = parsed.world
	for fi in range(0, mini(32, world.face_ids.size())):
		var a: Vector3 = world.positions[world.indices[fi * 3]]
		var b: Vector3 = world.positions[world.indices[fi * 3 + 1]]
		var c: Vector3 = world.positions[world.indices[fi * 3 + 2]]
		var center := (a + b + c) / 3.0
		var sample := Loader.height_at(world, Vector2(center.x, center.z))
		check(sample.ok and absf(sample.height - center.y) < 0.00001, "stored PL face interpolation %d" % fi)
		var hit := Loader.ray_pick(world, center + Vector3.UP * 10.0, Vector3.DOWN)
		check(hit.ok and absf(hit.height - center.y) < 0.00001, "stored triangle ray %d" % fi)
	check(not Loader.ray_pick(world, Vector3(500, 10, 500), Vector3.DOWN).ok, "blank pick is empty")
	var view := View.new(); root.add_child(view); await process_frame
	for iteration in range(3):
		view.show_world(world)
		check(view.terrain_root.get_child_count() == view.chunk_count + 1, "reload terrain node count %d" % iteration)
		view.set_grid_visible(false)
		check(not view.grid_root.visible, "grid node hidden %d" % iteration)
		view.set_grid_visible(true)
		check(view.grid_root.visible, "grid node shown %d" % iteration)
		view.fit_overview()
		check(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and absf(view.camera.global_basis.z.y - 1.0) < 0.00001, "true vertical overview %d" % iteration)
		view.focus_close()
		view.zoom(-1000.0)
		check(view.distance == 4.0 and view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "close minimum distance %d" % iteration)
		view.zoom(1000.0)
		check(view.distance == 180.0, "far clamp %d" % iteration)
		await process_frame
	view.set_height_scale(2.0)
	check(view.content_root.scale == Vector3(1,2,1), "2x unified visual transform")
	check(view.terrain_root.get_parent() == view.content_root and view.grid_root.get_parent() == view.content_root, "terrain/grid same display parent")
	check(view.world.positions == world.positions, "2x source geometry unchanged")
	view.fit_overview()
	var fi := 20
	var source_point: Vector3 = (world.positions[world.indices[fi * 3]] + world.positions[world.indices[fi * 3 + 1]] + world.positions[world.indices[fi * 3 + 2]]) / 3.0
	var displayed := view.content_root.global_transform * source_point
	var scaled_hit := view.inspect(view.camera.unproject_position(displayed))
	check(scaled_hit.ok and absf(scaled_hit.height - source_point.y) < 0.0001 and absf(scaled_hit.display_height - source_point.y * 2.0) < 0.0001, "2x inverse-transform pick preserves source height")
	view.set_height_scale(1.0)
	check(view.content_root.scale == Vector3.ONE, "1x restored")
	view.clear_world(); await process_frame
	check(view.world.is_empty() and view.terrain_root == null and view.grid_root == null, "clear releases view state")
	view.queue_free(); await process_frame
	var report := {"checks": checks, "failures": failures, "fixture": false, "input": path, "semantic_hash": world.semantic_hash, "scope": "new read-only adapter and scene; headless is not GL/FPS acceptance"}
	file = FileAccess.open("res://artifacts/hex_world_rebuilt_20261002/viewer_test_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("RECOVERED_VIEW_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
