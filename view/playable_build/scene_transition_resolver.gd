extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Transitions = preload("res://core/ai_gm_rebuilt/scene_transitions.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const ID := "coast_scene_transition_v1"
func resolver_id() -> String: return ID
func action_schema() -> Dictionary:
	return {"schema_version":"scene_transition/v1","resolver_id":ID,"bindings":{"actor_id":"actor_player","entrance_id":"explicit authored scene_transitions ID"},"components":["transition"],"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/scene_transitions/<entrance_id>","/scenes/<destination_scene_id>","/scene_hexes/<destination_scene_id>/<q,r> or /hexes/<q,r>"],"cost":"authored entrance stamina_cost 1..8","preconditions":"actor on source entrance; registered destination; grounded safe landing; sufficient stamina; reciprocal return entrance","turn_cost":1,"hooks_per_action":1,"every_intent_requires_assessment":true,"content_scope":"transition framework, detailed interiors deferred"}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String: return "scene_transition:"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, _assessment: Dictionary) -> Dictionary:
	return {"actor":snapshot.actors.actor_player,"scenes":snapshot.scenes,"hexes":snapshot.hexes,"scene_hexes":snapshot.get("scene_hexes",{}),"entrances":snapshot.get("scene_transitions",{}),"world":snapshot.get("generated_world",{})}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var frozen := freeze(snapshot,assessment)
	return {"ok":true,"policies":{"transition":"safe_direct"}} if frozen.ok else frozen
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	if not C.exact_fields(b,["actor_id","entrance_id"]) or b.actor_id!="actor_player" or not b.entrance_id is String: return C.fail("ACTION_BINDING","场景转换需要旅人与明确的作者入口ID。")
	if assessment.components.size()!=1 or assessment.components[0].id!="transition": return C.fail("ACTION_COMPONENT","场景转换需要唯一transition评估分量。")
	var planned := Transitions.plan(snapshot,b.actor_id,b.entrance_id)
	if not planned.ok: return planned
	var e: Dictionary = planned.entrance
	for point in [{"scene_id":e.source_scene_id,"hex":e.source_hex},{"scene_id":e.destination_scene_id,"hex":e.landing_hex}]:
		var landing := Navigation.validate_scene_landing(snapshot,point.scene_id,point.hex)
		if not landing.ok: return landing
	var patches: Array = [{"type":"actor_scene_transition","actor_id":b.actor_id,"entrance_id":e.id,"source_scene_id":e.source_scene_id,"source_hex":e.source_hex.duplicate(),"scene_id":e.destination_scene_id,"hex":e.landing_hex.duplicate()},{"type":"actor_pool_delta","actor_id":b.actor_id,"pool":"stamina","delta":-planned.cost}]
	return {"ok":true,"resolver_id":ID,"branches":[{"id":"scene_transition_success","requires":{"transition":true},"patches":patches},{"id":"scene_transition_failure","requires":{"transition":false},"patches":[]}]}
