extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventoryExamples=preload("res://view/generated_v3_inventory/assessments.gd")
const PublicProjection=preload("res://view/generated_v3_npc/projection.gd")
const Conversation=preload("res://core/source_npc/conversation.gd")
const AUTHOR="project_authored_v3_npc_examples/v1"
static func goal(kind: String,target: Array=[]) -> String:
	if kind=="talk":return "【交谈示例】向守路村民询问村落入口。"
	return InventoryExamples.goal(kind,target)
static func build(request: Dictionary) -> Dictionary:
	if not request.get("context") is Dictionary or not request.context.get("facts") is Dictionary or request.context.facts.get("context_scope",{}).get("schema_version")!=PublicProjection.ID:return C.fail("NPC_EXAMPLE_SCOPE","请提交完整行动示例，或导入这次意图的评估。")
	if request.context.get("goal")!=goal("talk"):
		var compatible: Dictionary=request.duplicate(true)
		compatible.context.facts.context_scope.schema_version=InventoryExamples.PublicProjection.ID
		var result: Dictionary=InventoryExamples.build(compatible)
		if result.ok:result.assessment.provenance.provider=AUTHOR
		return result
	var facts: Dictionary=request.context.facts
	if request.context.get("actor_id")!="actor_player" or facts.get("npc_targets",{}).size()!=1:return C.fail("NPC_EXAMPLE_SCOPE","交谈示例需要登记的守路村民。")
	var id: String=facts.npc_targets.keys()[0]
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"已准备交谈评估，尚未获知新信息。","interpretation":"离线剧情演示（预设裁定），没有调用实时模型。","resolver_id":Conversation.ID,"bindings":{"actor_id":"actor_player","target_actor_id":id,"topic_id":"entry_directions"},"components":[{"id":"talk","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","npc"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"npc","path":"/npc_targets/"+id,"expected":facts.npc_targets[id]}],"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
static func verify(snapshot: Dictionary,reply: Dictionary,goal_: String,focus: Dictionary) -> bool:
	if not PublicProjection.matching_identity(snapshot):return false
	var expected: Dictionary=build({"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":PublicProjection.facts(snapshot,focus),"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}})
	return expected.ok and C.bytes(expected.assessment)==C.bytes(reply)
