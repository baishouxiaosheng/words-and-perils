extends "res://core/ai_gm_rebuilt/basic_actions.gd"
## Reuse whole-stack custody. No coast actors, locations, weapons or content table.
var source: RefCounted
func _init(source_: RefCounted, kind_: String) -> void:
	source = source_; kind = kind_
func resolver_id() -> String: return "generated_" + kind + "_v1"
func action_schema() -> Dictionary:
	var result := super.action_schema()
	result.schema_version = "generated_inventory_actions/v1"
	result.bindings = {"actor_id": "actor_player", "item_id": "item_travel_bundle"}
	result.required_fact_paths = ["/actors/actor_player", "/items/item_travel_bundle"]
	result.authority = "Assessed whole-stack drop or pickup only. Reuses registered BasicActions and BasicEffects ownership/range/custody checks. Pickup is on the current dry cell or directly connected dry neighbor. No item creation, splitting, consumption, equipment, transfer or combat."
	return result
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var checked: Dictionary = source.validate_state(snapshot)
	if not checked.ok: return checked
	if not kind in ["drop_item", "pickup_item"] or assessment.bindings.get("actor_id") != "actor_player" or assessment.bindings.get("item_id") != "item_travel_bundle":
		return C.fail("GENERATED_ITEM_SCOPE", "Only the registered travel bundle can be dropped or picked up in this profile.")
	if kind == "pickup_item":
		var item: Dictionary = snapshot.items.item_travel_bundle
		if item.has("hex"):
			var from_key: String = "%d,%d" % snapshot.actors.actor_player.hex
			var to_key: String = "%d,%d" % item.hex
			if from_key != to_key and not to_key in source.navigation.allowed.get(from_key, []):
				return C.fail("GENERATED_ITEM_REACH", "Pickup requires current-cell or verified directly connected dry-cell reach.")
	return super.freeze(snapshot, assessment)
