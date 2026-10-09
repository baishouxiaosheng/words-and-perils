extends RefCounted
## The exact V3 exploration examples are reused with their original provenance.
## Only two new exact authored item examples can select the item resolvers.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseExamples = preload("res://view/generated_v3_adventure/assessments.gd")
const PublicProjection = preload("res://view/generated_v3_inventory/projection.gd")
const AUTHOR := "project_authored_v3_inventory_examples/v1"
static func goal(kind: String, target: Array = []) -> String:
	if kind == "drop_item": return "【行囊示例】把自带的行礼包整件放在脚边。"
	if kind == "pickup_item": return "【行囊示例】拾回附近地上的那件行礼包。"
	return BaseExamples.goal(kind,target)
static func build(request: Dictionary) -> Dictionary:
	if not request.get("context") is Dictionary or not request.context.get("facts") is Dictionary or request.context.facts.get("context_scope",{}).get("schema_version") != PublicProjection.ID: return C.fail("V3_INVENTORY_EXAMPLE_SCOPE","请先提交这张地图的完整行囊示例行动。")
	var kind := ""
	for candidate in ["drop_item","pickup_item"]:
		if request.context.get("goal") == goal(candidate): kind = candidate
	if kind.is_empty():
		# BaseExamples checks only its context tag before building exact immutable
		# exploration refs; do not mutate the real request or saved context.
		var compatible: Dictionary = request.duplicate(true)
		compatible.context.facts.context_scope.schema_version = BaseExamples.PublicProjection.ID
		return BaseExamples.build(compatible)
	var facts: Dictionary = request.context.facts
	if request.context.get("actor_id") != "actor_player" or not facts.get("items",{}).has("item_travel_bundle") or not facts.get("actors",{}).has("actor_player"): return C.fail("V3_INVENTORY_EXAMPLE_SCOPE","这个署名示例需要已登记的旅人与行礼包。")
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"行囊示例评估已准备，物品尚未移动。","interpretation":"这是作者预先编写的完整物品示例，未调用模型。","resolver_id":"generated_v3_"+kind+"_v1","bindings":{"actor_id":"actor_player","item_id":"item_travel_bundle"},"components":[{"id":"interact","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","item"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"item","path":"/items/item_travel_bundle","expected":facts.items.item_travel_bundle}],"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
static func verify(snapshot: Dictionary, reply: Dictionary, goal_: String, focus: Dictionary) -> bool:
	if not PublicProjection.matching_identity(snapshot): return false
	var expected := build({"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":PublicProjection.facts(snapshot,focus),"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}})
	return expected.ok and C.bytes(expected.assessment) == C.bytes(reply)
