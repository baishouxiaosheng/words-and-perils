extends SceneTree
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const Cells=preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const F=preload("res://tests/status_gameplay/fixture.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Action=preload("res://core/status_gameplay/action.gd")
const Movement=preload("res://core/status_gameplay/movement.gd")
const Traversal=preload("res://core/ai_gm_rebuilt/traversal.gd")
const Policy=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Weighted=preload("res://view/playable_build/weighted_movement_resolver.gd")
const Navigation=preload("res://view/playable_build/navigation.gd")
const Save=preload("res://view/status_gameplay/save.gd")
const Details=preload("res://view/status_gameplay/details.gd")
const TinyAdapter=preload("res://tests/status_gameplay/tiny_adapter.gd")
const ActualAdapter=preload("res://view/playable_build/adapter.gd")
var count:=0
var failures:Array=[]
func expect(value:bool,label:String) -> void:
 count+=1
 if not value:failures.append(label);printerr("FAIL "+label)
func require_game(game:RefCounted,label:String) -> bool:
 expect(game!=null and game.ready().ok,label)
 if game==null or not game.ready().ok:finish();return false
 return true
func _initialize() -> void:
 if "--reload" in OS.get_cmdline_user_args():
  var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("user://status_loop_saved.json"))
  var decoded:Dictionary=Save.unwrap(parsed);expect(decoded.ok,"separate process unwraps explicit new version")
  if not decoded.ok:finish();return
  var restored:=F.engine();var loaded:Dictionary=restored.load_data(decoded.engine)
  expect(loaded.ok,"separate process restores exact committed source/action state")
  if loaded.ok:expect(not F.status(restored.state_copy(),"actor_keeper","poison").is_empty(),"poison persists across real process restart")
  finish();return
 var adapter:=TinyAdapter.new(1,true,true)
 expect(adapter.engine.ready().ok and adapter.status_gameplay_mode,"real adapter initializes around authored small world")
 var move_goal:String=adapter.movement_goal([0,0])
 var move_spec:Dictionary=adapter._movement_fixture_spec(adapter.state_copy(),move_goal)
 expect(not adapter.engine.supports_resolver("coast_move_path_v2") and move_spec.get("resolver_id")==Weighted.ID,"adapter signed weighted matcher does not require removed legacy route resolver")
 expect(adapter.movement_preview([0,0]).ok,"adapter weighted preview uses the same real registered tiny-world route")
 expect(adapter.sample_goal("move",{"kind":"tile","hex":[0,0]})==move_goal,"selected-cell adapter movement sample uses active weighted resolver")
 var default_goal:String=adapter.sample_goal("move")
 expect(not default_goal.is_empty() and adapter._movement_fixture_spec(adapter.state_copy(),default_goal).get("resolver_id")==Weighted.ID,"unfocused adapter movement sample also uses active weighted resolver")
 var game:=F.successful_source("item_poison_vial","actor_keeper")
 if not require_game(game,"real registered source reaches successful offline poison branch"):return
 var state:Dictionary=game.state_copy()
 expect(state.actors.actor_keeper.health.current==120 and F.status(state,"actor_keeper","poison").remaining==3,"new poison applies without same-action tick")
 expect(state.items.item_poison_vial.quantity==1 and state.actors.actor_player.stamina.current==9,"actual source unit and stamina spent once")
 expect(game.authoritative_result(game.save_data().receipts.keys()[0]).public_effects.any(func(e):return e.type=="status_v2_event" and e.change=="applied"),"committed narration receives typed status application evidence")
 var prior_hp:int=state.actors.actor_keeper.health.current
 var result:Dictionary=F.execute(game,"coast_rest",{"actor_id":"actor_player"},["rest"])
 expect(result.ok and game.state_copy().actors.actor_keeper.health.current==prior_hp and F.status(game.state_copy(),"actor_keeper","poison").remaining==3,"another actor's ordinary action does not age poison")
 result=F.execute(game,"coast_drop_item_v1",{"actor_id":"actor_keeper","item_id":"item_npc_token"},["interact"])
 expect(result.ok and game.state_copy().actors.actor_keeper.health.current==107 and F.status(game.state_copy(),"actor_keeper","poison").remaining==2,"NPC ordinary assessed action uses same pipeline and ticks 1+10% poison")
 var details:Dictionary=Details.public_details(game.state_copy(),game.state_copy().actors.actor_keeper)
 expect(details.available and details.rows[0].damage.at_current_health==13,"status details reflect actual trusted parameters and HP")
 var before:String=C.bytes(game.save_data())
 expect(game.commit(result.receipt.action_id,result.receipt.stage_hash).already_committed and C.bytes(game.save_data())==before,"duplicate receipt cannot double spend or double tick")
 expect(Save.save_file(game,"user://status_loop_saved.json").ok,"explicit new save wrapper written atomically")
 var prior_save_hash:String=FileAccess.get_sha256("user://status_loop_saved.json")
 var temp_obstruction:String="user://status_loop_saved.json.tmp"
 expect(DirAccess.make_dir_absolute(temp_obstruction)==OK,"owned temporary-path obstruction created")
 expect(Save.save_file(game,"user://status_loop_saved.json").get("code")=="STATUS_SAVE_IO" and FileAccess.get_sha256("user://status_loop_saved.json")==prior_save_hash,"temporary write failure cannot replace existing status save")
 expect(DirAccess.remove_absolute(temp_obstruction)==OK,"owned empty temporary obstruction removed")
 var wrap:Dictionary=Save.make_envelope(game)
 var broken:Dictionary=wrap.duplicate(true);broken.engine.state.erase("actors")
 expect(not Save.unwrap(broken).ok,"malformed new save rejects without host-collection access exception")
 expect(not Save.unwrap(game.save_data()).ok,"legacy raw envelope is not silently reinterpreted")
 var oversized:=FileAccess.open("user://oversize_status_guard.json",FileAccess.WRITE)
 oversized.seek(Save.MAX_SAVE_BYTES);oversized.store_8(32);oversized.close()
 expect(Save.save_file(game,"user://oversize_status_guard.json").get("code")=="STATUS_SAVE_BUDGET","existing oversized destination rejects before reading or overwriting contents")
 expect(adapter.load_file("user://oversize_status_guard.json").get("code")=="STATUS_SAVE_BUDGET","real adapter rejects oversized input before reading or checking world resources")
 var clone:=F.engine();var loaded:Dictionary=clone.load_data(Save.unwrap(wrap).engine)
 expect(loaded.ok and C.bytes(clone.save_data())==C.bytes(game.save_data()),"new committed save restores exact facts/RNG/receipts")
 # Independent offline seed lineages exercise the real antidote source and its cost.
 var cured:=false
 for seed in range(1,33):
  var cure_game:=F.engine(seed)
  var poison_result:Dictionary=F.source(cure_game,"item_poison_vial","actor_keeper")
  if not poison_result.ok or not poison_result.receipt.outcomes.delivery or not poison_result.receipt.outcomes.effect:continue
  var cure_result:Dictionary=F.source(cure_game,"item_status_antidote","actor_keeper")
  if cure_result.ok and cure_result.receipt.outcomes.delivery and cure_result.receipt.outcomes.effect:
   cured=F.status(cure_game.state_copy(),"actor_keeper","poison").is_empty() and cure_game.state_copy().items.item_status_antidote.quantity==1 and cure_game.state_copy().actors.actor_player.stamina.current==8
   expect(cure_game.authoritative_result(cure_result.receipt.action_id).public_effects.any(func(e):return e.type=="status_v2_event" and e.change=="removed"),"antidote committed removal has typed narration evidence")
   break
 expect(cured,"real antidote consumes its authored costs and removes poison in the same action pipeline")

 var weak_world:Dictionary=F.world()
 var weak_poison:Dictionary=Foundation.runtime().apply_status(weak_world.status_foundation,"poison","actor","actor_keeper","offline_weak_weapon",{"intensity":1,"flat_damage":1,"max_health_bps":0})
 weak_world.status_foundation=weak_poison.store
 var weak_game:=F.engine(1,weak_world)
 var weak_begin:Dictionary=F.begin(weak_game,Action.ID,{"actor_id":"actor_player","target_actor_id":"actor_keeper","source_id":"item_poison_vial"},["delivery","effect"])
 var weak_before:String=C.bytes(weak_game.save_data())
 expect(weak_game.prepare_assessment(weak_begin.reply).get("code")=="STATUS_DIFFERENT_POTENCY" and C.bytes(weak_game.save_data())==weak_before,"strong vial cannot silently refresh weaker existing poison or charge on rejection")
 var fp_world:Dictionary=F.world(0)
 var fp_assessment:Dictionary={"bindings":{"actor_id":"actor_player","target_actor_id":"actor_keeper","source_id":"item_poison_vial"}}
 var fp_before:Dictionary=Action.new().attempt_fingerprint(fp_world,fp_assessment)
 fp_world.actors.actor_player.stamina.current=1
 var fp_after:Dictionary=Action.new().attempt_fingerprint(fp_world,fp_assessment)
 expect(not fp_before.can_pay and fp_after.can_pay and C.bytes(fp_before)!=C.bytes(fp_after),"actual retry fingerprint changes when rest restores source affordability")
 # Every component must bind the required true evidence, not just carry unused refs.
 var untouched:=F.engine()
 var begun:Dictionary=F.begin(untouched,Action.ID,{"actor_id":"actor_player","target_actor_id":"actor_keeper","source_id":"item_poison_vial"},["delivery","effect"])
 var reply:Dictionary=begun.reply
 reply.fact_refs.append({"id":"irrelevant","path":"/flags/coast_observed","expected":false})
 for part in reply.components:part.fact_ref_ids=["irrelevant"]
 before=C.bytes(untouched.save_data())
 expect(not untouched.prepare_assessment(reply).ok and C.bytes(untouched.save_data())==before,"unused source refs cannot bypass per-component evidence requirement")
 untouched.cancel_intent(reply.action_id)
 begun=F.begin(untouched,Action.ID,{"actor_id":"actor_player","target_actor_id":"actor_player","source_id":"item_feather_vial"},["delivery","effect"])
 reply=begun.reply;reply.components[1].parameters.flat_damage=99999
 expect(not untouched.prepare_assessment(reply).ok,"AI cannot inject potency or formula fields")
 untouched.cancel_intent(reply.action_id)
 begun=F.begin(untouched,Action.ID,{"actor_id":"actor_player","target_actor_id":"actor_player","source_id":"item_feather_vial"},["delivery","effect"])
 before=C.bytes(untouched.save_data())
 expect(untouched.query_capability(begun.reply).available and C.bytes(untouched.save_data())==before,"production source preview leaves facts/RNG/cost unchanged")
 var prepared:Dictionary=untouched.prepare_assessment(begun.reply)
 expect(prepared.ok and prepared.checks.all(func(check):return check.method=="random"),"AI certain disposition cannot bypass contested source dice")
 var pending_save:Dictionary=Save.make_envelope(untouched)
 var pending_clone:=F.engine();loaded=pending_clone.load_data(Save.unwrap(pending_save).engine)
 expect(loaded.ok and C.bytes(pending_clone.save_data())==C.bytes(untouched.save_data()),"prepared source save re-derives same branch plan")
 # Real flight source, permanent ground obstruction, ordinary drop and weighted move.
 var flying:=F.successful_source("item_feather_vial","actor_player",F.world(10,"ground_obstruction"))
 if not require_game(flying,"real source creates flight in authored obstacle world"):return
 result=F.execute(flying,"coast_drop_item_v1",{"actor_id":"actor_player","item_id":"item_status_antidote"},["interact"])
 expect(result.ok and F.status(flying.state_copy(),"actor_player","flight").remaining==2,"ordinary action advances owner flight clock")
 var actor:Dictionary=flying.state_copy().actors.actor_player
 expect(Traversal.can_enter(flying.state_copy(),actor,[0,0]),"same traversal predicate admits flight over persistent ground state")
 for obstruction in ["air_obstruction","solid_barrier"]:
  var blocked:Dictionary=flying.state_copy()
  var added:Dictionary=Foundation.runtime().apply_status(blocked.status_foundation,obstruction,"tile",Cells.local_id(F.ROOM,[0,0]),"offline_"+obstruction)
  expect(added.ok,"authored "+obstruction+" fixture is valid")
  if added.ok:
   blocked.status_foundation=added.store
   expect(not Traversal.can_enter(blocked,blocked.actors.actor_player,[0,0]),"flight cannot bypass "+obstruction)
   expect(not Navigation.plan_weighted_route(blocked,"actor_player",[0,0],10).ok,"route preview agrees for "+obstruction)
 var planned:Dictionary=Navigation.plan_weighted_route(flying.state_copy(),"actor_player",[0,0],actor.stamina.current)
 expect(planned.ok,"production weighted preview admits hover with affordable escape")
 result=F.execute(flying,Weighted.ID,{"actor_id":"actor_player","target_hex":[0,0]},["move"])
 expect(result.ok and F.status(flying.state_copy(),"actor_player","flight").remaining==1,"flight can end an action over obstruction when a safe exit remains")
 if not result.ok:printerr(result);finish();return
 before=C.bytes(flying.save_data())
 begun=F.begin(flying,Action.ID,{"actor_id":"actor_player","target_actor_id":"actor_player","source_id":"land"},["delivery","effect"])
 expect(not flying.prepare_assessment(begun.reply).ok,"landing on obstruction is rejected")
 flying.cancel_intent(begun.reply.action_id)
 result=F.execute(flying,Weighted.ID,{"actor_id":"actor_player","target_hex":[1,0]},["move"])
 expect(result.ok and F.status(flying.state_copy(),"actor_player","flight").is_empty(),"last flight action escapes safely without impossible-failure-branch trap")
 expect(not Traversal.can_enter(flying.state_copy(),flying.state_copy().actors.actor_player,[0,0]),"expired flight restores ground blockage")
 expect(Details.public_rows(flying.state_copy(),flying.state_copy().actors.actor_player).is_empty(),"expiry removes committed status details")
 var landing:=F.successful_source("item_feather_vial")
 if not require_game(landing,"second independent flight lineage for explicit landing"):return
 result=F.source(landing,"land")
 expect(result.ok and F.status(landing.state_copy(),"actor_player","flight").is_empty(),"explicit landing still requires an assessed ordinary action")
 var drained:=F.successful_source("item_feather_vial","actor_player",F.world(2,"ground_obstruction"))
 if not require_game(drained,"independent low-stamina flight fixture"):return
 result=F.execute(drained,"coast_drop_item_v1",{"actor_id":"actor_player","item_id":"item_status_antidote"},["interact"])
 expect(result.ok,"low-stamina ordinary action reaches remaining-two setup")
 before=C.bytes(drained.save_data())
 begun=F.begin(drained,Weighted.ID,{"actor_id":"actor_player","target_hex":[0,0]},["move"])
 var rejected:Dictionary=drained.prepare_assessment(begun.reply)
 expect(not rejected.ok and rejected.code=="STATUS_FLIGHT_EXIT_REQUIRED","zero-stamina airborne terminal soft lock rejected before dice")
 expect(drained.state_copy().actors.actor_player.hex==[-1,0] and F.status(drained.state_copy(),"actor_player","flight").remaining==2,"rejected unsafe plan makes no move, tick or payment")
 finish()
func finish() -> void:
 var file:=FileAccess.open("res://artifacts/status_closed_loop.json",FileAccess.WRITE)
 if file:file.store_string(JSON.stringify({"assertions":count,"passed":count-failures.size(),"failures":failures,"model_calls":0,"fixture":"offline authored cells and assessments; actual release resolver/calculator/engine"},"  "))
 print("STATUS_GAMEPLAY_LOOP ",count-failures.size(),"/",count," ",JSON.stringify(failures))
 quit(0 if failures.is_empty() else 1)
