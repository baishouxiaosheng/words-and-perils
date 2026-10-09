extends RefCounted
## Separate bounded public projection; old generated contexts remain byte-exact.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseProjection = preload("res://view/generated_adventure/projection.gd")
const ID := "generated_inventory_context/v1"
const ITEM_FIELDS := ["id", "name", "description", "quantity", "hex", "scene_id", "owner_actor_id", "interaction_profile", "custody_revision"]
static func active(state: Dictionary) -> bool:
	var source: Dictionary = state.get("generated_world", {})
	return source.get("source_contract") == "generated_macro_source/v1" and source.get("projection_id") == ID and source.get("inventory_profile") == "generated_inventory/v1" and state.get("world_id") == "generated_inventory_v1_" + str(source.get("content_hash", "")) and state.get("actors", {}).get("actor_player", {}).get("scene_id") == "scene_generated" and state.get("scenes", {}).has("scene_generated")
static func facts(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	var result := BaseProjection.facts(state, focus)
	result.context_scope.schema_version = ID
	result.context_scope["item_scope"] = "one known starting travel bundle; its recorded custody/location remains public, not generated loot"
	result.generated_source["inventory_profile"] = state.generated_world.inventory_profile
	result.generated_source["inventory_profile_hash"] = state.generated_world.inventory_profile_hash
	for id in state.items: result.items[id] = BaseProjection.pick(state.items[id], ITEM_FIELDS)
	return C.normalized(result)
