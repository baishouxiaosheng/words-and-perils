extends RefCounted
## One shared status predicate: path, reachable cells and final landing all use this.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells=preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const Runtime=preload("res://core/status_foundation/runtime.gd")

static func context(world:Dictionary,actor:Dictionary,cell:Dictionary) -> Dictionary:
 if not Content.active(world) or not world.status_gameplay.scene_space.has(actor.scene_id):return {}
 var space:Dictionary=world.status_gameplay.scene_space[actor.scene_id]
 var load_units:=0
 for id in actor.inventory:
  if world.items.has(id) and world.items[id].get("owner_actor_id","")==actor.id:load_units+=int(world.items[id].quantity)*int(world.status_gameplay.default_unit_mass)
 return {"air_blocked":bool(cell.air_blocked),"no_flight":bool(space.no_flight),"ceiling_clearance":int(space.ceiling_clearance),"required_clearance":int(actor.status_body.required_clearance),"current_load":load_units,"load_limit":int(actor.status_body.load_limit),"movement_mode":"flight"}

static func has_flight(world:Dictionary,actor:Dictionary) -> bool:
 if not Content.active(world):return false
 for s in world.status_foundation.instances.values():
  if s.owner_kind=="actor" and s.owner_id==actor.id and s.definition_id=="flight":return true
 return false

static func flight_at(world:Dictionary,actor:Dictionary,cell:Dictionary) -> bool:
 var facts:=context(world,actor,cell)
 if facts.is_empty():return false
 var evaluated:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"actor",actor.id,facts)
 if not evaluated.ok:return false
 var tile:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"tile",cell.id,facts)
 return tile.ok and Runtime.can_enter(evaluated.aggregate,tile.aggregate,_space_cell(cell,facts),"flight")

static func _space_cell(cell:Dictionary,facts:Dictionary) -> Dictionary:
 var result:Dictionary=cell.duplicate(true)
 for key in ["no_flight","ceiling_clearance","required_clearance","current_load","load_limit"]:
  if facts.has(key):result[key]=facts[key]
 return result

static func can_enter(world:Dictionary,actor:Dictionary,cell:Dictionary) -> bool:
 if cell.is_empty() or cell.scene_id!=actor.scene_id:return false
 var facts:=context(world,actor,cell)
 if facts.is_empty():facts={"movement_mode":"walk"}
 var actor_query:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"actor",actor.id,facts)
 var tile_query:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"tile",cell.id,facts)
 if not actor_query.ok or not tile_query.ok:return false
 # An active flight status means the current traversal mode is flight. Air blocks
 # cannot be bypassed by silently toggling back to walk without a landing action.
 var mode:String="flight" if has_flight(world,actor) else "walk"
 return Runtime.can_enter(actor_query.aggregate,tile_query.aggregate,_space_cell(cell,facts),mode)

static func can_land(world:Dictionary,actor:Dictionary,hex:Array) -> bool:
 var cell:Dictionary=Cells.cell(world,actor.scene_id,hex)
 if cell.is_empty():return false
 var actor_query:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"actor",actor.id,{"movement_mode":"walk"})
 var tile_query:Dictionary=Foundation.runtime().evaluate(world.status_foundation,"tile",cell.id,{"movement_mode":"walk"})
 return actor_query.ok and tile_query.ok and Runtime.can_enter(actor_query.aggregate,tile_query.aggregate,cell,"walk")

static func can_finish_action(world:Dictionary,actor:Dictionary,hex:Array) -> bool:
 if not Content.active(world):return true
 var expiring:=false
 for s in world.status_foundation.instances.values():
  if s.owner_kind=="actor" and s.owner_id==actor.id and s.definition_id=="flight" and int(s.remaining)==1:expiring=true
 return not expiring or can_land(world,actor,hex)

static func validate_after_turn(before:Dictionary,after:Dictionary) -> Dictionary:
 if not Content.active(before):return {"ok":true}
 for id in before.actors:
  if after.actors[id].health.current<=0:continue # Existing downed/terminal state is not granted immortality by landing checks
  if has_flight(before,before.actors[id]) and not has_flight(after,after.actors[id]) and not can_land(after,after.actors[id],after.actors[id].hex):return C.fail("STATUS_UNSAFE_EXPIRY","这次行动会在未登记落脚处结束飞行；本原型尚未接入坠落、抓攀与救援结算，因此尚未执行。")
  if has_flight(after,after.actors[id]) and not can_land(after,after.actors[id],after.actors[id].hex):
   var exit:Dictionary=_safe_exit(after,id)
   if not exit.ok:return exit
 return {"ok":true}

static func _safe_exit(world:Dictionary,actor_id:String) -> Dictionary:
 # Fixed trusted module path, not a model-provided executable/expression.
 var navigation=load("res://view/playable_build/navigation.gd")
 return navigation.safe_landing_route(world,actor_id,func(hex):return can_land(world,world.actors[actor_id],hex))

static func can_finish_route(world:Dictionary,actor_id:String,target:Array,cost:int) -> Dictionary:
 if not Content.active(world):return {"ok":true}
 var actor:Dictionary=world.actors[actor_id]
 if not can_finish_action(world,actor,target):return C.fail("STATUS_LANDING","本次行动会在空中耗尽飞行；原型尚未接入坠落、抓攀和救援后果，请改选已登记落脚点。")
 if not has_flight(world,actor) or can_land(world,actor,target):return {"ok":true}
 var candidate:Dictionary=world.duplicate(true)
 candidate.actors[actor_id].hex=target.duplicate()
 candidate.actors[actor_id].stamina.current-=cost
 if candidate.actors[actor_id].stamina.current<0:return C.fail("STAMINA_REQUIRED","移动体力不足。")
 return _safe_exit(candidate,actor_id)
