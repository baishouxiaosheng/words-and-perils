extends SceneTree
const GameState = preload("res://core/game_state.gd")
const Relay = preload("res://core/json_relay_provider.gd")
var checks := 0
var failures: Array = []
const GOAL := "喝下雾行药剂，穿过浅水走到那里，再试着说服守卫放下武器。"
const PLAN := "res://tests/recorded_compound_planning.json"
const FINAL := "res://tests/recorded_compound_resolution_d20_9.json"

func _initialize() -> void:
	var game := GameState.new()
	var relay := Relay.new()
	var asked: Dictionary = game.request(GOAL, Vector2i(1, -1))
	var planning: Dictionary = relay.recorded_example_for(asked.request, PLAN)
	_check(planning.ok, "recorded plan matches exact fresh world")
	if not planning.ok:
		printerr(planning)
		_finish()
		return
	_check(planning.decision.action_id == asked.request.action_id, "replay binds this session action ID")
	_check(not planning.decision.provenance.live and planning.recorded_example, "replay retains truthful source label")
	var accepted: Dictionary = game.apply_planning(planning.decision)
	_check(accepted.ok, "recorded planning applies")
	if not accepted.ok:
		printerr(accepted)
		_finish()
		return
	var rolled: Dictionary = game.roll_action(asked.request.action_id, 9)
	if not rolled.ok:
		printerr(rolled)
		_finish()
		return
	var final: Dictionary = relay.recorded_example_for(rolled.request, FINAL)
	_check(final.ok, "resolution matches recorded D20=9")
	_check(game.commit_decision(final.decision).ok, "recorded canonical resolution commits")
	_check(game.state.events[0].provenance.provider == "recorded_external_gm_example", "durable event labels recorded source")
	_check(not relay.import_decision(PLAN).ok, "recorded wrapper cannot pretend to be a live reply")
	var altered := GameState.new()
	altered.state.items.item_mist_draught.quantity = 0
	var altered_request: Dictionary = altered.request(GOAL, Vector2i(1, -1))
	_check(not relay.recorded_example_for(altered_request.request, PLAN).ok, "same version with changed numerical inventory is rejected")
	altered.new_world()
	altered.state.hexes["0,1"].terrain = "bridge"
	altered_request = altered.request(GOAL, Vector2i(1, -1))
	_check(not relay.recorded_example_for(altered_request.request, PLAN).ok, "changed terrain is rejected")
	altered.new_world()
	altered_request = altered.request("different goal", Vector2i(1, -1))
	_check(not relay.recorded_example_for(altered_request.request, PLAN).ok, "different player goal rejected")
	altered.new_world()
	altered_request = altered.request(GOAL, Vector2i(1, 0))
	_check(not relay.recorded_example_for(altered_request.request, PLAN).ok, "different target rejected")
	altered.new_world()
	altered_request = altered.request(GOAL, Vector2i(1, -1))
	var replay: Dictionary = relay.recorded_example_for(altered_request.request, PLAN)
	altered.apply_planning(replay.decision)
	var different_roll: Dictionary = altered.roll_action(altered_request.request.action_id, 8)
	_check(not relay.recorded_example_for(different_roll.request, FINAL).ok, "different D20 cannot reuse recorded resolution")
	var no_snapshot: Dictionary = relay.transport.read_json(PLAN).data
	no_snapshot.erase("expected_snapshot")
	relay.transport.write_json("user://unsafe_recorded.json", no_snapshot)
	_check(not relay.recorded_example_for(altered_request.request, "user://unsafe_recorded.json").ok, "replay requires exact expected snapshot")
	_finish()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("RECORDED PROVIDER TESTS PASSED: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + str(failure))
		quit(1)
