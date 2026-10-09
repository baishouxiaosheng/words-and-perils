extends RefCounted
## A named, exact offline two-operation example. No free-text parser.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const ID := "coast_move_then_attack_v1"
static func spec(snapshot: Dictionary, focus: Dictionary = {}) -> Dictionary:
	var actor: Dictionary = snapshot.actors.actor_player
	var weapon_id: String = actor.get("equipment", {}).get("weapon", "")
	var target_id: String = focus.get("id", "actor_raider") if focus.get("kind", "") == "actor" else "actor_raider"
	if actor.scene_id != "scene_coast" or not snapshot.items.has(weapon_id) or not snapshot.items[weapon_id].has("weapon_profile") or not snapshot.actors.has(target_id): return {}
	var target: Dictionary = snapshot.actors[target_id]; var profile: Dictionary = snapshot.items[weapon_id].weapon_profile
	if target.health.current <= 0 or not target.faction in actor.get("combat_profile", {}).get("hostile_factions", []) or actor.scene_id != target.scene_id: return {}
	var candidates: Array = []
	if focus.get("kind", "") == "tile": candidates.append(focus.hex.duplicate())
	else:
		for delta in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]: candidates.append([int(target.hex[0]) + delta[0], int(target.hex[1]) + delta[1]])
	var best: Dictionary = {}
	for point in candidates:
		var route := Navigation.plan_weighted_route(snapshot, actor.id, point, int(actor.stamina.current) - int(profile.stamina_cost))
		if not route.ok: continue
		var at_arrival: Dictionary = snapshot.duplicate(true); at_arrival.actors[actor.id].hex = point.duplicate(); at_arrival.actors[actor.id].stamina.current -= int(route.cost)
		if not Basic.can_authored_attack(at_arrival, actor.id, target_id): continue
		if best.is_empty() or int(route.cost) < int(best.cost): best = {"cost": route.cost, "arrival": point.duplicate()}
	if best.is_empty(): return {}
	return {"actor_id": actor.id, "target_hex": best.arrival, "target_actor_id": target_id, "weapon_item_id": weapon_id}
static func goal(facts: Dictionary, bindings: Dictionary) -> String:
	if not C.exact_fields(bindings, ["actor_id", "target_hex", "target_actor_id", "weapon_item_id"]) or not facts.items.has(bindings.weapon_item_id) or not facts.actors.has(bindings.target_actor_id) or not bindings.target_hex is Array or bindings.target_hex.size() != 2 or not C.integer(bindings.target_hex[0]) or not C.integer(bindings.target_hex[1]): return ""
	return "【署名复合样例】先按地形路线行至（%d，%d），再用%s攻击%s（%s）。" % [bindings.target_hex[0], bindings.target_hex[1], facts.items[bindings.weapon_item_id].name, facts.actors[bindings.target_actor_id].name, bindings.target_actor_id]
static func assessment(request: Dictionary, bindings: Dictionary) -> Dictionary:
	var facts: Dictionary = request.context.facts
	if request.context.actor_id != "actor_player" or request.context.goal != goal(facts, bindings): return C.fail("FIXTURE_SCOPE", "The entire two-operation goal and exact bindings must match the authored sample.")
	var paths: Array = ["/actors/actor_player", "/actors/" + bindings.target_actor_id, "/items/" + bindings.weapon_item_id, "/hexes/%d,%d" % bindings.target_hex]
	var ammo: String = facts.items[bindings.weapon_item_id].weapon_profile.cost_item_id
	if not ammo.is_empty(): paths.append("/items/" + ammo)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found := C.pointer(facts, path)
		if not found.ok: return C.fail("FIXTURE_FACT", "A required compound fact is unavailable.")
		var id := "compound_" + str(refs.size()); refs.append({"id": id, "path": path, "expected": found.value}); ids.append(id)
	var components: Array = []
	for id in ["move", "accuracy", "impact"]: components.append({"id": id, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "possible", "fact_ref_ids": ids.duplicate()})
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "两项署名操作已共同评估，路线、攻击和全部分支将一起冻结；尚无结果。", "interpretation": "仅这两项明确顺序操作；不忽略额外意图，不免费追加攻击。", "resolver_id": ID, "bindings": bindings.duplicate(true), "components": components, "fact_refs": refs, "provenance": {"provider": "项目作者 · 明确署名复合样例 move_then_attack/v1", "live": false, "kind": "fixture"}}}
