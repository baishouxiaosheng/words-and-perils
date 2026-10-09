extends SceneTree
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
func _initialize() -> void:
	var e := GMEngine.new(Story.world(), Rule.new(), {"fixture_gate": Resolver.new("gate")}, {}, 123)
	var request: Dictionary = e.begin_intent("尝试").request
	var a: Dictionary = Story.assessment(request)
	for field in ["schema_version", "context_hash", "action_id", "resolver_id"]:
		var bad: Dictionary = a.duplicate(true); bad[field] = true
		print("ASSESSMENT_FIELD ", field, " ", JSON.stringify(e.prepare_assessment(bad)))
	for field in ["schema_version", "rule_id", "resolver_ids"]:
		var bad: Dictionary = e.save_data(); bad[field] = true
		print("SAVE_FIELD ", field, " ", JSON.stringify(e.load_data(bad)))
	for field in ["state_version", "context_hash"]:
		var bad: Dictionary = e.save_data(); bad.pending[request.action_id][field] = true
		print("PENDING_FIELD ", field, " ", JSON.stringify(e.load_data(bad)))
	var w: Dictionary = Story.world(); w.schema_version = true
	print("WORLD_SCHEMA ", JSON.stringify(World.validate(w)))
	w = Story.world(); w.actors.actor_player.id = true
	print("WORLD_ACTOR_ID ", JSON.stringify(World.validate(w)))
	quit()
