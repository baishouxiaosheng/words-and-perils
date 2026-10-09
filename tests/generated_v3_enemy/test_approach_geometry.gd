extends SceneTree
## Finite, presentation-only QA: native raw bodies and actual carried/dropped pack.
## Vegetation-off geometry gate; vegetation/cutaway is a separate composed UI gate.
## Does not mutate accepted state or infer a global navigation guarantee.
const Source = preload("res://view/generated_v3_enemy/source.gd")
const Board = preload("res://view/generated_v3_enemy/board.gd")
const G = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface = preload("res://core/generated_v3_placement/surface.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const Placement = preload("res://view/generated_v3_enemy/placement.gd")
var checks = 0
var failures: Array = []
var cases: Array = []
var raw_bounds: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("ENEMY_GEOMETRY_FAIL ", label)
	return value
func _parts(node: Node, result: Array) -> void:
	if str(node.name) in ["SelectedEdgeGlow", "SelectionRing"]: return
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): _parts(child, result)
func _bounds(part: MeshInstance3D) -> AABB:
	var id: int = part.mesh.get_instance_id()
	if not raw_bounds.has(id):
		var found = false; var box = AABB()
		for surface_index in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface_index)
			for p in arrays[Mesh.ARRAY_VERTEX]:
				box = box.expand(p) if found else AABB(p, Vector3.ZERO); found = true
		raw_bounds[id] = box
	return part.global_transform * raw_bounds[id]
func _overlaps(parts: Array, obstacles: Array) -> int:
	var count = 0
	for part in parts:
		var bound: AABB = _bounds(part)
		for obstacle in obstacles:
			if bound.intersects(obstacle.bounds): count += 1
	return count
func _pack_support(board: Node3D) -> Dictionary:
	var projected: Array = []; var min_y = INF
	for part in board.inventory_pack.mesh_parts:
		for surface_index in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface_index)
			for local in arrays[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = part.global_transform * local
				projected.append(Vector2(p.x, p.z)); min_y = minf(min_y, p.y)
	var footprint: Array = Surface.quantized_enclosure(projected)
	var support: Dictionary = board.admitted_source.placement_result.surface.support(footprint, 65536.0, 65536.0, .0001)
	return {"ok":support.ok and min_y + .001 >= float(support.get("max_height", INF)), "support":support, "raw_min_y":min_y, "full_raw_footprint":Surface.as_json(footprint)}
func _edges(proof: Dictionary) -> Array:
	var found: Dictionary = {}; var result: Array = []
	for group in [proof.approach] + proof.bypasses:
		for plan in group.runtime_plans:
			for i in range(1, plan.route.size()):
				var a: Array = plan.route[i - 1]; var b: Array = plan.route[i]
				var id = Planner.key(a) + "|" + Planner.key(b)
				if not found.has(id): found[id] = true; result.append([a.duplicate(), b.duplicate()])
	return result
func _verify_runtime_plans(source: RefCounted, proof: Dictionary) -> bool:
	var probe: Dictionary = source.world.duplicate(true); var ok = true
	for group in [proof.approach] + proof.bypasses:
		for expected in group.runtime_plans:
			probe.actors.actor_player.hex = expected.from.duplicate()
			probe.actors.actor_player.stamina.current = expected.budget
			var actual: Dictionary = source.navigation.plan(probe, expected.target, int(expected.budget))
			ok = check(actual.ok and C.bytes(actual.get("route", [])) == C.bytes(expected.route) and actual.get("cost") == expected.cost, "actual weighted runtime route reproduces " + str(expected.from) + " -> " + str(expected.target)) and ok
	return ok
func run() -> void:
	var accepted = 0
	for radius in [4, 12]:
		for recipe in G.RECIPES:
			var label = "726381/r%d/%s" % [radius, recipe]
			var source = Source.new()
			var admission: Dictionary = source.admit(G.generate(726381, radius, recipe).source)
			if not admission.ok:
				cases.append({"seed":726381, "radius":radius, "recipe":recipe, "admitted":false, "vegetation":false, "explicit_rejection":admission})
				continue
			accepted += 1
			var state_before: String = C.bytes(source.world)
			var proof: Dictionary = source.enemy_placement_result.placement_witness.support_witness.encounter_route_support
			_verify_runtime_plans(source, proof)
			var viewport = SubViewport.new(); viewport.size = Vector2i(1280, 800); root.add_child(viewport)
			var board = Board.new(source); viewport.add_child(board); board.set_world(source.world)
			if not check(board.load_error.is_empty(), label + " composed board ready"):
				board.free(); viewport.free(); continue
			var obstacles: Array = []
			for id in [source.enemy_id, source.npc_id]:
				var parts: Array = []; _parts(board.token_nodes[id], parts)
				for part in parts: obstacles.append({"id":id + "/" + str(part.name), "bounds":_bounds(part)})
			for building in source.placement_result.manifest.buildings:
				if not board.village_nodes.has(building.id): continue
				var parts: Array = []; _parts(board.village_nodes[building.id], parts)
				for part in parts: obstacles.append({"id":str(building.id) + "/" + str(part.name), "bounds":_bounds(part)})
			var player_parts: Array = []; _parts(board.token_nodes.actor_player, player_parts)
			var edge_reports: Array = []; var samples = 0; var all_clear = true
			for edge in _edges(proof):
				var points: Array = source.navigation.route_points(edge)
				if not check(points.size() >= 2, label + " route has native points " + str(edge)): all_clear = false; continue
				var first: Dictionary = board.token_support_pose(points[0], -16.0)
				var last: Dictionary = board.token_support_pose(points[-1], -16.0)
				points[0] = first.position; points[-1] = last.position
				for i in range(1, points.size() - 1): points[i] += Vector3(0, .12, 0)
				board.presentation.set_actor_rotation("actor_player", first.rotation); board.presentation.reset_actor("actor_player", first.position)
				board.presentation.set_actor_rotation("actor_player", last.rotation); board.presentation.move_actor_path("actor_player", points, 1)
				var duration: float = board.presentation.actors.actor_player.duration
				var body_candidates = 0; var pack_candidates = 0; var pack_support_failures = 0
				for i in range(41):
					board.presentation._process(duration / 40.0 if i > 0 else 0.0); board.inventory_pack.sync_position(); samples += 1
					body_candidates += _overlaps(player_parts, obstacles)
					pack_candidates += _overlaps(board.inventory_pack.mesh_parts, obstacles)
					if not _pack_support(board).ok: pack_support_failures += 1
				var clear = body_candidates == 0 and pack_candidates == 0 and pack_support_failures == 0
				all_clear = check(clear, label + " actual body/pack swept samples clear " + str(edge)) and all_clear
				edge_reports.append({"route":edge, "samples":41, "body_raw_aabb_overlap_candidates":body_candidates, "pack_raw_aabb_overlap_candidates":pack_candidates, "pack_native_support_failures":pack_support_failures})
			board.set_world(source.world)
			# Test the original full-scale dropped asset at the selected attack anchor.
			# This is a presentation probe, not an invented custody receipt.
			var pose: Dictionary = board.inventory_pack.placement_for(source.enemy_placement_result.attack_anchor_hex)
			var drop_ok: bool = pose.get("footprint_verified", false) and float(pose.get("scale", 0.0)) == 1.0 and not board.inventory_pack.overlaps_static_prop(pose)
			check(drop_ok, label + " full-size dropped pack fits attack anchor")
			if drop_ok:
				board.inventory_pack.carried = false; board.inventory_pack.ground_position = pose.position
				var n: Array = pose.normal
				board.inventory_pack.pack.basis = Basis(Quaternion(Vector3.UP, Vector3(n[0], n[1], n[2])))
				board.inventory_pack.sync_position()
				check(_overlaps(board.inventory_pack.mesh_parts, obstacles) == 0, label + " dropped raw asset clears enemy/NPC/buildings")
			check(C.bytes(source.world) == state_before, label + " finite motion and drop probes do not mutate authority")
			cases.append({"seed":726381, "radius":radius, "recipe":recipe, "admitted":true, "vegetation":false, "enemy_hex":source.world.actors[source.enemy_id].hex, "attack_anchor_hex":source.enemy_placement_result.attack_anchor_hex, "approach":proof.approach.route, "bypasses":proof.bypasses, "motion_samples":samples, "edges":edge_reports, "all_samples_clear":all_clear, "full_size_drop_fits":drop_ok, "asset_sources":{"tokens":FileAccess.get_sha256("res://view/chess_tokens.gd"), "pack":FileAccess.get_sha256("res://view/generated_inventory/item_view.gd")}, "scope":"actual admitted weighted approach/bypass routes only; finite 41-sample motion per directed edge; raw native AABB non-overlap is conservative"})
			board.free(); viewport.free(); raw_bounds.clear(); await process_frame
	check(accepted > 0, "at least one unchanged requested seed/recipe is admitted")
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_enemy")
	FileAccess.open("res://artifacts/generated_v3_enemy/approach_geometry_report.json", FileAccess.WRITE).store_string(C.bytes({"checks":checks, "failures":failures, "cases":cases, "ok":failures.is_empty()}))
	print("ENEMY_APPROACH_GEOMETRY ", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)
