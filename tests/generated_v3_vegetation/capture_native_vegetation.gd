extends SceneTree
## Real Compatibility-only captures and bounded presentation-motion regression.
## No source, state, navigation, runtime, or admitted placement writes.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const VillageAdapter = preload("res://view/generated_v3_village/adapter.gd")
const Board = preload("res://view/generated_v3_settlement/board.gd")
const Planner = preload("res://core/generated_v3_vegetation/planner.gd")
const Surface = preload("res://core/generated_v3_placement/surface.gd")
const VegetationView = preload("res://view/generated_v3_vegetation/vegetation_view.gd")
const OUT := "res://artifacts/generated_v3_vegetation/"
const MAX_UNDIRECTED_EDGES := 64
const MOTION_INTERVALS := 40
const MAX_MULTI_ANCHOR_EDGES := 16
const MAX_MULTI_ROUTE_PAIRS := 12
const MAX_MULTI_PAIRS_PER_ANCHOR := 2
const MAX_MULTI_ROUTE_EDGES := 4
const MAX_MULTI_PLAN_CALLS := 256
const MAX_TRIANGLE_PAIR_TESTS := 1000000
const MAX_CANDIDATE_RECORDS := 2048
const MAX_INTERSECTION_WITNESSES := 32
const CONTACT_EPSILON := 0.000001
const TREE_ASSETS := ["temperate", "tropical", "sapling"]
var _checks: int = 0
var _failures: Array[String] = []
var _cases: Array = []
var _mesh_cache: Dictionary = {}
var _probe_stats: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("VEGETATION_CAPTURE_FAIL ", label)
	return condition

func _save(name_: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(OUT + name_, FileAccess.WRITE)
	if file == null:
		_check(false, "cannot write " + name_)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()

func _checkpoint() -> void:
	_save("native_capture_report.json", {"checks": _checks, "failures": _failures,
		"cases": _cases, "renderer": RenderingServer.get_current_rendering_method(),
		"display": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"engine": Engine.get_version_info(), "target_gpu_tested": false,
		"scope": "matched pixels, native counters and bounded sampled motion; not swept-volume proof"})

func _frames(count: int = 3) -> void:
	for index in range(count):
		await process_frame
	await RenderingServer.frame_post_draw

static func _v(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _box(value: AABB) -> Dictionary:
	return {"min": _v(value.position), "max": _v(value.end), "size": _v(value.size)}

static func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _v(value.origin), "basis_columns": [_v(value.basis.x), _v(value.basis.y), _v(value.basis.z)]}

func _native_counters() -> Dictionary:
	return {"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"engine_static_memory_bytes": OS.get_static_memory_usage(),
		"engine_peak_static_memory_bytes": OS.get_static_memory_peak_usage(),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"buffer_memory_bytes": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		"visible_draw_calls": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draw_calls": root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}

static func _digest_bytes(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		context.update(bytes)
	return context.finish().hex_encode()

static func _mesh_buffer_hashes(mesh: Mesh) -> Array:
	var result: Array = []
	if mesh == null:
		return result
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		result.append({"vertices": _digest_bytes(vertices.to_byte_array()), "indices": _digest_bytes(indices.to_byte_array())})
	return result

func _source_snapshot(adapter: RefCounted) -> Dictionary:
	var source: RefCounted = adapter.source
	return {"source": C.digest(source.data), "navigation": C.digest(source.navigation.allowed),
		"state": C.digest(adapter.save_data()), "village": C.digest(source.placement_result.manifest),
		"ground_buffers": _mesh_buffer_hashes(source.renderer_bundle.ground_mesh),
		"water_buffers": _mesh_buffer_hashes(source.renderer_bundle.water_mesh)}

func _tree_focus(source: RefCounted, rows: Array) -> Dictionary:
	var centers: Dictionary = {}
	for row in rows:
		if row.asset_id in TREE_ASSETS:
			centers[Planner.key(row.hex)] = row.hex
	var keys: Array = centers.keys()
	keys.sort()
	var best_hex: Array = source.placement_result.manifest.origin_hex.duplicate()
	var best_count: int = -1
	for key in keys:
		var center: Vector3 = source.navigation.cell_center(centers[key])
		var count: int = 0
		for row in rows:
			if row.asset_id not in TREE_ASSETS:
				continue
			var p: Array = row.position
			if Vector2(float(p[0]) - center.x, float(p[2]) - center.z).length_squared() <= 16.0:
				count += 1
		if count > best_count:
			best_count = count
			best_hex = centers[key].duplicate()
	return {"hex": best_hex, "nearby_tree_count_within_4_world_units": maxi(0, best_count),
		"selection": "maximum tree count in radius4, lexical source-hex tie break",
		"position": source.navigation.cell_center(best_hex)}

func _pointer_query(board: Node3D, vegetation: Node3D, pointer: Vector2) -> Dictionary:
	# Retain the frozen board's accepted terrain/actor/pack/village query; append
	# current raw vegetation only within its actual nearest opaque distance.
	var base: Array = board.pick_focus(pointer)
	var limit: float = INF
	for hit in base:
		limit = minf(limit, float(hit.distance))
	var origin: Vector3 = board.camera.project_ray_origin(pointer)
	var direction: Vector3 = board.camera.project_ray_normal(pointer)
	var hits: Array = vegetation.pick(origin, direction, limit + 0.001)
	var picker: RefCounted = vegetation.get("_picker")
	var diagnostics: Dictionary = picker.get("last_query")
	if not bool(diagnostics.get("complete", false)):
		return {"complete": false, "error": diagnostics.get("error", "picker_unavailable"), "hits": 0}
	var nearest: float = limit
	for hit in hits:
		nearest = minf(nearest, float(hit.distance))
	var final_count: int = 0
	for hit in base:
		if float(hit.distance) <= nearest + 0.001:
			final_count += 1
	for hit in hits:
		if float(hit.distance) <= nearest + 0.001:
			final_count += 1
	return {"complete": true, "hits": final_count, "raw_vegetation_hits": hits.size(),
		"raw_vegetation_us": int(diagnostics.get("elapsed_us", 0)),
		"triangle_tests": int(diagnostics.get("triangle_tests", 0))}

static func _distribution(values: Array) -> Dictionary:
	if values.is_empty():
		return {"samples": 0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50_us": sorted[int(sorted.size() * 0.50)],
		"p95_us": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max_us": sorted[-1]}

func _pointer_timings(board: Node3D, vegetation: Node3D, focus: Vector3) -> Dictionary:
	var points: Array = [board.camera.unproject_position(focus + Vector3.UP * 0.3)]
	for index in range(64):
		points.append(Vector2(80 + (index * 173) % 1120, 60 + (index * 131) % 780))
	var complete: Array = []
	var raw: Array = []
	var failures: int = 0
	var hits: int = 0
	for point in points:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = _pointer_query(board, vegetation, point)
		complete.append(Time.get_ticks_usec() - start)
		raw.append(result.get("raw_vegetation_us", 0))
		if not bool(result.complete):
			failures += 1
		hits += int(result.hits)
	var repeated: Array = []
	for index in range(30):
		var start: int = Time.get_ticks_usec()
		_pointer_query(board, vegetation, points[0])
		repeated.append(Time.get_ticks_usec() - start)
	return {"complete_pointer_grid": _distribution(complete), "raw_vegetation_grid": _distribution(raw),
		"complete_repeated_focus": _distribution(repeated), "incomplete_queries": failures,
		"visible_hit_total": hits, "focus_pointer": [points[0].x, points[0].y],
		"includes": "frozen board terrain/actor/pack/village query + raw vegetation + nearest-hit arbitration"}

func _capture_pair(board: Node3D, vegetation: Node3D, recipe: String, view_name: String, focus: Vector3) -> Dictionary:
	if view_name == "overview":
		board.reset_camera()
	else:
		board.overview_mode = false
		board.view_focus = focus + Vector3.UP * 0.25
		board.camera.size = 12.0 if view_name == "normal_12" else 7.5
		board.orbit_camera(0.0, 0.0)
	board.village_view.update_lod(board.camera)
	vegetation.update_lod(board.camera)
	var camera_transform: Transform3D = board.camera.global_transform
	var pair: Dictionary = {"view": view_name, "camera_size": board.camera.size,
		"camera_transform": _transform(camera_transform), "focus": _v(board.view_focus), "frames": []}
	for enabled in [false, true]:
		vegetation.visible = enabled
		await _frames(4)
		var counters: Dictionary = _native_counters()
		var image: Image = root.get_texture().get_image()
		var filename: String = "726381_r12_%s__%s__vegetation_%s.png" % [recipe, view_name, "on" if enabled else "off"]
		_check(image.save_png(OUT + filename) == OK, "save " + filename)
		_check(board.camera.global_transform.is_equal_approx(camera_transform), "matched off/on camera " + recipe + "/" + view_name)
		pair.frames.append({"vegetation_enabled": enabled, "file": filename,
			"width": image.get_width(), "height": image.get_height(), "native_counters": counters,
			"vegetation": vegetation.report()})
	pair["pointer_timings"] = _pointer_timings(board, vegetation, focus)
	_check(int(pair.pointer_timings.incomplete_queries) == 0, "complete pointer queries " + recipe + "/" + view_name)
	return pair

func _raw_mesh(mesh: Mesh) -> Dictionary:
	var key: int = mesh.get_instance_id()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var faces: PackedVector3Array = PackedVector3Array()
	var bytes: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			return {"ok": false}
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		bytes += vertices.size() * 12 + indices.size() * 4
		if indices.is_empty():
			faces.append_array(vertices)
		else:
			for index in indices:
				if index < 0 or index >= vertices.size():
					return {"ok": false}
				faces.append(vertices[index])
	if faces.is_empty() or faces.size() % 3 != 0:
		return {"ok": false}
	var bounds: AABB = AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		if not vertex.is_finite():
			return {"ok": false}
		bounds = bounds.expand(vertex)
	var result: Dictionary = {"ok": true, "faces": faces, "bounds": bounds,
		"triangles": int(faces.size() / 3), "raw_array_bytes": bytes,
		"raw_expanded_vertex_sha256": _digest_bytes(faces.to_byte_array())}
	_mesh_cache[key] = result
	return result

func _actor_parts(node: Node, root_: Node3D, result: Array) -> void:
	if node is MeshInstance3D and node.mesh != null and node.is_visible_in_tree():
		var data: Dictionary = _raw_mesh(node.mesh)
		if _check(bool(data.ok), "actual player raw mesh " + str(node.name)):
			result.append({"node": node, "label": "player/" + str(root_.get_path_to(node)), "data": data})
	for child in node.get_children():
		_actor_parts(child, root_, result)

static func _world_faces(local: PackedVector3Array, transform_: Transform3D) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	result.resize(local.size())
	for index in range(local.size()):
		result[index] = transform_ * local[index]
	return result

static func _faces_box(faces: PackedVector3Array) -> AABB:
	var result: AABB = AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		result = result.expand(vertex)
	return result

static func _triangle_boxes(faces: PackedVector3Array) -> Array:
	var result: Array = []
	for index in range(0, faces.size(), 3):
		result.append(AABB(faces[index], Vector3.ZERO).expand(faces[index + 1]).expand(faces[index + 2]).grow(CONTACT_EPSILON))
	return result

func _plants_for_probe(vegetation: Node3D, rows: Array) -> Array:
	var result: Array = []
	var slots: Dictionary = vegetation.get("_slots")
	for row in rows:
		if row.asset_id not in TREE_ASSETS:
			continue
		var slot: Dictionary = slots[row.id]
		var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
		var transform_: Transform3D = node.global_transform * node.multimesh.get_instance_transform(int(slot.slot))
		var raw: Dictionary = _raw_mesh(node.multimesh.mesh)
		if not _check(bool(raw.ok), "actual plant raw mesh " + str(row.asset_id)):
			continue
		var faces: PackedVector3Array = _world_faces(raw.faces, transform_)
		result.append({"id": row.id, "asset_id": row.asset_id, "hex": row.hex,
			"faces": faces, "boxes": _triangle_boxes(faces), "bounds": _faces_box(faces),
			"transform": transform_, "raw_hash": raw.raw_expanded_vertex_sha256,
			"corridor_envelope": Surface.expanded(Surface.as_points(row.canopy_footprint), Planner.CLEARANCE)})
	return result

static func _triangle_contact(a: Vector3, b: Vector3, c: Vector3, d: Vector3, e: Vector3, f: Vector3) -> bool:
	# Separating axes for two actual 3D triangles, including coplanar in-plane
	# axes. Epsilon is world-space contact tolerance, not penetration depth.
	var edges_a: Array = [b - a, c - b, a - c]
	var edges_b: Array = [e - d, f - e, d - f]
	var normal_a: Vector3 = (b - a).cross(c - a)
	var normal_b: Vector3 = (e - d).cross(f - d)
	if normal_a.length_squared() == 0.0 or normal_b.length_squared() == 0.0:
		return false
	var axes: Array = [normal_a, normal_b]
	for edge_a in edges_a:
		axes.append(normal_a.cross(edge_a))
		for edge_b in edges_b:
			axes.append(edge_a.cross(edge_b))
	for edge_b in edges_b:
		axes.append(normal_b.cross(edge_b))
	for raw_axis in axes:
		var axis: Vector3 = raw_axis
		if axis.length_squared() <= 1e-24:
			continue
		axis = axis.normalized()
		var minimum_a: float = minf(axis.dot(a), minf(axis.dot(b), axis.dot(c)))
		var maximum_a: float = maxf(axis.dot(a), maxf(axis.dot(b), axis.dot(c)))
		var minimum_b: float = minf(axis.dot(d), minf(axis.dot(e), axis.dot(f)))
		var maximum_b: float = maxf(axis.dot(d), maxf(axis.dot(e), axis.dot(f)))
		if maximum_a < minimum_b - CONTACT_EPSILON or maximum_b < minimum_a - CONTACT_EPSILON:
			return false
	return true

func _refine(part_faces: PackedVector3Array, plant: Dictionary) -> Dictionary:
	var plant_faces: PackedVector3Array = plant.faces
	for a_index in range(0, part_faces.size(), 3):
		var a_box: AABB = AABB(part_faces[a_index], Vector3.ZERO).expand(part_faces[a_index + 1]).expand(part_faces[a_index + 2]).grow(CONTACT_EPSILON)
		if not a_box.intersects(plant.bounds.grow(CONTACT_EPSILON)):
			continue
		for b_index in range(0, plant_faces.size(), 3):
			if int(_probe_stats.triangle_pair_tests) >= MAX_TRIANGLE_PAIR_TESTS:
				return {"status": "budget_unresolved"}
			_probe_stats.triangle_pair_tests += 1
			if not a_box.intersects(plant.boxes[int(b_index / 3)]):
				continue
			_probe_stats.triangle_sat_tests += 1
			if _triangle_contact(part_faces[a_index], part_faces[a_index + 1], part_faces[a_index + 2],
				plant_faces[b_index], plant_faces[b_index + 1], plant_faces[b_index + 2]):
				return {"status": "triangle_surface_contact", "part_triangle_index": int(a_index / 3),
					"plant_triangle_index": int(b_index / 3),
					"part_triangle": [_v(part_faces[a_index]), _v(part_faces[a_index + 1]), _v(part_faces[a_index + 2])],
					"plant_triangle": [_v(plant_faces[b_index]), _v(plant_faces[b_index + 1]), _v(plant_faces[b_index + 2])]}
	# The original tree crown/trunk surfaces are not certified closed volumes.
	# No surface crossing alone cannot disprove volumetric containment.
	return {"status": "surface_disjoint_containment_unresolved"}

static func _sample_ranges(indices: Array) -> Array:
	var result: Array = []
	for value in indices:
		var index: int = int(value)
		if not result.is_empty() and int(result[-1][1]) + 1 == index:
			result[-1][1] = index
		else:
			result.append([index, index])
	return result

func _route_contains_edge(route: Array, a: Array, b: Array) -> bool:
	for index in range(1, route.size()):
		if (route[index - 1] == a and route[index] == b) or (route[index - 1] == b and route[index] == a):
			return true
	return false

func _route_edge_indices(route: Array, a: Array, b: Array) -> Array:
	var result: Array = []
	for index in range(1, route.size()):
		if (route[index - 1] == a and route[index] == b) or (route[index - 1] == b and route[index] == a):
			result.append(index - 1)
	return result

func _route_endpoints(nav: RefCounted, center: Array) -> Array:
	var center_key: String = Planner.key(center)
	var queue: Array = [{"hex": center.duplicate(), "key": center_key, "hops": 0}]
	var seen: Dictionary = {center_key: true}
	var cursor: int = 0
	while cursor < queue.size():
		var current: Dictionary = queue[cursor]
		cursor += 1
		if int(current.hops) >= MAX_MULTI_ROUTE_EDGES - 1:
			continue
		for next_key in nav.allowed.get(current.key, []):
			if not seen.has(next_key):
				seen[next_key] = true
				queue.append({"hex": Planner.hex_(str(next_key)), "key": next_key, "hops": int(current.hops) + 1})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.hops) > int(b.hops) if a.hops != b.hops else str(a.key) < str(b.key))
	return queue

func _route_plant_indices(nav: RefCounted, route: Array, plants: Array, bins: Dictionary) -> Array:
	var found: Dictionary = {}
	for index in range(1, route.size()):
		var a3: Vector3 = nav.cell_center(route[index - 1])
		var b3: Vector3 = nav.cell_center(route[index])
		var a: Vector2 = Vector2(a3.x, a3.z)
		var b: Vector2 = Vector2(b3.x, b3.z)
		for plant_index in Planner.near_rows([a, b], bins):
			if Surface.segment_hits(a, b, plants[int(plant_index)].corridor_envelope):
				found[int(plant_index)] = true
	var result: Array = found.keys()
	result.sort()
	return result

func _multi_route_jobs(adapter: RefCounted, candidates: Array, plants: Array, bins: Dictionary) -> Dictionary:
	# Only this detached copy's starting hex changes. No action/turn/state is
	# committed, no actor capability/stamina is changed, and native navigation
	# supplies the exact canonical terrain-cost route for both endpoint orders.
	var state: Dictionary = adapter.state_copy()
	var nav: RefCounted = adapter.source.navigation
	var requested_budget: int = int(state.actors.actor_player.stamina.current)
	var jobs: Array = []
	var seen_pairs: Dictionary = {}
	var accepted_pairs: int = 0
	var plan_calls: int = 0
	var rejected: Dictionary = {}
	var considered_anchors: int = 0
	for anchor_index in range(mini(MAX_MULTI_ANCHOR_EDGES, candidates.size())):
		if accepted_pairs >= MAX_MULTI_ROUTE_PAIRS or plan_calls + 2 > MAX_MULTI_PLAN_CALLS:
			break
		considered_anchors += 1
		var anchor: Dictionary = candidates[anchor_index]
		var pairs: Array = []
		for endpoint in _route_endpoints(nav, anchor.to):
			if int(endpoint.hops) > 0:
				pairs.append({"start": anchor.from, "end": endpoint.hex, "extension_hops": endpoint.hops})
		for endpoint in _route_endpoints(nav, anchor.from):
			if int(endpoint.hops) > 0:
				pairs.append({"start": endpoint.hex, "end": anchor.to, "extension_hops": endpoint.hops})
		pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.extension_hops) > int(b.extension_hops) if a.extension_hops != b.extension_hops else (Planner.key(a.start) + "/" + Planner.key(a.end)) < (Planner.key(b.start) + "/" + Planner.key(b.end)))
		var anchor_pairs: int = 0
		for pair in pairs:
			if anchor_pairs >= MAX_MULTI_PAIRS_PER_ANCHOR or accepted_pairs >= MAX_MULTI_ROUTE_PAIRS or plan_calls + 2 > MAX_MULTI_PLAN_CALLS:
				break
			if pair.start == pair.end:
				continue
			var endpoint_keys: Array = [Planner.key(pair.start), Planner.key(pair.end)]
			endpoint_keys.sort()
			var pair_key: String = str(endpoint_keys[0]) + "/" + str(endpoint_keys[1])
			if seen_pairs.has(pair_key):
				continue
			seen_pairs[pair_key] = true
			var plans: Array = []
			var rejection: String = ""
			for endpoints in [[pair.start, pair.end], [pair.end, pair.start]]:
				var hypothetical: Dictionary = state.duplicate(true)
				hypothetical.actors.actor_player.hex = endpoints[0].duplicate()
				var planned: Dictionary = nav.plan(hypothetical, endpoints[1], requested_budget)
				plan_calls += 1
				if not bool(planned.get("ok", false)):
					rejection = str(planned.get("code", "route_rejected"))
					break
				var route: Array = planned.route
				if route.size() < 3 or route.size() - 1 > MAX_MULTI_ROUTE_EDGES:
					rejection = "outside_two_to_four_edge_scope"
					break
				if not _route_contains_edge(route, anchor.from, anchor.to):
					rejection = "canonical_route_bypasses_selected_crown_edge"
					break
				plans.append(planned)
			if not rejection.is_empty() or plans.size() != 2:
				rejected[rejection] = int(rejected.get(rejection, 0)) + 1
				continue
			for planned in plans:
				var route: Array = planned.route
				jobs.append({"kind": "whole_multi_edge_route", "route": route.duplicate(true),
					"plant_indices": _route_plant_indices(nav, route, plants, bins),
					"admission": {"policy_id": planned.policy_id, "terrain_cost": planned.cost,
						"edge_costs": planned.edge_costs, "budget": planned.budget, "cell_edges": planned.distance,
						"policy_source_digest": planned.source_digest, "paired_endpoints": [pair.start, pair.end],
						"anchor_edge": [anchor.from, anchor.to],
						"anchor_edge_indices_zero_based": _route_edge_indices(route, anchor.from, anchor.to),
						"detached_hypothetical_start": true, "state_or_stamina_committed": false}})
			accepted_pairs += 1
			anchor_pairs += 1
	return {"jobs": jobs, "scope": {"selected_anchor_edges_considered": considered_anchors,
		"max_anchor_edges": MAX_MULTI_ANCHOR_EDGES, "accepted_endpoint_pairs": accepted_pairs,
		"directed_routes": jobs.size(), "max_endpoint_pairs": MAX_MULTI_ROUTE_PAIRS,
		"max_pairs_per_anchor": MAX_MULTI_PAIRS_PER_ANCHOR, "plan_calls": plan_calls,
		"max_plan_calls": MAX_MULTI_PLAN_CALLS, "route_edge_range": [2, MAX_MULTI_ROUTE_EDGES],
		"actual_actor_stamina_budget_requested": requested_budget, "rejected_pairs": rejected,
		"planning_scope": "canonical native route plan on detached start-hex copies; all real actor costs/capabilities unchanged",
		"ordering": "longer endpoint extensions first, lexical tie-break, at most two pairs per anchor",
		"finite_route_subset_only": true}}

func _motion_probe(adapter: RefCounted, board: Node3D, vegetation: Node3D, placement: Dictionary, recipe: String) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	board.camera.size = 7.5
	vegetation.update_lod(board.camera)
	board.presentation.set_process(false)
	for pack in board.inventory_packs.values():
		pack.set_process(false)
	var parts: Array = []
	var actor_state: Dictionary = adapter.state_copy().actors.actor_player
	var token_yaw: float = float(actor_state.get("token_rotation", -16.0))
	var token: Node3D = board.token_nodes.actor_player
	_actor_parts(token, token, parts)
	for pack in board.inventory_packs.values():
		if not pack.carried:
			continue
		for node in pack.mesh_parts:
			var raw: Dictionary = _raw_mesh(node.mesh)
			if _check(bool(raw.ok), "actual carried pack raw mesh " + str(node.name)):
				parts.append({"node": node, "label": "pack/" + str(pack.pack.get_path_to(node)), "data": raw})
	var part_evidence: Array = []
	var raw_body_meshes: Dictionary = {}
	for part in parts:
		var world_faces: PackedVector3Array = _world_faces(part.data.faces, part.node.global_transform)
		var hash_: String = str(part.data.raw_expanded_vertex_sha256)
		part_evidence.append({"label": part.label, "raw_mesh_hash": hash_, "triangles": part.data.triangles,
			"local_raw_bounds": _box(part.data.bounds), "initial_world_raw_bounds": _box(_faces_box(world_faces)),
			"initial_transform": _transform(part.node.global_transform)})
		if not raw_body_meshes.has(hash_):
			var vertices: Array = []
			for vertex in part.data.faces:
				vertices.append(_v(vertex))
			raw_body_meshes[hash_] = vertices
	_save("body_raw_meshes_" + recipe + ".json", {"parts": part_evidence, "meshes": raw_body_meshes,
		"raw_source": "surface_get_arrays", "guessed_human_dimensions": false})
	var plants: Array = _plants_for_probe(vegetation, placement.manifest.plants)
	var bin_rows: Array = []
	for plant in plants:
		bin_rows.append({"polygon": plant.corridor_envelope})
	var bins: Dictionary = Planner.bin_rows(bin_rows, "polygon")
	var candidates: Array = []
	for edge in placement.audit.corridors:
		var nearby: Array = Planner.near_rows([edge.a, edge.b], bins)
		var matching: Array = []
		for index in nearby:
			if Surface.segment_hits(edge.a, edge.b, plants[int(index)].corridor_envelope):
				matching.append(int(index))
		if not matching.is_empty():
			matching.sort()
			candidates.append({"key": Planner.key(edge.from) + "/" + Planner.key(edge.to),
				"from": edge.from, "to": edge.to, "plant_indices": matching})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.plant_indices.size() > b.plant_indices.size() if a.plant_indices.size() != b.plant_indices.size() else str(a.key) < str(b.key))
	var edge_inventory: Array = []
	for index in range(candidates.size()):
		var entry: Dictionary = candidates[index]
		var ids: Array = []
		for plant_index in entry.plant_indices:
			ids.append(plants[plant_index].id)
		edge_inventory.append({"from": entry.from, "to": entry.to, "plants": ids, "sampled": index < MAX_UNDIRECTED_EDGES})
	var multi_routes: Dictionary = _multi_route_jobs(adapter, candidates.slice(0, MAX_UNDIRECTED_EDGES), plants, bins)
	# Prioritize the whole-route low-early/late-hop regression before a shared
	# refinement budget can be consumed by the original single-edge samples.
	var jobs: Array = multi_routes.jobs.duplicate()
	for edge_index in range(mini(MAX_UNDIRECTED_EDGES, candidates.size())):
		var edge: Dictionary = candidates[edge_index]
		for route in [[edge.from, edge.to], [edge.to, edge.from]]:
			jobs.append({"kind": "single_edge", "route": route, "plant_indices": edge.plant_indices, "admission": {}})
	_probe_stats = {"samples": 0, "directed_edges": 0, "directed_multi_routes": 0,
		"directed_motions": 0, "traversed_cell_edges": 0, "part_plant_aabb_candidates": 0,
		"triangle_pair_tests": 0, "triangle_sat_tests": 0, "triangle_contacts": 0,
		"surface_disjoint_containment_unresolved": 0, "budget_unresolved": 0,
		"candidate_records_omitted": 0}
	var motions: Array = []
	var candidate_records: Array = []
	var witnesses: Array = []
	for job_index in range(jobs.size()):
		var job: Dictionary = jobs[job_index]
		var route: Array = job.route
		var points: Array = adapter.source.navigation.route_points(route)
		if not _check(points.size() >= 2, "native route for sampled edge"):
			continue
		var first: Dictionary = board.token_support_pose(points[0], token_yaw)
		var last: Dictionary = board.token_support_pose(points[-1], token_yaw)
		points[0] = first.position
		points[-1] = last.position
		for index in range(1, points.size() - 1):
			points[index] += Vector3(0.0, 0.12, 0.0)
		board.presentation.set_actor_rotation("actor_player", first.rotation)
		board.presentation.reset_actor("actor_player", first.position)
		board.presentation.set_actor_rotation("actor_player", last.rotation)
		board.presentation.move_actor_path("actor_player", points, route.size() - 1)
		var duration: float = float(board.presentation.actors.actor_player.duration)
		var intervals: int = MOTION_INTERVALS * (route.size() - 1)
		var step: float = duration / float(intervals)
		var motion_records: Dictionary = {}
		var sampled_bounds: Array = []
		for sample_index in range(intervals + 1):
			board.presentation._process(step if sample_index > 0 else 0.0)
			for pack in board.inventory_packs.values():
				pack.sync_position()
			_probe_stats.samples += 1
			var aggregate: AABB
			var found: bool = false
			for part in parts:
				var node: MeshInstance3D = part.node
				var broad: AABB = node.global_transform * part.data.bounds
				aggregate = aggregate.merge(broad) if found else broad
				found = true
				var current_faces: PackedVector3Array = PackedVector3Array()
				for plant_index in job.plant_indices:
					var plant: Dictionary = plants[plant_index]
					if not broad.grow(CONTACT_EPSILON).intersects(plant.bounds.grow(CONTACT_EPSILON)):
						continue
					_probe_stats.part_plant_aabb_candidates += 1
					if current_faces.is_empty():
						current_faces = _world_faces(part.data.faces, node.global_transform)
					var refined: Dictionary = _refine(current_faces, plant)
					var status: String = str(refined.status)
					if status == "triangle_surface_contact":
						_probe_stats.triangle_contacts += 1
						if witnesses.size() < MAX_INTERSECTION_WITNESSES:
							witnesses.append({"route": route, "motion_kind": job.kind, "sample": sample_index, "seconds": step * sample_index,
								"part": part.label, "plant": plant.id, "actual_contact": refined,
								"part_world_transform": _transform(node.global_transform), "plant_transform": _transform(plant.transform)})
					else:
						_probe_stats[status] += 1
					var record_key: String = str(part.label) + "/" + str(plant.id) + "/" + status
					if not motion_records.has(record_key):
						motion_records[record_key] = {"route": route, "motion_kind": job.kind, "part": part.label, "plant": plant.id,
							"status": status, "indices": [], "part_world_bounds": _box(_faces_box(current_faces)),
							"plant_world_bounds": _box(plant.bounds), "first_sample": sample_index}
					motion_records[record_key].indices.append(sample_index)
			if sample_index in [0, int(intervals / 2), intervals]:
				sampled_bounds.append({"sample": sample_index, "seconds": step * sample_index,
					"aggregate_transformed_local_aabb": _box(aggregate), "actor_transform": _transform(token.global_transform)})
		for record in motion_records.values():
			record["sample_ranges_inclusive"] = _sample_ranges(record.indices)
			record.erase("indices")
			if candidate_records.size() < MAX_CANDIDATE_RECORDS:
				candidate_records.append(record)
			else:
				_probe_stats.candidate_records_omitted += 1
		var route_points: Array = []
		for point in points:
			route_points.append(_v(point))
		motions.append({"route": route, "motion_kind": job.kind, "route_admission": job.admission,
			"whole_route_hops": 1, "cell_edges": route.size() - 1,
			"duration_seconds": duration, "samples": intervals + 1,
			"sample_interval_seconds": step, "nominal_sample_rate_hz": 1.0 / step,
			"first_rotation": _v(first.rotation), "last_rotation": _v(last.rotation),
			"first_support": {"lift": first.lift, "slope_degrees": first.slope_degrees, "unsupported_samples": first.unsupported_samples},
			"last_support": {"lift": last.lift, "slope_degrees": last.slope_degrees, "unsupported_samples": last.unsupported_samples},
			"production_route_points": route_points, "sampled_bounds": sampled_bounds})
		_probe_stats.directed_motions += 1
		_probe_stats.traversed_cell_edges += route.size() - 1
		if job.kind == "single_edge":
			_probe_stats.directed_edges += 1
		else:
			_probe_stats.directed_multi_routes += 1
		if job_index % 8 == 7:
			await process_frame
	board.set_world(adapter.state_copy())
	for pack in board.inventory_packs.values():
		pack.sync_position()
	var plant_bounds: Array = []
	for plant in plants:
		plant_bounds.append({"id": plant.id, "asset_id": plant.asset_id, "hex": plant.hex,
			"actual_full_world_bounds": _box(plant.bounds), "native_instance_transform": _transform(plant.transform),
			"raw_mesh_hash": plant.raw_hash})
	return {"scope": "sampled actual player+carried-pack surfaces against full tree geometry; not swept-volume proof",
		"elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0, "stats": _probe_stats.duplicate(true),
		"selection": "legal edges overlapping outward-expanded actual canopy polygon by the declared full-plinth radius; largest candidate count then lexical edge",
		"eligible_undirected_edges": candidates.size(), "sampled_undirected_edges": mini(MAX_UNDIRECTED_EDGES, candidates.size()),
		"unsampled_undirected_edges": maxi(0, candidates.size() - MAX_UNDIRECTED_EDGES),
		"triangle_pair_budget": MAX_TRIANGLE_PAIR_TESTS, "contact_tolerance_world_units": CONTACT_EPSILON,
		"multi_route_scope": multi_routes.scope,
		"refinement_order": "whole multi-edge routes first, then single edges; one shared pair-test budget",
		"sample_rate_policy": "40 intervals per cell edge over one complete production hop; at most161 samples per four-edge route",
		"native_body_parts": part_evidence, "native_plants": plant_bounds, "edge_inventory": edge_inventory,
		"motions": motions, "aabb_candidate_ranges": candidate_records, "triangle_witnesses": witnesses,
		"tested_samples_no_aabb_overlap": int(_probe_stats.part_plant_aabb_candidates) == 0,
		"tested_samples_no_triangle_contact": int(_probe_stats.triangle_contacts) == 0 and int(_probe_stats.budget_unresolved) == 0,
		"unresolved_aabb_candidates": int(_probe_stats.budget_unresolved) + int(_probe_stats.surface_disjoint_containment_unresolved),
		"full_clearance_proof": false,
		"conclusion": "raw triangle contact found" if int(_probe_stats.triangle_contacts) > 0 else "no triangle contact found in tested samples; unresolved candidates and unsampled motion remain",
		"limitations": ["finite sample rate", "bounded edge and route subsets", "hypothetical start cells with unchanged real movement budget", "triangle budget", "open surfaces: containment not certified", "contact can be tangency within tolerance"]}

func _reservation_fixture(recipe: String) -> Variant:
	var path: String = "res://artifacts/generated_v3_npc/placement_" + recipe + "_r12.json"
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not _check(DisplayServer.get_name() != "headless", "real display required; headless MultiMesh storage is a stub"):
		_checkpoint()
		quit(2)
		return
	if not _check(RenderingServer.get_current_rendering_method() == "gl_compatibility", "Compatibility renderer required"):
		_checkpoint()
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.msaa_3d = Viewport.MSAA_2X
	var capture_only: bool = OS.get_environment("FOGBANK_VEGETATION_CAPTURE_ONLY") == "1"
	for recipe in Generator.RECIPES:
		var adapter: RefCounted = VillageAdapter.new(Generator.generate(726381, 12, recipe).source)
		if not _check(bool(adapter.ready().ok), "frozen village adapter " + str(recipe)):
			continue
		var before: Dictionary = _source_snapshot(adapter)
		var board: Node3D = Board.new(adapter.source)
		root.add_child(board)
		board.set_world(adapter.state_copy())
		board.presentation.set_process(false)
		if not _check(str(board.load_error).is_empty(), "frozen village board " + str(recipe)):
			board.free()
			continue
		await _frames(3)
		var case_report: Dictionary = {"recipe": recipe, "seed": 726381, "radius": 12,
			"before_vegetation_planning": _native_counters(), "captures": [], "probe": {"status": "pending"}}
		var started: int = Time.get_ticks_usec()
		var source: RefCounted = adapter.source
		# The shared player/village presentation is unchanged. Feed the exact
		# closed NPC source reservation fixture so this forest matches the new
		# composed profile without constructing a second terrain/board copy.
		var npc_fixture:Variant=_reservation_fixture(str(recipe))
		if not _check(npc_fixture is Dictionary and npc_fixture.get("reservations") is Array,"closed NPC reservations present "+str(recipe)):
			board.free();continue
		var reservations:Array=npc_fixture.reservations
		case_report["npc_reservations"]=reservations.duplicate(true)
		case_report["npc_reservation_hash"]=C.digest(reservations)
		case_report["presentation_scope"]="NPC-reservation-bound forest with unchanged shared player/pack/village presentation; Main composition tested separately"
		var planned: Dictionary = Planner.build(source.data, source.renderer_bundle, source.navigation,
			source.placement_result, source.placement_result.manifest.origin_hex,reservations)
		case_report["planner_ms"] = (Time.get_ticks_usec() - started) / 1000.0
		case_report["after_planning"] = _native_counters()
		if not _check(bool(planned.ok), "native vegetation planning " + str(recipe)):
			board.free()
			continue
		var vegetation: Node3D = VegetationView.new()
		board.add_child(vegetation)
		var configured: Dictionary = vegetation.configure(planned)
		if not _check(bool(configured.ok), "native vegetation configure " + str(recipe)):
			case_report["configure_failure"] = configured
			_cases.append(case_report)
			board.free()
			continue
		case_report["after_renderer_configure"] = _native_counters()
		case_report["vegetation_hash"] = planned.manifest.vegetation_hash
		case_report["source_hash"] = source.data.content_hash
		case_report["geometry_hash"] = source.renderer_bundle.geometry_hash
		var focus: Dictionary = _tree_focus(source, planned.manifest.plants)
		case_report["tree_focus"] = {"hex": focus.hex, "position": _v(focus.position),
			"nearby_tree_count_within_4_world_units": focus.nearby_tree_count_within_4_world_units, "selection": focus.selection}
		_cases.append(case_report)
		for view_name in ["overview", "normal_12", "closest_7_5"]:
			case_report.captures.append(await _capture_pair(board, vegetation, str(recipe), view_name, focus.position))
			_checkpoint()
		print("VEGETATION_CAPTURE_READY ", recipe, " six matched frames")
		if capture_only:
			case_report.probe = {"status": "not_run_capture_only", "no_clearance_claim": true}
		else:
			case_report.probe = await _motion_probe(adapter, board, vegetation, planned, str(recipe))
			_save("body_canopy_probe_" + str(recipe) + ".json", case_report.probe)
		case_report["source_and_state_unchanged"] = _source_snapshot(adapter) == before
		_check(bool(case_report.source_and_state_unchanged), "exact source/navigation/ground/state preserved " + str(recipe))
		_checkpoint()
		board.free()
		_mesh_cache.clear()
		await _frames(2)
	_checkpoint()
	print("VEGETATION_NATIVE_CAPTURE ", _checks - _failures.size(), "/", _checks)
	quit(0 if _failures.is_empty() else 1)
