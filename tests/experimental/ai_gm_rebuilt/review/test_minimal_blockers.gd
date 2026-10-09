extends SceneTree
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
func registry() -> Dictionary:
	return {"fixture_gate": Resolver.new("gate"), "fixture_listen": Resolver.new("listen")}
func game() -> RefCounted:
	return GMEngine.new(Story.world(), Rule.new(), registry(), {}, 123)
func fixture(engine: RefCounted, goal: String, resolver: String = "fixture_gate") -> Dictionary:
	return Story.assessment(engine.begin_intent(goal).request, resolver, ["certain", "certain"])
func execute(engine: RefCounted, reply: Dictionary) -> Dictionary:
	var p: Dictionary = engine.prepare_assessment(reply)
	if not p.get("ok", false): return p
	var r: Dictionary = engine.roll_once(reply.action_id)
	if not r.get("ok", false): return r
	var s: Dictionary = engine.stage(reply.action_id)
	if not s.get("ok", false): return s
	return engine.commit(reply.action_id, s.stage_hash)
func _initialize() -> void:
	var engine := game()
	var data: Dictionary = engine.save_data()
	data.policy.npc_secret_allowlist = ["/actors/actor_guard_a/secrets/gate_password"]
	var loaded: Dictionary = engine.load_data(data)
	var request: Dictionary = engine.begin_intent("询问渡口安排").request
	print("POLICY_ESCALATION ", JSON.stringify({"loaded": loaded, "secret_exposed": C.bytes(request).contains("low_tide")}))

	engine = game()
	var first: Dictionary = fixture(engine, "首次交涉")
	var committed: Dictionary = execute(engine, first)
	data = engine.save_data(); data.next_action = 1
	loaded = engine.load_data(data)
	var second: Dictionary = fixture(engine, "第二次交涉，同ID不同计划")
	var prepared: Dictionary = engine.prepare_assessment(second)
	var rolled: Dictionary = engine.roll_once(second.action_id)
	var staged: Dictionary = engine.stage(second.action_id)
	var frozen: Dictionary = engine.action_copy(second.action_id)
	var result: Dictionary = engine.commit(second.action_id, staged.get("stage_hash", ""))
	print("ACTION_ID_REUSE ", JSON.stringify({"loaded": loaded, "same_id": first.action_id == second.action_id, "plan_differs": committed.get("receipt", {}).get("plan_hash", "") != frozen.get("plan_hash", ""), "prepared": prepared, "rolled": rolled, "staged": staged, "commit": result, "state_version": engine.state_copy().state_version, "pending_status": engine.action_copy(second.action_id).get("status", "none")}))

	engine = game()
	var crossed: Dictionary = fixture(engine, "玩家请求交酒")
	crossed.bindings.actor_id = "actor_guard_z"
	result = execute(engine, crossed)
	print("BOUND_ACTOR_SUBSTITUTION ", JSON.stringify({"result": result, "player_stamina": engine.state_copy().actors.actor_player.stamina.current, "other_stamina": engine.state_copy().actors.actor_guard_z.stamina.current}))
	quit()
