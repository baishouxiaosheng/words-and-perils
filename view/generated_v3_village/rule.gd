extends "res://view/playable_build/rule_release_v1.gd"
const Examples = preload("res://view/generated_v3_village/assessments.gd")
const VILLAGE_ID := "generated_v3_village_inventory_release/v1"
func rule_id() -> String: return VILLAGE_ID
func rule_schema() -> Dictionary:
	var result: Dictionary = super.rule_schema()
	result.schema_version = VILLAGE_ID
	result["formula_origin"] = "coast_release/v1"
	result["supported_scope"] = "exact V3 terrain plus validated fixed village obstruction; move, cell observation, rest, existing whole-stack bundle drop/pickup only"
	return result
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return Examples.verify(snapshot,reply,goal,focus)
