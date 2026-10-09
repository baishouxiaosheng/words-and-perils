extends RefCounted
## Exact authored offline assessments, shared by runtime UI and release fixture verifier.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const Basic = preload("res://view/playable_build/basic_examples.gd")
const Effects = preload("res://view/playable_build/effect_examples.gd")
const Story = preload("res://view/playable_build/story.gd")
const Composite = preload("res://view/playable_build/composite_examples.gd")
const CreativeExamples = preload("res://view/playable_build/creative_examples.gd")
const SettlementExamples = preload("res://view/playable_build/settlement_examples.gd")
const AUTHOR := "项目作者 · 明确署名海岸功能样例 coast_actions/v1"
static func build(request: Dictionary, binding_hint: Dictionary = {}) -> Dictionary:
	var context: Dictionary = request.context; var facts: Dictionary = context.facts
	var creative := CreativeExamples.find_goal(request)
	if not creative.is_empty(): return CreativeExamples.assessment(request,creative.source_id,creative.target_id,creative.operation)
	for site_id in facts.get("settlements",{}):
		for operation in ["open","close"]:
			if not SettlementExamples.public_goal(operation,facts,site_id).is_empty() and context.goal==SettlementExamples.public_goal(operation,facts,site_id): return SettlementExamples.assessment(request,operation,site_id)
	if C.exact_fields(binding_hint, ["actor_id", "target_hex", "target_actor_id", "weapon_item_id"]) and context.goal == Composite.goal(facts, binding_hint): return Composite.assessment(request, binding_hint)
	for id in facts.get("scene_transitions", {}):
		if context.goal == transition_goal(facts, id): return transition_assessment(request, id)
	for kind in Basic.KINDS + ["enemy_response"]:
		var expected: String = Basic.goal(kind, facts, context.attention_focus, context.actor_id)
		if not expected.is_empty() and context.goal == expected: return Basic.assessment(request, kind)
	for kind in ["fell", "poison", "flight"]:
		var expected: String = Effects.goal(kind, facts, context.attention_focus)
		if not expected.is_empty() and context.goal == expected: return Effects.assessment(request, kind)
	if context.actor_id != "actor_player": return C.fail("FIXTURE_SCOPE", "No authored NPC assessment matches this complete goal.")
	var kind := ""; var bindings := {"actor_id": "actor_player"}; var resolver := ""
	var exact_goals := {"observe": "【署名样例】停下脚步，观察南潮海岸，记下旧灯附近的线索。", "talk": "【署名样例】拿出一份随身果酒，向芦灯询问旧灯熄灭和船队失踪的事。", "repair": Story.GOAL, "rest": "【署名样例】原地休息片刻，恢复体力，然后继续探路。"}
	for candidate in exact_goals:
		if context.goal == exact_goals[candidate]: kind = candidate; break
	if kind.is_empty():
		var targets: Array = []
		if binding_hint.get("target_hex") is Array: targets.append(binding_hint.target_hex)
		else:
			for cell in facts.get("scene_hexes", {}).get(facts.actors.actor_player.scene_id, facts.hexes).values(): targets.append([cell.q, cell.r])
		for target in targets:
			if target.size() != 2 or not C.integer(target[0]) or not C.integer(target[1]): continue
			if context.goal == "【署名样例】按地形耗力行至（%d，%d）。" % target:
				kind = "move"; resolver = "coast_move_route_v3"; bindings.target_hex = target.duplicate(); break
			if context.goal == "【署名样例】沿干燥路线步行到（%d，%d）。" % target:
				kind = "move"; resolver = "coast_move_path_v2"; bindings.target_hex = target.duplicate(); break
			if context.goal == "【署名样例】步行到相邻格的干燥落脚点（%d，%d）。" % target:
				kind = "move"; resolver = "coast_move"; bindings.target_hex = target.duplicate(); break
	if kind.is_empty(): return C.fail("FIXTURE_SCOPE", "Only exact complete authored example goals have offline assessments.")
	if kind == "talk": bindings.target_actor_id = "actor_keeper"
	if resolver.is_empty(): resolver = "coast_" + kind
	var refs: Array = [{"id": "player", "path": "/actors/actor_player", "expected": facts.actors.actor_player}]
	if kind == "move":
		var key := "%d,%d" % bindings.target_hex
		var scene_id: String = facts.actors.actor_player.scene_id
		var cells: Dictionary = facts.get("scene_hexes", {}).get(scene_id, facts.hexes)
		if not cells.has(key): return C.fail("FIXTURE_SCOPE", "The exact movement target is not in the frozen map.")
		refs.append({"id": "target", "path": ("/scene_hexes/" + scene_id + "/" if facts.get("scene_hexes", {}).has(scene_id) else "/hexes/") + key, "expected": cells[key]})
	if kind == "talk":
		refs.append({"id": "keeper", "path": "/actors/actor_keeper", "expected": facts.actors.actor_keeper})
		refs.append({"id": "wine", "path": "/items/item_wine", "expected": facts.items.item_wine})
	if kind == "repair":
		refs.append({"id": "keeper", "path": "/actors/actor_keeper", "expected": facts.actors.actor_keeper})
		refs.append({"id": "clue", "path": "/flags/coast_observed", "expected": facts.flags.coast_observed})
		refs.append({"id": "trust", "path": "/flags/keeper_trust", "expected": facts.flags.keeper_trust})
	var ids: Array = []
	for ref in refs: ids.append(ref.id)
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "你准备执行署名的%s样例，尚未移动、消耗或改变事实。" % kind, "interpretation": "明确署名功能样例，精确文字目标绑定；没有运行模型。", "resolver_id": resolver, "bindings": bindings, "components": [{"id": kind, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "possible" if kind == "talk" else "certain", "fact_ref_ids": ids}], "fact_refs": refs, "provenance": {"provider": AUTHOR, "live": false, "kind": "fixture"}}}
static func verify(snapshot: Dictionary, reply: Dictionary, goal: String, focus: Dictionary) -> bool:
	var flags: Array = []
	for id in ["coast_observed", "keeper_trust", "lamp_restored"]:
		if snapshot.flags.has(id): flags.append(id)
	var facts := ModelView.facts(snapshot, {"npc_secret_allowlist": [], "public_flag_ids": flags})
	var request := {"phase": "assessment", "contract": {"resolver_ids": [reply.resolver_id]}, "action_id": reply.action_id, "state_version": reply.state_version, "context_hash": reply.context_hash, "context": {"facts": facts, "attention_focus": ModelView.focus_view(focus, facts), "goal": goal, "actor_id": reply.bindings.get("actor_id", "")}}
	var expected := build(request, reply.bindings)
	return expected.ok and C.bytes(expected.assessment) == C.bytes(reply)

static func transition_goal(facts: Dictionary, entrance_id: String) -> String:
	if not facts.get("scene_transitions", {}).has(entrance_id): return ""
	var e: Dictionary = facts.scene_transitions[entrance_id]
	return "【署名场景样例】通过%s（%s）进入%s。" % [e.name, e.id, facts.scenes[e.destination_scene_id].name]
static func transition_assessment(request: Dictionary, entrance_id: String) -> Dictionary:
	var facts: Dictionary = request.context.facts
	if request.context.actor_id != "actor_player" or request.context.goal != transition_goal(facts, entrance_id): return C.fail("FIXTURE_SCOPE", "Scene transition requires its exact explicitly authored goal.")
	var e: Dictionary = facts.scene_transitions[entrance_id]
	var scalar_scene: bool = "coast_scene_transition_v2" in request.get("contract",{}).get("resolver_ids",[])
	var scene_path: String = "/scenes/"+e.destination_scene_id+("/id" if scalar_scene else "")
	var cell_path: String = ("/scene_hexes/" + e.destination_scene_id + "/" if facts.get("scene_hexes", {}).has(e.destination_scene_id) else "/hexes/") + "%d,%d" % e.landing_hex
	var refs: Array = []; var ids: Array = []
	for path in ["/actors/actor_player", "/scene_transitions/" + entrance_id, scene_path, cell_path]:
		var found := C.pointer(facts, path)
		if not found.ok: return C.fail("FIXTURE_FACT", "A transition destination fact is not in public context.")
		var id := "transition_" + str(refs.size()); refs.append({"id": id, "path": path, "expected": found.value}); ids.append(id)
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "署名入口评估已准备，尚未切换场景。", "interpretation": "使用已有入口和安全落点；不生成室内内容。", "resolver_id": "coast_scene_transition_v2" if scalar_scene else "coast_scene_transition_v1", "bindings": {"actor_id": "actor_player", "entrance_id": entrance_id}, "components": [{"id": "transition", "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "possible", "fact_ref_ids": ids}], "fact_refs": refs, "provenance": {"provider": "项目作者 · 明确署名场景框架样例 scene_framework/v1", "live": false, "kind": "fixture"}}}
