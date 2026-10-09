extends RefCounted
## Versioned replacement: old coast_move_path_v2 is deliberately unchanged.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const ID := "coast_move_route_v3"
func resolver_id() -> String: return ID
func action_schema() -> Dictionary:
	return {"schema_version":"coast_movement/v3","resolver_id":ID,"bindings":{"actor_id":"actor_player","target_hex":"explicit current-scene destination [q,r]"},"components":["move"],"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/hexes/<target_q,r> or /scene_hexes/<scene_id>/<target_q,r>"],"traversal_policy":Policy.ID,"terrain_costs":Policy.COSTS,"unknown_terrain_cost":2,"capabilities":"immutable authored traversal_profile discounts 0..2, max_action_cost 1..32; active flight lowers dry terrain effort to 1 but cannot cross water or air/all walls","budget":"min(current stamina, authored max_action_cost)","route_policy":"deterministic minimum accumulated cost with positive integer edges; source rules terrain only; visual height excluded","turn_cost":1,"hooks_per_action":1,"every_intent_requires_assessment":true}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String: return "weighted_move:"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, _assessment: Dictionary) -> Dictionary:
	var result := {"actor":snapshot.actors.actor_player,"cells":Policy.scene_cells(snapshot,snapshot.actors.actor_player.scene_id),"world":snapshot.get("generated_world",{})}
	if snapshot.has("settlement_state"): result.settlement = snapshot.settlement_state
	return result
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var frozen := freeze(snapshot,assessment)
	return {"ok":true,"policies":{"move":"safe_direct"}} if frozen.ok else frozen
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if not C.exact_fields(b,["actor_id","target_hex"]) or b.actor_id != "actor_player": return C.fail("ACTION_BINDING","移动必须明确绑定旅人与当前场景目标格。")
	if assessment.components.size()!=1 or assessment.components[0].id!="move": return C.fail("ACTION_COMPONENT","加权移动需要唯一move评估分量。")
	var actor: Dictionary = snapshot.actors.actor_player
	if actor.health.current<=0: return C.fail("ACTOR_INCAPACITATED","旅人已无法行动。")
	var planned := Navigation.plan_weighted_route(snapshot,b.actor_id,b.target_hex,int(actor.stamina.current))
	if not planned.ok: return planned
	var patches: Array = [{"type":"actor_pool_delta","actor_id":b.actor_id,"pool":"stamina","delta":-planned.cost}]
	for i in range(1,planned.route.size()): patches.append({"type":"actor_move","actor_id":b.actor_id,"scene_id":actor.scene_id,"hex":planned.route[i].duplicate()})
	if preload("res://core/status_gameplay/content.gd").active(snapshot):
		# The existing release check_policy is safe_direct: no false movement
		# outcome exists. Keep one total branch instead of freezing an impossible
		# stay-in-air failure that would prevent escaping on the last flight turn.
		return {"ok":true,"resolver_id":ID,"branches":[{"id":"status_weighted_route_success","requires":{},"patches":patches}]}
	return {"ok":true,"resolver_id":ID,"branches":[{"id":"weighted_route_success","requires":{"move":true},"patches":patches},{"id":"weighted_route_failure","requires":{"move":false},"patches":[]}]}
