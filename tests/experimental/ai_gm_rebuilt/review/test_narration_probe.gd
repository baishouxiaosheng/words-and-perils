extends SceneTree
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
func _initialize() -> void:
	var state := Story.world()
	state.actors.actor_guard_z.hooks = ["patrol"]
	state.actors.actor_guard_z.patrol = {"route": [[0, 1], [1, 0]], "index": 0}
	var e := GMEngine.new(state, Rule.new(), {"fixture_gate": Resolver.new("gate")}, {}, 123)
	var begun: Dictionary = e.begin_intent("交酒问渡口", {"world_id": state.world_id, "kind": "actor", "id": "actor_guard_a"})
	var a := Story.assessment(begun.request, "fixture_gate", ["possible", "possible"])
	e.prepare_assessment(a); e.roll_once(a.action_id); var staged: Dictionary = e.stage(a.action_id)
	var req: Dictionary = e.narration_request(a.action_id)
	print("STAGED_NARRATION ", JSON.stringify(req))
	var reply := {"schema_version": "ai_gm_narration/v1", "action_id": a.action_id, "state_version": true, "context_hash": req.context_hash, "narration": "描述"}
	print("BOOL_VERSION ", JSON.stringify(e.validate_narration_reply(reply)))
	e.commit(a.action_id, staged.stage_hash)
	print("COMMITTED_NARRATION ", JSON.stringify(e.narration_request(a.action_id)))
	quit()
