extends Node3D
## Original, source-conforming miniature art. The manifest and saved core state
## own identity, boundary and gate permission; this renderer grants no actions.
## Design research (no source code, models or textures copied):
## - 0 A.D. WallSet: separate wall/gate/tower pieces and explicit overlap.
##   https://docs.wildfiregames.com/entity-docs/a23.html#WallSet
##   https://play0ad.com/game-info/project-overview/ (GPL code / CC-BY-SA art)
## - Godot demo projects: MIT; batched procedural static geometry conventions.
##   https://github.com/godotengine/godot-demo-projects
## - Wesnoth: distinct settlement/castle terrain identity, not an economy layer.
##   https://github.com/wesnoth/wesnoth (GPL; artwork licenses vary)
const Content = preload("res://view/playable_build/settlement_content.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
var _wall_width := 0.16
var _wall_height := 0.42
const ACTOR_CLEARANCE := 0.26
const GATE_LEAF_HALF_THICKNESS := 0.018
const ROAD_WIDTH := 0.40
const ROAD_LIFT := 0.018
const STONE := Color("b7b9a0")
const STONE_LIGHT := Color("d9d5b2")
const STONE_DARK := Color("858e82")
const TIMBER := Color("634d39")
const METAL := Color("344e52")
const OCHRE := Color("ceac64")
const ROOFS := [Color("be593d"), Color("367b88"), Color("c77c40"), Color("557f6d")]
const KIT_MODELS := {
	"affluent": ["rich_manor", "rich_townhouse"],
	"industrial": ["industrial_forge", "industrial_workshop"],
	"modest": ["poor_home_a", "poor_home_b"],
	"rural": ["village_cottage_a", "village_cottage_b"],
	"civic": ["civic_hall", "rich_townhouse"]
}
const COMPOSITION_RECIPES := {
	"affluent": [["rich_manor", 0.255], ["rich_townhouse", 0.205], ["garden_court", 0.105]],
	"industrial": [["industrial_forge", 0.235], ["industrial_workshop", 0.200], ["village_barn", 0.170], ["workyard", 0.105]],
	"modest": [["poor_home_a", 0.220], ["poor_home_b", 0.190], ["poor_home_a", 0.165], ["poor_home_b", 0.145], ["shared_well", 0.085]],
	"rural": [["village_cottage_a", 0.180], ["village_barn", 0.150], ["village_cottage_b", 0.130], ["shared_well", 0.075]],
	"civic": [["civic_hall", 0.220], ["rich_townhouse", 0.180], ["rich_townhouse", 0.160], ["poor_home_a", 0.150], ["garden_court", 0.085]]
}
const MIN_ROOF_VISUAL_WIDTH := 0.17
const BUILDING_GAP := 0.035
const CANDIDATE_STEP := 0.05
# Orthographic camera distance alone does not describe screen size. Authored
# LOD1 drops sub-pixel roof seams/trim while retaining each module's silhouette.
const LOD_ENTER_PIXELS := 32.0
const LOD_EXIT_PIXELS := 44.0

var board: Node3D
var manifest: Dictionary = {}
var settlement_root: Node3D
var gate_root: Node3D
var gate_leaf: Node3D
var road_root: Node3D
var title: Label3D
var diagnostics: Dictionary = {}
var _configured := false
var _gate_open := false
var _material: StandardMaterial3D
var _route_segments: Array = []
var _boundary_segments: Array = []
var _interior_anchors: Array = []
var _sample_cache: Dictionary = {}
var _building_sites: Array = []
var _prop_sites: Array = []
var _gate_endpoints: Array = []
var _gate_leaves: Array = []
var _gate_reserved_segments: Array = []
var _district_rows: Array = []
var _district_roots: Dictionary = {}
var _additional_views: Array = []
var _asset_rows: Dictionary = {}
var _kit_material: Material
var _title_base_position := Vector3.ZERO
var _label_bounds_cache: Dictionary = {}
var _title_style_applied := false
var _lod_entries: Array = []
var _lod_mesh_cache: Dictionary = {}
var _lod_camera_signature: Array = []
var _lod_asset_failures: Array = []
var _lod_switches := 0

func configure(owner_board: Node3D, site_override: Dictionary = {}) -> void:
	board = owner_board
	for child in get_children():
		remove_child(child)
		child.queue_free()
	manifest = Content.manifest() if site_override.is_empty() else site_override
	_wall_width = float(manifest.get("wall_thickness", 0.16))
	_wall_height = float(manifest.get("wall_height", 0.42))
	_configured = false
	_sample_cache.clear()
	_route_segments.clear()
	_boundary_segments.clear()
	_interior_anchors.clear()
	_building_sites.clear()
	_prop_sites.clear()
	_gate_endpoints.clear()
	_gate_leaves.clear()
	_gate_reserved_segments.clear()
	_district_rows.clear()
	_district_roots.clear()
	_additional_views.clear()
	_asset_rows.clear()
	_label_bounds_cache.clear()
	_title_style_applied = false
	_lod_entries.clear()
	_lod_mesh_cache.clear()
	_lod_camera_signature.clear()
	_lod_asset_failures.clear()
	_lod_switches = 0
	diagnostics = {"mesh_nodes": 0, "triangles": 0, "wall_edges": 0,
		"gate_edges": 0, "wall_joints": 0, "road_spans": 0, "buildings": 0,
		"physics_nodes": 0, "source_height_samples": 0, "gate_full_edge_clearance": true,
		"wall_endpoint_mismatches": 0, "house_route_clearance": ACTOR_CLEARANCE,
		"authored_wall_samples": 0, "authored_road_sections": 0,
		"source_mesh_sha256": manifest.get("source_mesh_sha256", ""),
		"content_id": manifest.get("id", ""), "copied_external_assets": false,
		"wall_height": _wall_height, "wall_width": _wall_width,
		"districts": {}, "missing_district_sites": [], "authored_models": 0,
		"site_kind": manifest.get("site_kind", "large_city"), "walled": bool(manifest.get("walled", true)),
		"footprint_hex_count": manifest.get("interior_hexes", []).size(), "boundary_edges": manifest.get("wall_edges", []).size(),
		"asset_hash_failures": [], "missing_asset_resources": [], "gate_open_leaves": [],
		"decorative_props": 0, "unplaced_recipe_entries": [], "minimum_visual_model_width": 0.0, "minimum_roof_visual_width": 0.0}
	visible = false
	if manifest.is_empty() or not is_instance_valid(board): return
	_load_asset_manifest()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.96
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	settlement_root = _root("AuthoredSettlement", self)
	settlement_root.set_meta("source_mesh_sha256", manifest.get("source_mesh_sha256", ""))
	settlement_root.set_meta("authored_content_id", manifest.get("id", ""))
	gate_root = _root("FullWidthGate", self)
	gate_leaf = _root("SavedStateTwinLeaves", gate_root)
	road_root = _root("SourceFollowingRoad", self)
	_seed_source_samples()
	_collect_constraints()
	_build_road()
	if bool(manifest.get("walled", true)): _build_wall_ring()
	else: _build_civic_ground()
	_build_district_roots()
	_build_houses()
	_build_title()
	_configured = true
	if site_override.is_empty():
		for site in manifest.get("additional_settlements", []):
			var extra: Node3D = get_script().new()
			extra.name = "AuthoredSite_" + str(site.get("site_kind", "settlement"))
			add_child(extra)
			extra.configure(owner_board, site)
			_additional_views.append(extra)
	sync_state(board.world_state)

func sync_state(state: Dictionary) -> void:
	# Loading an older save must never introduce new scenery or a new blocker.
	var saved: Dictionary = state.get("settlement_state", {})
	visible = _configured and Content.active(state)
	for extra in _additional_views: extra.sync_state(state)
	if not visible: return
	_gate_open = not str(manifest.get("gate_id", "")).is_empty() and Content.gate_open(state, str(manifest.get("gate_id", "")))
	gate_leaf.position.y = 0.0
	for leaf in _gate_leaves: leaf.node.rotation.y = float(leaf.open_yaw) if _gate_open else float(leaf.closed_yaw)
	gate_root.set_meta("gate_open", _gate_open)
	gate_root.set_meta("state_revision", int(saved.get("revision", 0)))
	if is_instance_valid(title):
		title.text = str(manifest.get("name", "海岸聚落"))
		title.visible = not bool(board.world_view.overview)

func selection_nodes() -> Array:
	if not _configured or not visible: return []
	var found: Array = [{"id": str(manifest.id), "node": settlement_root, "hex": manifest.center_hex.duplicate()}]
	if bool(manifest.get("walled", true)) and not str(manifest.get("gate_id", "")).is_empty():
		found.append({"id": str(manifest.gate_id), "node": gate_root, "hex": manifest.gate_outside_hex.duplicate()})
	for row in _district_rows:
		if not _district_roots.has(row.id) or row.get("support_hexes", []).is_empty(): continue
		found.append({"id": str(row.id), "node": _district_roots[row.id], "hex": row.support_hexes[0].duplicate()})
	for extra in _additional_views: found.append_array(extra.selection_nodes())
	return found

func report() -> Dictionary:
	var result: Dictionary = diagnostics.duplicate(true)
	result["lod"] = lod_report()
	result["configured"] = _configured
	result["visible"] = visible
	result["gate_open"] = _gate_open
	result["gate_lift"] = 0.0
	result["gate_style"] = "hinged_twin_leaf"
	result["gate_leaf_angles"] = []
	for leaf in _gate_leaves: result.gate_leaf_angles.append(float(leaf.node.rotation.y))
	result["buildings_are_fixed_art"] = true
	result["building_sites"] = _building_sites.duplicate(true)
	result["prop_sites"] = _prop_sites.duplicate(true)
	result["perimeter_source"] = "authored_manifest_exact_xz_edges"
	result["site_count"] = 1 + _additional_views.size()
	if not _additional_views.is_empty():
		var primary: Dictionary = result.duplicate(true)
		primary["site_count"] = 1
		primary["lod"] = lod_report(false)
		var sites: Array = [primary]
		for extra in _additional_views:
			var other: Dictionary = extra.report()
			sites.append(other)
			for key in ["mesh_nodes", "triangles", "wall_edges", "gate_edges", "wall_joints", "road_spans", "buildings", "authored_models", "authored_wall_samples", "authored_road_sections", "source_height_samples", "decorative_props"]:
				result[key] = int(result.get(key, 0)) + int(other.get(key, 0))
			result.districts.merge(other.get("districts", {}))
			result.building_sites.append_array(other.get("building_sites", []))
			result.prop_sites.append_array(other.get("prop_sites", []))
			result.unplaced_recipe_entries.append_array(other.get("unplaced_recipe_entries", []))
			result.missing_district_sites.append_array(other.get("missing_district_sites", []))
			result.asset_hash_failures.append_array(other.get("asset_hash_failures", []))
			result.missing_asset_resources.append_array(other.get("missing_asset_resources", []))
		result["sites"] = sites
	return result

func _root(label: String, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node

func _v(raw: Array) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

func _sample(p: Vector3) -> Vector3:
	var key := _point_key(p)
	if _sample_cache.has(key): return _sample_cache[key]
	var height: float = p.y
	if is_instance_valid(board.world_view):
		if board.world_view.has_method("_height_at_xz"):
			var sampled: float = board.world_view.call("_height_at_xz", _xz(p))
			if is_finite(sampled): height = sampled
		height = board.world_view.presentation_height_at_xz(_xz(p), height)
	var result := Vector3(p.x, height, p.z)
	_sample_cache[key] = result
	diagnostics.source_height_samples += 1
	return result

func _collect_constraints() -> void:
	for h in manifest.get("interior_hexes", []):
		var p: Vector3 = board._source_position(h)
		_interior_anchors.append({"hex": h, "position": p})
	for i in range(_interior_anchors.size()):
		for j in range(i + 1, _interior_anchors.size()):
			var a: Array = _interior_anchors[i].hex
			var b: Array = _interior_anchors[j].hex
			var dq := int(a[0]) - int(b[0])
			var dr := int(a[1]) - int(b[1])
			if maxi(absi(dq), maxi(absi(dr), absi(dq + dr))) == 1:
				_route_segments.append([_xz(_interior_anchors[i].position), _xz(_interior_anchors[j].position)])
	if not bool(manifest.get("walled", true)):
		var neighbors: Dictionary = Bundle.document("navigation").get("allowed_neighbors", {})
		var external_count := 0
		for h in manifest.get("interior_hexes", []):
			var origin: Vector3 = board._source_position(h)
			for key in neighbors.get("%d,%d" % h, []):
				var parts: PackedStringArray = str(key).split(",")
				if parts.size() != 2: continue
				var neighbor_hex: Array = [int(parts[0]), int(parts[1])]
				var destination: Vector3 = board._source_position(neighbor_hex)
				_route_segments.append([_xz(origin), _xz(destination)])
				external_count += 1
		diagnostics["unwalled_approach_corridors"] = external_count
	var road: Array = manifest.get("road_points", [])
	for i in range(1, road.size()): _route_segments.append([_xz(_v(road[i - 1])), _xz(_v(road[i]))])
	for edge in manifest.get("wall_edges", []):
		var a := _v(edge.a)
		var b := _v(edge.b)
		_boundary_segments.append([_xz(a), _xz(b)])
		if edge.get("is_gate", false): _gate_endpoints = [a, b]

func _seed_source_samples() -> void:
	# These baked face+barycentric samples are the active source authority.
	# Never substitute a re-generated circle, terrain tile or a visual height guess.
	for edge in manifest.get("wall_edges", []):
		for row in edge.get("samples", []):
			var p := _v(row.position)
			_sample_cache[_point_key(p)] = p
			diagnostics.authored_wall_samples += 1
	for section in manifest.get("road_sections", []):
		for key in ["left", "center", "right"]:
			var p := _v(section[key].position)
			_sample_cache[_point_key(p)] = p
		diagnostics.authored_road_sections += 1

func _build_road() -> void:
	var sections: Array = manifest.get("road_sections", [])
	if sections.size() < 2: return
	var ribbon := _geometry()
	for i in range(1, sections.size()):
		var before: Dictionary = sections[i - 1]
		var after: Dictionary = sections[i]
		var a: Array[Vector3] = []
		var b: Array[Vector3] = []
		for key in ["left", "center", "right"]:
			a.append(_v(before[key].position) + Vector3.UP * ROAD_LIFT)
			b.append(_v(after[key].position) + Vector3.UP * ROAD_LIFT)
		var shade: float = [0.98, 1.015, 1.04, 1.0][i % 4]
		_ground_quad(ribbon, a[0], a[1], b[1], b[0], OCHRE * shade)
		_ground_quad(ribbon, a[1], a[2], b[2], b[1], Color("d6bb7d") * shade)
		diagnostics.road_spans += 1
	_commit("WarmPackedEarthRibbon", ribbon, road_root, false)

func _build_civic_ground() -> void:
	# An unwalled village needs its own visible pick surface in addition to its
	# named roof district. This shallow court follows source land, not a platform.
	var ground := _geometry()
	var center: Vector3 = _sample(board._source_position(manifest.center_hex))
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var b := TAU * float(i + 1) / 6.0
		var pa := _sample(center + Vector3(cos(a), 0, sin(a)) * 0.42) + Vector3.UP * 0.020
		var pb := _sample(center + Vector3(cos(b), 0, sin(b)) * 0.42) + Vector3.UP * 0.020
		_tri(ground, center + Vector3.UP * 0.020, pb, pa, Color("c8b381") * (0.96 + float(i % 3) * 0.025))
	_commit("VillagePackedEarthCourt", ground, settlement_root, false)

func _build_wall_ring() -> void:
	var body_height := maxf(0.18, _wall_height - 0.11)
	diagnostics["wall_body_height"] = body_height
	var wall := _geometry()
	var joints: Dictionary = {}
	var endpoint_counts: Dictionary = {}
	var gate_keys: Dictionary = {}
	for endpoint in _gate_endpoints: gate_keys[_point_key(endpoint)] = true
	for edge in manifest.get("wall_edges", []):
		var a := _v(edge.a)
		var b := _v(edge.b)
		for endpoint in [a, b]:
			var endpoint_key := _point_key(endpoint)
			endpoint_counts[endpoint_key] = int(endpoint_counts.get(endpoint_key, 0)) + 1
		if edge.get("is_gate", false):
			_build_gate(a, b)
			diagnostics.gate_edges += 1
			continue
		# Every edge is the exact authored cell-union boundary, never a circle.
		var samples: Array = edge.get("samples", [])
		for i in range(1, samples.size()):
			var start := _v(samples[i - 1].position)
			var finish := _v(samples[i].position)
			_foundation_span(wall, start, finish, _wall_width, body_height, STONE)
			_foundation_span(wall, start, finish, _wall_width + 0.032, 0.055, STONE_LIGHT, body_height)
		var length: float = _xz(a).distance_to(_xz(b))
		var merlons := maxi(2, floori(length / 0.27))
		var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		for i in range(merlons):
			var p := _sample(a.lerp(b, (float(i) + 0.5) / float(merlons)))
			_box(wall, p + Vector3.UP * (body_height + 0.075), Vector3(0.11, 0.070, _wall_width + 0.025), STONE_LIGHT, -atan2(tangent.z, tangent.x))
		for p in [a, b]: joints[_point_key(p)] = p
		diagnostics.wall_edges += 1
	for count in endpoint_counts.values():
		if int(count) != 2: diagnostics.wall_endpoint_mismatches += 1
	diagnostics["perimeter_closed"] = diagnostics.wall_endpoint_mismatches == 0
	for key in joints:
		# The gate posts sit beyond its ends; round joints must not pinch the opening.
		if gate_keys.has(key): continue
		var p: Vector3 = _sample(joints[key])
		_cylinder(wall, p + Vector3.UP * ((_wall_height - 0.035) * 0.5), 0.115, _wall_height - 0.035, STONE_DARK, 6)
		_cylinder(wall, p + Vector3.UP * (_wall_height - 0.007), 0.135, 0.055, STONE_LIGHT, 6)
		diagnostics.wall_joints += 1
	_commit("ContinuousFacetedCurtainWall", wall, settlement_root)

func _build_gate(a: Vector3, b: Vector3) -> void:
	var fixed := _geometry()
	var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var yaw := -atan2(tangent.z, tangent.x)
	var span := _xz(a).distance_to(_xz(b))
	var leaf_length := span * 0.5 + 0.012
	var gate_height := _wall_height - 0.02
	# Low posts sit wholly beyond the authored opening. There is no overhead frame.
	for endpoint in [_sample(a) - tangent * 0.085, _sample(b) + tangent * 0.085]:
		var base: Vector3 = _sample(endpoint)
		_box(fixed, base + Vector3.UP * (gate_height * 0.5), Vector3(0.13, gate_height + 0.07, 0.13), STONE, yaw)
		_box(fixed, base + Vector3.UP * (gate_height + 0.05), Vector3(0.15, 0.055, 0.15), STONE_LIGHT, yaw)
	var minimum_clearance := INF
	for index in range(2):
		var source: Vector3 = _sample(a if index == 0 else b)
		var direction: Vector3 = tangent if index == 0 else -tangent
		var pivot := _root("LeftHingedLeaf" if index == 0 else "RightHingedLeaf", gate_leaf)
		pivot.position = source
		var closed_yaw := -atan2(direction.z, direction.x)
		var pose := _clear_gate_pose(_xz(source), Vector2(direction.x, direction.z), leaf_length)
		var moving := _geometry()
		var count := maxi(5, ceili(leaf_length / 0.065))
		for i in range(count):
			var distance := (float(i) + 0.5) * leaf_length / float(count)
			var foot := _sample(source + direction * distance)
			var local_center := Vector3(distance, foot.y - source.y + gate_height * 0.5 - 0.012, 0)
			_box(moving, local_center, Vector3(leaf_length / float(count) + 0.001, gate_height + 0.018, 0.030), TIMBER.lightened(float(i % 3) * 0.04))
		for level in [0.24, 0.80]:
			var middle := _sample(source + direction * leaf_length * 0.5)
			_box(moving, Vector3(leaf_length * 0.5, middle.y - source.y + gate_height * float(level), 0), Vector3(leaf_length, 0.038, 0.036), METAL)
		_commit("LowHingedWoodGate", moving, pivot)
		pivot.rotation.y = closed_yaw
		_gate_leaves.append({"node": pivot, "closed_yaw": closed_yaw, "open_yaw": float(pose.yaw), "clearance": float(pose.clearance)})
		minimum_clearance = minf(minimum_clearance, float(pose.clearance))
		var open_direction := Vector3(cos(float(pose.yaw)), 0, -sin(float(pose.yaw)))
		var open_end := source + open_direction * leaf_length
		_gate_reserved_segments.append([_xz(source), _xz(open_end)])
		diagnostics.gate_open_leaves.append({"hinge": [source.x, source.y, source.z],
			"open_end": [open_end.x, open_end.y, open_end.z], "closed_yaw": closed_yaw,
			"open_yaw": float(pose.yaw), "leaf_length": leaf_length,
			"half_thickness": GATE_LEAF_HALF_THICKNESS, "corridor_clearance": float(pose.clearance)})
	_commit("LowGatePosts", fixed, gate_root)
	gate_root.set_meta("clear_opening_endpoints", [a, b])
	gate_root.set_meta("gate_id", manifest.get("gate_id", ""))
	diagnostics["gate_open_corridor_clearance"] = minimum_clearance
	diagnostics["gate_full_edge_clearance"] = minimum_clearance >= ACTOR_CLEARANCE
	diagnostics["gate_frame_height"] = gate_height + 0.08

func _clear_gate_pose(hinge: Vector2, closed_direction: Vector2, length: float) -> Dictionary:
	# Prefer folding along the neighboring side-wall pocket. Evaluate final poses
	# against the true support-to-support corridor, never the geometric hex center.
	var inside: Vector3 = board._source_position(manifest.gate_inside_hex)
	var outside: Vector3 = board._source_position(manifest.gate_outside_hex)
	var best := {"yaw": -atan2(closed_direction.y, closed_direction.x), "clearance": -INF, "score": -INF}
	for degrees in [150.0, -150.0, 180.0, 120.0, -120.0, 90.0, -90.0]:
		var direction := closed_direction.rotated(deg_to_rad(float(degrees)))
		var minimum := INF
		var pocket_distance := 0.0
		for i in range(13):
			var point := hinge + direction * length * float(i) / 12.0
			minimum = minf(minimum, _segment_distance(point, _xz(inside), _xz(outside)) - GATE_LEAF_HALF_THICKNESS)
			pocket_distance += _boundary_distance(point)
		var clear := minimum >= ACTOR_CLEARANCE
		var score := (10.0 if clear else 0.0) + minf(minimum, 0.7) - pocket_distance * 0.20
		if score > float(best.score): best = {"yaw": -atan2(direction.y, direction.x), "clearance": minimum, "score": score}
	return best

func _build_houses() -> void:
	# Occupancy is a measured roof-overhang circle, not the whole available pocket.
	# Staged recipes create a coherent main roof, smaller neighbors, and yard cues.
	var candidates: Array = []
	if _boundary_segments.is_empty(): return
	var low: Vector2 = _boundary_segments[0][0]
	var high := low
	for pair in _boundary_segments:
		for p in pair:
			low = low.min(p)
			high = high.max(p)
	var center: Vector3 = board._source_position(manifest.center_hex)
	var step := 0.025 if manifest.get("site_kind", "") == "village" else CANDIDATE_STEP
	var wall_inset := _wall_width * 0.5 if bool(manifest.get("walled", true)) else 0.0
	for ix in range(floori(low.x / step), ceili(high.x / step) + 1):
		for iz in range(floori(low.y / step), ceili(high.y / step) + 1):
			var point := Vector2(float(ix) * step, float(iz) * step)
			if not _inside_union(point): continue
			var clearance := _route_distance(point)
			var boundary := _boundary_distance(point) - wall_inset
			var capacity := minf(clearance - ACTOR_CLEARANCE, boundary - 0.055)
			for gate_segment in _gate_reserved_segments:
				capacity = minf(capacity, _segment_distance(point, gate_segment[0], gate_segment[1]) - GATE_LEAF_HALF_THICKNESS - BUILDING_GAP)
			if capacity < 0.070: continue
			candidates.append({"position": Vector3(point.x, center.y, point.y), "capacity": capacity, "clearance": clearance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.capacity), float(b.capacity)): return float(a.capacity) > float(b.capacity)
		var ap: Vector3 = a.position
		var bp: Vector3 = b.position
		return ap.x < bp.x if not is_equal_approx(ap.x, bp.x) else ap.z < bp.z)
	var districts: Array = _district_rows.duplicate(true)
	if districts.is_empty(): districts = [{"id": "", "architectural_kit": "rural", "support_hexes": manifest.interior_hexes}]
	var geometries: Dictionary = {}
	for row in districts: geometries[str(row.id)] = _geometry()
	var lookahead_complete := false
	if manifest.get("site_kind", "") == "village" and districts.size() == 1:
		var budget := {"remaining": 10000, "visited": 0}
		var options: Array = []
		for item in COMPOSITION_RECIPES.rural:
			var available: Array = []
			for candidate in candidates:
				if float(candidate.capacity) + 0.000001 >= float(item[1]): available.append(candidate)
			options.append(available)
		var packed := _pack_village(options, COMPOSITION_RECIPES.rural, 0, [], budget)
		diagnostics["composition_search_visits"] = int(budget.visited)
		diagnostics["composition_search_exhausted"] = int(budget.remaining) <= 0
		lookahead_complete = packed.size() == COMPOSITION_RECIPES.rural.size()
		if lookahead_complete:
			for i in range(packed.size()):
				var row: Dictionary = districts[0].duplicate(true)
				row["model_path"] = "res://assets/city_districts/models/" + str(COMPOSITION_RECIPES.rural[i][0]) + ".glb"
				if str(COMPOSITION_RECIPES.rural[i][0]) == "shared_well": _emit_prop(geometries[str(row.id)], packed[i], row)
				else: _emit_house(geometries[str(row.id)], packed[i], row, i)
		diagnostics["village_lookahead_complete"] = lookahead_complete
	for stage in range(0 if lookahead_complete else 5):
		for row in districts:
			var kit := str(row.get("architectural_kit", "modest"))
			var recipe: Array = COMPOSITION_RECIPES.get(kit, COMPOSITION_RECIPES.modest)
			if stage >= recipe.size(): continue
			var asset_id := str(recipe[stage][0])
			var radius := float(recipe[stage][1])
			var chosen: Dictionary = {}
			for candidate in candidates:
				if float(candidate.capacity) + 0.000001 < radius: continue
				var point: Vector3 = candidate.position
				if not _inside_district(_xz(point), row): continue
				var allowed := true
				for existing in _building_sites + _prop_sites:
					if _xz(point).distance_to(Vector2(existing.position[0], existing.position[2])) < radius + float(existing.radius) + BUILDING_GAP:
						allowed = false
						break
				if allowed:
					chosen = candidate.duplicate(true)
					chosen["radius"] = radius
					break
			if chosen.is_empty():
				diagnostics.unplaced_recipe_entries.append({"district_id": str(row.id), "asset": asset_id, "radius": radius})
				continue
			var authored: Dictionary = row.duplicate(true)
			authored["model_path"] = "res://assets/city_districts/models/" + asset_id + ".glb"
			var is_prop := asset_id in ["garden_court", "workyard", "shared_well"]
			if is_prop: _emit_prop(geometries[str(row.id)], chosen, authored)
			else: _emit_house(geometries[str(row.id)], chosen, authored, stage)
	for row in districts:
		var target: Node3D = _district_roots.get(str(row.id), settlement_root)
		_commit("DistrictClosedRoofArt_" + str(row.get("architectural_kit", "modest")), geometries[str(row.id)], target)
		if diagnostics.districts.has(str(row.id)) and int(diagnostics.districts[str(row.id)].buildings) == 0:
			diagnostics.missing_district_sites.append(str(row.id))
	diagnostics["candidate_count"] = candidates.size()
	diagnostics["building_gap"] = BUILDING_GAP

func _pack_village(options: Array, recipe: Array, stage: int, chosen: Array, budget: Dictionary) -> Array:
	if stage == recipe.size(): return chosen.duplicate(true)
	if int(budget.remaining) <= 0: return []
	var radius := float(recipe[stage][1])
	for candidate in options[stage]:
		budget.remaining -= 1
		budget.visited += 1
		if int(budget.remaining) < 0: return []
		if float(candidate.capacity) + 0.000001 < radius: continue
		var position_: Vector3 = candidate.position
		var allowed := true
		for existing in chosen:
			if _xz(position_).distance_to(_xz(existing.position)) < radius + float(existing.radius) + BUILDING_GAP:
				allowed = false
				break
		if not allowed: continue
		var next: Dictionary = candidate.duplicate(true)
		next["radius"] = radius
		chosen.append(next)
		var feasible := true
		for future in range(stage + 1, recipe.size()):
			var has_space := false
			var future_radius := float(recipe[future][1])
			for possible in options[future]:
				var fits := true
				for occupied in chosen:
					if _xz(possible.position).distance_to(_xz(occupied.position)) < future_radius + float(occupied.radius) + BUILDING_GAP:
						fits = false
						break
				if fits:
					has_space = true
					break
			if not has_space:
				feasible = false
				break
		if not feasible:
			chosen.pop_back()
			continue
		var result := _pack_village(options, recipe, stage + 1, chosen, budget)
		if not result.is_empty(): return result
		chosen.pop_back()
	return []

func _build_district_roots() -> void:
	for value in manifest.get("districts", []):
		if not value is Dictionary or str(value.get("id", "")).is_empty(): continue
		var row: Dictionary = value.duplicate(true)
		var node := _root("District_" + str(row.get("architectural_kit", "modest")), self)
		node.set_meta("district_id", str(row.id))
		node.set_meta("architectural_kit", str(row.get("architectural_kit", "modest")))
		node.set_meta("source_mesh_sha256", manifest.get("source_mesh_sha256", ""))
		_district_roots[str(row.id)] = node
		_district_rows.append(row)
		diagnostics.districts[str(row.id)] = {"architectural_kit": row.get("architectural_kit", "modest"), "buildings": 0}

func _inside_district(point: Vector2, row: Dictionary) -> bool:
	for h in row.get("support_hexes", []):
		var center := Vector2(sqrt(3.0) * (float(h[0]) + float(h[1]) * 0.5), float(h[1]) * 1.5)
		var accepted := true
		# Convex pointy-top source hex, using the same one-unit source radius.
		for i in range(6):
			var angle := PI / 6.0 + TAU * float(i) / 6.0
			var next_angle := PI / 6.0 + TAU * float(i + 1) / 6.0
			var a := center + Vector2(cos(angle), sin(angle))
			var b := center + Vector2(cos(next_angle), sin(next_angle))
			if (b - a).cross(point - a) < -0.00001:
				accepted = false
				break
		if accepted: return true
	return false

func _street_facing_yaw(position_: Vector3, variation: float = 0.0) -> float:
	var point := _xz(position_)
	var target := point + Vector2(0, -1)
	var best := INF
	for segment in _route_segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var direction := b - a
		var t := clampf((point - a).dot(direction) / maxf(direction.length_squared(), 0.000001), 0.0, 1.0)
		var closest := a + direction * t
		var distance := point.distance_squared_to(closest)
		if distance < best:
			best = distance
			target = closest
	var facing := target - point
	if facing.length_squared() < 0.000001: return variation
	# Original kit fronts face local -Z; the conservative footprint stays invariant.
	return atan2(-facing.x, -facing.y) + variation

func _emit_house(buildings: Dictionary, candidate: Dictionary, row: Dictionary, pass_index: int) -> void:
	var p: Vector3 = _sample(candidate.position)
	var radius: float = candidate.radius
	var index := _building_sites.size()
	var kit := str(row.get("architectural_kit", "modest"))
	var district_id := str(row.get("id", ""))
	var wealthy := kit in ["affluent", "wealthy", "rich", "civic"]
	var industrial := kit in ["industrial", "industry", "workshop"]
	var hall := wealthy and pass_index == 0
	var yaw := _street_facing_yaw(p, 0.06 if index % 2 == 0 else -0.06)
	var width := radius * 1.18
	var depth := radius * 1.20
	var height := 1.20 if hall else (0.96 if industrial else (0.72 if kit == "rural" else 0.84))
	var roof_height := 0.44 if wealthy else (0.23 if industrial else 0.33)
	var plaster := Color("f0e2bf") if wealthy else (Color("9b7e65") if industrial else Color("d8ad76"))
	var roof_color := Color("347f92") if wealthy else (Color("58716c") if industrial else (Color("bba256") if kit == "rural" else Color("bf613d")))
	var floor_y := p.y
	var low_y := p.y
	var basis := Basis(Vector3.UP, yaw)
	for dx in [-0.5, 0.5]:
		for dz in [-0.5, 0.5]:
			var corner := _sample(p + basis * Vector3(width * float(dx), 0, depth * float(dz)))
			floor_y = maxf(floor_y, corner.y)
			low_y = minf(low_y, corner.y)
	var foundation_height := floor_y - low_y + 0.065
	p.y = floor_y + 0.025
	var target: Node3D = _district_roots.get(district_id, settlement_root)
	var model_row: Dictionary = row.duplicate(true)
	if str(model_row.get("model_path", "")).is_empty() and KIT_MODELS.has(kit):
		var variants: Array = KIT_MODELS[kit]
		model_row["model_path"] = "res://assets/city_districts/models/" + str(variants[pass_index % variants.size()]) + ".glb"
	var asset_data: Dictionary = _asset_rows.get(str(model_row.get("model_path", "")), {})
	var rendered_width := width
	var rendered_height := height + roof_height
	if not asset_data.is_empty():
		var asset_fit := radius * 0.95 / maxf(float(asset_data.get("footprint_radius", 0.001)), 0.001)
		var footprint: Array = asset_data.get("footprint_xz", [width, depth])
		rendered_width = minf(float(footprint[0]), float(footprint[1])) * asset_fit
		rendered_height = float(asset_data.get("height", rendered_height)) * asset_fit
	if rendered_width < MIN_ROOF_VISUAL_WIDTH:
		diagnostics.unplaced_recipe_entries.append({"district_id": district_id, "model_path": model_row.get("model_path", ""), "reason": "below_minimum_readable_roof_width"})
		return
	_box(buildings, Vector3(p.x, low_y + foundation_height * 0.5 - 0.035, p.z), Vector3(width + 0.018, foundation_height, depth + 0.018), STONE_DARK, yaw)
	var model_used := _instance_authored_kit(model_row, target, p, radius, yaw)
	if not model_used:
		_box(buildings, p + Vector3.UP * height * 0.5, Vector3(width, height, depth), plaster, yaw)
		_box(buildings, p + Vector3.UP * (height * 0.83), Vector3(width + 0.006, 0.028, depth + 0.006), STONE_LIGHT if wealthy else TIMBER, yaw)
		for dx in [-0.45, 0.45]:
			var beam := p + basis * Vector3(width * float(dx), height * 0.5, -depth * 0.503)
			_box(buildings, beam, Vector3(0.024, height, 0.024), STONE_LIGHT if wealthy else TIMBER, yaw)
		var door := p + basis * Vector3(0, height * 0.22, -depth * 0.506)
		_box(buildings, door, Vector3(width * (0.46 if industrial else 0.27), height * 0.43, 0.009), TIMBER, yaw)
		for sign_ in [-1.0, 1.0] if wealthy else [1.0]:
			var window := p + basis * Vector3(width * 0.27 * float(sign_), height * 0.61, -depth * 0.51)
			_box(buildings, window, Vector3(width * 0.16, height * 0.19, 0.011), Color("385d64"), yaw)
		_roof(buildings, p + Vector3.UP * height, Vector3(width + 0.024, roof_height, depth + 0.024), roof_color, yaw)
		if hall or industrial:
			var chimney := p + basis * Vector3(-width * 0.23, height + roof_height * 0.65, depth * 0.20)
			_box(buildings, chimney, Vector3(0.080 if industrial else 0.060, 0.42 if industrial else 0.22, 0.075), STONE_DARK if industrial else STONE_LIGHT, yaw)
	_building_sites.append({"position": [p.x, p.y, p.z], "radius": radius, "route_clearance": float(candidate.clearance) - radius,
		"kind": "closed_architectural_kit", "architectural_kit": kit, "district_id": district_id, "authored_model": model_used,
		"model_path": model_row.get("model_path", "") if model_used else "",
		"rendered_width": rendered_width, "rendered_height": rendered_height})
	if float(diagnostics.minimum_roof_visual_width) <= 0.0: diagnostics.minimum_roof_visual_width = rendered_width
	else: diagnostics.minimum_roof_visual_width = minf(float(diagnostics.minimum_roof_visual_width), rendered_width)
	diagnostics.buildings += 1
	if diagnostics.districts.has(district_id): diagnostics.districts[district_id].buildings += 1

func _emit_prop(ground: Dictionary, candidate: Dictionary, row: Dictionary) -> void:
	var radius: float = candidate.radius
	var p: Vector3 = _sample(candidate.position)
	var low_y := p.y
	var high_y := p.y
	for i in range(8):
		var angle := TAU * float(i) / 8.0
		var support := _sample(p + Vector3(cos(angle), 0, sin(angle)) * radius * 0.9)
		low_y = minf(low_y, support.y)
		high_y = maxf(high_y, support.y)
	var thickness := high_y - low_y + 0.03
	_cylinder(ground, Vector3(p.x, low_y + thickness * 0.5 - 0.018, p.z), radius * 0.91, thickness, STONE_DARK, 6)
	p.y = high_y + 0.012
	var district_id := str(row.get("id", ""))
	var target: Node3D = _district_roots.get(district_id, settlement_root)
	var yaw := _street_facing_yaw(p, 0.0)
	var model_used := _instance_authored_kit(row, target, p, radius, yaw)
	if not model_used: _cylinder(ground, p + Vector3.UP * radius * 0.35, radius * 0.72, radius * 0.7, STONE_LIGHT, 6)
	_prop_sites.append({"position": [p.x, p.y, p.z], "radius": radius,
		"route_clearance": float(candidate.clearance) - radius, "district_id": district_id,
		"architectural_kit": row.get("architectural_kit", ""), "model_path": row.get("model_path", ""), "authored_model": model_used})
	diagnostics.decorative_props += 1

func _load_asset_manifest() -> void:
	var material_path := "res://assets/city_districts/city_vertex_color.tres"
	_kit_material = load(material_path) as Material if ResourceLoader.exists(material_path) else null
	diagnostics["kit_vertex_color_fix"] = _kit_material != null
	var path := "res://assets/city_districts/manifest.json"
	if not FileAccess.file_exists(path): return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or raw.get("schema", "") != "city_district_kit/v1": return
	for row in raw.get("assets", []):
		if not row is Dictionary: continue
		var relative := str(row.get("glb", ""))
		if not relative.begins_with("models/") or relative.contains(".."): continue
		_asset_rows["res://assets/city_districts/" + relative] = row

func _instance_authored_kit(row: Dictionary, parent: Node3D, anchor: Vector3, radius: float, yaw: float) -> bool:
	var path := str(row.get("model_path", ""))
	if path.is_empty() or not path.begins_with("res://assets/city_districts/"): return false
	if not _asset_rows.has(path) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(_asset_rows[path].get("sha256", "")):
		if not path in diagnostics.asset_hash_failures: diagnostics.asset_hash_failures.append(path)
		return false
	if not ResourceLoader.exists(path):
		if not path in diagnostics.missing_asset_resources: diagnostics.missing_asset_resources.append(path)
		return false
	var resource: Resource = load(path)
	if not resource is PackedScene: return false
	var model: Node3D = resource.instantiate() as Node3D
	if model == null: return false
	parent.add_child(model)
	var found := false
	var bounds := AABB()
	var inverse := model.global_transform.affine_inverse()
	var mesh_nodes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D: mesh_nodes.append(model)
	for mesh_node in mesh_nodes:
		if mesh_node.mesh == null: continue
		if _kit_material != null: mesh_node.material_override = _kit_material
		diagnostics.triangles += int(mesh_node.mesh.get_faces().size() / 3)
		var box: AABB = inverse * mesh_node.global_transform * mesh_node.mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if not found:
		parent.remove_child(model)
		model.queue_free()
		return false
	var footprint_radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	if footprint_radius <= 0.0001:
		parent.remove_child(model)
		model.queue_free()
		return false
	var fit := radius * 0.95 / footprint_radius
	var centered_floor := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * fit)
	model.transform = Transform3D(basis, anchor - basis * centered_floor)
	model.set_meta("district_id", str(row.get("id", "")))
	model.set_meta("source_asset", path)
	model.set_meta("safe_footprint_radius", radius)
	var visual_width := minf(bounds.size.x, bounds.size.z) * fit
	if float(diagnostics.minimum_visual_model_width) <= 0.0: diagnostics.minimum_visual_model_width = visual_width
	else: diagnostics.minimum_visual_model_width = minf(float(diagnostics.minimum_visual_model_width), visual_width)
	# Reuse the same MeshInstance so district identity, exact mesh picking and
	# Godot frustum culling stay valid. Never run near and far nodes together.
	if mesh_nodes.size() == 1:
		var low_mesh := _load_lod_mesh(path, model, mesh_nodes[0])
		if low_mesh != null:
			var node: MeshInstance3D = mesh_nodes[0]
			_lod_entries.append({"node": node, "near": node.mesh, "far": low_mesh, "bounds": node.mesh.get_aabb(), "low": false, "pixels": 0.0})
			node.set_meta("city_lod", "full")
	diagnostics.authored_models += 1
	diagnostics.mesh_nodes += mesh_nodes.size()
	return true

func _local_mesh_transform(model: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != model:
		result = current.transform * result
		current = current.get_parent() as Node3D
		if current == null: return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
	return result

func _load_lod_mesh(path: String, model: Node3D, high_node: MeshInstance3D) -> Mesh:
	if _lod_mesh_cache.has(path): return _lod_mesh_cache[path]
	_lod_mesh_cache[path] = null
	var row: Dictionary = _asset_rows[path]
	var relative := str(row.get("lod1_glb", ""))
	if not relative.begins_with("lod1/") or relative.contains(".."):
		_lod_asset_failures.append(path + ": invalid LOD path")
		return null
	var low_path := "res://assets/city_districts/" + relative
	if not FileAccess.file_exists(low_path) or FileAccess.get_sha256(low_path) != str(row.get("lod1_sha256", "")) or not ResourceLoader.exists(low_path):
		_lod_asset_failures.append(low_path + ": missing or hash mismatch; full detail retained")
		return null
	var resource := load(low_path) as PackedScene
	if resource == null:
		_lod_asset_failures.append(low_path + ": not a PackedScene; full detail retained")
		return null
	var low_instance := resource.instantiate()
	if not low_instance is Node3D:
		_lod_asset_failures.append(low_path + ": not a Node3D; full detail retained")
		low_instance.free()
		return null
	var low_model: Node3D = low_instance
	var nodes: Array = low_model.find_children("*", "MeshInstance3D", true, false)
	if low_model is MeshInstance3D: nodes.append(low_model)
	var low_mesh: Mesh
	if nodes.size() == 1 and nodes[0].mesh != null and _local_mesh_transform(low_model, nodes[0]).is_equal_approx(_local_mesh_transform(model, high_node)):
		low_mesh = nodes[0].mesh
	else:
		_lod_asset_failures.append(low_path + ": unsupported hierarchy; full detail retained")
	low_model.free()
	_lod_mesh_cache[path] = low_mesh
	return low_mesh

func _projected_model_pixels(entry: Dictionary, camera: Camera3D) -> float:
	var box: AABB = entry.bounds
	var node: MeshInstance3D = entry.node
	var rectangle := Rect2()
	for i in range(8):
		var world := node.global_transform * box.get_endpoint(i)
		# Avoid perspective singularities. Frustum culling remains the renderer's job.
		if camera.is_position_behind(world): return INF
		var point := camera.unproject_position(world)
		if i == 0: rectangle = Rect2(point, Vector2.ZERO)
		else: rectangle = rectangle.expand(point)
	return maxf(rectangle.size.x, rectangle.size.y)

func _update_building_lod() -> void:
	if not is_instance_valid(board) or not is_instance_valid(board.camera): return
	var camera: Camera3D = board.camera
	var signature: Array = [camera.global_transform, camera.projection, camera.size, camera.fov, camera.keep_aspect, camera.get_viewport().get_visible_rect().size]
	if signature == _lod_camera_signature: return
	_lod_camera_signature = signature
	for entry in _lod_entries:
		if not is_instance_valid(entry.node): continue
		entry.pixels = _projected_model_pixels(entry, camera)
		var low := float(entry.pixels) < (LOD_EXIT_PIXELS if entry.low else LOD_ENTER_PIXELS)
		if low == bool(entry.low): continue
		entry.low = low
		var node: MeshInstance3D = entry.node
		node.mesh = entry.far if low else entry.near
		node.set_meta("city_lod", "simplified" if low else "full")
		var outline := node.get_node_or_null("SelectedEdgeGlow") as MeshInstance3D
		if outline != null: outline.mesh = node.mesh
		_lod_switches += 1

func lod_report(include_children: bool = true) -> Dictionary:
	var result: Dictionary = {"tracked_models": _lod_entries.size(), "full_models": 0, "simplified_models": 0, "displayed_kit_triangles": 0, "full_kit_triangles": 0, "switches": _lod_switches, "asset_failures": _lod_asset_failures.duplicate(), "enter_pixels": LOD_ENTER_PIXELS, "exit_pixels": LOD_EXIT_PIXELS}
	for entry in _lod_entries:
		if not is_instance_valid(entry.node): continue
		result["simplified_models" if entry.low else "full_models"] += 1
		result.displayed_kit_triangles += int(entry.node.mesh.get_faces().size() / 3)
		result.full_kit_triangles += int(entry.near.get_faces().size() / 3)
	if not include_children: return result
	for extra in _additional_views:
		var other: Dictionary = extra.lod_report()
		for key in ["tracked_models", "full_models", "simplified_models", "displayed_kit_triangles", "full_kit_triangles", "switches"]: result[key] += other[key]
		result.asset_failures.append_array(other.asset_failures)
	return result

func _build_title() -> void:
	title = Label3D.new()
	title.name = "SettlementName"
	title.text = str(manifest.get("name", "海岸聚落"))
	title.font_size = 26
	title.pixel_size = 0.006
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color.WHITE
	title.outline_size = 0
	var center: Vector3 = board._source_position(manifest.center_hex)
	var hexes: Array = manifest.get("interior_hexes", [])
	if hexes.size() > 1:
		center = Vector3.ZERO
		for h in hexes: center += board._source_position(h)
		center /= float(hexes.size())
	var source_anchor := _sample(center)
	_title_base_position = source_anchor + Vector3(0, 1.10, 0)
	title.position = _title_base_position
	settlement_root.add_child(title)
	diagnostics["title_source_anchor"] = [source_anchor.x, source_anchor.y, source_anchor.z]
	call_deferred("_apply_title_style")

func _apply_title_style() -> void:
	if _title_style_applied or not is_instance_valid(title) or not is_instance_valid(board): return
	if not is_instance_valid(board.name_style): return
	board.name_style.attach(title)
	_title_style_applied = true
	diagnostics["title_uses_existing_name_style"] = true

func _process(_delta: float) -> void:
	if visible: _update_building_lod()
	if visible and is_instance_valid(title) and is_instance_valid(board) and is_instance_valid(board.world_view):
		_apply_title_style()
		title.visible = not bool(board.world_view.overview)
		if title.visible: _separate_title_from_actor_names()

func _separate_title_from_actor_names() -> void:
	if not is_instance_valid(board.camera): return
	var camera: Camera3D = board.camera
	# Recompute from the fixed source-relative base, so camera movement cannot
	# accumulate offsets. Only this presentation label is ever repositioned.
	title.position = _title_base_position
	if camera.is_position_behind(title.global_position): return
	var base_world := title.global_position
	var title_rect := _projected_label_rect(title, camera)
	if not title_rect.has_area(): return
	var blockers: Array = []
	for actor_id in board.token_nodes:
		var token: Node3D = board.token_nodes[actor_id]
		if not is_instance_valid(token): continue
		var plate := token.get_node_or_null("Nameplate") as Label3D
		if not is_instance_valid(plate) or not plate.is_visible_in_tree() or camera.is_position_behind(plate.global_position): continue
		var rectangle := _projected_label_rect(plate, camera)
		if rectangle.has_area(): blockers.append({"id": str(actor_id), "rectangle": rectangle})
	var shifted := title_rect
	var offset_px := 0.0
	for attempt in range(blockers.size() + 1):
		var move_up := 0.0
		for block in blockers:
			var rectangle: Rect2 = block.rectangle
			if shifted.intersects(rectangle.grow(7.0)):
				move_up = maxf(move_up, shifted.end.y - rectangle.position.y + 8.0)
		if move_up <= 0.0: break
		offset_px += move_up
		shifted.position.y -= move_up
	if offset_px > 0.0:
		var base_screen := camera.unproject_position(base_world)
		var camera_local := camera.global_transform.affine_inverse() * base_world
		title.global_position = camera.project_position(base_screen - Vector2(0, offset_px), maxf(camera.near + 0.001, -camera_local.z))
	var final_rect := _projected_label_rect(title, camera)
	var overlaps := 0
	var minimum_gap := INF
	var actor_rects: Array = []
	for block in blockers:
		var rectangle: Rect2 = block.rectangle
		if final_rect.intersects(rectangle): overlaps += 1
		var dx := maxf(0.0, maxf(rectangle.position.x - final_rect.end.x, final_rect.position.x - rectangle.end.x))
		var dy := maxf(0.0, maxf(rectangle.position.y - final_rect.end.y, final_rect.position.y - rectangle.end.y))
		minimum_gap = minf(minimum_gap, Vector2(dx, dy).length())
		actor_rects.append({"id": block.id, "rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y]})
	diagnostics["title_screen_offset_px"] = offset_px
	diagnostics["title_actor_overlap_count"] = overlaps
	diagnostics["title_actor_min_gap_px"] = minimum_gap if is_finite(minimum_gap) else -1.0
	diagnostics["title_rect_px"] = [final_rect.position.x, final_rect.position.y, final_rect.size.x, final_rect.size.y]
	diagnostics["title_actor_rects_px"] = actor_rects
	diagnostics["title_source_base_height"] = 1.10

func _projected_label_rect(label: Label3D, camera: Camera3D) -> Rect2:
	var font_id := label.font.get_instance_id() if label.font != null else 0
	var key := "%d|%s|%d|%.8f|%s|%d" % [font_id, label.text, label.font_size, label.pixel_size, str(label.offset), label.outline_size]
	var local: Rect2
	if _label_bounds_cache.has(key): local = _label_bounds_cache[key]
	else:
		var mesh: TriangleMesh = label.generate_triangle_mesh()
		if mesh == null: return Rect2()
		var faces := mesh.get_faces()
		if faces.is_empty(): return Rect2()
		var first_vertex := Vector2(faces[0].x, faces[0].y)
		local = Rect2(first_vertex, Vector2.ZERO)
		for vertex in faces: local = local.expand(Vector2(vertex.x, vertex.y))
		if _label_bounds_cache.size() >= 128: _label_bounds_cache.clear()
		_label_bounds_cache[key] = local
	# Label3D is billboarded by the renderer; use camera axes rather than the
	# character's rotated basis, while retaining its actual inherited scale.
	var size_scale := label.global_transform.basis.get_scale().abs()
	var right := camera.global_transform.basis.x.normalized()
	var up := camera.global_transform.basis.y.normalized()
	var result := Rect2()
	var first_corner := true
	for corner in [local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]:
		var point := label.global_position + right * float(corner.x) * size_scale.x + up * float(corner.y) * size_scale.y
		var screen := camera.unproject_position(point)
		if first_corner:
			result = Rect2(screen, Vector2.ZERO)
			first_corner = false
		else: result = result.expand(screen)
	# Include anti-aliasing/outline and the soft actor-name shadow fringe.
	return result.grow(4.0)

func _point_key(p: Vector3) -> String:
	return "%d,%d" % [roundi(p.x * 100000.0), roundi(p.z * 100000.0)]

func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var direction := b - a
	var t := clampf((point - a).dot(direction) / maxf(direction.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + direction * t)

func _route_distance(point: Vector2) -> float:
	var result := INF
	for pair in _route_segments: result = minf(result, _segment_distance(point, pair[0], pair[1]))
	for row in _interior_anchors: result = minf(result, point.distance_to(_xz(row.position)))
	return result

func _boundary_distance(point: Vector2) -> float:
	var result := INF
	for pair in _boundary_segments: result = minf(result, _segment_distance(point, pair[0], pair[1]))
	return result

func _inside_union(point: Vector2) -> bool:
	# Odd-even test works without relying on manifest edge ordering.
	var crossings := 0
	for pair in _boundary_segments:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		if (a.y > point.y) == (b.y > point.y): continue
		var crossing_x := a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
		if crossing_x > point.x: crossings += 1
	return crossings % 2 == 1

func _geometry() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}

func _tri(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Helpers describe outward CCW faces; Godot front faces use clockwise order.
	for p in [a, c, b]:
		g.vertices.append(p)
		g.normals.append(normal)
		g.colors.append(color)

func _quad(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(g, a, b, c, color)
	_tri(g, a, c, d, color)

func _ground_quad(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y < 0.0: _quad(g, d, c, b, a, color)
	else: _quad(g, a, b, c, d, color)

func _box(g: Dictionary, center: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var p: Array[Vector3] = []
	for offset in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1), Vector3(-1,-1,1),
		Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(-1,1,1)]:
		p.append(center + basis * (offset * size * 0.5))
	var faces := [[0,1,2,3], [4,7,6,5], [0,4,5,1], [1,5,6,2], [2,6,7,3], [3,7,4,0]]
	for i in range(faces.size()):
		var f: Array = faces[i]
		var tone: float = [0.78, 1.06, 0.95, 0.88, 1.0, 0.92][i]
		_quad(g, p[f[0]], p[f[1]], p[f[2]], p[f[3]], color * tone)

func _roof(g: Dictionary, base: Vector3, size: Vector3, color: Color, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var p: Array[Vector3] = []
	for offset in [Vector3(-size.x*0.5,0,-size.z*0.5), Vector3(size.x*0.5,0,-size.z*0.5),
		Vector3(size.x*0.5,0,size.z*0.5), Vector3(-size.x*0.5,0,size.z*0.5),
		Vector3(0,size.y,-size.z*0.5), Vector3(0,size.y,size.z*0.5)]: p.append(base + basis * offset)
	_quad(g, p[0], p[3], p[5], p[4], color.lightened(0.07))
	_quad(g, p[1], p[4], p[5], p[2], color.darkened(0.09))
	_tri(g, p[0], p[4], p[1], color.darkened(0.16))
	_tri(g, p[3], p[2], p[5], color.darkened(0.10))
	_quad(g, p[0], p[1], p[2], p[3], TIMBER)

func _cylinder(g: Dictionary, center: Vector3, radius: float, height: float, color: Color, sides: int) -> void:
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		var b := TAU * float(i + 1) / float(sides)
		var lo := center + Vector3.UP * (-height * 0.5)
		var hi := center + Vector3.UP * (height * 0.5)
		var radial_a := Vector3(cos(a), 0, sin(a)) * radius
		var radial_b := Vector3(cos(b), 0, sin(b)) * radius
		_quad(g, lo + radial_a, hi + radial_a, hi + radial_b, lo + radial_b, color * (0.89 + 0.035 * float(i % 4)))
		_tri(g, hi, hi + radial_b, hi + radial_a, color.lightened(0.06))

func _foundation_span(g: Dictionary, a: Vector3, b: Vector3, width: float, height: float, color: Color, offset: float = 0.0) -> void:
	var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var side := Vector3(-tangent.z, 0, tangent.x) * width * 0.5
	var p: Array[Vector3] = [_sample(a - side), _sample(b - side), _sample(b + side), _sample(a + side)]
	for i in range(p.size()): p[i] += Vector3.UP * (offset - 0.028)
	var upper: Array[Vector3] = []
	for point in p: upper.append(point + Vector3.UP * (height + 0.028))
	for i in range(4):
		var j := (i + 1) % 4
		_quad(g, p[i], upper[i], upper[j], p[j], color * (0.97 if i % 2 == 0 else 0.90))
	_quad(g, upper[0], upper[3], upper[2], upper[1], color.lightened(0.06))

func _commit(label: String, g: Dictionary, parent: Node3D, shadows: bool = true) -> void:
	if g.vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g.vertices
	arrays[Mesh.ARRAY_NORMAL] = g.normals
	arrays[Mesh.ARRAY_COLOR] = g.colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	diagnostics.mesh_nodes += 1
	diagnostics.triangles += int(g.vertices.size() / 3)
