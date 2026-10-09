extends RefCounted
## A fixed, full-size original pawn, admitted only at an existing dry cell center.
## No source, mesh, scale, spawn or original edge is modified to make it fit.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface = preload("res://core/generated_v3_placement/surface.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const Tokens = preload("res://view/chess_tokens.gd")
const Navigation = preload("res://view/generated_v3_enemy/navigation.gd")
const ID = "generated_v3_stationary_enemy_placement/v1"
const ROLE = "stationary_enemy_0"
const SCALE = 1.0
const CLEARANCE = .38
const MAX_GRADIENT = .30
const MAX_SPREAD = .055
const DRY_CLEARANCE = .01

static func build(source: RefCounted, enemy_id: String) -> Dictionary:
	if source == null or enemy_id.is_empty(): return C.fail("ENEMY_SOURCE", "敌人安放需要已经校验的村落来源。")
	var data: Variant = source.get("data"); var identity: Variant = source.get("identity")
	var placement: Variant = source.get("placement_result"); var world: Variant = source.get("world")
	var nav: Variant = source.get("navigation")
	if not data is Dictionary or not identity is Dictionary or not placement is Dictionary or not world is Dictionary or not nav is RefCounted or not placement.get("ok", false): return C.fail("ENEMY_SOURCE", "敌人安放需要已经校验的村落来源。")
	if source.get("features") != {"vegetation":false} or not source.get("vegetation_result") is Dictionary or not source.get("vegetation_result").is_empty(): return C.fail("ENEMY_PLACEMENT_ORDER", "请先安放敌人，再以完整人物占地建立植被。")
	var manifest: Dictionary = placement.get("manifest", {})
	var surface: Variant = placement.get("surface")
	if not surface is RefCounted or manifest.get("source_hash") != data.get("content_hash") or manifest.get("geometry_hash") != identity.get("geometry_hash") or surface.get("geometry_hash") != identity.get("geometry_hash") or nav.get("placement_hash") != manifest.get("placement_hash") or not manifest.get("settlements") is Array or manifest.settlements.is_empty(): return C.fail("ENEMY_SOURCE", "敌人与村落、原生地面和通路必须属于同一来源。")
	if not world.get("actors") is Dictionary or not world.actors.has("actor_player"): return C.fail("ENEMY_ORIGIN", "敌人安放缺少原始旅人起点。")
	var origin: Array = world.actors.actor_player.hex.duplicate()
	if not Navigation.valid_hex(origin) or not nav.supported.get(Planner.key(origin), false): return C.fail("ENEMY_ORIGIN", "原始旅人起点必须有干地支撑。")
	var original: Dictionary = Planner.distances(nav.allowed, Planner.key(origin))
	var original_keys: Array = original.keys(); original_keys.sort()
	var declared: Variant = source.get("spawn_component")
	if not declared is Dictionary: return C.fail("ENEMY_COMPONENT", "原始连通地格资料缺失。")
	var declared_keys: Array = declared.keys(); declared_keys.sort()
	if original_keys != declared_keys: return C.fail("ENEMY_COMPONENT", "村落通路与原始起点连通域不一致。")
	var site: Dictionary = manifest.settlements[0]
	var npc_reservations: Variant = source.get("npc_reservations")
	if not npc_reservations is Array: return C.fail("ENEMY_NPC_RESERVATIONS", "守路村民的完整占地资料缺失。")
	for reservation in npc_reservations:
		if not reservation is Dictionary or reservation.get("source_hash") != data.content_hash or reservation.get("geometry_hash") != identity.geometry_hash or reservation.get("placement_hash") != manifest.placement_hash or not reservation.get("footprint") is Array or not Surface.valid_polygon(Surface.as_points(reservation.footprint)): return C.fail("ENEMY_NPC_RESERVATIONS", "人物占地与当前地图不一致。")
	var token: Node3D = Tokens.build(enemy_id, {"role":"enemy", "faction":"hostile"})
	var points: Array = []
	var measured = _vertices(token, Transform3D.IDENTITY, points)
	var native_piece: String = str(token.get_meta("chess_piece", "")); token.free()
	if not measured or points.is_empty() or native_piece != "pawn": return C.fail("ENEMY_ASSET", "敌人必须使用完整原始兵棋模型。")
	var projected: Array = []; var low: Array = []; var ymin = INF; var ymax = -INF; var radius = 0.0
	for p: Vector3 in points:
		projected.append(Vector2(p.x, p.z)); ymin = minf(ymin, p.y); ymax = maxf(ymax, p.y)
		radius = maxf(radius, Vector2(p.x, p.z).length())
	for p: Vector3 in points:
		if p.y <= ymin + .025: low.append(Vector2(p.x, p.z))
	var raw_full: Array = Surface.hull(projected); var raw_sole: Array = Surface.hull(low)
	if not Surface.valid_polygon(raw_full) or not Surface.valid_polygon(raw_sole) or radius > .381 or radius < .379: return C.fail("ENEMY_ASSET_BOUNDS", "敌人的原始模型占地不符；未缩小或替换棋子。")
	var geometry: Dictionary = geometry_record(points)
	var entry_distances: Dictionary = Planner.distances(nav.allowed, Planner.key(site.entry_hex))
	var candidates: Array = original.keys()
	# Closest to the admitted village entry first, then a stable axial key.
	# This finite order is seed/source derived and independent of camera/save state.
	candidates.sort_custom(func(a, b): return int(entry_distances.get(a, 2147483647)) < int(entry_distances.get(b, 2147483647)) if entry_distances.get(a, 2147483647) != entry_distances.get(b, 2147483647) else a < b)
	var rejected: Dictionary = {}; var attempted = 0; var edge_support_cache: Dictionary = {}
	for key in candidates:
		attempted += 1
		var hex: Array = Planner.hex_(key)
		var taken = false
		for actor in world.actors.values():
			if C.bytes(actor.hex) == C.bytes(hex): taken = true; break
		if taken: _reject(rejected, "actor_cell"); continue
		if not nav.supported.get(key, false) or data.cells[key].get("river", false): _reject(rejected, "unsupported_or_river"); continue
		var center: Vector3 = nav.cell_center(hex)
		if not center.is_finite(): _reject(rejected, "center"); continue
		var offset = Vector2(center.x, center.z)
		var full_points: Array = []; var sole_points: Array = []
		for p in raw_full: full_points.append(p + offset)
		for p in raw_sole: sole_points.append(p + offset)
		var full: Array = Surface.quantized_enclosure(full_points)
		var sole: Array = Surface.quantized_enclosure(sole_points)
		var support: Dictionary = surface.support(full, MAX_GRADIENT, MAX_SPREAD, DRY_CLEARANCE)
		if not support.ok: _reject(rejected, str(support.get("code", "support"))); continue
		var blocked = false
		for building in manifest.buildings:
			if Surface.area(Surface.clip(full, Surface.as_points(building.footprint))) > .00000001: blocked = true; break
		if blocked: _reject(rejected, "building_overlap"); continue
		for reservation in npc_reservations:
			if Surface.area(Surface.clip(full, Surface.as_points(reservation.footprint))) > .00000001: blocked = true; break
		if blocked: _reject(rejected, "npc_overlap"); continue
		# Every still-usable walking edge must clear both full plinths. The six
		# incident edges terminate at the enemy and are removed from movement.
		var envelope: Array = Surface.expanded(full, CLEARANCE)
		for a in nav.allowed:
			if a == key: continue
			var pa: Vector3 = nav.cell_center(Planner.hex_(a))
			for b in nav.allowed[a]:
				if b == key or a >= b: continue
				var pb: Vector3 = nav.cell_center(Planner.hex_(b))
				if Surface.segment_hits(Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), envelope): blocked = true; break
			if blocked: break
		if blocked: _reject(rejected, "remaining_corridor"); continue
		var occupied_nav = Navigation.new(nav, hex)
		if not occupied_nav.ready: _reject(rejected, "navigation"); continue
		var reachable: Dictionary = Planner.distances(occupied_nav.allowed, Planner.key(origin))
		var expected: Array = original_keys.duplicate(); expected.erase(key)
		var reached: Array = reachable.keys(); reached.sort()
		if reached != expected: _reject(rejected, "disconnects_original_component"); continue
		var anchors: Array = []
		for adjacent in nav.allowed[key]:
			if reachable.has(adjacent) and nav.step(Planner.hex_(adjacent), hex).get("ok", false) and nav.step(hex, Planner.hex_(adjacent)).get("ok", false): anchors.append(adjacent)
		if anchors.is_empty(): _reject(rejected, "no_reachable_melee_anchor"); continue
		anchors.sort_custom(func(a, b): return int(reachable[a]) < int(reachable[b]) if reachable[a] != reachable[b] else a < b)
		var approach: Dictionary = {}; var bypasses: Array = []
		# Witnesses are scoped to this encounter, not a new global navigation rule.
		# Find genuine full-foot dry routes without changing any baseline edge.
		for adjacent in anchors:
			var route_proof: Dictionary = _safe_path(occupied_nav, surface, manifest, npc_reservations, world, Planner.key(origin), adjacent, edge_support_cache)
			if route_proof.ok:
				approach = route_proof; break
		if approach.is_empty(): _reject(rejected, "no_full_foot_dry_approach"); continue
		var anchor_key: String = Planner.key(approach.route[-1])
		for adjacent in anchors:
			if adjacent == anchor_key: continue
			var bypass: Dictionary = _safe_path(occupied_nav, surface, manifest, npc_reservations, world, anchor_key, adjacent, edge_support_cache)
			if not bypass.ok: blocked = true; break
			bypasses.append(bypass)
		if blocked: _reject(rejected, "no_full_foot_dry_bypass"); continue
		var y = Surface.ceil_q(float(support.max_height) - ymin + .002)
		var gaps: Dictionary = surface.plane_gaps(sole, [0.0, 0.0, y + ymin])
		if not gaps.ok or gaps.min_gap < 0.0 or gaps.max_gap > MAX_SPREAD + .003: _reject(rejected, "sole_gaps"); continue
		var position_ = Vector3(center.x, y, center.z)
		var anchor: Array = Planner.hex_(anchor_key)
		var witness = {"schema_version":ID, "placement_hash":manifest.placement_hash, "settlement_id":site.id, "role":ROLE, "hex":hex, "position_q40":Planner.exact_coordinate_row(position_), "position_scale":Planner.COORDINATE_SCALE, "support_witness":{"source_hash":data.content_hash, "geometry_hash":identity.geometry_hash, "token_source_sha256":geometry.token_source_sha256, "raw_geometry_sha256":geometry.float32_sha256, "scale":SCALE, "yaw":0, "raw_full_footprint":raw_footprint_encoding(raw_full), "footprint":Surface.as_json(full), "bounds":{"radius":Surface.ceil_q(radius), "min_y":Surface.floor_q(ymin), "max_y":Surface.ceil_q(ymax)}, "support":support, "sole_gaps":gaps, "clearance_radius":CLEARANCE, "corridors_clear":true, "cell_center_exact":true, "fixed_candidate":attempted - 1, "attack_anchor_hex":anchor, "original_spawn_hex":origin, "original_component_size":original_keys.size(), "remaining_component_size":reached.size(), "remaining_component_hash":C.digest(reached), "preserves_all_other_original_nodes":true, "encounter_route_support":{"radius":CLEARANCE, "dry_clearance":DRY_CLEARANCE, "approach":approach, "bypasses":bypasses, "scope":"selected spawn approach and enemy-neighbor bypasses only; original graph unchanged"}}}
		var reservation = {"source_hash":data.content_hash, "geometry_hash":identity.geometry_hash, "placement_hash":manifest.placement_hash, "actor_id":enemy_id, "hex":hex, "footprint":Surface.as_json(full), "position_q40":witness.position_q40, "position_scale":Planner.COORDINATE_SCALE, "scale":SCALE, "occupies_entire_hex":true}
		var diagnostics = {"attempted":attempted, "rejected":rejected, "native_vertex_count":points.size(), "candidate_policy":"village_entry_graph_distance_then_axial_key", "full_size_original_pawn":true, "attack_anchor_hex":anchor, "attack_anchor_distance_from_spawn":approach.route.size() - 1, "route_support_edges_checked":edge_support_cache.size(), "original_component_size":original_keys.size(), "remaining_component_size":reached.size(), "sole_footprint":Surface.as_json(sole)}
		return {"ok":true, "placement_witness":C.normalized(witness), "reservations":C.normalized([reservation]), "diagnostics":C.normalized(diagnostics), "metrics":C.normalized(diagnostics), "raw_geometry":geometry, "attack_anchor_hex":anchor.duplicate()}
	return {"ok":false, "code":"ENEMY_PLACEMENT_UNAVAILABLE", "errors":["这张地图没有同时满足完整尺寸干地支撑、人物净空和连通通路的敌人位置；未改变种子、地形、起点或棋子尺寸。"], "diagnostics":{"attempted":attempted, "rejected":rejected, "fixed_scale":SCALE}}

static func _safe_path(nav: RefCounted, surface: RefCounted, manifest: Dictionary, reservations: Array, state: Dictionary, start: String, target: String, cache: Dictionary) -> Dictionary:
	if not nav.allowed.has(start) or not nav.allowed.has(target): return {"ok":false}
	var center: Vector3 = nav.cell_center(Planner.hex_(target))
	var anchor_support: Dictionary = surface.support(Surface.expanded([Vector2(center.x, center.z)], CLEARANCE), 65536.0, 65536.0, DRY_CLEARANCE)
	if not anchor_support.ok: return {"ok":false, "code":"anchor_full_foot_support"}
	var parents: Dictionary = {start:""}; var queue: Array = [start]; var cursor = 0
	while cursor < queue.size() and not parents.has(target):
		var current: String = queue[cursor]; cursor += 1
		for next in nav.allowed[current]:
			if parents.has(next): continue
			var edge_key: String = current + "|" + next if current < next else next + "|" + current
			if not cache.has(edge_key): cache[edge_key] = _edge_support(nav, surface, manifest, reservations, current, next)
			if not cache[edge_key].ok: continue
			parents[next] = current; queue.append(next)
	if not parents.has(target): return {"ok":false, "code":"no_full_foot_support_route"}
	var route: Array = []; var edge_witnesses: Array = []; var key_: String = target
	while not key_.is_empty():
		route.push_front(Planner.hex_(key_))
		var prior: String = parents[key_]
		if not prior.is_empty():
			var edge_key: String = prior + "|" + key_ if prior < key_ else key_ + "|" + prior
			edge_witnesses.push_front({"from":Planner.hex_(prior), "to":Planner.hex_(key_), "support":cache[edge_key].support, "swept_footprint_hash":cache[edge_key].swept_footprint_hash})
		key_ = prior
	var actual: Dictionary = _runtime_routes(nav, surface, manifest, reservations, state, route, cache)
	if not actual.ok: return actual
	return {"ok":true, "route":route, "anchor_full_foot_support":anchor_support, "edges":edge_witnesses, "runtime_plans":actual.plans, "runtime_route_policy":"actual Navigation.plan at maximum existing stamina, every waypoint to final target and each next committed step"}

static func _runtime_routes(nav: RefCounted, surface: RefCounted, manifest: Dictionary, reservations: Array, state: Dictionary, route: Array, cache: Dictionary) -> Dictionary:
	var probe: Dictionary = state.duplicate(true); var plans: Array = []
	probe.actors.actor_player.stamina.current = probe.actors.actor_player.stamina.max
	var budget: int = int(probe.actors.actor_player.stamina.current)
	for i in range(route.size() - 1):
		probe.actors.actor_player.hex = route[i].duplicate()
		var targets: Array = [route[i + 1]]
		if route[i + 1] != route[-1]: targets.append(route[-1])
		for target in targets:
			var actual: Dictionary = nav.plan(probe, target, budget)
			if not actual.ok:
				if target == route[i + 1] or actual.get("code") != "MOVE_UNREACHABLE_WITHIN_BUDGET": return {"ok":false, "code":"runtime_route_missing"}
				continue
			for j in range(1, actual.route.size()):
				var a: String = Planner.key(actual.route[j - 1]); var b: String = Planner.key(actual.route[j])
				var edge_key: String = a + "|" + b if a < b else b + "|" + a
				if not cache.has(edge_key): cache[edge_key] = _edge_support(nav, surface, manifest, reservations, a, b)
				if not cache[edge_key].ok: return {"ok":false, "code":"actual_runtime_route_footprint", "from":route[i], "target":target, "edge":[a, b]}
			plans.append({"from":route[i].duplicate(), "target":target.duplicate(), "route":actual.route.duplicate(true), "cost":actual.cost, "budget":actual.budget})
	return {"ok":true, "plans":plans}

static func _edge_support(nav: RefCounted, surface: RefCounted, manifest: Dictionary, reservations: Array, a: String, b: String) -> Dictionary:
	var pa: Vector3 = nav.cell_center(Planner.hex_(a)); var pb: Vector3 = nav.cell_center(Planner.hex_(b))
	var sweep: Array = Surface.expanded([Vector2(pa.x, pa.z), Vector2(pb.x, pb.z)], CLEARANCE)
	var support: Dictionary = surface.support(sweep, 65536.0, 65536.0, DRY_CLEARANCE)
	if not support.ok: return {"ok":false, "code":support.get("code", "full_foot_support")}
	for building in manifest.buildings:
		if Surface.area(Surface.clip(sweep, Surface.as_points(building.footprint))) > .00000001: return {"ok":false, "code":"full_foot_building"}
	for reservation in reservations:
		if Surface.area(Surface.clip(sweep, Surface.as_points(reservation.footprint))) > .00000001: return {"ok":false, "code":"full_foot_npc"}
	return {"ok":true, "support":support, "swept_footprint_hash":C.digest(Surface.as_json(sweep))}

static func _reject(rejected: Dictionary, code: String) -> void:
	rejected[code] = int(rejected.get(code, 0)) + 1

static func _vertices(node: Node, parent: Transform3D, result: Array) -> bool:
	var transform = parent
	if node is Node3D: transform = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return false
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = transform * vertex
				if not point.is_finite(): return false
				result.append(point)
	for child in node.get_children():
		if not _vertices(child, transform, result): return false
	return true

static func position(witness: Dictionary) -> Vector3:
	var p: Array = witness.position_q40
	return Vector3(p[0], p[1], p[2]) / float(witness.position_scale)

static func raw_footprint_encoding(points: Array) -> Dictionary:
	# Raw Vector2 mesh coordinates are float32. Keep their exact bits across
	# JSON/disk round trips instead of lossy decimal double serialization.
	# encode_float writes IEEE754 binary32 in little-endian byte order.
	var bytes = PackedByteArray()
	bytes.resize(points.size() * 8)
	for i in points.size():
		var point: Vector2 = points[i]
		bytes.encode_float(i * 8, point.x)
		bytes.encode_float(i * 8 + 4, point.y)
	return {"encoding":"float32_le_xz_hex/v1", "point_count":points.size(), "bytes_hex":bytes.hex_encode()}

static func geometry_record(points: Array) -> Dictionary:
	var packed = PackedVector3Array(points); var hash_ = HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256); hash_.update(packed.to_byte_array())
	var rows: Array = []
	for p in packed: rows.append([p.x, p.y, p.z])
	return {"vertices":rows, "float32_sha256":hash_.finish().hex_encode(), "token_source_sha256":FileAccess.get_sha256("res://view/chess_tokens.gd"), "fixed_scale":SCALE, "indexed":false, "scope":"all emitted raw surface vertices with node transforms; duplicate vertices retained"}
