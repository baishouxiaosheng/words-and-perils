extends "res://view/playable_build/rule_release_v1.gd"
## Same fixed release formula, new identity and exact generated-only fixture registry.
const Examples = preload("res://view/generated_adventure/assessments.gd")
const GENERATED_ID := "generated_exploration_release/v1"
func rule_id() -> String:return GENERATED_ID
func rule_schema() -> Dictionary:
	var result: Dictionary=super.rule_schema()
	result.schema_version=GENERATED_ID
	result["formula_origin"]="coast_release/v1"
	result["supported_scope"]="generated move, adjacent observe, rest; no coast story or environmental effects"
	return result
func allows_fixture_assessment(snapshot: Dictionary,reply: Dictionary,goal: String,focus: Dictionary) -> bool:
	return Examples.verify(snapshot,reply,goal,focus)
