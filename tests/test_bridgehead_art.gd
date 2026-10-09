extends SceneTree
## Render-only contract: real world facts are fixtures, never authored by scenery.
## Run with fully writable, isolated XDG directories and the headless renderer.
const Board = preload("res://view/hex_board.gd")
const Field = preload("res://view/terrain_field.gd")
const Game = preload("res://core/game_state.gd")
const Generator = preload("res://core/world_generator.gd")
const BRIDGEHEAD_SAVE = "res://tests/assistant_mediated_session/round2_committed_state.json"
const EPSILON = 0.00002
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 610)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var board = Board.new()
	viewport.add_child(board)
	await process_frame
	var game = Game.new()
	var original: Dictionary = game.state.duplicate(true)
	check_original_identity(original)
	board.set_world(game.state)
	await process_frame
	check_original_field(board)
	check_structural_art(board)
	check_meshes(board, "original")
	check_batching(board, "original")
	check(game.state == original, "Original scenery and mesh sampling leave every canonical fact unchanged")
	var restored = Game.new()
	var loaded: Dictionary = restored.load_from_file(BRIDGEHEAD_SAVE)
	check(loaded.ok, "Recorded bridgehead save remains valid")
	if loaded.ok:
		var bridgehead: Dictionary = restored.state.duplicate(true)
		check_bridgehead_facts(bridgehead)
		check(bridgehead.hexes == original.hexes, "Recorded bridgehead keeps every original semantic cell and stable ID")
		board.set_world(restored.state)
		await process_frame
		check_ray_selection(board)
		check_actor_refresh(board, restored)
		check(restored.state == bridgehead, "Camera, picking and actor presentation leave all bridgehead facts unchanged")
		var path := "user://bridgehead_art_roundtrip.json"
		var saved: Dictionary = restored.save_to_file(path)
		var roundtrip = Game.new()
		var reloaded: Dictionary = roundtrip.load_from_file(path)
		check(saved.ok and reloaded.ok and roundtrip.state == bridgehead, "Render-only bridgehead facts roundtrip exactly")
	check_generated_wiring(board)
	await process_frame
	# Returning from a generated map must not retain generated surfaces or actors.
	board.set_world(game.state)
	await process_frame
	check(not board.terrain_field.generated and board.tiles.size() == 61, "Generated-to-original refresh restores the original 61-cell field")
	check(board.token_nodes.size() == 2, "World refresh retains exactly the original two actor tokens")
	check(game.state == original, "Full render regression leaves original canonical state untouched")
	viewport.queue_free()
	await process_frame
	print("BRIDGEHEAD ART METRICS: ", JSON.stringify(metrics, "", true, true))
	if failures.is_empty():
		print("BRIDGEHEAD ART PASSED: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		printerr("BRIDGEHEAD ART FAILED: %d/%d assertions" % [failures.size(), checks])
		quit(1)

func check_original_identity(state: Dictionary) -> void:
	check(state.board_radius == 4 and state.hexes.size() == 61, "Original fixture identity remains radius 4 / 61 cells")
	var expected_count := 0
	for q in range(-4, 5):
		for r in range(-4, 5):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) > 4:
				continue
			expected_count += 1
			var cell_key := "%d,%d" % [q, r]
			check(state.hexes.has(cell_key), "Original cell remains present: " + cell_key)
			if not state.hexes.has(cell_key):
				continue
			var cell: Dictionary = state.hexes[cell_key]
			var terrain := "plain"
			if q == 0:
				terrain = "bridge" if r == 0 else "river"
			elif q == -1 and r < 0:
				terrain = "swamp"
			elif q >= 2 and r >= 0:
				terrain = "mountain"
			if Vector2i(q, r) in [Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 1)]:
				terrain = "wall"
			check(cell.id == "hex_%d_%d" % [q, r] and cell.q == q and cell.r == r and cell.terrain == terrain, "Original ID, coordinates and semantic terrain remain exact: " + cell_key)
	check(expected_count == state.hexes.size(), "Original map has no added or removed semantic cells")
	check(state.actors.actor_player.hex == [-2, 1] and state.actors.actor_sentinel.hex == [2, -1], "Original actor spawn facts remain exact")
	check(state.state_version == 0 and state.world_time == 0 and state.events.is_empty(), "Original fixture has no scenery-authored events, version or time")

func check_bridgehead_facts(state: Dictionary) -> void:
	check(state.hexes.size() == 61 and state.hexes["0,0"].terrain == "bridge", "Saved bridgehead retains the original bridge and all 61 semantic cells")
	check(state.state_version == 2 and state.world_time == 3 and state.events.size() == 2, "Recorded bridgehead version, time and event count remain exact")
	check(state.actors.actor_player.hex == [1, -1] and state.actors.actor_player.stamina.current == 7 and state.actors.actor_player.health.current == 20, "Recorded traveler position, stamina and health remain exact")
	check(state.actors.actor_sentinel.hex == [2, -1] and state.actors.actor_sentinel.health.current == 12, "Recorded sentinel facts remain exact")
	check(state.items.item_hemp_rope.quantity == 1 and state.items.item_hemp_rope.location.hex == [0, 0] and state.items.item_hemp_rope.location.placement == "tied_to_bridge_rail", "Recorded rope remains deployed at its bridge rail")
	check(not state.actors.actor_player.inventory.has("item_hemp_rope") and state.flags.rope_deployed.recovered == false, "Recorded rope is deployed without changing quantity or recovering it")
	check(state.flags.bridge_bank_inspection.load_bearing_verified == false, "Improved bridge art does not assert load-bearing safety")

func check_original_field(board) -> void:
	var field = board.terrain_field
	check(not field.generated and board.tiles.size() == 61, "Original fixture uses the original visual field")
	check(field.river_nodes.has("0,2") and board.tiles["0,2"].terrain == "wall", "Wall culvert keeps river continuity without changing the semantic wall")
	var max_error := 0.0
	var finite_samples := 0
	for tile in board.tiles.values():
		for edge in range(6):
			var neighbor: Vector2i = tile.hex + Field.DIRS[posmod(5 - edge, 6)]
			for sample_index in range(11):
				var t := float(sample_index) / 10.0
				var p: Vector3 = Field.center(tile.hex) + Field.corner(edge).lerp(Field.corner(edge + 1), t)
				var land: float = field.land_height(p)
				var water: float = field.water_height(p)
				var surface: float = field.surface_height(p)
				check(is_finite(land) and is_finite(water) and is_finite(surface), "Original field has finite land/water/surface sample at %s edge %d sample %d" % [tile.hex, edge, sample_index])
				finite_samples += 1
				if not board.tiles.has(Field.key(neighbor)):
					continue
				var q: Vector3 = Field.center(neighbor) + Field.corner(edge + 4).lerp(Field.corner(edge + 3), t)
				max_error = maxf(max_error, absf(land - field.land_height(q)))
				max_error = maxf(max_error, absf(surface - field.surface_height(q)))
		var support: float = field.support_height(tile.hex)
		check(is_finite(support), "Original support is finite: " + Field.key(tile.hex))
		for radial in [0.0, 0.25, 0.50, 0.75]:
			for direction in range(6):
				var inside: Vector3 = Field.center(tile.hex) + Field.corner(direction) * radial
				check(is_finite(field.land_height(inside)) and is_finite(field.water_height(inside)) and is_finite(field.surface_height(inside)), "Original interior field is finite at %s radius %s direction %d" % [tile.hex, radial, direction])
				finite_samples += 1
	check(max_error < EPSILON, "Original shared-edge land and surface samples agree; error=%s" % max_error)
	check(field.shared_vertex_count > 0, "Continuous terrain retains shared world-space sampling")
	metrics.original_shared_edge_error = max_error
	metrics.original_field_samples = finite_samples
	check_river_banks(field)
	check(field.support_height(Vector2i.ZERO) > field.water_height(Vector3.ZERO) + 0.20, "Bridge actor support remains safely above the visual water surface")
	check(field.mountain_height((Field.center(Vector2i(2, 0)) + Field.center(Vector2i(3, 0))) * 0.5) > 0.55, "Original mountain saddle remains continuous across semantic cells")

func check_river_banks(field) -> void:
	var target := Field.center(Vector2i(0, -2))
	var best: Dictionary = {}
	var closest := INF
	for segment in field.channels:
		var midpoint: Vector3 = (segment.a + segment.b) * 0.5
		var distance := midpoint.distance_to(target)
		if distance < closest:
			closest = distance
			best = segment
	check(not best.is_empty(), "Original river exposes a drawable channel section")
	if best.is_empty():
		return
	var channel_center: Vector3 = (best.a + best.b) * 0.5
	var direction: Vector3 = best.b - best.a
	direction.y = 0.0
	direction = direction.normalized()
	var normal := Vector3(-direction.z, 0, direction.x)
	var bed: float = field.land_height(channel_center)
	var water: float = field.water_height(channel_center)
	check(bed < water - 0.15, "Original channel bed is geometrically underwater")
	var max_drop := 0.0
	var bank_rise := INF
	for side in [-1.0, 1.0]:
		var previous: float = bed
		for step in range(1, 17):
			var point: Vector3 = channel_center + normal * side * float(step) * 0.05
			var height: float = field.land_height(point)
			max_drop = maxf(max_drop, previous - height)
			check(is_finite(height), "Original bank cross-section is finite at side %s step %d" % [side, step])
			previous = height
		bank_rise = minf(bank_rise, previous - water)
	check(max_drop <= 0.03, "Both original riverbanks rise readably from the bed, allowing at most 0.03 of deliberate undulation; maximum drop=%s" % max_drop)
	check(bank_rise > 0.15, "Both original banks emerge clearly above water; minimum rise=%s" % bank_rise)
	metrics.bank_max_drop = max_drop
	metrics.bank_minimum_above_water = bank_rise

func check_meshes(board, label: String) -> void:
	var count := 0
	var shared: Dictionary = {}
	var mesh_edge_error := 0.0
	for layer in ["land", "bank", "water", "skirt"]:
		var node = board.terrain_root.get_node_or_null(layer)
		check(node is MeshInstance3D and node.mesh != null, "%s continuous terrain has a %s mesh" % [label, layer])
		if not node is MeshInstance3D or node.mesh == null:
			continue
		var finite := true
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex in vertices:
				finite = finite and vertex.is_finite()
				count += 1
				if layer == "land":
					var point_key := "%d:%d" % [roundi(vertex.x * 100000.0), roundi(vertex.z * 100000.0)]
					if shared.has(point_key):
						mesh_edge_error = maxf(mesh_edge_error, absf(float(shared[point_key]) - vertex.y))
					else:
						shared[point_key] = vertex.y
			for normal in normals:
				finite = finite and normal.is_finite()
		check(finite, "%s actual %s mesh vertices and normals contain no nonfinite geometry" % [label, layer])
	check(mesh_edge_error < EPSILON, "%s actual land mesh preserves shared world-space vertex heights; error=%s" % [label, mesh_edge_error])
	metrics[label + "_mesh_vertices"] = count
	metrics[label + "_mesh_shared_error"] = mesh_edge_error

func check_batching(board, label: String) -> void:
	var scenery = board.get_node_or_null("BatchedScenery")
	check(scenery is Node3D, "%s scenery retains the static batching root" % label)
	if not scenery is Node3D:
		return
	var count := 0
	var all_batched := true
	for node in scenery.find_children("*", "MeshInstance3D", true, false):
		if not node.visible or node.is_queued_for_deletion():
			continue
		count += 1
		all_batched = all_batched and String(node.name).begins_with("Batched_")
	check(count > 0 and all_batched, "%s visible immutable scenery remains merged by material" % label)
	for actor in board.token_nodes.values():
		check(not scenery.is_ancestor_of(actor), "%s actor token remains outside immutable scenery batches" % label)
	check(not scenery.is_ancestor_of(board.overlays) and not scenery.is_ancestor_of(board.presentation), "%s advisory overlays and action effects remain dynamic" % label)
	metrics[label + "_static_batches"] = count

func check_ray_selection(board) -> void:
	board.focus_player()
	var default_angle: float = board.view_angle
	var default_pitch: float = board.orbit_pitch
	var default_focus: Vector3 = board.view_focus
	var default_distance: float = board.camera_distance
	check(board.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Bridgehead default camera remains perspective")
	check(is_equal_approx(board.camera.fov, 40.0) and is_equal_approx(default_distance, 10.1) and is_equal_approx(default_pitch, 0.62), "Bridgehead default camera retains its FOV, focus distance and pitch")
	var picked := 0
	var occluded := 0
	for offset in [0.0, -0.65, 0.80, 1.65]:
		board.view_angle = default_angle + offset
		board.orbit_camera(0.0, 0.0)
		check(board.view_focus.is_equal_approx(default_focus) and absf(board.camera.position.distance_to(default_focus) - default_distance) < 0.0001, "Camera orbit preserves bridgehead focus and radius at angle offset %s" % offset)
		for hex in [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, -1), Vector2i(2, -1), Vector2i(0, -1), Vector2i(0, 2), Vector2i(1, 1)]:
			var target: Vector3 = board.hex_pos(hex)
			target.y = board.terrain_field.surface_height(target)
			var screen: Vector2 = board.camera.unproject_position(target)
			var ray: Vector3 = board.camera.project_ray_normal(screen)
			check(screen.is_finite() and ray.is_finite() and ray.y < 0.0, "Real perspective camera projects a finite downward selection ray for %s at angle %s" % [hex, offset])
			var selection: Vector2i = board.pick(screen)
			var reference: Vector2i = reference_ray_pick(board, screen)
			check(selection == reference, "Real camera ray agrees with independent first-visible-surface selection for %s at angle %s; got %s, reference %s" % [hex, offset, selection, reference])
			if hex in [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, -1), Vector2i(0, -1)]:
				check(selection == hex, "Visible bridge, bank and traveler landmarks remain directly selectable at angle %s: %s" % [offset, hex])
			if selection != hex:
				occluded += 1
			picked += 1
	board.view_angle = default_angle
	board.orbit_camera(0.0, 0.0)
	metrics.camera_ray_selections = picked
	metrics.camera_occluded_ground_centers = occluded

func reference_ray_pick(board, screen: Vector2) -> Vector2i:
	# Independent fine-step/bisection reference, rather than projecting onto y=0
	# or presuming a ground center is visible through foreground mountains.
	var origin: Vector3 = board.camera.project_ray_origin(screen)
	var direction: Vector3 = board.camera.project_ray_normal(screen)
	var finish := (-0.78 - origin.y) / direction.y
	var previous := 0.0
	var distance := 0.0
	while distance <= finish:
		var point := origin + direction * distance
		var hex := reference_nearest_hex(point)
		if board.tiles.has(Field.key(hex)) and point.y <= board.terrain_field.surface_height(point):
			var low := previous
			var high := distance
			for iteration in range(18):
				var middle := (low + high) * 0.5
				var hit := origin + direction * middle
				if hit.y > board.terrain_field.surface_height(hit):
					low = middle
				else:
					high = middle
			return reference_nearest_hex(origin + direction * ((low + high) * 0.5))
		previous = distance
		distance += 0.025
	return Vector2i(99, 99)

func reference_nearest_hex(point: Vector3) -> Vector2i:
	var qf := point.x / sqrt(3.0) - point.z / 3.0
	var rf := point.z * 2.0 / 3.0
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var error_q := absf(q - qf)
	var error_r := absf(r - rf)
	var error_s := absf(s - sf)
	if error_q > error_r and error_q > error_s:
		q = -r - s
	elif error_r > error_s:
		r = -q - s
	return Vector2i(q, r)

func check_actor_refresh(board, game) -> void:
	var scenery_id: int = board.static_root.get_instance_id()
	var terrain_id: int = board.terrain_root.get_instance_id()
	var player_id: int = board.token_nodes.actor_player.get_instance_id()
	board.set_world(game.state)
	check(board.static_root.get_instance_id() == scenery_id and board.terrain_root.get_instance_id() == terrain_id, "Actor-only refresh retains existing terrain and scenery batches")
	check(board.token_nodes.actor_player.get_instance_id() == player_id, "Actor-only refresh retains stable player token identity")
	for actor_id in game.state.actors:
		var coordinates: Array = game.state.actors[actor_id].hex
		var hex := Vector2i(coordinates[0], coordinates[1])
		var support: Vector3 = board.hex_pos(hex) + Vector3(0, board.terrain_field.support_height(hex), 0)
		check(board.token_nodes[actor_id].position.is_equal_approx(support), "Actor %s lands exactly on current render support without changing its fact coordinates" % actor_id)

func check_generated_wiring(board) -> void:
	var world: Dictionary = Generator.generate(726381, 7)
	var expected_world: Dictionary = world.duplicate(true)
	var generated = Game.new()
	generated.state.hexes = world.hexes.duplicate(true)
	generated.state.board_radius = world.board_radius
	generated.state.generated_world = world.duplicate(true)
	for actor_id in world.actor_spawn_hexes:
		generated.state.actors[actor_id].hex = world.actor_spawn_hexes[actor_id].duplicate()
	var before: Dictionary = generated.state.duplicate(true)
	board.set_world(generated.state)
	var field = board.terrain_field
	check(field.generated and board.tiles.size() == 169, "Generated radius-7 world retains its separate 169-cell rendering route")
	var directed: Array = field.channels.filter(func(segment): return not segment.get("outlet_extension", false))
	check(directed.size() == world.river_edges.size(), "Generated renderer draws exactly the saved directed river graph")
	for index in range(mini(directed.size(), world.river_edges.size())):
		var segment: Dictionary = directed[index]
		var edge: Dictionary = world.river_edges[index]
		var from_point := Field.center(Vector2i(edge.from_hex[0], edge.from_hex[1]))
		var to_point := Field.center(Vector2i(edge.to_hex[0], edge.to_hex[1]))
		from_point.y = float(edge.from_elevation) + 0.025
		to_point.y = float(edge.to_elevation) + 0.025
		check(segment.a.is_equal_approx(from_point) and segment.b.is_equal_approx(to_point), "Generated river channel preserves saved edge endpoint geometry: " + String(edge.id))
	check(field.channels.any(func(segment): return segment.get("outlet_extension", false)), "Generated boundary outlets still continue to the board cut edge")
	for segment in field.channels:
		var p: Vector3 = (segment.a + segment.b) * 0.5
		check(is_finite(field.land_height(p)) and is_finite(field.water_height(p)), "Generated river geometry remains finite")
		if segment.get("mouth", false):
			var direction: Vector3 = segment.b - segment.a
			direction.y = 0.0
			var continuation: Vector3 = segment.b + direction.normalized() * 0.22
			check(field.land_height(continuation) < field.water_height(continuation), "Generated mouth stays underwater without a terminal bank berm")
	var infrastructure = board.get_node_or_null("BatchedScenery/SettlementsAndRoads")
	check(infrastructure is Node3D, "Generated roads and settlements remain wired into scenery batches")
	if infrastructure is Node3D:
		for settlement in world.settlements:
			var village = infrastructure.get_node_or_null(String(settlement.id))
			check(village is Node3D and int(village.get_meta("building_count", 0)) >= 4, "Generated settlement cluster metadata survives batching: " + String(settlement.id))
	check_meshes(board, "generated")
	check_batching(board, "generated")
	check(world == expected_world and generated.state == before, "Art does not mutate generated drainage, roads, settlements, IDs or actor facts")
	var projected: Dictionary = generated._model_snapshot(generated._snapshot())
	check(projected.generated_world.river_edges == before.generated_world.river_edges and projected.generated_world.roads == before.generated_world.roads and projected.generated_world.content_hash == before.generated_world.content_hash, "GM projection retains exact generated river graph, roads and content hash")

func check_structural_art(board) -> void:
	var bridge = board.static_root.get_node_or_null("Scenery_0,0")
	check(bridge != null and bridge.has_meta("art_bridge"), "Original bridge carries auditable visual structure metadata")
	if bridge != null and bridge.has_meta("art_bridge"):
		var info: Dictionary = bridge.get_meta("art_bridge")
		check(info.mode == "original" and is_equal_approx(float(info.span_half), 0.90), "Bridge remains the original span rather than a new route")
		check(is_equal_approx(float(info.deck_top), board.terrain_field.support_height(Vector2i.ZERO)), "Bridge deck top agrees exactly with actor support")
		check(info.abutment_contacts.size() == 2, "Bridge has exactly two bank-grounded abutments")
		for contact in info.abutment_contacts:
			var land: float = board.terrain_field.land_height(contact)
			check(contact.is_finite() and contact.y <= land and contact.y >= land - 0.12, "Bridge abutment is embedded within 0.12 of existing bank surface")
	var walls = board.static_root.get_node_or_null("ConnectedFortifications")
	check(walls != null and walls.has_meta("art_wall_spans"), "Wall network carries auditable joins and ground contacts")
	if walls != null and walls.has_meta("art_wall_spans"):
		var spans: Array = walls.get_meta("art_wall_spans")
		check(spans.size() == 2, "Original two-edge wall elbow graph remains unchanged")
		check(walls.get_meta("art_wall_corners").size() == 3, "Three original wall cells retain joined corners")
		for span in spans:
			check(span.a.is_finite() and span.b.is_finite() and is_finite(float(span.top)), "Joined wall span has finite endpoints and crown height")
			check(span.culvert, "Both original joined spans preserve the pre-existing river culvert")
		for contact in walls.get_meta("art_foundation_contacts"):
			var land: float = board.terrain_field.land_height(contact.point)
			check(float(contact.bottom) <= land + 0.025 and float(contact.bottom) >= land - 0.35, "Wall foundation meets existing terrain without a floating bottom")
	var bank=board.terrain_root.get_node_or_null("bank")
	check(bank != null and bank.mesh != null, "Dry/wet bank triangles form a distinct geometry surface")
	for actor_id in board.token_nodes:
		var plate: Label3D = board.token_nodes[actor_id].get_node("Nameplate")
		check(plate.modulate == Color.WHITE and plate.outline_size == 0, "In-world actor label is pure white without outline: " + actor_id)
