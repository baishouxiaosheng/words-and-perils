extends "res://view/generated_inventory/resolver.gd"
## The proven whole-stack resolver remains the item engine. Only this profile's
## public contract and resolver identity differ; all custody checks are shared.
func resolver_id() -> String: return "generated_v3_" + kind + "_v1"
func action_schema() -> Dictionary:
	var result: Dictionary = super.action_schema()
	result.schema_version = "generated_v3_inventory_actions/v1"
	result.resolver_id = resolver_id()
	result["source_profile"] = "generated_v3_inventory/v1"
	return result
