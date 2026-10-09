extends "res://view/playable_build/rule_release_v1.gd"
const Examples = preload("res://view/generated_v3_npc/assessments.gd")
const NPC_ID := "generated_v3_village_npc_release/v1"
func rule_id() -> String: return NPC_ID
func rule_schema() -> Dictionary:
	var result: Dictionary = super.rule_schema()
	result.schema_version = NPC_ID
	result["formula_origin"] = "coast_release/v1"
	result["supported_scope"] = "exact V3 terrain plus validated fixed village obstruction; move, cell observation, rest, whole-stack bundle drop/pickup and finite assessed cooperative conversation"
	return result
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return Examples.verify(snapshot,reply,goal,focus)
