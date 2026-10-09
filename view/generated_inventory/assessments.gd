extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseExamples = preload("res://view/generated_adventure/assessments.gd")
const PublicProjection = preload("res://view/generated_inventory/projection.gd")
const AUTHOR := "项目作者 · 明确署名行囊样例 generated_inventory_examples/v1"
static func goal(kind: String, target: Array = []) -> String:
	if kind == "drop_item": return "【署名物品样例】把自带的行礼包整件放在脚边。"
	if kind == "pickup_item": return "【署名物品样例】拾回附近地上的那件行礼包。"
	return BaseExamples.goal(kind, target)
static func build(request: Dictionary) -> Dictionary:
	var kind := ""
	for candidate in ["drop_item", "pickup_item"]:
		if request.context.goal == goal(candidate): kind = candidate
	if kind.is_empty(): return BaseExamples.build(request)
	var facts: Dictionary = request.context.facts
	if request.context.actor_id != "actor_player" or not facts.items.has("item_travel_bundle"):
		return C.fail("FIXTURE_SCOPE", "This signed supply example requires the registered traveler and known travel bundle.")
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "明确署名的行囊评估已准备，物品尚未移动。", "interpretation": "仅适用于完整匹配的署名行动，没有调用模型。", "resolver_id": "generated_" + kind + "_v1", "bindings": {"actor_id": "actor_player", "item_id": "item_travel_bundle"}, "components": [{"id": "interact", "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "possible", "fact_ref_ids": ["actor", "item"]}], "fact_refs": [{"id": "actor", "path": "/actors/actor_player", "expected": facts.actors.actor_player}, {"id": "item", "path": "/items/item_travel_bundle", "expected": facts.items.item_travel_bundle}], "provenance": {"provider": AUTHOR, "live": false, "kind": "fixture"}}}
static func verify(snapshot: Dictionary, reply: Dictionary, goal_: String, focus: Dictionary) -> bool:
	var expected := build({"action_id": reply.action_id, "state_version": reply.state_version, "context_hash": reply.context_hash, "context": {"facts": PublicProjection.facts(snapshot, focus), "goal": goal_, "actor_id": reply.bindings.get("actor_id", "")}})
	return expected.ok and C.bytes(expected.assessment) == C.bytes(reply)
