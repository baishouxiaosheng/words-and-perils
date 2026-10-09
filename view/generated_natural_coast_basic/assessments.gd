extends RefCounted
## Exact authored demonstration assessments. Free text never selects these by
## keyword, current focus or a guessed target; it awaits a valid separate reply.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicProjection = preload("res://view/generated_natural_coast_basic/projection.gd")
const AUTHOR := "project_authored_natural_coast_basic_examples/v1"
static func goal(kind: String, target: Array = []) -> String:
	if kind == "drop_item": return "【行囊示例】把自带的行礼包整件放在脚边。"
	if kind == "pickup_item": return "【行囊示例】拾回附近地上的那件行礼包。"
	if kind == "rest": return "【探索示例】原地休息，恢复最多两点体力。"
	if target.size() != 2: return ""
	if kind == "move": return "【探索示例】沿可通行的干地走到（%d，%d）。" % target
	if kind == "observe": return "【探索示例】观察附近地格（%d，%d），记录地形。" % target
	return ""
static func build(request: Dictionary) -> Dictionary:
	if not request.get("context") is Dictionary or not request.context.get("facts") is Dictionary or request.context.facts.get("context_scope",{}).get("schema_version") != PublicProjection.ID: return C.fail("V3_EXAMPLE_SCOPE","请先提交这张地图的完整示例行动。")
	var facts: Dictionary = request.context.facts
	var kind := "rest" if request.context.goal == goal("rest") else ""
	for item_kind in ["drop_item","pickup_item"]:
		if request.context.goal == goal(item_kind): kind = item_kind
	var target: Array = []
	for cell in facts.hexes.values():
		for candidate in ["move","observe"]:
			if request.context.goal == goal(candidate,[cell.q,cell.r]): kind = candidate; target = [cell.q,cell.r]; break
	if kind.is_empty() or request.context.actor_id != "actor_player": return C.fail("V3_EXAMPLE_SCOPE","这段自由文字需要另行评估；内置示例不能替它决定行动。")
	var bindings := {"actor_id":"actor_player"}
	var refs: Array = [{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player}]
	var ids: Array = ["actor"]
	if kind in ["move","observe"]:
		bindings.target_hex = target
		refs.append({"id":"target","path":"/hexes/"+"%d,%d" % target,"expected":facts.hexes["%d,%d" % target]}); ids.append("target")
	if kind in ["drop_item","pickup_item"]:
		if not facts.get("items",{}).has("item_travel_bundle"): return C.fail("COAST_ITEM","The registered travel bundle is missing.")
		bindings["item_id"] = "item_travel_bundle"
		refs.append({"id":"item","path":"/items/item_travel_bundle","expected":facts.items.item_travel_bundle}); ids.append("item")
	var component_id := "interact" if kind in ["drop_item","pickup_item"] else kind
	return {"ok":true,"assessment":{"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"示例评估已准备，行动尚未执行。","interpretation":"这是作者预先编写的完整行动示例，未调用模型。","resolver_id":"natural_coast_"+kind+"_v1","bindings":bindings,"components":[{"id":component_id,"parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":ids}],"fact_refs":refs,"provenance":{"provider":AUTHOR,"live":false,"kind":"fixture"}}}
static func verify(snapshot: Dictionary, reply: Dictionary, goal_: String, focus: Dictionary) -> bool:
	if not PublicProjection.active(snapshot): return false
	var facts := PublicProjection.facts(snapshot,focus)
	var request := {"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":facts,"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}}
	var expected := build(request)
	return expected.ok and C.bytes(expected.assessment) == C.bytes(reply)
