extends RefCounted
## Versioned, trusted dry-route movement. Never derives an action from attention.
## The ordered move patches are the frozen route, not a cosmetic/recomputed path.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const ID := "coast_move_path_v2"
func resolver_id() -> String: return ID
func action_schema()->Dictionary:
	return {"schema_version":"coast_movement/v2","resolver_id":ID,"bindings":{"actor_id":"actor_player","target_hex":"explicit destination [q,r]"},"components":["move"],"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/hexes/<target_q,r>"],"cost_per_edge":1,"budget":"current stamina","route_policy":"deterministic shortest legal dry-support path; existing flight bypasses ground-only blockers, never water clearance","turn_cost":1,"hooks_per_action":1,"route_and_patches_from":"trusted program only","every_intent_requires_assessment":true}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var plan := freeze(snapshot, assessment)
	if not plan.ok: return plan
	return {"ok": true, "policies": {"move": "safe_direct"}}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return "move:" + C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, _assessment: Dictionary) -> Dictionary:
	# Scout patrol/wording cannot reset an unchanged failed movement attempt.
	var result := {"actor":snapshot.actors.actor_player,"hexes":snapshot.hexes,"world":snapshot.get("generated_world",{})}
	if snapshot.has("settlement_state"): result.settlement = snapshot.settlement_state
	return result
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if not C.exact_fields(b,["actor_id","target_hex"]) or b.get("actor_id") != "actor_player": return C.fail("ACTION_BINDING","步行必须明确绑定旅人与目标格。")
	if assessment.components.size()!=1 or assessment.components[0].id!="move": return C.fail("ACTION_COMPONENT","路线步行需要唯一 move 评估分量。")
	var actor: Dictionary = snapshot.actors.actor_player
	if actor.health.current <= 0: return C.fail("ACTOR_INCAPACITATED","旅人已无法行动；未移动或扣费。")
	var planned := Navigation.plan_route(snapshot,"actor_player",b.target_hex,int(actor.stamina.current))
	if not planned.ok: return planned
	# Candidate construction remains atomic. Costs are checked before any segment.
	var patches: Array = [{"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-planned.cost}]
	for i in range(1,planned.route.size()):
		patches.append({"type":"actor_move","actor_id":"actor_player","scene_id":actor.scene_id,"hex":planned.route[i].duplicate()})
	return {"ok":true,"resolver_id":ID,"branches":[{"id":"move_path_success","requires":{"move":true},"patches":patches},{"id":"move_path_failure","requires":{"move":false},"patches":[]}]}
