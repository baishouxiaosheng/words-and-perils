extends SceneTree
const Transport = preload("res://view/tabletop_interaction/local_intent_transport.gd")
const Gate = preload("res://view/tabletop_interaction/public_snapshot_gate.gd")
const Stub = preload("res://view/tabletop_interaction/intent_transport.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label); printerr("FAIL: ", label)

func command(state: Dictionary) -> Dictionary:
	return {"schema": "tabletop_intent/v1", "session_id": "local_fixture_1", "request_id": "request_1", "sequence": 1,
		"world_id": state.world_id, "expected_state_version": state.state_version, "ownership_version": 1,
		"actor_id": "actor_player", "goal": "看看眼前的门", "attention": {}}

func snapshot() -> Dictionary:
	return {"schema": "tabletop_public_snapshot/v1", "session_id": "local_fixture_1", "audience_id": "player_1", "world_id": "world_fixture",
		"sequence": 5, "state_version": 3, "entities": [{"id": "actor_player", "kind": "actor", "scene_id": "scene_coast", "hex": [0, 0], "label": "旅人"}]}

func _initialize() -> void:
	var engine := GMEngine.new(Story.world())
	check(engine.ready().ok, "Actual mandatory-assessment engine accepts the fixture")
	var before: Dictionary = engine.state_copy()
	var before_rng: Dictionary = engine.save_data().rng
	var transport := Transport.new(engine, "local_fixture_1", "player_1", ["actor_player"])
	var request := command(before)
	check(not Stub.new().submit_intent(request).ok, "Unconfigured transport fails closed")
	for mutation in ["position", "transform", "effects", "assessment", "commit", "peer_id"]:
		var invalid := request.duplicate(true); invalid[mutation] = {}
		check(not transport.submit_intent(invalid).ok, "Client cannot submit " + mutation)
	for row in [["goal", " "], ["actor_id", "actor_keeper"], ["session_id", "other"], ["world_id", "other"], ["ownership_version", 2], ["expected_state_version", -1], ["sequence", 2], ["sequence", 1.5]]:
		var invalid := request.duplicate(true); invalid[row[0]] = row[1]
		check(not transport.submit_intent(invalid).ok, "Reject invalid " + str(row[0]) + " without admission")
	var ack: Dictionary = transport.submit_intent(request)
	check(ack.get("ok", false) and ack.get("phase") == "awaiting_assessment", "Explicit intent only opens an assessment request")
	check(engine.state_copy() == before and engine.save_data().rng == before_rng, "Admission changes neither world facts nor RNG")
	check(not ack.has("request") and not ack.has("state") and not ack.has("rng"), "Client acknowledgment does not contain host/model internals")
	var action_id := str(ack.get("action_id", ""))
	check(engine.action_copy(action_id).get("status") == "awaiting_assessment", "Core remains authoritative after local admission")
	var repeated: Dictionary = transport.submit_intent(request)
	check(repeated.get("duplicate_request", false) and repeated.get("action_id") == action_id, "Exact retry returns the same action ID")
	var altered := request.duplicate(true); altered.goal = "改成攻击"
	check(transport.submit_intent(altered).get("code") == "REQUEST_ID_CONFLICT", "Changed text cannot reuse the request ID")
	request.attention["caller_mutation"] = true
	check(engine.action_copy(action_id).get("focus", {}).is_empty(), "Caller-owned attention cannot mutate admitted action")
	check(not engine.roll_once(action_id).ok and not engine.stage(action_id).ok and not engine.commit(action_id, "forged").ok, "Transport admission never skips assessment or grants commit")
	engine.cancel_intent(action_id)
	var next := command(before); next.request_id = "request_2"; next.sequence = 2
	check(transport.submit_intent(next).get("ok", false), "Next explicit intent works after host cancellation")
	check(engine.state_copy() == before and engine.save_data().rng == before_rng, "Rejected commands, retry and cancellation leave all facts/RNG exact")
	var gate := Gate.new("host", "local_fixture_1", "player_1", "world_fixture")
	var display := snapshot()
	check(not gate.accept_snapshot("client", display).ok, "Only transport-verified authority can publish display snapshots")
	for row in [["world_id", "other"], ["audience_id", "other"], ["session_id", "old"], ["sequence", -1]]:
		var invalid := display.duplicate(true); invalid[row[0]] = row[1]
		check(not gate.accept_snapshot("host", invalid).ok, "Snapshot scope/version rejects " + str(row[0]))
	for secret in ["secrets", "rng", "inventory", "receipts", "pending", "transform"]:
		var invalid := display.duplicate(true); invalid.entities[0][secret] = {"private": true}
		check(not gate.accept_snapshot("host", invalid).ok, "Public display rejects unsupported/private field " + secret)
	var admitted: Dictionary = gate.accept_snapshot("host", display)
	check(admitted.ok and admitted.render, "Fresh complete public snapshot is admitted for rendering only")
	var duplicate: Dictionary = gate.accept_snapshot("host", display)
	check(duplicate.ok and not duplicate.render, "Duplicate snapshot cannot retrigger presentation effects")
	display.entities[0].label = "caller edit"
	check(admitted.snapshot.entities[0].label == "旅人", "Accepted snapshot is detached from sender memory")
	check(gate.accept_snapshot("host", display).get("code") == "SNAPSHOT_SEQUENCE_CONFLICT", "Same sequence with changed data is rejected")
	var stale := snapshot(); stale.sequence = 4
	check(gate.accept_snapshot("host", stale).get("code") == "SNAPSHOT_STALE", "Late packet cannot rewind presentation")
	stale.sequence = 6; stale.state_version = 2
	check(gate.accept_snapshot("host", stale).get("code") == "SNAPSHOT_STALE", "New sequence cannot hide an older authoritative version")
	var newer := snapshot(); newer.sequence = 8; newer.state_version = 4
	check(gate.accept_snapshot("host", newer).ok, "Complete snapshot may bridge a lost packet without delta replay")
	check(engine.state_copy() == before, "Rendering snapshot admission cannot mutate the game engine")
	print("TABLETOP TRANSPORT: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
