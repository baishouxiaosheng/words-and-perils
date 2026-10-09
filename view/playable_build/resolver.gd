extends RefCounted
## Trusted finite actions. Assessments select identity/parameters, never write effects.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const Story = preload("res://view/playable_build/story.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
var kind := "observe"
func _init(kind_: String = "observe") -> void: kind = kind_
func resolver_id() -> String: return "coast_" + kind
func action_schema() -> Dictionary:
	var bindings := {"actor_id": "actor_player"}
	if kind == "move": bindings.target_hex = "adjacent [q,r]"
	if kind == "talk": bindings.target_actor_id = "actor_keeper"
	var scopes := {"observe": "Observe the authored south coast/old lamp clues only; success sets coast_observed. Arbitrary investigation or invented discoveries are not supported.", "talk": "Offer one owned wine to adjacent keeper actor_keeper to discuss the old lamp and missing fleet; success sets keeper_trust. No generic diplomacy or relationship rewrite.", "repair": "Repair the authored old lamp only, after coast_observed, within one cell of keeper, stamina cost2 or1 with keeper_trust. Success sets lamp_restored; completed lamp cannot be repaired twice. This is the finite chapter ending.", "rest": "Rest in place to recover at most two stamina, up to current maximum. No healing or new capabilities.", "move": "One adjacent legal dry ground step only; one stamina. Use coast_move_path_v2 for a longer explicit route."}
	var paths: Array = ["/actors/actor_player"]
	if kind == "talk": paths.append_array(["/actors/actor_keeper", "/items/item_wine"])
	if kind == "repair": paths.append_array(["/actors/actor_keeper", "/flags/coast_observed", "/flags/keeper_trust"])
	if kind == "move": paths.append("/hexes/<target_q,r>")
	return {"schema_version": "coast_legacy_actions/v1", "resolver_id": resolver_id(), "bindings": bindings, "components": [kind], "numeric_assessment": {"A": [0, 4], "D": [0, 4], "P": [-2, 2]}, "required_fact_paths": paths, "intent_scope": scopes.get(kind, "unsupported"), "every_intent_requires_assessment": true, "disposition": "advisory_only_under_release_v1", "rule_policy": "contested" if kind in ["talk", "repair"] else "safe_direct_after_preconditions", "authority": "Trusted resolver fixes all costs and effects. No keyword interpretation or invented outcomes."}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var plan := freeze(snapshot, assessment)
	if not plan.ok: return plan
	return {"ok": true, "policies": {kind: "contested" if kind in ["talk", "repair"] else "safe_direct"}}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return kind + ":" + C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, _assessment: Dictionary) -> Dictionary:
	var result := {"actor": snapshot.actors.actor_player, "keeper": snapshot.actors.actor_keeper, "scout": snapshot.actors.actor_scout, "wine": snapshot.items.item_wine, "flags": snapshot.flags}
	if snapshot.has("settlement_state"): result.settlement = snapshot.settlement_state
	return result
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary = assessment.bindings
	var expected: Array = ["actor_id", "target_hex"] if kind == "move" else (["actor_id", "target_actor_id"] if kind == "talk" else ["actor_id"])
	if not C.exact_fields(b, expected) or b.get("actor_id") != "actor_player": return C.fail("ACTION_BINDING", "动作必须绑定当前旅人和该resolver所需目标。")
	if assessment.components.size() != 1 or assessment.components[0].id != kind: return C.fail("ACTION_COMPONENT", "该有限动作需要唯一同名分量。")
	var actor: Dictionary = snapshot.actors.actor_player
	if kind != "rest" and actor.scene_id != "scene_coast": return C.fail("ACTION_SCENE", "This authored coast action is unavailable in another scene.")
	var success: Array = []; var failure: Array = []
	match kind:
		"move":
			if not b.target_hex is Array or b.target_hex.size() != 2 or not C.integer(b.target_hex[0]) or not C.integer(b.target_hex[1]) or b.target_hex == actor.hex: return C.fail("MOVE_TARGET", "需要不同的相邻真实格坐标。")
			var route := Traversal.path(snapshot, "actor_player", b.target_hex, 1)
			if route.size() != 2: return C.fail("MOVE_UNREACHABLE", "当前演示步行只允许一个相邻有合法干燥落脚点的land格；不能跨海跳跃。")
			var clear_step := Navigation.step(actor.hex,b.target_hex)
			if not clear_step.ok: return clear_step
			if actor.stamina.current < 1: return C.fail("STAMINA_REQUIRED", "体力不足，可先评估休息。")
			success = [{"type": "actor_move", "actor_id": "actor_player", "scene_id": actor.scene_id, "hex": b.target_hex.duplicate()}, {"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": -1}]
		"observe": success = [{"type": "flag_set", "flag_id": "coast_observed", "value": true}]
		"talk":
			if b.target_actor_id != "actor_keeper": return C.fail("TALK_TARGET", "当前交涉演示仅支持芦灯。")
			var other: Dictionary = snapshot.actors.actor_keeper
			var dq: int = actor.hex[0]-other.hex[0]; var dr: int = actor.hex[1]-other.hex[1]
			if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) > 1: return C.fail("TALK_DISTANCE", "先走到芦灯附近一格内，再交涉。")
			if snapshot.items.item_wine.quantity < 1 or actor.stamina.current < 1: return C.fail("TALK_COST", "交涉需要随身果酒和一点体力。")
			failure = [{"type": "item_quantity_delta", "item_id": "item_wine", "delta": -1}, {"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": -1}]
			success = failure.duplicate(true); success.append({"type": "flag_set", "flag_id": "keeper_trust", "value": true})
		"repair":
			var repair := Story.repair_branches(snapshot)
			if not repair.ok: return repair
			success = repair.success; failure = repair.failure
		"rest":
			var amount: int = mini(2, actor.stamina.max-actor.stamina.current)
			if amount <= 0: return C.fail("REST_FULL", "体力已满，无需恢复。")
			success = [{"type": "actor_pool_delta", "actor_id": "actor_player", "pool": "stamina", "delta": amount}]
		_: return C.fail("UNKNOWN_ACTION", "未知演示resolver。")
	return {"ok": true, "resolver_id": resolver_id(), "branches": [{"id": kind+"_success", "requires": {kind: true}, "patches": success}, {"id": kind+"_failure", "requires": {kind: false}, "patches": failure}]}
