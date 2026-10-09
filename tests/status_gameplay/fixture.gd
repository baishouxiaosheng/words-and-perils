extends RefCounted
## OFFLINE author fixture. Tiny authored cells only, no model/provider or terrain import.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Story=preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Action=preload("res://core/status_gameplay/action.gd")
const EngineCore=preload("res://core/ai_gm_rebuilt/engine.gd")
const Rule=preload("res://tests/core_gameplay/test_release_rule.gd")
const Rest=preload("res://view/playable_build/resolver.gd")
const Weighted=preload("res://view/playable_build/weighted_movement_resolver.gd")
const Basic=preload("res://core/status_gameplay/basic_actions.gd")
const Effects=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Cells=preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const ROOM:="status_fixture_room"
static func world(stamina:int=10,barrier:String="") -> Dictionary:
 var state:Dictionary=Story.world()
 state.world_id="offline_status_gameplay_fixture"
 state.actors.actor_keeper=state.actors.actor_guard_a;state.actors.actor_keeper.id="actor_keeper";state.actors.erase("actor_guard_a")
 state.actors.actor_scout=state.actors.actor_guard_z;state.actors.actor_scout.id="actor_scout";state.actors.erase("actor_guard_z")
 state.flags={"coast_observed":false,"keeper_trust":false,"lamp_restored":false}
 state.scene_hexes={ROOM:{}}
 state.scenes[ROOM]={"id":ROOM,"name":"离线高棚试验场","layer_id":"offline_fixture","hex_ids":[],"renderer_id":"authored_test_room/v1","navigation_id":"authored_dry_cells/v1","bundle_id":"authored_test_room/v1"}
 for cell in state.hexes.values():
  var local:Dictionary=cell.duplicate(true);local.id=Cells.local_id(ROOM,[cell.q,cell.r]);local.scene_id=ROOM;local.terrain="floor"
  state.scene_hexes[ROOM][Cells.key([cell.q,cell.r])]=local;state.scenes[ROOM].hex_ids.append(local.id)
 for actor in state.actors.values():
  actor.scene_id=ROOM;actor.health={"current":120,"max":120};actor.stamina={"current":stamina,"max":10};actor.hooks=[]
 state.actors.actor_player.hex=[-1,0];state.actors.actor_keeper.hex=[-1,1];state.actors.actor_scout.hex=[0,1]
 state.items.item_npc_token={"id":"item_npc_token","name":"离线测试木牌","description":"仅用于验证NPC普通行动时钟的已持有物品。","owner_actor_id":"actor_keeper","quantity":1,"interaction_profile":Effects.interaction()}
 state.actors.actor_keeper.inventory.append("item_npc_token")
 var installed:Dictionary=Content.install_new_world(state)
 if not installed.ok:return {}
 state=installed.world
 if not barrier.is_empty():
  var applied:Dictionary=Foundation.runtime().apply_status(state.status_foundation,barrier,"tile",Cells.local_id(ROOM,[0,0]),"authored_offline_obstacle")
  if not applied.ok:return {}
  state.status_foundation=applied.store
 return C.normalized(state)
static func registry() -> Dictionary:
 var out:Dictionary={Action.ID:Action.new(),Weighted.ID:Weighted.new()}
 var rest:=Rest.new("rest");out[rest.resolver_id()]=rest
 for kind in Basic.KINDS:
  var action:=Basic.new(kind);out[action.resolver_id()]=action
 return out
static func engine(seed:int=1,initial:Dictionary={}) -> RefCounted:
 var registered:=registry()
 return EngineCore.new(world() if initial.is_empty() else initial,Rule.new(registered),registered,{"npc_secret_allowlist":[],"public_flag_ids":["coast_observed","keeper_trust","lamp_restored"]},seed)
static func assessment(request:Dictionary,resolver_id:String,bindings:Dictionary,components:Array) -> Dictionary:
 var paths:Array=["/actors/"+bindings.actor_id]
 if bindings.has("target_actor_id") and not "/actors/"+bindings.target_actor_id in paths:paths.append("/actors/"+bindings.target_actor_id)
 if bindings.has("source_id"):
  paths.append("/actors/"+bindings.actor_id+"/status_actions/land" if bindings.source_id=="land" else "/items/"+bindings.source_id)
 if bindings.has("item_id"):paths.append("/items/"+bindings.item_id)
 if bindings.has("weapon_item_id"):paths.append("/items/"+bindings.weapon_item_id)
 if bindings.has("target_hex"):paths.append("/scene_hexes/"+ROOM+"/"+Cells.key(bindings.target_hex))
 var refs:Array=[];var ids:Array=[]
 for i in range(paths.size()):
  var found:Dictionary=C.pointer(request.context.facts,paths[i])
  if not found.ok:return {}
  var id:String="fact_"+str(i);ids.append(id);refs.append({"id":id,"path":paths[i],"expected":found.value})
 var parts:Array=[]
 for id in components:parts.append({"id":id,"parameters":{"A":4,"D":0,"P":2},"disposition":"certain","fact_ref_ids":ids.duplicate()})
 return {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"离线测试评估，尚未执行；不代表真实模型判断。","interpretation":"Offline authored assessment bound to the actual trusted source and target; not a live model call.","resolver_id":resolver_id,"bindings":bindings.duplicate(true),"components":parts,"fact_refs":refs,"provenance":{"provider":"offline_status_gameplay_fixture","live":false,"kind":"model_reply"}}
static func begin(engine_:RefCounted,resolver_id:String,bindings:Dictionary,components:Array) -> Dictionary:
 var result:Dictionary=engine_.begin_intent("离线明确意图："+resolver_id+" "+C.bytes(bindings),{},bindings.actor_id)
 if not result.ok:return result
 var reply:=assessment(result.request,resolver_id,bindings,components)
 return {"ok":true,"reply":reply,"request":result.request}
static func execute(engine_:RefCounted,resolver_id:String,bindings:Dictionary,components:Array) -> Dictionary:
 var begun:=begin(engine_,resolver_id,bindings,components)
 if not begun.ok:return begun
 var reply:Dictionary=begun.reply
 var prepared:Dictionary=engine_.prepare_assessment(reply)
 if not prepared.ok:return prepared
 var rolled:Dictionary=engine_.roll_once(reply.action_id)
 if not rolled.ok:return rolled
 var stage:Dictionary=engine_.stage(reply.action_id)
 if not stage.ok:return stage
 return engine_.commit(reply.action_id,stage.stage_hash)
static func source(engine_:RefCounted,id:String,target:String="actor_player",actor:String="actor_player") -> Dictionary:
 return execute(engine_,Action.ID,{"actor_id":actor,"target_actor_id":target,"source_id":id},["delivery","effect"])
static func successful_source(id:String,target:String="actor_player",initial:Dictionary={}) -> RefCounted:
 # Independent seeded new-world fixtures, not retrying a failed player lineage.
 for seed in range(1,33):
  var game:=engine(seed,initial)
  if not game.ready().ok:return null
  var result:=source(game,id,target)
  if result.ok and result.receipt.outcomes.delivery and result.receipt.outcomes.effect:return game
 return null
static func status(world_:Dictionary,owner:String,id:String) -> Dictionary:
 for s in world_.status_foundation.instances.values():
  if s.owner_kind=="actor" and s.owner_id==owner and s.definition_id==id:return s
 return {}
