extends RefCounted
## Exact visibly signed offline examples. Never interprets arbitrary user text.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Base=preload("res://view/generated_v3_npc/assessments.gd")
const PublicProjection=preload("res://view/generated_v3_equipment/projection.gd")
const Catalog=preload("res://core/source_equipment/catalog.gd")
const AUTHOR="project_authored_v3_equipment_examples/v1"
static func goal(kind:String,target:Array=[])->String:
	if kind=="attack":return attack_goal(Catalog.STAFF)
	if kind=="pickup_blade":return "【拾取示例】取走倒下拦路者持有的苦叶短刃。"
	if kind=="equip_blade":return "【装备示例】换上我持有的苦叶短刃，木杖留在行囊里。"
	if kind=="equip_staff":return "【装备示例】换上我持有的潮岸木杖，短刃留在行囊里。"
	if kind in ["enemy_attack","enemy_response"]:return "【敌方近战示例】持刃拦路者用苦叶短刃攻击旅人。"
	return Base.goal(kind,target)
static func build(request:Dictionary)->Dictionary:
	if not request.get("context") is Dictionary or not request.context.get("facts") is Dictionary or request.context.facts.get("context_scope",{}).get("schema_version")!=PublicProjection.ID:return C.fail("ENEMY_EXAMPLE_SCOPE","请提交完整署名行动示例，或导入当前意图的评估。")
	for kind in ["pickup_blade","equip_blade","equip_staff"]:
		if request.context.get("goal")==goal(kind):return equipment_assessment(request,kind)
	var equipped:String=str(request.context.facts.get("actors",{}).get("actor_player",{}).get("equipment",{}).get("weapon",""))
	if request.context.get("goal")==attack_goal(equipped):return attack_assessment(request,"attack")
	for kind in ["enemy_attack"]:
		if request.context.get("goal")==goal(kind):return attack_assessment(request,kind)
	var compatible:Dictionary=request.duplicate(true);compatible.context.facts.context_scope.schema_version=Base.PublicProjection.ID
	var result:Dictionary=Base.build(compatible)
	if result.ok:result.assessment.provenance.provider=AUTHOR
	return result
static func attack_assessment(request:Dictionary,kind:String)->Dictionary:
	var facts:Dictionary=request.context.facts
	var actor_id:String=Catalog.ENEMY if kind=="enemy_attack" else "actor_player"
	var target_id:String="actor_player" if kind=="enemy_attack" else Catalog.ENEMY
	var weapon_id:String=str(facts.get("actors",{}).get(actor_id,{}).get("equipment",{}).get("weapon",""))
	if request.context.get("actor_id")!=actor_id or not facts.get("actors",{}).has(actor_id) or not facts.actors.has(target_id) or not facts.get("items",{}).has(weapon_id):return C.fail("ENEMY_EXAMPLE_ACTOR","示例需要当前回合的准确角色、目标和武器。")
	var refs:Array=[{"id":"actor","path":"/actors/"+actor_id,"expected":facts.actors[actor_id]},{"id":"target","path":"/actors/"+target_id,"expected":facts.actors[target_id]},{"id":"weapon","path":"/items/"+weapon_id,"expected":facts.items[weapon_id]}]
	var components:Array=[]
	for id in ["accuracy","impact"]:components.append({"id":id,"parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","target","weapon"]})
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"近战评估已准备；尚未命中、扣费或施毒。","interpretation":"明确署名离线预设裁定，未调用实时AI；结果由固定规则独立检定。","resolver_id":"coast_basic_attack_v1","bindings":{"actor_id":actor_id,"target_actor_id":target_id,"weapon_item_id":weapon_id},"components":components,"fact_refs":refs,"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
static func verify(snapshot:Dictionary,reply:Dictionary,goal_:String,focus:Dictionary)->bool:
	if not PublicProjection.matching_identity(snapshot):return false
	var expected:Dictionary=build({"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":PublicProjection.facts(snapshot,focus),"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}})
	return expected.ok and C.bytes(expected.assessment)==C.bytes(reply)

static func attack_goal(weapon_id:String)->String:
	return "【近战示例】用"+("苦叶短刃" if weapon_id==Catalog.BLADE else "潮岸木杖")+"攻击持刃拦路者。"
static func equipment_assessment(request:Dictionary,kind:String)->Dictionary:
	var facts:Dictionary=request.context.facts
	var item_id:String=Catalog.STAFF if kind=="equip_staff" else Catalog.BLADE
	if request.context.get("actor_id")!="actor_player" or not facts.get("items",{}).has(item_id):return C.fail("EQUIPMENT_EXAMPLE","这个示例需要准确旅人和登记武器。")
	var refs:Array=[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"item","path":"/items/"+item_id,"expected":facts.items[item_id]}]
	var ids:Array=["actor","item"]
	if kind=="pickup_blade":
		refs.append({"id":"owner","path":"/actors/"+Catalog.ENEMY,"expected":facts.actors[Catalog.ENEMY]});ids.append("owner")
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"物品操作评估已准备，归属和装备尚未改变。","interpretation":"明确署名的离线物品示例，未调用实时AI；取走与换装是分别评估的行动。","resolver_id":"coast_pickup_item_v1" if kind=="pickup_blade" else "coast_equip_item_v1","bindings":{"actor_id":"actor_player","item_id":item_id},"components":[{"id":"interact","parameters":{"A":2,"D":1,"P":0},"disposition":"possible","fact_ref_ids":ids}],"fact_refs":refs,"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
