extends RefCounted
## Explicit new-world ruleset. Never installs into a loaded or pending legacy save.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Foundation = preload("res://core/status_foundation/engine_bridge.gd")
const SCHEMA := "status_gameplay_world/v1"
const SourceProfiles=preload("res://core/status_gameplay/source_profiles.gd")
const SOURCE_SCHEMA=SourceProfiles.SOURCE_SCHEMA
const SOURCES=SourceProfiles.SOURCES
const ITEMS := {
 "item_poison_vial":{"profile_id":"poison_vial","name":"苦叶毒剂","description":"经评估递送与生效后使目标中毒；每次目标行动结束损失1生命及最大生命的10%，持续3次目标行动。","quantity":2},
 "item_feather_vial":{"profile_id":"feather_vial","name":"轻羽药剂","description":"经评估使自己飞行3次自身行动；可越地面阻挡，空中/全域障碍与负重、净空仍生效。","quantity":2},
 "item_status_antidote":{"profile_id":"antidote","name":"苦叶解毒剂","description":"经评估解除同场景自己或邻近目标的苦叶中毒；不复原已经损失的生命。","quantity":2}
}

static func active(world: Dictionary) -> bool:
 var config:Variant=world.get("status_gameplay")
 return config is Dictionary and config.get("schema_version") is String and config.schema_version==SCHEMA

static func profile(id:String) -> Dictionary:return SourceProfiles.profile(id)

static func install_new_world(world: Dictionary) -> Dictionary:
 if world.get("turn",-1)!=0 or world.get("state_version",-1)!=0 or world.has("status_foundation") or world.has("status_gameplay"): return C.fail("STATUS_NEW_WORLD_ONLY","Status gameplay can only be installed before a new world starts")
 for actor in world.get("actors",{}).values():
  if not actor.get("statuses",{}).is_empty(): return C.fail("STATUS_LEGACY_CONDITION","Do not reinterpret pre-existing legacy statuses")
 if not world.get("actors",{}).has("actor_player"): return C.fail("STATUS_PLAYER","New world requires a stable player")
 var next: Dictionary=world.duplicate(true)
 var spaces: Dictionary={}
 for scene_id in next.scenes:
  # Authored initial scenes in this opt-in outdoor slice have open sky. New/unknown scenes fail flight closed.
  spaces[scene_id]={"ceiling_clearance":100,"no_flight":false}
 next["status_gameplay"]={"schema_version":SCHEMA,"catalog_hash":Foundation.runtime().catalog_hash,"scene_space":spaces,"default_unit_mass":1}
 next["status_foundation"]=Foundation.runtime().empty()
 for actor in next.actors.values():
  actor["status_body"]={"required_clearance":2,"load_limit":30}
  actor["status_actions"]={"land":profile("land")}
 for id in ITEMS:
  var authored: Dictionary=ITEMS[id]
  if not next.items.has(id):
   next.items[id]={"id":id,"name":authored.name,"description":authored.description,"quantity":authored.quantity,"owner_actor_id":"actor_player","interaction_profile":preload("res://core/ai_gm_rebuilt/basic_effects.gd").interaction()}
  var item: Dictionary=next.items[id]
  if item.get("owner_actor_id","")!="actor_player":return C.fail("STATUS_STARTER_CUSTODY","New-world source ID is already assigned elsewhere")
  item.erase("condition_source")
  item["status_source"]=profile(authored.profile_id)
  item.name=authored.name;item.description=authored.description
  if not id in next.actors.actor_player.inventory:next.actors.actor_player.inventory.append(id)
 for item in next.items.values():
  if item.get("weapon_profile",{}).get("on_full_hit","")=="poison":item["status_on_hit"]={"definition_id":"poison","parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0},"duration_owner_actions":3}
 return {"ok":true,"world":C.normalized(next)}

static func validate_profile(value:Variant) -> bool:return SourceProfiles.validate_profile(value)

static func validate(world: Dictionary) -> Dictionary:
 if not world.has("status_gameplay"): return {"ok":true}
 if not C.safe(world):return C.fail("STATUS_RULESET","World must contain finite typed data")
 for collection in ["actors","items","scenes"]:
  if not world.get(collection) is Dictionary:return C.fail("STATUS_WORLD_SHAPE","Status ruleset requires complete host collections")
 var config: Variant=world.status_gameplay
 if not C.exact_fields(config,["schema_version","catalog_hash","scene_space","default_unit_mass"]) or not config.schema_version is String or config.schema_version!=SCHEMA or not config.catalog_hash is String or config.catalog_hash!=Foundation.runtime().catalog_hash or not config.scene_space is Dictionary or not C.integer(config.default_unit_mass) or config.default_unit_mass!=1: return C.fail("STATUS_RULESET","Unsupported explicit status gameplay ruleset")
 if not world.has("status_foundation"):return C.fail("STATUS_RULESET","Ruleset requires its versioned status store")
 for id in config.scene_space:
  var space: Variant=config.scene_space[id]
  if not world.scenes.has(id) or not C.exact_fields(space,["ceiling_clearance","no_flight"]) or not C.integer(space.ceiling_clearance) or space.ceiling_clearance<0 or space.ceiling_clearance>10000 or not space.no_flight is bool:return C.fail("STATUS_SPACE","Invalid authored scene flight clearance")
 for actor in world.actors.values():
  if not actor is Dictionary:return C.fail("STATUS_WORLD_SHAPE","Actor record must be an object")
  if not C.exact_fields(actor.get("status_body"),["required_clearance","load_limit"]):return C.fail("STATUS_BODY","Missing authored body clearance/carry budget")
  for value in actor.status_body.values():
   if not C.integer(value) or value<1 or value>10000:return C.fail("STATUS_BODY","Invalid authored body bounds")
  if not C.exact_fields(actor.get("status_actions"),["land"]) or not validate_profile(actor.status_actions.land):return C.fail("STATUS_INTRINSIC","Invalid authored intrinsic source")
 for item in world.items.values():
  if not item is Dictionary:return C.fail("STATUS_WORLD_SHAPE","Item record must be an object")
  if item.has("status_on_hit") and C.bytes(item.status_on_hit)!=C.bytes({"definition_id":"poison","parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0},"duration_owner_actions":3}):return C.fail("STATUS_HIT_SOURCE","Changed authored weapon poison profile")
  if item.has("status_source") and not validate_profile(item.status_source):return C.fail("STATUS_SOURCE","Unrecognized or changed trusted source profile")
 return {"ok":true}

static func stable(before: Dictionary,after: Dictionary) -> bool:
 if before.has("status_gameplay")!=after.has("status_gameplay"):return false
 if not before.has("status_gameplay"):return true
 if C.bytes(before.status_gameplay)!=C.bytes(after.status_gameplay):return false
 for id in before.actors:
  for field in ["status_body","status_actions"]:
   if C.bytes(before.actors[id].get(field))!=C.bytes(after.actors[id].get(field)):return false
 for id in before.items:
  for field in ["status_source","status_on_hit"]:
   if C.bytes(before.items[id].get(field))!=C.bytes(after.items[id].get(field)):return false
 return true
