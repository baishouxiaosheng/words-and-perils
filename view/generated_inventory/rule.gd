extends "res://view/playable_build/rule_release_v1.gd"
## Same fixed formula/policy; separately pinned registry and fixture provenance.
const Examples = preload("res://view/generated_inventory/assessments.gd")
const INVENTORY_ID := "generated_inventory_release/v1"
func rule_id() -> String: return INVENTORY_ID
func rule_schema() -> Dictionary:
	var result := super.rule_schema()
	result.schema_version = INVENTORY_ID
	result["formula_origin"] = "coast_release/v1"
	result["supported_scope"] = "generated move, adjacent observe, rest, and one registered whole-stack travel bundle drop/pickup"
	return result
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return Examples.verify(snapshot, reply, goal, focus)
