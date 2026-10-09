extends SceneTree
## Integration audit of externally produced model fixtures. Never manufactures
## a model outcome when a reply is missing. Missing files cause a failed check.
const GameState = preload("res://core/game_state.gd")
const Relay = preload("res://core/json_relay_provider.gd")
var failures: Array = []
var report: Array = []

func _initialize() -> void:
	_test_compound()
	for case_id in ["ordinary", "fakeadmin", "impossible"]:
		_test_case(case_id)
	var relay := Relay.new()
	relay.transport.write_json("res://tests/recorded_case_report.json", {"schema_version": 1, "cases": report, "failures": failures, "all_supplied_fixtures_pass": failures.is_empty()})
	for entry in report:
		print(JSON.stringify(entry))
	if failures.is_empty():
		print("RECORDED FOUR-CASE AUDIT PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + str(failure))
		quit(1)

func _test_compound() -> void:
	var game := GameState.new()
	var loaded: Dictionary = game.load_from_file("res://tests/compound_waiting_resolution_state.json")
	var relay := Relay.new()
	var reply: Dictionary = relay.import_decision("res://tests/compound_resolution_luna_d20_9.json")
	if not loaded.ok or not reply.ok:
		_fail("compound", "Missing/invalid actual model resolution or recorded pending state.")
		return
	var before := game.state.duplicate(true)
	var committed: Dictionary = game.commit_decision(reply.decision)
	if not committed.ok:
		_fail("compound", str(committed))
		return
	var event: Dictionary = committed.event
	if event.roll.value != 9 or event.planning.difficulty != 14:
		_fail("compound", "Recorded D20 or GM difficulty changed during commit.")
	if game.state.state_version != 1 or game.state.events.size() != 1:
		_fail("compound", "Expected one atomic resolution commit.")
	if not game.commit_decision(reply.decision).get("already_committed", false) or game.state.events.size() != 1:
		_fail("compound", "Duplicate model resolution was not idempotent.")
	report.append({"case": "compound_partial_d20_9", "stage": "resolution_committed", "gm_outcome": event.outcome, "player_d20": event.roll.value, "gm_difficulty": event.planning.difficulty, "before": {"position": before.actors.actor_player.hex, "health": before.actors.actor_player.health, "stamina": before.actors.actor_player.stamina, "potion_quantity": before.items.item_mist_draught.quantity}, "after": {"position": game.state.actors.actor_player.hex, "health": game.state.actors.actor_player.health, "stamina": game.state.actors.actor_player.stamina, "potion_quantity": game.state.items.item_mist_draught.quantity}, "patches": event.patches, "numerical_integrity": true, "idempotent": true})

func _test_case(case_id: String) -> void:
	var relay := Relay.new()
	var source: Dictionary = relay.transport.read_json("res://tests/" + case_id + "_planning_request.json")
	var loaded: Dictionary = relay.import_decision("res://tests/" + case_id + "_planning_luna.json")
	if not source.ok or not loaded.ok:
		_fail(case_id, "Missing/invalid actual model planning response.")
		return
	var fixture: Dictionary = source.data
	var reply: Dictionary = loaded.decision
	if reply.action_id != fixture.action_id or reply.state_version != fixture.state_version:
		_fail(case_id, "Model reply mismatches the actual fixture identity/version.")
		return
	var game := GameState.new()
	game.state.world_id = fixture.world_id
	var asked: Dictionary = game.request(fixture.goal, Vector2i(fixture.target_hex[0], fixture.target_hex[1]))
	# Same exact facts, new stable session action ID; the recorded provider uses
	# the same binding, with explicit recorded provenance, in the application.
	reply.action_id = asked.request.action_id
	var before := game.state.duplicate(true)
	var accepted: Dictionary = game.apply_planning(reply)
	if not accepted.ok:
		_fail(case_id, str(accepted))
		return
	if game.state.actors != before.actors or game.state.items != before.items or game.state.state_version != 0:
		_fail(case_id, "Planning mutated numerical world state.")
		return
	var entry := {"case": case_id, "stage": "planning_validated", "needs_roll": reply.needs_roll, "gm_difficulty": reply.get("difficulty"), "narration": reply.narration, "context": reply.context, "numerical_state_unchanged": true, "full_resolution_supplied": false}
	var resolution_path := "res://tests/" + case_id + "_resolution_luna.json"
	if FileAccess.file_exists(resolution_path):
		var final_reply: Dictionary = relay.import_decision(resolution_path)
		if not final_reply.ok:
			_fail(case_id, str(final_reply))
			return
		if reply.needs_roll:
			var roll_value := int(final_reply.decision.get("recorded_player_d20", 9))
			game.roll_action(asked.request.action_id, roll_value)
		final_reply.decision.action_id = asked.request.action_id
		var committed: Dictionary = game.commit_decision(final_reply.decision)
		if not committed.ok:
			_fail(case_id, str(committed))
			return
		entry.stage = "resolution_committed"
		entry.full_resolution_supplied = true
		entry.gm_outcome = committed.event.outcome
		entry.patches = committed.event.patches
		entry.numerical_state_unchanged = game.state.actors == before.actors and game.state.items == before.items
	report.append(entry)

func _fail(case_id: String, reason: String) -> void:
	failures.append(case_id + ": " + reason)
	report.append({"case": case_id, "stage": "not_verified", "reason": reason})
