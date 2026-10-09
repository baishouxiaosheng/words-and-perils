extends "res://view/generated_v3_adventure/resolver.gd"
func resolver_id() -> String: return "natural_coast_"+kind+"_v1"
func action_schema() -> Dictionary:
	var result: Dictionary = super.action_schema()
	result.schema_version = "natural_coast_basic_actions/v1"
	result["source_profile"] = "natural_coast_basic/v1"
	result.water_policy = "exact emitted natural-coast ground and ground-clipped sea; no river, bridge or flight capability"
	return result
