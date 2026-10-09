extends "res://tests/generated_v3_vegetation/capture_native_vegetation.gd"
## Visual-policy regression only. The original real canopy contacts remain in
## pre_cutaway_contact_generation_038; no physical crown-clearance claim.
const REPLAY_FIXTURE := "res://tests/generated_v3_vegetation/fixtures/cutaway_route_replay.json"

func _reservation_fixture(recipe: String) -> Variant:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPLAY_FIXTURE))
	return {"reservations": fixture.cases[recipe].npc_reservations}

func _save(name_: String, value: Variant) -> void:
	var actual_name: String = name_
	if name_ == "native_capture_report.json":
		actual_name = "cutaway_native_capture_report.json"
	elif name_.begins_with("body_canopy_probe_"):
		actual_name = name_.replace("body_canopy_probe_", "cutaway_motion_policy_")
	super._save(actual_name, value)

func _capture_pair(board: Node3D, vegetation: Node3D, recipe: String, view_name: String, focus: Vector3) -> Dictionary:
	# Exercise the final shader for every overview/normal/closest landscape
	# capture, using the real live bodies even while the camera looks elsewhere.
	var parts: Array = []
	var player: Node3D = board.token_nodes.actor_player
	_actor_parts(player, player, parts)
	var groups: Dictionary = {}
	for part in parts:
		var box: AABB = part.node.global_transform * part.data.bounds
		groups.player = groups.player.merge(box) if groups.has("player") else box
	for pack in board.inventory_packs.values():
		for node in pack.mesh_parts:
			if node.is_visible_in_tree():
				var box: AABB = node.global_transform * _raw_mesh(node.mesh).bounds
				groups.pack = groups.pack.merge(box) if groups.has("pack") else box
	var boxes: Array[AABB] = []
	for box in groups.values():
		boxes.append(box)
	var installed: Dictionary = vegetation.set_body_cutaway_bounds(boxes, true)
	_check(bool(installed.ok), "final cutaway shader prepared for landscape " + recipe + "/" + view_name)
	return await super._capture_pair(board, vegetation, recipe, view_name, focus)

func _canopy_rows(vegetation: Node3D, placement: Dictionary) -> Array:
	var result: Array = []
	var slots: Dictionary = vegetation.get("_slots")
	for row in placement.manifest.plants:
		if row.asset_id not in TREE_ASSETS:
			continue
		var slot: Dictionary = slots[row.id]
		var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
		var transform_: Transform3D = node.global_transform * node.multimesh.get_instance_transform(int(slot.slot))
		var measured: Dictionary = placement.assets.measurements[row.asset_id]
		# These are independent native raw vertices, not renderer mask bounds.
		var vertices: PackedVector3Array = measured.canopy_vertices.duplicate()
		vertices.append_array(measured.far_vertices)
		var faces: PackedVector3Array = _world_faces(vertices, transform_)
		result.append({"id": row.id, "asset_id": row.asset_id,
			"bounds": _faces_box(faces), "transform": transform_,
			"full_crown_vertices": measured.canopy_vertices.size(), "far_vertices": measured.far_vertices.size()})
	return result

func _solid_control_routes(adapter: RefCounted, board: Node3D, vegetation: Node3D, placement: Dictionary, parts: Array, recipe: String) -> Dictionary:
	# A bounded unmasked-solid control set: first deterministic row of each
	# present kind, nearest actually admitted edge, both directions, 17 poses.
	var kinds: Dictionary = {}
	for row in placement.manifest.plants:
		if not kinds.has(row.asset_id):
			kinds[row.asset_id] = row
	_probe_stats = {"triangle_pair_tests": 0, "triangle_sat_tests": 0}
	var result: Dictionary = {"samples": 0, "triangle_contacts": 0, "budget_unresolved": 0,
		"open_surface_containment_unresolved": 0, "low_foliage_masked": 0, "controls": []}
	for kind in kinds:
		var row: Dictionary = kinds[kind]
		var p: Array = row.position
		var xz: Vector2 = Vector2(float(p[0]), float(p[2]))
		var edge: Dictionary = {}
		var nearest: float = INF
		for candidate in placement.audit.corridors:
			var d: float = xz.distance_squared_to(Geometry2D.get_closest_point_to_segment(xz, candidate.a, candidate.b))
			if d < nearest:
				nearest = d
				edge = candidate
		if edge.is_empty():
			continue
		var slot: Dictionary = vegetation.get("_slots")[row.id]
		var node: MultiMeshInstance3D = slot.node.get_ref() as MultiMeshInstance3D
		var transform_: Transform3D = node.global_transform * node.multimesh.get_instance_transform(int(slot.slot))
		var local: PackedVector3Array = placement.assets.measurements[kind].solid_vertices
		var faces: PackedVector3Array = _world_faces(local, transform_)
		var solid: Dictionary = {"faces": faces, "bounds": _faces_box(faces), "boxes": _triangle_boxes(faces)}
		var control: Dictionary = {"id": row.id, "asset_id": kind, "edge": [edge.from, edge.to],
			"mask_scope": "bark retained" if kind in TREE_ASSETS else "all low foliage retained", "samples": 0}
		for route in [[edge.from, edge.to], [edge.to, edge.from]]:
			var points: Array = adapter.source.navigation.route_points(route)
			var yaw: float = float(adapter.state_copy().actors.actor_player.get("token_rotation", -16.0))
			var first: Dictionary = board.token_support_pose(points[0], yaw)
			var last: Dictionary = board.token_support_pose(points[-1], yaw)
			points[0] = first.position
			points[-1] = last.position
			for index in range(1, points.size() - 1):
				points[index] += Vector3(0.0, 0.12, 0.0)
			board.presentation.set_actor_rotation("actor_player", first.rotation)
			board.presentation.reset_actor("actor_player", first.position)
			board.presentation.set_actor_rotation("actor_player", last.rotation)
			board.presentation.move_actor_path("actor_player", points, 1)
			var step: float = float(board.presentation.actors.actor_player.duration) / 16.0
			for sample in range(17):
				board.presentation._process(step if sample > 0 else 0.0)
				for pack in board.inventory_packs.values():
					pack.sync_position()
				var aggregate: AABB
				var found: bool = false
				for part in parts:
					var box: AABB = part.node.global_transform * part.data.bounds
					aggregate = aggregate.merge(box) if found else box
					found = true
				vegetation.set_body_cutaway_bounds([aggregate], true)
				if kind not in TREE_ASSETS and vegetation.is_canopy_cut_away(str(row.id)):
					result.low_foliage_masked += 1
				for part in parts:
					var box: AABB = part.node.global_transform * part.data.bounds
					if not box.intersects(solid.bounds):
						continue
					var contact: Dictionary = _refine(_world_faces(part.data.faces, part.node.global_transform), solid)
					if contact.status == "triangle_surface_contact":
						result.triangle_contacts += 1
					elif contact.status == "budget_unresolved":
						result.budget_unresolved += 1
					else:
						result.open_surface_containment_unresolved += 1
				result.samples += 1
				control.samples += 1
		result.controls.append(control)
	result["triangle_pair_tests"] = _probe_stats.triangle_pair_tests
	result["triangle_sat_tests"] = _probe_stats.triangle_sat_tests
	result["full_clearance_proof"] = false
	_check(int(result.low_foliage_masked) == 0, "low foliage remains unmasked on actual control routes " + recipe)
	_check(int(result.triangle_contacts) == 0, "no actual solid triangle crossings on finite control routes " + recipe)
	_check(int(result.budget_unresolved) == 0, "solid control triangle budget complete " + recipe)
	return result

func _motion_probe(adapter: RefCounted, board: Node3D, vegetation: Node3D, placement: Dictionary, recipe: String) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPLAY_FIXTURE))
	var previous: Dictionary = fixture.cases[recipe]
	var matching_hash: String = str(previous.vegetation_hash)
	if not _check(matching_hash == placement.manifest.vegetation_hash, "cutaway replay exact admitted vegetation " + recipe):
		return {"status": "source_mismatch"}
	board.presentation.set_process(false)
	for pack in board.inventory_packs.values():
		pack.set_process(false)
	var parts: Array = []
	var token: Node3D = board.token_nodes.actor_player
	_actor_parts(token, token, parts)
	for pack in board.inventory_packs.values():
		if not pack.carried:
			continue
		for node in pack.mesh_parts:
			var raw: Dictionary = _raw_mesh(node.mesh)
			if _check(bool(raw.ok), "cutaway actual carried mesh " + str(node.name)):
				parts.append({"node": node, "label": "pack/" + str(pack.pack.get_path_to(node)), "data": raw})
	var canopies: Array = _canopy_rows(vegetation, placement)
	var stats: Dictionary = {"samples": 0, "motions": 0, "required_suppression_tests": 0,
		"visible_crown_body_aabb_intersections": 0, "suppression_observed": 0,
		"lod_transitions": 0, "source_state_mutated": false}
	var timings: Array = []
	var actual_motion_inventory: Array = []
	var samples: Array = []
	var saved_contact_frame: bool = false
	var witness: Dictionary = previous.triangle_witnesses[0]
	var last_bounds: Array[AABB] = []
	var before: Dictionary = _source_snapshot(adapter)
	for job_index in range(previous.motions.size()):
		var motion: Dictionary = previous.motions[job_index]
		var route: Array = motion.route
		var points: Array = adapter.source.navigation.route_points(route)
		var yaw: float = float(adapter.state_copy().actors.actor_player.get("token_rotation", -16.0))
		var first: Dictionary = board.token_support_pose(points[0], yaw)
		var last: Dictionary = board.token_support_pose(points[-1], yaw)
		points[0] = first.position
		points[-1] = last.position
		for index in range(1, points.size() - 1):
			points[index] += Vector3(0.0, 0.12, 0.0)
		var expected_points: PackedVector3Array = PackedVector3Array(points)
		var recorded_points: PackedVector3Array = PackedVector3Array()
		for point in motion.production_route_points:
			recorded_points.append(Vector3(float(point[0]), float(point[1]), float(point[2])))
		_check(expected_points.to_byte_array() == recorded_points.to_byte_array(), "same exact float32 production route " + recipe + "/" + str(job_index))
		board.presentation.set_actor_rotation("actor_player", first.rotation)
		board.presentation.reset_actor("actor_player", first.position)
		board.presentation.set_actor_rotation("actor_player", last.rotation)
		board.presentation.move_actor_path("actor_player", points, route.size() - 1)
		var duration: float = float(board.presentation.actors.actor_player.duration)
		var intervals: int = int(motion.samples) - 1
		var step: float = duration / float(intervals)
		board.camera.size = 23.0 if job_index % 2 == 0 else 7.5
		vegetation.update_lod(board.camera)
		stats.lod_transitions += 1
		for sample_index in range(intervals + 1):
			board.presentation._process(step if sample_index > 0 else 0.0)
			for pack in board.inventory_packs.values():
				pack.sync_position()
			var body_bounds: Array[AABB] = []
			var groups: Dictionary = {}
			for part in parts:
				if part.node.is_visible_in_tree():
					var part_box: AABB = part.node.global_transform * part.data.bounds
					body_bounds.append(part_box)
					var group_name: String = "pack" if str(part.label).begins_with("pack/") else "player"
					groups[group_name] = groups[group_name].merge(part_box) if groups.has(group_name) else part_box
			var policy_bounds: Array[AABB] = []
			for group_box in groups.values():
				policy_bounds.append(group_box)
			var tick: int = Time.get_ticks_usec()
			vegetation.set_body_cutaway_bounds(policy_bounds, true)
			timings.append(Time.get_ticks_usec() - tick)
			last_bounds = policy_bounds
			stats.samples += 1
			var required: Array = []
			var aggregate: AABB = body_bounds[0]
			for body_index in range(1, body_bounds.size()):
				aggregate = aggregate.merge(body_bounds[body_index])
			for canopy in canopies:
				if not canopy.bounds.intersects(aggregate):
					continue
				var intersects: bool = false
				for box in body_bounds:
					if canopy.bounds.intersects(box):
						intersects = true
						break
				if not intersects:
					continue
				required.append(canopy.id)
				stats.required_suppression_tests += 1
				if not vegetation.is_canopy_cut_away(str(canopy.id)):
					stats.visible_crown_body_aabb_intersections += 1
				else:
					stats.suppression_observed += 1
			if sample_index in [0, int(intervals / 2), intervals] and samples.size() < 96:
				var boxes: Array = []
				for box in body_bounds:
					boxes.append(_box(box))
				var policy_boxes: Array = []
				for box in policy_bounds:
					policy_boxes.append(_box(box))
				samples.append({"route": route, "sample": sample_index, "seconds": step * sample_index,
					"body_bounds": boxes, "supplied_merged_policy_bounds": policy_boxes, "required_hidden_canopy_ids": required,
					"cutaway": vegetation.report().get("cutaway", {})})
			if not saved_contact_frame and route == witness.route and sample_index == int(witness.sample):
				board.overview_mode = false
				board.view_focus = token.global_position + Vector3.UP * 0.25
				board.camera.size = 7.5
				board.orbit_camera(0.0, 0.0)
				vegetation.update_lod(board.camera)
				vegetation.select(str(witness.plant))
				for enabled in [false, true]:
					vegetation.set_body_cutaway_bounds(policy_bounds, enabled)
					await _frames(3)
					var filename: String = "cutaway_" + recipe + "__prior_contact__" + ("on" if enabled else "off") + ".png"
					_check(root.get_texture().get_image().save_png(OUT + filename) == OK, "save cutaway witness " + filename)
				saved_contact_frame = true
				vegetation.select("")
		actual_motion_inventory.append({"route": route, "samples": intervals + 1, "duration": duration,
			"motion_kind": motion.motion_kind, "whole_route_hops": 1})
		stats.motions += 1
		if job_index % 12 == 11:
			await process_frame
	_check(int(stats.visible_crown_body_aabb_intersections) == 0, "no visible canopy AABB overlaps supplied body bounds " + recipe)
	_check(int(stats.required_suppression_tests) > 0, "real crown/body cutaway exercised " + recipe)
	_check(saved_contact_frame, "matched previously proven contact pixels " + recipe)
	# Restart/reconfigure rebuilds presentation only; authoritative inputs stay identical.
	vegetation.set_body_cutaway_bounds([], false)
	var restored: int = 0
	for canopy in canopies:
		if not vegetation.is_canopy_cut_away(str(canopy.id)):
			restored += 1
	_check(restored == canopies.size(), "explicit disable restores every canopy " + recipe)
	var rebuilt: Dictionary = vegetation.configure(placement)
	_check(bool(rebuilt.ok), "presentation reconfigure " + recipe)
	vegetation.set_body_cutaway_bounds(last_bounds, true)
	for canopy in canopies:
		for box in last_bounds:
			if canopy.bounds.intersects(box):
				_check(vegetation.is_canopy_cut_away(str(canopy.id)), "reconfigure current bounds restored " + str(canopy.id))
	var solid_controls: Dictionary = _solid_control_routes(adapter, board, vegetation, placement, parts, recipe)
	board.set_world(adapter.state_copy())
	for pack in board.inventory_packs.values():
		pack.sync_position()
	vegetation.set_body_cutaway_bounds([], false)
	stats.source_state_mutated = _source_snapshot(adapter) != before
	_check(not bool(stats.source_state_mutated), "cutaway preserves authoritative source/nav/state " + recipe)
	return {"status": "visual_policy_sampled", "policy": "visual_canopy_cutaway/v1",
		"vegetation_hash": placement.manifest.vegetation_hash, "stats": stats,
		"update_timings": _distribution(timings), "elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0,
		"motion_inventory": actual_motion_inventory, "selected_pose_evidence": samples, "unmasked_solid_controls": solid_controls,
		"renderer": vegetation.report(), "scope": "all recorded finite production poses from preserved contact generation, full/far alternation, raw body AABB mask coverage",
		"prior_real_contacts_preserved": true, "physical_canopy_clearance_claim": false,
		"limitations": ["finite motion samples", "shader pixels and CPU mask validated separately", "physical trunks governed by admitted corridor profile", "actual drop and fresh-process save reload tested by composed Main lane"]}
