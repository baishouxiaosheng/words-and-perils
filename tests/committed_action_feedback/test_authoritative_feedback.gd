extends SceneTree
## Real engine receipts from a small explicit test world; no full terrain load.
const EngineCore=preload("res://core/ai_gm_rebuilt/engine.gd")
const Story=preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Actions=preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const TestRule=preload("res://tests/core_gameplay/test_release_rule.gd")
const Router=preload("res://view/playable_build/committed_effect_router.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures:Array[String]=[]
var records:Array=[]
func _initialize()->void:
	create_timer(25.0).timeout.connect(func():printerr("FAIL: authoritative feedback watchdog");quit(2))
	call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: "+label)
func make_world(style:String)->Dictionary:
	var state:Dictionary=Story.world()
	state.actors.actor_player.combat_profile=Basic.combatant(["harbor_watch"])
	state.actors.actor_player.equipment={"weapon":"item_vfx_weapon"}
	state.actors.actor_player.hooks=["status_tick"]
	state.actors.actor_guard_a.hooks=["status_tick"]
	state.items.item_vfx_weapon={"id":"item_vfx_weapon","name":"明示演出测试武器","description":"测试场景明确编写的战斗能力","quantity":1,"owner_actor_id":"actor_player","interaction_profile":Basic.interaction("weapon"),"weapon_profile":Basic.weapon(3,true,style,"" if style=="melee" else "item_vfx_charge")}
	state.items.item_vfx_charge={"id":"item_vfx_charge","name":"测试弹药/晶能","description":"测试能力明示消耗","quantity":3,"owner_actor_id":"actor_player","interaction_profile":Basic.interaction()}
	state.actors.actor_player.inventory.append_array(["item_vfx_weapon","item_vfx_charge"])
	return C.normalized(state)
func assessment(engine:RefCounted)->Dictionary:
	var started:Dictionary=engine.begin_intent("【明确测试】使用已装备测试能力攻击相邻敌人。",{},"actor_player")
	if not started.ok:return started
	var req:Dictionary=started.request;var refs:Array=[];var ids:Array=[]
	for path in ["/actors/actor_player","/actors/actor_guard_a","/items/item_vfx_weapon","/items/item_vfx_charge"]:
		var found:Dictionary=C.pointer(req.context.facts,path)
		var id:="fact_%d"%refs.size();refs.append({"id":id,"path":path,"expected":found.value});ids.append(id)
	var components:Array=[]
	for id in ["accuracy","impact"]:components.append({"id":id,"parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":ids.duplicate()})
	return {"schema_version":"ai_gm_assessment/v1","action_id":req.action_id,"state_version":req.state_version,"context_hash":req.context_hash,"narration":"明确离线测试评估，结果由本地引擎计算。","interpretation":"使用已编写能力和稳定目标","resolver_id":"coast_basic_attack_v1","bindings":{"actor_id":"actor_player","target_actor_id":"actor_guard_a","weapon_item_id":"item_vfx_weapon"},"components":components,"fact_refs":refs,"provenance":{"provider":"explicit integration fixture","live":false,"kind":"fixture"}}
func run()->void:
	var a:=Node3D.new();var b:=Node3D.new();root.add_child(a);root.add_child(b);b.position=Vector3(2,0,0)
	var tokens:={"actor_player":a,"actor_guard_a":b}
	var router:=Router.new();root.add_child(router)
	for style in ["melee","ranged","magic"]:
		var seen:Dictionary={}
		for seed in range(1,40):
			var registry:Dictionary={"coast_basic_attack_v1":Actions.new("basic_attack")}
			var engine:=EngineCore.new(make_world(style),TestRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":[]},seed)
			check(engine.ready().ok,style+" engine ready")
			var before:Dictionary=engine.state_copy();router.reset_to(before)
			var reply:=assessment(engine);var prepared:Dictionary=engine.prepare_assessment(reply)
			check(prepared.ok,style+" assessment frozen")
			if not prepared.ok:break
			var rolls:Dictionary=engine.roll_once(reply.action_id);check(rolls.ok,style+" genuine RNG")
			var staged:Dictionary=engine.stage(reply.action_id);check(staged.ok,style+" staged")
			check(not router.consume(engine.authoritative_result(reply.action_id),before,before,tokens).ok,"staged authoritative summary cannot trigger VFX")
			var result:Dictionary=engine.commit(reply.action_id,staged.stage_hash)
			check(result.ok,"genuine commit")
			var after:Dictionary=engine.state_copy();var health_loss:int=int(before.actors.actor_guard_a.health.current)-int(after.actors.actor_guard_a.health.current)
			var outcome:String=""
			for patch in result.receipt.patches:
				if patch.type=="combat_event":outcome=patch.outcome
			check(router.consume(result.receipt,before,after,tokens).ok,"fresh genuine receipt renders")
			check(router.last_events.filter(func(e):return e.kind==style).size()==1,"exact authored style once")
			var damage_events:Array=router.last_events.filter(func(e):return e.kind=="damage")
			check(damage_events.size()==(1 if health_loss>0 else 0),"hit flash only with actual HP loss")
			if health_loss>0:check(damage_events[0].amount==health_loss,"popup equals exact real state delta")
			else:check(router.last_events.filter(func(e):return e.kind=="miss").size()==1,"actual RNG miss yields only whiff label")
			var duplicate:Dictionary=engine.commit(reply.action_id,staged.stage_hash)
			check(duplicate.already_committed and not router.consume(duplicate.receipt,before,after,tokens).ok,"idempotent engine replay never replays effects")
			router.reset_to(after)
			check(not router.consume(result.receipt,before,after,tokens).ok and router.active_count()==0,"loaded committed world never replays effects")
			if not seen.has(outcome):records.append({"style":style,"outcome":outcome,"actual_damage":health_loss,"receipt_hash":result.receipt.receipt_hash,"seed":seed})
			seen[outcome]=true
			if seen.size()==3:break
		check(seen.size()==3,"real miss/graze/hit all covered for "+style)
	check(tokens.size()==2,"all load/reset cycles preserve actual token identity map")
	var file:=FileAccess.open("res://tests/committed_action_feedback/authoritative_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"));file.close()
	router.queue_free();a.queue_free();b.queue_free();await process_frame
	if failures.is_empty():print("AUTHORITATIVE ACTION FEEDBACK PASSED: %d assertions"%checks);quit(0)
	else:quit(1)
