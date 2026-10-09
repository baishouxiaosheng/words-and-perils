extends SceneTree

const GameState = preload("res://core/game_state.gd")
const Relay = preload("res://core/json_relay_provider.gd")
var checks := 0
var failures: Array = []

func _initialize() -> void:
	_run_tests()
	if failures.is_empty():
		print("CORE TESTS PASSED: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + str(failure))
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _plan(request: Dictionary, needs_roll: bool = true) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "planning", "narration": "测试专用 GM 规划；生产路径不调用它。", "needs_roll": needs_roll, "difficulty": 13, "context": "由 GM 提供的难度与上下文"}

func _resolution(request: Dictionary, patches: Array) -> Dictionary:
	return {"schema_version": 1, "action_id": request.action_id, "state_version": request.state_version, "phase": "resolution", "narration": "测试专用的已确定结果。", "outcome": "test_success", "patches": patches, "provenance": {"provider": "test_fixture", "live": false}}

func _run_tests() -> void:
	var game := GameState.new()
	_check(game.state.hexes.size() == 61, "radius-4 board contains 61 cells")
	_check(game.state.actors.actor_player.hex == [-2, 1], "starting player coordinates")
	_check(game.state.hexes["0,0"].terrain == "bridge", "center bridge")
	_check(game.state.hexes["0,1"].terrain == "river", "central river")
	_check(game.state.items.item_mist_draught.has("description") and not game.state.items.item_mist_draught.has("effects"), "inventory is descriptive, no built-in effects")
	_check(not game.request("", Vector2i.ZERO).ok, "empty goals rejected")
	_check(not game.request("go", Vector2i(10, 10)).ok, "off-board targets rejected")
	var asked: Dictionary = game.request("测试移动", Vector2i(-1, 1))
	_check(asked.ok and asked.request.phase == "planning", "planning request created")
	var action_id: String = asked.request.action_id
	_check(asked.request.snapshot.state_version == 0, "exact state snapshot")
	_check(asked.request.preview.advisory_only, "preview does not decide rules")
	asked.request.snapshot.actors.actor_player.health.current = 0
	_check(game.state.actors.actor_player.health.current == 20, "snapshot is detached")
	var planning := _plan(asked.request)
	planning[&"provenance"] = {&"provider": &"test_fixture", "live": false}
	_check(game.validate_decision(planning).ok, "internal StringName metadata normalizes safely to JSON strings")
	var malformed_plan := planning.duplicate(true)
	malformed_plan["patches"] = 42
	_check(not game.validate_decision(malformed_plan).ok, "malformed planning patches rejected without runtime error")
	var accepted: Dictionary = game.apply_planning(planning)
	_check(accepted.ok and accepted.needs_roll, "GM planning accepted")
	_check(game.state.actors.actor_player.hex == [-2, 1], "planning does not change exact world state")
	_check(not game.apply_planning(planning).ok, "repeated planning rejected")
	_check(not game.roll_action(action_id, 0).ok, "invalid D20 rejected")
	var rolled: Dictionary = game.roll_action(action_id, 14)
	_check(rolled.ok and rolled.roll.value == 14, "player roll stored exactly")
	_check(rolled.request.context.player_roll.value == 14, "resolution context carries player D20")
	_check(not game.roll_action(action_id, 2).ok, "no reroll or double roll")
	var decision := _resolution(rolled.request, [{"op": "set", "path": "/actors/actor_player/hex", "value": [-1, 1]}, {"op": "set", "path": "/actors/actor_player/stamina/current", "value": 8}])
	var invalid := decision.duplicate(true)
	invalid.patches.append({"op": "set", "path": "/actors/actor_player/health/current", "value": -1})
	_check(not game.commit_decision(invalid).ok, "negative pool rejected atomically")
	_check(game.state.actors.actor_player.hex == [-2, 1] and game.state.state_version == 0, "invalid commit leaves entire world unchanged")
	invalid = decision.duplicate(true)
	invalid.patches = [{"op": "set", "path": "/actors/actor_player/id", "value": "replacement"}]
	_check(not game.commit_decision(invalid).ok, "stable IDs protected")
	invalid.patches = [{"op": "set", "path": "/state_version", "value": 100}]
	_check(not game.commit_decision(invalid).ok, "GM cannot patch bookkeeping")
	invalid.patches = [{"op": "set", "path": "/actors/actor_player/hex", "value": [8, 8]}]
	_check(not game.commit_decision(invalid).ok, "invalid coordinates protected")
	invalid.patches = [{"op": "set", "path": "/actors/actor_player/hex", "value": [4294967294, 1]}]
	_check(not game.commit_decision(invalid).ok, "coordinates cannot wrap through Vector2i integer conversion")
	invalid.patches = [{"op": "set", "path": "/actors/actor_player/inventory", "value": ["unknown_item"]}]
	_check(not game.commit_decision(invalid).ok, "inventory references protected")
	var committed: Dictionary = game.commit_decision(decision)
	_check(committed.ok and not committed.already_committed, "canonical patches committed")
	_check(game.state.actors.actor_player.hex == [-1, 1] and game.state.actors.actor_player.stamina.current == 8, "GM numerical patches applied exactly")
	_check(game.state.state_version == 1 and game.state.events.size() == 1, "one durable event and one version increment")
	_check(game.state.events[0].roll.value == 14, "exact roll in durable event")
	_check(game.commit_decision(decision).already_committed and game.state.events.size() == 1, "idempotent duplicate commit")
	invalid = decision.duplicate(true)
	invalid.narration = "modified decision"
	_check(not game.commit_decision(invalid).ok, "conflicting replay refused")
	var save_path := "user://core_test_state.json"
	_check(game.save_to_file(save_path).ok, "atomic save")
	var restored := GameState.new()
	_check(restored.load_from_file(save_path).ok, "load save")
	_check(restored.state == game.state, "state, event, IDs and numerical values roundtrip exactly")
	_check(restored.commit_decision(decision).already_committed, "idempotency survives persistence")
	var stale_a: Dictionary = restored.request("A", Vector2i.ZERO)
	var stale_b: Dictionary = restored.request("B", Vector2i.ZERO)
	var a_plan: Dictionary = restored.apply_planning(_plan(stale_a.request, false))
	var a_decision := _resolution(a_plan.request, [{"op": "set", "path": "/flags/test", "value": true}])
	_check(restored.commit_decision(a_decision).ok, "no-roll resolution supported")
	_check(not restored.apply_planning(_plan(stale_b.request)).ok, "stale concurrent request refused")
	var relay := Relay.new()
	_check(not relay.provider_info().live, "relay truthfully reports no live model")
	var fresh: Dictionary = restored.request("external context", Vector2i.ZERO)
	var request_path := "user://test_request.json"
	_check(relay.export_request(fresh.request, request_path).ok, "relay request export")
	var exported: Dictionary = relay.transport.read_json(request_path)
	_check(exported.ok and exported.data.action_id == fresh.request.action_id, "export retains stable ID")
	var reply_path := "user://test_reply.json"
	_check(relay.transport.write_json(reply_path, _plan(fresh.request)).ok, "test reply transport")
	var reply: Dictionary = relay.import_decision(reply_path)
	_check(reply.ok and restored.apply_planning(reply.decision).ok, "imported external GM reply applies")
	var pending_path := "user://test_pending.json"
	_check(restored.save_to_file(pending_path).ok, "save awaiting player roll")
	var pending := GameState.new()
	_check(pending.load_from_file(pending_path).ok, "restore pending action")
	_check(pending.resume_request(fresh.request.action_id).needs_roll, "restored pending action can resume")
	_check(pending.roll_action(fresh.request.action_id).ok, "real random player D20 supported")
	_check(pending.state.pending_actions[fresh.request.action_id].roll.value >= 1 and pending.state.pending_actions[fresh.request.action_id].roll.value <= 20, "random D20 is valid")
	_check(not relay.import_decision("user://missing.json").ok, "missing import handled")
	_check(not pending.load_from_file("user://missing.json").ok, "missing save handled")
	var corrupt_path := "user://test_corrupt.json"
	var corrupted := game.state.duplicate(true)
	corrupted.actors.actor_player.health.current = 999
	relay.transport.write_json(corrupt_path, corrupted)
	var before_load := pending.state.duplicate(true)
	_check(not pending.load_from_file(corrupt_path).ok and pending.state == before_load, "invalid load does not mutate live state")
	_check(pending.cancel_action(fresh.request.action_id).ok, "cancel pending action")
	_check(not pending.cancel_action(fresh.request.action_id).ok, "double cancel handled")
