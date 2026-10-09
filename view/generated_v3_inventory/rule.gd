extends "res://view/playable_build/rule_release_v1.gd"
## Original release formula and registered resolver policies, with a new exact
## registry/provenance identity. No model choice or dice policy is rewritten.
const Examples = preload("res://view/generated_v3_inventory/assessments.gd")
const INVENTORY_ID := "generated_v3_inventory_release/v1"
func rule_id() -> String: return INVENTORY_ID
func rule_schema() -> Dictionary:
	var result: Dictionary = super.rule_schema()
	result.schema_version = INVENTORY_ID
	result["formula_origin"] = "coast_release/v1"
	result["supported_scope"] = "V3 dry-triangle move, present/adjacent observe, rest, and one registered whole-stack travel bundle drop/pickup"
	return result
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return Examples.verify(snapshot,reply,goal,focus)
