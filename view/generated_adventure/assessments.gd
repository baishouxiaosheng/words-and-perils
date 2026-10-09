extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicProjection = preload("res://view/generated_adventure/projection.gd")
const AUTHOR := "项目作者 · 明确署名多地貌探索样例 generated_examples/v1"
static func goal(kind: String,target: Array=[]) -> String:
	if kind=="rest":return "【署名多地貌样例】原地休息，恢复最多两点体力。"
	if target.size()!=2:return ""
	if kind=="move":return "【署名多地貌样例】按已验证干地路线行至（%d，%d）。"%target
	if kind=="observe":return "【署名多地貌样例】观察邻近地格（%d，%d），记下其地貌。"%target
	return ""
static func build(request: Dictionary) -> Dictionary:
	var facts: Dictionary=request.context.facts
	var kind := "rest" if request.context.goal==goal("rest") else ""
	var target: Array=[]
	for cell in facts.hexes.values():
		for candidate in ["move","observe"]:
			if request.context.goal==goal(candidate,[cell.q,cell.r]):kind=candidate;target=[cell.q,cell.r];break
	if kind.is_empty() or request.context.actor_id!="actor_player":return C.fail("FIXTURE_SCOPE","Only the exact complete signed generated example has an authored assessment.")
	var bindings := {"actor_id":"actor_player"}
	var refs: Array=[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player}]
	var ids: Array=["actor"]
	if kind!="rest":
		bindings.target_hex=target
		refs.append({"id":"target","path":"/hexes/"+"%d,%d"%target,"expected":facts.hexes["%d,%d"%target]});ids.append("target")
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"明确署名的多地貌探索评估已准备，事实尚未改变。","interpretation":"仅适用于完整匹配的署名行动，没有调用模型。","resolver_id":"generated_"+kind+"_v1","bindings":bindings,"components":[{"id":kind,"parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":ids}],"fact_refs":refs,"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
static func verify(snapshot: Dictionary,reply: Dictionary,goal_: String,focus: Dictionary) -> bool:
	var facts:=PublicProjection.facts(snapshot,focus)
	var request: Dictionary={"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":facts,"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}}
	var expected:=build(request)
	return expected.ok and C.bytes(expected.assessment)==C.bytes(reply)
