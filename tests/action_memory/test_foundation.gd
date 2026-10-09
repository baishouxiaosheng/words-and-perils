extends SceneTree
const EngineCore = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Memory = preload("res://core/campaign_memory/journal.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
var checks := 0
var failures: Array = []
const SAVE := "user://action_memory_restart.json"
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL " + label)
func make() -> RefCounted:
	return EngineCore.new(Story.world(), Rule.new(), {"fixture_gate": Resolver.new("gate"), "fixture_unknown_patch": Resolver.new("unknown_patch")}, {"npc_secret_allowlist": [], "public_flag_ids": ["gate_open"]}, 123)
func begin(engine: RefCounted, variant: String = "fixture_gate") -> Dictionary:
	return Story.assessment(engine.begin_intent("Explicit authored test intention").request, variant, ["certain", "certain"])
func _initialize() -> void:
	if "--reload" in OS.get_cmdline_user_args():
		var restored := make(); var loaded: Dictionary = restored.load_file(SAVE)
		expect(loaded.ok, "separate process loads memory save")
		expect(restored.memory_context().facts.size() == 1, "separate process recalls committed fact")
		finish(); return
	var engine := make(); var before: String = C.bytes(engine.save_data())
	var catalog: Dictionary = engine.capability_catalog()
	expect(catalog.entries.size() == 2 and catalog.readonly, "all registered resolvers catalogued")
	expect(catalog.entries[0].available and catalog.entries[0].reason_code == "ASSESSMENT_REQUIRED", "admission is explicitly not exact action legality")
	expect(not catalog.target_refs.is_empty() and C.bytes(engine.save_data()) == before, "typed target query leaves state/RNG unchanged")
	expect(engine.capability_catalog("missing").entries[0].reason_code == "UNKNOWN_ACTOR", "unavailable actor reason")
	var reply := begin(engine); before = C.bytes(engine.save_data())
	var pending: Dictionary = engine.action_copy(reply.action_id)
	var queried: Dictionary = engine.query_capability(reply)
	expect(queried.available and queried.readonly and not queried.roll_or_execution_performed, "valid exact dry-run")
	expect(C.bytes(engine.save_data()) == before, "dry-run preserves pending plan, memory, ledger and RNG")
	var bad: Dictionary = reply.duplicate(true); bad.fact_refs[0].expected = 999
	queried = engine.query_capability(bad)
	expect(not queried.available and queried.reason_code == "INVALID_FACT_REF", "invalid exact dry-run reason")
	expect(C.bytes(engine.save_data()) == before, "failed dry-run is read-only")
	expect(engine.capability_catalog().entries[0].reason_code == "ACTION_IN_PROGRESS", "pending admission blocks a new intent")
	# A legacy pending snapshot has no new field; context/RNG are not rewritten.
	var legacy: Dictionary = engine.save_data(); legacy.erase("campaign_memory")
	var old := make(); var loaded: Dictionary = old.load_data(legacy)
	expect(loaded.ok, "old pending save accepted without memory migration")
	expect(C.bytes(old.action_copy(reply.action_id)) == C.bytes(pending) and C.bytes(old.save_data().rng) == C.bytes(legacy.rng), "old pending hash and RNG remain exact")
	expect(old.model_request(reply.action_id).context_hash == reply.context_hash, "old model context identity preserved")
	var prepared: Dictionary = engine.prepare_assessment(reply)
	expect(prepared.ok and engine.memory_context().facts.is_empty(), "assessment cannot create memory fact")
	expect(engine.roll_once(reply.action_id).ok, "roll resolves in program")
	var legacy_rolled: Dictionary = engine.save_data(); legacy_rolled.erase("campaign_memory")
	old = make(); loaded = old.load_data(legacy_rolled)
	expect(loaded.ok and C.bytes(old.action_copy(reply.action_id)) == C.bytes(engine.action_copy(reply.action_id)) and C.bytes(old.save_data().rng) == C.bytes(engine.save_data().rng), "old rolled action preserves actual dice and RNG")
	var staged: Dictionary = engine.stage(reply.action_id)
	expect(staged.ok and engine.memory_context().facts.is_empty(), "staging cannot create memory fact")
	var legacy_staged: Dictionary = engine.save_data(); legacy_staged.erase("campaign_memory")
	old = make(); loaded = old.load_data(legacy_staged)
	expect(loaded.ok and C.bytes(old.action_copy(reply.action_id)) == C.bytes(engine.action_copy(reply.action_id)), "old staged action preserves exact commit token")
	before = C.bytes(engine.save_data())
	expect(not engine.commit(reply.action_id, "wrong-token").ok and C.bytes(engine.save_data()) == before, "failed commit cannot create memory or alter staged action")
	var result: Dictionary = engine.commit(reply.action_id, staged.stage_hash)
	expect(result.ok and engine.memory_context().facts.size() == 1, "one committed receipt creates one event")
	var memory: Dictionary = engine.save_data().campaign_memory
	var event: Dictionary = memory.events[0]
	expect(event.source.receipt_hash == result.receipt.receipt_hash and event.source.kind == "committed_receipt", "facts retain exact committed evidence")
	expect(not C.bytes(memory).contains("npc_listened") and not C.bytes(memory).contains("private_quest_answer") and not C.bytes(memory).contains("narration") and not C.bytes(memory).contains("low_tide"), "narration and private data never become memory facts")
	expect(engine.memory_context("actor_guard_a").facts.is_empty() and engine.memory_context("actor_guard_z").facts.is_empty(), "nearby non-witness NPC receives no omniscient memory")
	expect(engine.memory_context("actor_player", "scene_harbor", "gate_open").facts.size() == 1 and engine.memory_context("actor_player", "absent").facts.is_empty(), "location and task filters")
	var tiny: Dictionary = engine.memory_context("actor_player", "", "", 8, 1)
	expect(tiny.facts.is_empty() and tiny.truncated and tiny.used_record_bytes <= 1, "recall obeys record byte budget with explicit omission")
	before = C.bytes(engine.save_data())
	expect(engine.commit(reply.action_id, staged.stage_hash).already_committed and C.bytes(engine.save_data()) == before, "duplicate commit adds no fact or roll")
	var narrate: Dictionary = engine.narration_request(reply.action_id)
	var narrative := {"schema_version":"ai_gm_narration/v1", "action_id":reply.action_id, "state_version":narrate.state_version, "context_hash":narrate.context_hash, "narration":"A false display claim: every hidden secret was revealed."}
	expect(engine.validate_narration_reply(narrative).ok and C.bytes(engine.save_data()) == before, "accepted display narration still cannot create facts or NPC knowledge")
	var replay: Dictionary = Memory.record(memory, result.receipt, Story.world(), {"public_flag_ids": ["gate_open"]}, "fixture_gate")
	expect(replay.ok and replay.already_recorded and replay.memory == memory, "receipt replay is idempotent")
	var witnessed: Dictionary = Memory.record(Memory.empty(Story.world().world_id), result.receipt, Story.world(), {"public_flag_ids": ["gate_open"]}, "fixture_gate", ["actor_guard_a"])
	expect(witnessed.ok and Memory.recall(witnessed.memory, "actor_guard_a").facts.size() == 1 and Memory.recall(witnessed.memory, "actor_guard_z").facts.is_empty(), "explicit trusted witness gets only its witnessed event")
	var source: Dictionary = result.receipt.duplicate(true); source.narration = "The secret was revealed and everyone knows it"
	expect(not Memory.record(Memory.empty(Story.world().world_id), source, Story.world(), {"public_flag_ids": ["gate_open"]}, "fixture_gate").ok, "unverified source receipt is rejected")
	var belief: Dictionary = Memory.add_belief(memory, "actor_player", event.event_id, "I suspect the guard remembers me")
	expect(belief.ok and belief.memory.events == memory.events and belief.memory.beliefs[0].truth_status == "unverified_belief", "source-linked belief is separate from canonical facts")
	expect(not Memory.add_belief(memory, "actor_guard_z", event.event_id, "I saw everything").ok, "belief requires the owner's actual witness source")
	var public_copy: Dictionary = engine.memory_context(); public_copy.facts.clear()
	expect(engine.memory_context().facts.size() == 1, "public recall is a detached copy")
	var restored := make(); loaded = restored.load_data(JSON.parse_string(C.bytes(engine.save_data())))
	expect(loaded.ok and C.bytes(restored.save_data()) == C.bytes(engine.save_data()), "JSON save/load preserves memory and RNG exactly")
	var corrupt: Dictionary = engine.save_data(); corrupt.campaign_memory.events[0].effects.append({"type":"flag_set", "flag_id":"private_quest_answer", "value":"stolen"})
	before = C.bytes(restored.save_data())
	expect(not restored.load_data(corrupt).ok and C.bytes(restored.save_data()) == before, "invented/private memory effect rejects atomically")
	expect(engine.save_file(SAVE).ok, "restart fixture saved")
	var request: Dictionary = engine.begin_intent("Next explicit intention").request
	expect(request.memory_context.facts.size() == 1 and not request.context.has("memory_context"), "DecisionModel gets public read-only memory outside legacy frozen context")
	engine.cancel_intent(request.action_id)
	var fresh := make(); var invalid := begin(fresh, "fixture_unknown_patch")
	expect(not fresh.prepare_assessment(invalid).ok and fresh.memory_context().facts.is_empty(), "failed plan creates no memory")
	finish()
func finish() -> void:
	print("ACTION_MEMORY ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
