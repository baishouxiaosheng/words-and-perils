extends RefCounted
## Reuse exact authored five-action examples; no static-object effect engine.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventoryExamples = preload("res://view/generated_v3_inventory/assessments.gd")
const PublicProjection = preload("res://view/generated_v3_village/projection.gd")
const AUTHOR := "project_authored_v3_village_inventory_examples/v1"
static func goal(kind: String, target: Array = []) -> String: return InventoryExamples.goal(kind,target)
static func build(request: Dictionary) -> Dictionary:
	if not request.get("context") is Dictionary or not request.context.get("facts") is Dictionary or request.context.facts.get("context_scope",{}).get("schema_version") != PublicProjection.ID: return C.fail("V3_VILLAGE_EXAMPLE_SCOPE","请先提交这张地图的完整探索或行囊示例。")
	var compatible: Dictionary = request.duplicate(true)
	compatible.context.facts.context_scope.schema_version = InventoryExamples.PublicProjection.ID
	var result: Dictionary = InventoryExamples.build(compatible)
	if result.ok: result.assessment.provenance.provider = AUTHOR
	return result
static func verify(snapshot: Dictionary, reply: Dictionary, goal_: String, focus: Dictionary) -> bool:
	if not PublicProjection.matching_identity(snapshot): return false
	var expected := build({"action_id":reply.action_id,"state_version":reply.state_version,"context_hash":reply.context_hash,"context":{"facts":PublicProjection.facts(snapshot,focus),"goal":goal_,"actor_id":reply.bindings.get("actor_id","")}})
	return expected.ok and C.bytes(expected.assessment) == C.bytes(reply)
