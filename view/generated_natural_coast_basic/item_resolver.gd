extends "res://view/generated_inventory/resolver.gd"
## The proven whole-stack resolver remains the item engine. Only this profile's
## public contract and resolver identity differ; all custody checks are shared.
func resolver_id() -> String: return "natural_coast_" + kind + "_v1"
func action_schema() -> Dictionary:
	var result: Dictionary = super.action_schema()
	result.schema_version = "natural_coast_basic_actions/v1"
	result.resolver_id = resolver_id()
	result["source_profile"] = "natural_coast_basic/v1"
	return result
