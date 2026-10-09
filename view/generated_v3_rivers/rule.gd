extends "res://view/playable_build/rule_release_v1.gd"
## Keep the trusted formula unchanged, while binding the exact new V3 registry.
const Examples = preload("res://view/generated_v3_rivers/assessments.gd")
const V3_ID := "generated_v3_rivers_exploration_release/v1"
func rule_id() -> String: return V3_ID
func rule_schema() -> Dictionary:
	var result: Dictionary = super.rule_schema()
	result.schema_version = V3_ID
	result["formula_origin"] = "coast_release/v1"
	result["supported_scope"] = "Actual river-water-clearance dry-anchor move, present/adjacent observe, rest; temporary one-anchor-per-cell traversal, no crossings/object/city/combat effects"
	return result
func allows_fixture_assessment(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	return Examples.verify(snapshot,reply,goal,focus)
