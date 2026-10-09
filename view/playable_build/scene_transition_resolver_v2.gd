extends "res://view/playable_build/scene_transition_resolver.gd"
## Bounded public evidence contract. V1 remains unchanged for frozen old saves.
const ID_V2 := "coast_scene_transition_v2"
func resolver_id() -> String: return ID_V2
func action_schema() -> Dictionary:
	var schema := super.action_schema()
	schema.schema_version="scene_transition/v2"
	schema.resolver_id=ID_V2
	schema.required_fact_paths=["/actors/actor_player","/scene_transitions/<entrance_id>","/scenes/<destination_scene_id>/id","/scene_hexes/<destination_scene_id>/<q,r> or /hexes/<q,r>"]
	schema.evidence_scope="Cite the scalar destination scene ID, never echo the scene's complete hex_ids catalog. The program still validates the full authored entrance, destination adapter, local landing and reciprocal return."
	return schema
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var planned := super.freeze(snapshot,assessment)
	if not planned.ok: return planned
	var entrance: Dictionary = snapshot.scene_transitions[assessment.bindings.entrance_id]
	var scene_path: String = "/scenes/"+entrance.destination_scene_id+"/id"
	var landing_path: String = ("/scene_hexes/"+entrance.destination_scene_id+"/" if snapshot.get("scene_hexes",{}).has(entrance.destination_scene_id) else "/hexes/")+"%d,%d"%entrance.landing_hex
	for path in ["/actors/actor_player","/scene_transitions/"+entrance.id,scene_path,landing_path]:
		if not _has_ref(assessment,path): return C.fail("SCENE_FACT_REF","Scene transition requires actor, authored entrance, scalar destination identity and exact landing-cell evidence.")
	for ref in assessment.fact_refs:
		if ref.path==scene_path and ref.get("expected")!=entrance.destination_scene_id: return C.fail("SCENE_FACT_REF","Destination scene identity differs from the authored entrance.")
	planned.resolver_id=ID_V2
	return planned
func _has_ref(assessment: Dictionary, path: String) -> bool:
	var ids: Array=assessment.components[0].get("fact_ref_ids",[])
	for ref in assessment.get("fact_refs",[]):
		if ref is Dictionary and ref.get("path")==path and ref.get("id") in ids:return true
	return false
