extends SceneTree
const Adapter = preload("res://view/ai_gm_playtest/adapter.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var count := 0
var failed: Array[String] = []
func check(value: bool, text: String) -> void:
	count += 1
	if not value: failed.append(text); printerr("FAIL: " + text)
func manual(adapter: RefCounted, resolver := "fixture_gate", direct := false) -> Dictionary:
	var reply := Story.assessment(adapter.request(), resolver, ["certain", "impossible"] if direct else ["possible", "possible"])
	reply.provenance = {"provider": "human_review", "live": false, "kind": "model_reply"}
	return reply
func restore(adapter: RefCounted, path: String) -> RefCounted:
	check(adapter.save_file(path).ok, "separate engine file saves")
	var loaded := Adapter.new(55)
	check(loaded.load_file(path).ok, "trusted rule/resolvers/policy reload")
	check(C.bytes(adapter.engine.save_data()) == C.bytes(loaded.engine.save_data()), "exact transaction/RNG JSON lineage preserved")
	check(adapter.active_action == loaded.active_action, "adapter restores pending identity")
	return loaded
func _initialize() -> void:
	var path := "user://adapter_test_save.json"
	var adapter := Adapter.new(123)
	check(adapter.engine.ready().ok and adapter.state_copy().hexes.size() == 19, "test mode uses valid 19-cell story")
	check(adapter.engine.rule_id() == "ai_gm_test_rule_a/v1", "test rule explicit, not production balance")
	check(Adapter.SAVE_PATH != "user://savegame.json", "v9 save cannot be overwritten by test mode")
	var before: Dictionary = adapter.engine.save_data()
	var focus := {"world_id": "test_harbor_story", "kind": "actor", "id": "actor_guard_z"}
	check(adapter.attention(focus).ok and adapter.engine.save_data() == before, "attention read-only")
	check(not adapter.begin_intent(" ", focus).ok and adapter.engine.save_data() == before, "empty text never becomes focus action")
	check(adapter.begin_intent("任意自由输入", focus).ok, "all deliberate text creates assessment stage")
	check(not adapter.fixture_available() and not adapter.prepare_fixture().ok, "no fixture answer for arbitrary input")
	check(not adapter.roll_once().ok and not adapter.stage().ok and not adapter.commit().ok, "assessment cannot be skipped")
	var id := adapter.active_action
	check(adapter.cancel().ok and adapter.engine.save_data().rng == before.rng, "pre-assessment cancel no RNG/factual change")
	check(adapter.begin_intent(Adapter.FIXTURE_GOAL, focus).ok and adapter.active_action != id, "cancelled IDs never reused")
	check(adapter.request().context.goal == Adapter.FIXTURE_GOAL and adapter.request().context.attention_focus.id == "actor_guard_z", "explicit芦灯text retains priority over桐岸focus")
	check(adapter.fixture_available(), "signed fixture matches exact initial state and exact text")
	var export_before := adapter.request()
	var bytes := C.bytes(export_before)
	for secret in ["low_tide", "hidden_motive", "private_notes", "private_quest_answer", '"seed"', '"rng"', '"receipts"', '"attempt_ledger"', '"rng_before"']:
		check(not bytes.contains(secret), "model projection excludes " + secret)
	check(adapter.export_request("user://adapter_test_request.json").ok, "assessment public JSON exports")
	adapter = restore(adapter, path)
	check(adapter.fixture_available() and adapter.prepare_fixture().ok, "exact authored fixture usable after awaiting save")
	check(adapter.phase() == "ready_roll" and adapter.can_cancel(), "prepared action cancellable before roll")
	check(adapter.action_copy().assessment.provenance.provider == Adapter.FIXTURE_AUTHOR and not adapter.action_copy().assessment.provenance.live, "authored fixture clearly signed offline")
	var frozen: Dictionary = adapter.engine.save_data()
	check(not adapter.prepare_fixture().ok and adapter.engine.save_data() == frozen, "repeat prepare does not refreeze")
	adapter = restore(adapter, path)
	var rolled := adapter.roll_once()
	check(rolled.ok and rolled.rolls.size() == 2 and adapter.phase() == "rolled", "program RNG resolves once per random component")
	check(not adapter.can_cancel() and not adapter.cancel().ok, "postroll cancellation refused")
	check(adapter.roll_once().rolls == rolled.rolls, "repeat roll returns locked vector")
	adapter = restore(adapter, path)
	check(adapter.roll_once().rolls == rolled.rolls, "reload rolled action cannot reroll")
	before = adapter.state_copy()
	check(adapter.stage().ok and adapter.phase() == "staged" and adapter.state_copy() == before, "staging previews without mutation")
	check(adapter.authority_text().contains("暂存预览，未提交"), "provisional results labelled")
	check(adapter.request().phase == "narration" and adapter.request().context.provisional_until_commit, "public narration request only after staging")
	var request := adapter.request()
	var bad := {"schema_version": "ai_gm_narration/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "我声称城门开放，但这不是数值事实。", "patches": []}
	frozen = adapter.engine.save_data()
	check(not adapter.import_reply(bad).ok and adapter.engine.save_data() == frozen, "narration patch extension refused unchanged")
	bad.erase("patches")
	check(adapter.import_reply(bad).ok and adapter.engine.save_data() == frozen, "contradictory narration remains display text")
	adapter = restore(adapter, path)
	check(adapter.commit().ok and adapter.state_copy().state_version == 1 and adapter.state_copy().turn == 1, "numeric commit succeeds without narration")
	check(adapter.state_copy().items.item_wine.quantity == 2 and adapter.state_copy().actors.actor_player.stamina.current == 7, "authoritative paid material cost committed")
	check(adapter.phase() == "idle" and adapter.active_action.is_empty() and not adapter.last_action.is_empty(), "commit permits next intent")
	check(adapter.authority_text().contains("已提交") and not adapter.request().context.provisional_until_commit, "committed authority separate from optional prose")
	check(not adapter.import_reply(bad).ok, "precommit narration hash stale after commit")
	adapter = restore(adapter, path)
	check(not adapter.last_action.is_empty() and adapter.authoritative_result().rolls == rolled.rolls, "committed save restores actual public dice")
	var altered: Dictionary = adapter.engine.save_data(); altered.policy.npc_secret_allowlist = ["/actors/actor_guard_a/secrets/gate_password"]
	frozen = adapter.engine.save_data()
	check(not adapter.engine.load_data(altered).ok and adapter.engine.save_data() == frozen, "save cannot expand trusted disclosure")
	check(adapter.begin_intent(Adapter.FIXTURE_GOAL).ok and not adapter.fixture_available() and not adapter.prepare_fixture().ok, "changed state cannot reuse initial fixture")
	check(adapter.import_reply(manual(adapter)).ok, "changed-state intent supports explicit offline manual assessment")
	check(adapter.action_copy().assessment.provenance.provider == "manual_offline_assessment", "file metadata cannot claim runtime provider")
	check(adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok, "manual assessment operates full loop")
	adapter = Adapter.new(321)
	adapter.begin_intent("手工评估允许的直接部分结果")
	var reply := manual(adapter, "fixture_gate", true)
	var live := reply.duplicate(true); live.provenance.live = true
	before = adapter.engine.save_data()
	check(not adapter.import_reply(live).ok and adapter.engine.save_data() == before, "fake live claim rejected")
	live = reply.duplicate(true); live.provenance.kind = "fixture"
	check(not adapter.import_reply(live).ok and adapter.engine.save_data() == before, "arbitrary JSON cannot launder authored fixture")
	check(not adapter.import_reply({"schema_version": 1, "phase": "resolution"}).ok, "v9 protocol refused by new mode")
	check(adapter.import_reply(reply).ok, "direct partial assessment accepted")
	check(adapter.roll_once().rolls.is_empty(), "direct result manufactures no dice")
	check(not adapter.cancel().ok and adapter.stage().ok and adapter.commit().ok, "direct result also locks before stage")
	check(not adapter.state_copy().flags.gate_open and adapter.state_copy().flags.npc_listened, "fixed partial branch only changes chosen facts")
	print("AI-GM PLAYTEST ADAPTER: %d checks, %d failures" % [count, failed.size()])
	quit(0 if failed.is_empty() else 1)
