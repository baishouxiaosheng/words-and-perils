extends SceneTree
## Authored small-world regression; actual focus/engine/history/projection code.
const Sources=preload("res://core/status_gameplay/source_profiles.gd")
const F=preload("res://tests/status_gameplay/fixture.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Focus=preload("res://core/focus_contract.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
const Details=preload("res://view/status_gameplay/details.gd")
const Bridge=preload("res://core/status_foundation/engine_bridge.gd")
var count:=0
var failures:Array=[]
func check(value:bool,label:String) -> bool:
 count+=1
 if not value:failures.append(label);printerr("FAIL "+label)
 return value
func reference(world:Dictionary) -> Dictionary:
 var a:Dictionary=world.actors.actor_keeper
 return {"world_id":world.world_id,"kind":"actor","id":a.id,"hex":a.hex.duplicate(),"scene_id":a.scene_id}
func _initialize() -> void:
 var game:=F.successful_source("item_poison_vial","actor_keeper")
 if not check(game!=null and game.ready().ok,"real public source creates observed poison"):finish();return
 var ref:Dictionary=reference(game.state_copy())
 var attention:Dictionary=game.attention(ref)
 check(attention.ok and not attention.focus.facts.status_details.rows.is_empty(),"current attention exposes the authored public outcome only")
 var started:Dictionary=game.begin_intent("离线历史焦点反例：关注中毒NPC，玩家原地休息。",ref)
 if not check(started.ok,"actor focus freezes through ordinary begin API"):finish();return
 var reply:Dictionary=F.assessment(started.request,"coast_rest",{"actor_id":"actor_player"},["rest"])
 if not check(game.prepare_assessment(reply).ok and game.roll_once(reply.action_id).ok,"ordinary assessed fixed-rule rest prepares and rolls"):finish();return
 var staged:Dictionary=game.stage(reply.action_id)
 if not check(staged.ok,"focus-bearing rest stages"):finish();return
 var staged_packet:Dictionary=game.narration_request(reply.action_id).context.attention_focus.facts.status_details
 check(Details.valid_public_details(staged_packet) and not staged_packet.rows.is_empty(),"stage has bounded real status packet")
 var pending_clone:=F.engine()
 check(pending_clone.load_data(game.save_data()).ok,"pending actor-focus save re-derives the same status packet")
 var committed:Dictionary=game.commit(reply.action_id,staged.stage_hash)
 if not check(committed.ok,"focus-bearing action commits"):finish();return
 var historical:Dictionary=game.narration_request(reply.action_id).context.attention_focus
 check(C.bytes(historical.facts.status_details)==C.bytes(staged_packet),"commit retains exact frozen public details")
 var changed:Dictionary=F.execute(game,"coast_drop_item_v1",{"actor_id":"actor_keeper","item_id":"item_npc_token"},["interact"])
 check(changed.ok and F.status(game.state_copy(),"actor_keeper","poison").remaining==2,"later NPC action changes current poison independently")
 check(C.bytes(game.narration_request(reply.action_id).context.attention_focus.facts.status_details)==C.bytes(staged_packet),"history never recomputes details from current status")
 var restored:=F.engine()
 check(restored.load_data(game.save_data()).ok and C.bytes(restored.narration_request(reply.action_id).context.attention_focus.facts.status_details)==C.bytes(staged_packet),"history packet survives validated load unchanged")
 var malformed:Dictionary=game.save_data().receipts[reply.action_id].attention_focus.duplicate(true)
 malformed.facts.status_details.rows[0].duration.erase("clock")
 check(not Focus.new().validate_historical(malformed,game.state_copy()).is_empty(),"missing historical duration clock rejects cleanly")
 check(Details.status_caption({"status_details":malformed.facts.status_details})==Details.UNAVAILABLE,"malformed display packet never indexes missing fields")
 var hidden_world:Dictionary=F.world()
 var hidden:Dictionary=Bridge.runtime().apply_status(hidden_world.status_foundation,"poison","actor","actor_keeper","PRIVATE_UNOBSERVED_CAUSE",{"intensity":1,"flat_damage":1,"max_health_bps":0})
 hidden_world.status_foundation=hidden.store
 check(Details.public_rows(hidden_world,hidden_world.actors.actor_keeper).is_empty(),"unregistered private NPC source is not automatically public")
 var hidden_game:=F.engine(1,hidden_world)
 var hidden_start:Dictionary=hidden_game.begin_intent("离线仅关注未观察状态的NPC，不执行揭露。",reference(hidden_world))
 check(hidden_start.ok and hidden_start.request.context.attention_focus.facts.status_details.rows.is_empty(),"selecting NPC does not reveal hidden source status")
 check(not C.bytes(hidden_start.request).contains("PRIVATE_UNOBSERVED_CAUSE"),"private source identity never enters Decision request")
 hidden_game.cancel_intent(hidden_start.request.action_id)
 var hidden_tick:Dictionary=F.execute(hidden_game,"coast_drop_item_v1",{"actor_id":"actor_keeper","item_id":"item_npc_token"},["interact"])
 check(hidden_tick.ok,"private mechanical state still settles its owner's action")
 if hidden_tick.ok:
  var effects:Array=hidden_game.authoritative_result(hidden_tick.receipt.action_id).public_effects
  check(not effects.any(func(e):return e.type=="status_v2_event"),"private NPC status does not leak through lifecycle public effects")
 var bad_world:Dictionary=hidden_world.duplicate(true)
 bad_world.status_gameplay="malformed"
 check(Details.public_rows(bad_world,bad_world.actors.actor_keeper).is_empty(),"bad world visibility marker fails closed without exception")
 bad_world=hidden_world.duplicate(true);bad_world.items=[]
 check(Details.public_rows(bad_world,bad_world.actors.actor_keeper).is_empty(),"bad item collection fails closed without exception")
 bad_world=hidden_world.duplicate(true);bad_world.items.item_broken={"weapon_profile":"malformed"}
 check(not Sources.public_instance(bad_world,{"owner_kind":"actor","owner_id":"actor_keeper","definition_id":"poison","source_id":"item_broken"}),"bad weapon visibility source fails closed without exception")
 finish()
func finish() -> void:
 print("STATUS_HISTORY_FOCUS ",count-failures.size(),"/",count," ",JSON.stringify(failures))
 quit(0 if failures.is_empty() else 1)
