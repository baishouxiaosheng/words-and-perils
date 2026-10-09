extends RefCounted
## Shared authored sources and bounded public-outcome policy; no runtime/state mutation.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const SOURCE_SCHEMA := "status_gameplay_source/v1"
const SOURCES := {
 "poison_vial":{"operation":"apply","definition_id":"poison","target_scope":"self_or_adjacent","units":1,"stamina":1,"parameters":{"intensity":1,"flat_damage":1,"max_health_bps":1000},"check_policy":"contested"},
 "feather_vial":{"operation":"apply","definition_id":"flight","target_scope":"self","units":1,"stamina":1,"parameters":{"intensity":1},"check_policy":"contested"},
 "antidote":{"operation":"remove","definition_id":"poison","target_scope":"self_or_adjacent","units":1,"stamina":1,"parameters":{},"check_policy":"contested"},
 "land":{"operation":"remove","definition_id":"flight","target_scope":"self","units":0,"stamina":0,"parameters":{},"check_policy":"safe_direct"}
}

static func profile(id: String) -> Dictionary:
 if not SOURCES.has(id): return {}
 var p: Dictionary=SOURCES[id].duplicate(true)
 p["schema_version"]=SOURCE_SCHEMA;p["profile_id"]=id
 return p

static func validate_profile(value: Variant) -> bool:
 if not value is Dictionary or not value.get("profile_id") is String or not SOURCES.has(value.profile_id): return false
 return C.bytes(value)==C.bytes(profile(value.profile_id))

static func public_instance(world:Dictionary,instance:Dictionary) -> bool:
 if instance.get("owner_kind")!="actor":return false
 if instance.get("owner_id")=="actor_player":return true
 var config:Variant=world.get("status_gameplay")
 if not config is Dictionary or config.get("schema_version")!="status_gameplay_world/v1" or not instance.get("definition_id") in ["poison","flight"]:return false
 var items:Variant=world.get("items")
 if not items is Dictionary:return false
 var item:Variant=items.get(instance.get("source_id",""))
 if not item is Dictionary:return false
 var source:Variant=item.get("status_source")
 if validate_profile(source) and source.operation=="apply" and source.definition_id==instance.definition_id:return true
 # Only current authored observable encounter hits. Secret/off-scene use of the
 # same material requires a future observer/knowledge contract, not this policy.
 var weapon:Variant=item.get("weapon_profile")
 return weapon is Dictionary and instance.definition_id=="poison" and weapon.get("on_full_hit","")=="poison" and C.bytes(item.get("status_on_hit"))==C.bytes({"definition_id":"poison","parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0},"duration_owner_actions":3})
