extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content=preload("res://view/playable_build/settlement_content.gd")
const Gate=preload("res://core/ai_gm_rebuilt/settlement_actions.gd")
static func goal(operation:String,state:Dictionary,focus:Dictionary={})->String:
	if not Content.active(state) or not operation in ["open","close"]:return ""
	var place:=Content.site(str(focus.get("id","")))
	if place.is_empty() or not place.walled:
		place=Content.manifest()
		for candidate in Content.all_settlements():
			if candidate.walled and state.actors.actor_player.hex in [candidate.gate_inside_hex,candidate.gate_outside_hex]:place=candidate;break
	return _goal(operation,place)
static func _goal(operation:String,place:Dictionary)->String:
	return "【署名围寨样例】%s%s城门（%s）。"%["开启" if operation=="open" else "关闭",place.name,place.gate_id] if place.get("walled",false) else ""
static func public_goal(operation:String,facts:Dictionary,site_id:String="")->String:
	var place:Dictionary=facts.get("settlement",{}) if site_id.is_empty() else facts.get("settlements",{}).get(site_id,{})
	return _goal(operation,place) if not place.is_empty() and operation in ["open","close"] else ""
static func assessment(request:Dictionary,operation:String,site_id:String="")->Dictionary:
	var facts:Dictionary=request.context.facts
	var place:Dictionary=facts.get("settlement",{}) if site_id.is_empty() else facts.get("settlements",{}).get(site_id,{})
	if request.context.actor_id!="actor_player" or place.is_empty() or request.context.goal!=public_goal(operation,facts,site_id):return C.fail("FIXTURE_SCOPE","Gate fixture requires its complete exact authored goal.")
	var refs:Array=[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"settlement","path":"/settlements/"+place.id,"expected":place}]
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"无锁木栅门操作已评估，尚未开关、扣费或推进回合。","interpretation":"明确署名围寨样例；没有调用模型，也不处理锁具或社会许可。","resolver_id":Gate.ID,"bindings":{"actor_id":"actor_player","gate_id":place.gate_id,"operation":operation},"components":[{"id":"operate","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","settlement"]}],"fact_refs":refs,"provenance":{"provider":"项目作者 · 明确署名围寨样例 coast_settlement/v1","live":false,"kind":"fixture"}}}
