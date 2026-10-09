extends RefCounted
## Full-cell occupancy overlay. The original dry/building graph stays immutable.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const TraversalPolicy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const ID = "generated_v3_stationary_enemy_navigation/v1"
var base: RefCounted
var enemy_hex: Array = []
var enemy_key = ""
var source_hash = ""
var geometry_hash = ""
var renderer_profile = ""
var placement_hash = ""
var placement_profile = ""
var allowed: Dictionary = {}
var supported: Dictionary = {}
var support_heights: Dictionary = {}
var diagnostics: Dictionary = {}
var ready = false

func _init(base_navigation: RefCounted = null, occupied_hex: Array = []) -> void:
	if base_navigation == null or not valid_hex(occupied_hex): return
	var key = Planner.key(occupied_hex)
	if not base_navigation.allowed.has(key) or not base_navigation.supported.get(key, false): return
	base = base_navigation
	enemy_hex = occupied_hex.duplicate(); enemy_key = key
	source_hash = base.source_hash; geometry_hash = base.geometry_hash
	renderer_profile = base.renderer_profile
	placement_hash = base.placement_hash; placement_profile = base.placement_profile
	allowed = base.allowed.duplicate(true)
	allowed.erase(enemy_key)
	for cell in allowed: allowed[cell].erase(enemy_key)
	supported = base.supported.duplicate(true); supported[enemy_key] = false
	support_heights = base.support_heights.duplicate(true)
	diagnostics = {"navigation_id":ID, "source_hash":source_hash, "geometry_hash":geometry_hash, "placement_hash":placement_hash, "enemy_hex":enemy_hex.duplicate(), "occupancy":"entire_hex_alive_or_downed", "removed_vertex":enemy_key, "removed_undirected_edges":base.allowed[enemy_key].size(), "base_graph_unchanged":true, "terrain_cost_modifier":1}
	ready = true

static func valid_hex(value: Variant) -> bool:
	return value is Array and value.size() == 2 and C.integer(value[0]) and C.integer(value[1]) and absf(float(value[0])) <= 1000 and absf(float(value[1])) <= 1000

func cell_center(hex: Array) -> Vector3:
	return base.cell_center(hex) if ready and valid_hex(hex) else Vector3.INF

func cell_at_xz(point: Vector2) -> Dictionary:
	return base.cell_at_xz(point) if ready else C.fail("ENEMY_NAV_NOT_READY", "敌人占格导航尚未通过校验。")

func height_at_xz(point: Vector2) -> Dictionary:
	return base.height_at_xz(point) if ready else C.fail("ENEMY_NAV_NOT_READY", "敌人占格导航尚未通过校验。")

func step(from: Array, to: Array) -> Dictionary:
	if not ready or not valid_hex(from) or not valid_hex(to): return C.fail("ENEMY_NAV_NOT_READY", "敌人占格导航或地格无效。")
	var a = Planner.key(from); var b = Planner.key(to)
	if a == enemy_key or b == enemy_key: return C.fail("ENEMY_OCCUPIED", "敌人占据整个地格；倒下后仍不能穿过。")
	if not allowed.has(a) or not allowed.has(b) or not b in allowed[a] or not a in allowed[b]: return C.fail("ENEMY_NO_EDGE", "没有经过校验且不穿过敌人的干地通路。")
	return base.step(from, to)

func route_points(route: Array) -> Array:
	if not ready or route.is_empty(): return []
	for hex in route:
		if not valid_hex(hex) or Planner.key(hex) == enemy_key or not allowed.has(Planner.key(hex)): return []
	for i in range(1, route.size()):
		if not step(route[i - 1], route[i]).ok: return []
	return base.route_points(route)

func plan(state: Dictionary, target: Variant, budget: int) -> Dictionary:
	var identity: Variant = state.get("generated_world", {})
	if not ready or not identity is Dictionary or identity.get("source_contract") != "generated_v3_source/v1" or identity.get("content_hash") != source_hash or identity.get("geometry_hash") != geometry_hash or identity.get("renderer_profile") != renderer_profile or identity.get("placement_hash") != placement_hash or identity.get("placement_profile") != placement_profile:
		return C.fail("ENEMY_NAV_IDENTITY", "世界与敌人占格导航的来源不一致，未执行移动。")
	if not valid_hex(target): return C.fail("MOVE_TARGET", "目标必须是两个整数构成的地格。")
	if not state.get("actors") is Dictionary or not state.actors.get("actor_player") is Dictionary or not valid_hex(state.actors.actor_player.get("hex")) or not state.get("hexes") is Dictionary: return C.fail("ENEMY_NAV_STATE", "移动缺少有效旅人或地格资料。")
	if Planner.key(target) == enemy_key: return C.fail("ENEMY_OCCUPIED", "敌人占据整个地格；倒下后仍不能进入。")
	return TraversalPolicy.plan(state, "actor_player", target, budget, func(a, b): return step(a, b))

func export_data(spawn: Array = []) -> Dictionary:
	return {"source_hash":source_hash, "geometry_hash":geometry_hash, "renderer_profile":renderer_profile, "placement_hash":placement_hash, "placement_profile":placement_profile, "enemy_hex":enemy_hex.duplicate(), "allowed":allowed.duplicate(true), "supported":supported.duplicate(true), "support_heights":support_heights.duplicate(true), "spawn":spawn.duplicate(), "diagnostics":diagnostics.duplicate(true)}
