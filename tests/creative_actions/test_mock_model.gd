extends SceneTree
## Injected transport exercises the real controller/codec; not a semantic model test.
const Runtime = preload("res://view/runtime_ai/controller.gd")
const Adapter = preload("res://view/playable_build/adapter.gd")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content = preload("res://view/playable_build/creative_content.gd")
const ControlReply = preload("res://core/ai_gm_rebuilt/creative_control.gd")
const SOURCE := "item_brace_bar"
const TARGET := "passage:coast_brace:north"
const KEY := "synthetic-offline-mock-marker-never-a-live-key"
var checks := 0
var failures: Array=[]
var accepted:=0
var completed:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->void:
	checks+=1
	if not value:failures.append(label_);printerr("FAIL: "+label_)
func envelope(reply:Dictionary)->String:return C.bytes({"choices":[{"finish_reason":"stop","message":{"content":C.bytes(reply)}}]})
func outgoing(mock:Node)->Dictionary:return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func provenance()->Dictionary:return {"provider":"mock_test_transport","live":false,"kind":"model_reply"}
func control(request:Dictionary,code:String,paths:Array=[])->Dictionary:
	return {"schema_version":ControlReply.SCHEMA,"action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"code":code,"message":"需要这份已公开的事实，再评估同一意图。" if code=="NEEDS_PUBLIC_CONTEXT" else "请澄清要阻路还是伤害角色。","candidates":[{"kind":"item","id":SOURCE}],"context_paths":paths,"provenance":provenance()}
func decision(request:Dictionary)->Dictionary:
	var paths:Array=["/actors/actor_player","/items/"+SOURCE,"/passage_targets/"+TARGET,"/physical_catalog","/creative_placements","/creative_relations"]
	for h in request.context.facts.passage_targets[TARGET].endpoints:paths.append("/hexes/%d,%d"%h)
	var refs:Array=[];var ids:Array=[]
	for path in paths:
		var ref_id: String="fact_"+str(refs.size());refs.append({"id":ref_id,"path":path,"expected":C.pointer(request.context.facts,path).value});ids.append(ref_id)
	return {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"准备把铁杆安放到北口支座；还没有发生结果。","interpretation":"Injected mock chooses the explicit bar/north relation; this tests transport only, not natural-language accuracy.","resolver_id":"coast_creative_obstruction_v1","bindings":{"actor_id":"actor_player","operation":"place_obstruction","source":{"kind":"item","id":SOURCE},"target":{"kind":"passage_edge","id":TARGET},"mechanism":"span_brace/v1","intended_effect":"restrict_ground_traversal"},"components":[{"id":"placement","parameters":{"A":2,"D":2,"P":0},"disposition":"possible","fact_ref_ids":ids},{"id":"stability","parameters":{"A":2,"D":2,"P":0},"disposition":"possible","fact_ref_ids":ids}],"fact_refs":refs,"provenance":provenance()}
func run()->void:
	var adapter:=Adapter.new(1,true);var runtime:=Runtime.new();root.add_child(runtime);var mock:=Mock.new();runtime.set_transport(mock);runtime.bind_adapter(adapter)
	runtime.request_finished.connect(func(result:Dictionary):completed.append(result))
	runtime.assessment_validated.connect(func(_id:String):accepted+=1;check(adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok,"trusted controller completion commits once"))
	check(runtime.configure({"endpoint":"https://example.invalid/v1/chat/completions","model":"mock-offline","timeout_seconds":30},KEY).ok,"mock-only config")
	runtime.connection_enabled=true
	var focus:=Content.make_reference("item_brace_plank",adapter.state_copy())
	check(adapter.begin_intent("不要用长板，把铁杆横卡在北坡窄口支座上阻止步行直接通过。",focus).ok,"free language request freezes")
	check(not adapter.fixture_available(),"free language is never exact-phrase fixture")
	var before:Dictionary=adapter.engine.save_data();var started:Dictionary=runtime.request_assessment();var request:=outgoing(mock)
	check(started.ok and request.contract.has("control_reply") and request.context.goal==adapter.action_copy().goal,"actual request preserves text and negotiation")
	var far_path:=""
	for key in adapter.state_copy().hexes:
		if not request.context.facts.hexes.has(key):far_path="/hexes/"+key;break
	check(not far_path.is_empty(),"test chooses an omitted but already-public whole cell")
	mock.respond(started.request_id,envelope(control(request,"NEEDS_PUBLIC_CONTEXT",[far_path])))
	check(completed.back().code=="NEEDS_PUBLIC_CONTEXT" and C.bytes(before)==C.bytes(adapter.engine.save_data()),"context reply costs no state/RNG/turn")
	check(mock.sent.size()==1 and accepted==0 and adapter.phase()=="awaiting_assessment","no automatic retry or execution for feedback")
	started=runtime.request_assessment();request=outgoing(mock)
	check(started.ok and C.pointer(request.context.facts,far_path).ok,"manual reassessment includes exact bounded requested fact")
	var bad:=decision(request);bad["patches"]=[{"type":"flag_set","flag_id":"keeper_trust","value":true}]
	mock.respond(started.request_id,envelope(bad));check(not completed.back().ok and C.bytes(before)==C.bytes(adapter.engine.save_data()),"raw effect injection fails without mutation")
	started=runtime.request_assessment();request=outgoing(mock)
	adapter.attention(Content.make_reference("passage:coast_brace:south",adapter.state_copy()))
	mock.respond(started.request_id,envelope(decision(request)))
	check(accepted==1 and adapter.phase()=="idle" and adapter.state_copy().turn==1,"mock model reply uses real strict pipeline exactly once")
	var committed:Dictionary=adapter.engine.save_data();mock.respond(started.request_id,envelope(decision(request)))
	check(accepted==1 and C.bytes(committed)==C.bytes(adapter.engine.save_data()),"late duplicate cannot reroll or recommit")
	check(not C.bytes(committed).contains(KEY),"synthetic credential never in save")
	var result:=adapter.authoritative_result();var narrated:bool=false
	for effect in result.public_effects:
		if effect.type=="creative_source_place" or effect.type=="creative_relation_set":narrated=true
	check(result.rolls.size()==2 and result.outcomes.has("placement"),"public receipt exposes real program dice/outcomes")
	var report:={"checks":checks,"failures":failures,"live_provider":false,"transport":"injected mock_test_transport","semantic_accuracy_claim":false,"request_bytes":runtime.last_metrics,"result":result,"creative_effects_present":narrated}
	var file:=FileAccess.open("res://artifacts/creative_actions_20261003/mock_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	runtime.queue_free();await process_frame
	print("CREATIVE_MOCK ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
