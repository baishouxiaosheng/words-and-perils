extends SceneTree
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://view/playable_build/world.gd")
const CoreWorld = preload("res://core/ai_gm_rebuilt/world.gd")
const Rule = preload("res://view/playable_build/rule.gd")
const Resolver = preload("res://view/playable_build/resolver.gd")
const Actions = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const Examples = preload("res://view/playable_build/effect_examples.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Movement = preload("res://view/playable_build/movement_resolver.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Conflict = preload("res://tests/persistent_world_effects/conflicting_resolver.gd")
var n := 0
var failures: Array[String] = []
var base: Dictionary = {}
var evidence: Dictionary = {}
func check(value: bool, label: String) -> void:
	n += 1
	if not value: failures.append(label); printerr("FAIL: " + label)
func make(initial: Dictionary = {}, conflict := false) -> RefCounted:
	var registry: Dictionary = {}
	for action in [Actions.new("manipulate_environment"), Actions.new("apply_condition"), Resolver.new("observe"), Resolver.new("rest"), Resolver.new("repair"), Movement.new()]: registry[action.resolver_id()] = action
	if conflict: registry["coast_manipulate_environment_v1"] = Conflict.new()
	return GMEngine.new(base if initial.is_empty() else initial, Rule.new(), registry, {"npc_secret_allowlist": [], "public_flag_ids": ["coast_observed", "keeper_trust", "lamp_restored"]}, 714)
func start(engine: RefCounted, kind: String, focus: Dictionary = {}) -> Dictionary:
	var started: Dictionary = engine.begin_intent(Examples.goal(kind, engine.state_copy(), focus), focus)
	check(started.ok, "begin " + kind)
	if not started.ok: return {}
	var example: Dictionary = Examples.assessment(started.request, kind)
	check(example.ok, "explicit offline example " + kind)
	return example.get("assessment", {})
func finish(engine: RefCounted, reply: Dictionary) -> Dictionary:
	var planned: Dictionary = engine.prepare_assessment(reply)
	check(planned.ok, "freeze " + str(reply.resolver_id) + ": " + str(planned))
	if not planned.ok: return {}
	check(engine.roll_once(reply.action_id).ok, "resolve once")
	check(engine.stage(reply.action_id).ok, "stage")
	var committed: Dictionary = engine.commit(reply.action_id, engine.action_copy(reply.action_id).stage_hash)
	check(committed.ok, "commit")
	return committed
func observe(engine: RefCounted) -> Dictionary:
	var begun: Dictionary = engine.begin_intent("等待并观察，推进一个经过评估的回合。")
	var r: Dictionary = begun.request
	return {"schema_version": "ai_gm_assessment/v1", "action_id": r.action_id, "state_version": r.state_version, "context_hash": r.context_hash, "narration": "离线评估：观察一回合。", "interpretation": "人工记录的观察评估，非在线模型。", "resolver_id": "coast_observe", "bindings": {"actor_id": "actor_player"}, "components": [{"id": "observe", "parameters": {"A": 2, "D": 1, "P": 0}, "disposition": "certain", "fact_ref_ids": ["actor"]}], "fact_refs": [{"id": "actor", "path": "/actors/actor_player", "expected": r.context.facts.actors.actor_player}], "provenance": {"provider": "offline integration assessment", "live": false, "kind": "model_reply"}}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	base = World.world()
	check(CoreWorld.validate(base).ok, "new game valid")
	check(base.items.item_poison_vial.quantity == 2 and base.items.item_feather_vial.quantity == 1, "new-game supplies explicit")
	var engine := make(); check(engine.ready().ok, "engine ready")
	var reply := start(engine, "poison"); var before := C.bytes(engine.state_copy())
	for field in ["duration", "magnitude"]:
		for value in [0, 4, 1.5, "1"]:
			var bad := reply.duplicate(true); bad.components[1].parameters[field] = value
			check(not engine.prepare_assessment(bad).ok and C.bytes(engine.state_copy()) == before, "invalid " + field + " atomic " + str(value))
	var bad := reply.duplicate(true); bad.bindings.target_actor_id = {"id": "actor_player"}
	check(not engine.prepare_assessment(bad).ok and C.bytes(engine.state_copy()) == before, "malformed target no mutation")
	bad = reply.duplicate(true); bad.state_version += 1
	check(not engine.prepare_assessment(bad).ok, "stale assessment rejected")
	bad = reply.duplicate(true); bad["patches"] = [{"type": "flag_set", "flag_id": "keeper_trust", "value": true}]
	check(not engine.prepare_assessment(bad).ok, "arbitrary patches rejected")
	bad = reply.duplicate(true); bad.fact_refs[0].path = "/actors/actor_keeper/secrets"
	check(not engine.prepare_assessment(bad).ok, "private fact reference rejected")
	check(engine.prepare_assessment(reply).ok, "valid compound condition frozen")
	check(engine.cancel_intent(reply.action_id).ok and C.bytes(engine.state_copy()) == before, "cancel typed prepared action no effects")
	reply = start(engine, "poison")
	check(engine.prepare_assessment(reply).ok, "reprepare after cancellation")
	var saved: Dictionary = engine.save_data(); var restored := make()
	check(restored.load_data(saved).ok and C.bytes(restored.state_copy()) == before, "ready load never applies poison")
	engine = restored
	check(engine.roll_once(reply.action_id).ok, "condition resolve")
	var rolls := C.bytes(engine.action_copy(reply.action_id)); engine.roll_once(reply.action_id)
	check(C.bytes(engine.action_copy(reply.action_id)) == rolls, "repeat resolve identical")
	check(engine.stage(reply.action_id).ok and C.bytes(engine.state_copy()) == before, "staging not publication")
	saved = engine.save_data(); restored = make()
	check(restored.load_data(saved).ok and C.bytes(restored.state_copy()) == before, "staged load no effect")
	engine = restored
	var token: String = engine.action_copy(reply.action_id).stage_hash
	check(engine.commit(reply.action_id, token).ok, "poison commit")
	var state: Dictionary = engine.state_copy()
	check(state.actors.actor_player.health.current == 12 and state.actors.actor_player.statuses.condition_poison.remaining_turns == 2, "new poison waits until next turn")
	check(state.items.item_poison_vial.quantity == 1 and state.actors.actor_player.stamina.current == 7, "fixed item and stamina cost")
	var committed_bytes := C.bytes(state)
	check(engine.commit(reply.action_id, token).already_committed and C.bytes(engine.state_copy()) == committed_bytes, "commit idempotency")
	check(not engine.commit(reply.action_id, "wrong-token").ok, "conflicting commit token rejected")
	restored = make(); check(restored.load_data(engine.save_data()).ok, "idle poisoned load")
	check(C.bytes(restored.state_copy()) == committed_bytes, "idle load never ticks")
	engine = restored
	var tick := observe(engine); finish(engine, tick)
	state = engine.state_copy()
	check(state.actors.actor_player.health.current == 11 and state.actors.actor_player.statuses.condition_poison.remaining_turns == 1, "one commit one poison tick")
	var tick_token: String = engine.save_data().receipts[tick.action_id].stage_hash
	restored = make(); check(restored.load_data(engine.save_data()).ok, "post tick load")
	check(restored.commit(tick.action_id, tick_token).already_committed and restored.state_copy().actors.actor_player.health.current == 11, "load replay does not duplicate tick")
	engine = restored; finish(engine, observe(engine))
	check(engine.state_copy().actors.actor_player.health.current == 10 and engine.state_copy().actors.actor_player.statuses.is_empty(), "second tick expires poison")
	finish(engine, observe(engine)); check(engine.state_copy().actors.actor_player.health.current == 10, "expired poison stays gone")
	evidence["poison"] = {"hp_after_apply": 12, "hp_after_tick_save_load_replay": 11, "hp_after_expiry": 10, "duration": 2, "live": false}
	_test_authored_capabilities()
	_test_failure_and_downed()
	_test_tree_and_flight()
	var report := {"checks": n, "passed": n-failures.size(), "failures": failures, "evidence": evidence, "scope": "typed effects offline integration; no live model, full combat or universal arbitrary action execution"}
	var file := FileAccess.open("res://tests/persistent_world_effects/report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ")); file.close()
	print("PERSISTENT WORLD EFFECTS ", n-failures.size(), "/", n)
	quit(0 if failures.is_empty() else 1)
func _test_authored_capabilities() -> void:
	var authored := base.duplicate(true)
	var source: Dictionary = authored.items.item_poison_vial.duplicate(true)
	source.id = "item_other_authored_source"; source.name = "另一种明确记载能力的补给"; source.quantity = 4; source.condition_source.units_per_use = 2
	authored.items[source.id] = source; authored.actors.actor_player.inventory.append(source.id)
	check(CoreWorld.validate(authored).ok, "capability schema accepts a new authored item identity")
	var engine := make(authored)
	var begun: Dictionary = engine.begin_intent("给自己使用另一份明确记载毒性能力的补给。")
	var fixture_request: Dictionary = begun.request.duplicate(true)
	fixture_request.context.goal = Examples.goal("poison")
	var made := Examples.assessment(fixture_request, "poison")
	var reply: Dictionary = made.assessment
	reply.bindings.source_item_id = source.id
	reply.fact_refs[1].path = "/items/" + source.id; reply.fact_refs[1].expected = begun.request.context.facts.items[source.id]
	reply.provenance = {"provider": "explicit offline authored capability assessment", "kind": "model_reply", "live": false}
	finish(engine, reply)
	check(engine.state_copy().items[source.id].quantity == 2 and engine.state_copy().actors.actor_player.statuses.has("condition_poison"), "new item capability applies authored consumption without ID/name switch")
	var invalid := authored.duplicate(true); invalid.items[source.id].condition_source.max_duration = 999
	check(not CoreWorld.validate(invalid).ok, "unbounded authored source rejected")
	invalid = authored.duplicate(true); invalid.items[source.id].condition_source.kind = "execute"
	check(not CoreWorld.validate(invalid).ok, "unregistered capability kind rejected")
	var renamed := authored.duplicate(true); renamed.items[source.id].erase("condition_source")
	check(Effects.validate_source(source.id, renamed.items[source.id]), "ordinary named item remains ordinary without capability")

func _test_failure_and_downed() -> void:
	var engine := make(); var reply := start(engine, "flight")
	reply.components[0].disposition = "impossible"
	finish(engine, reply)
	check(engine.state_copy().actors.actor_player.statuses.is_empty() and engine.state_copy().items.item_feather_vial.quantity == 0 and engine.state_copy().actors.actor_player.stamina.current == 7, "compound failure costs fixed resources without invented effect")
	var low := base.duplicate(true); low.actors.actor_player.health.current = 1
	engine = make(low); reply = start(engine, "poison"); reply.components[1].parameters.magnitude = 3; reply.components[1].parameters.duration = 1
	finish(engine, reply); finish(engine, observe(engine))
	check(engine.state_copy().actors.actor_player.health.current == 0, "poison damage floors at zero")
	var downed: Dictionary = engine.begin_intent(Examples.goal("flight"))
	check(not downed.ok and engine.state_copy().items.item_feather_vial.quantity == 1, "downed actor cannot begin any new action")
	engine = make(); reply = start(engine, "poison"); finish(engine, reply)
	reply = start(engine, "poison"); var before := C.bytes(engine.state_copy())
	check(not engine.prepare_assessment(reply).ok and before == C.bytes(engine.state_copy()), "same-kind reapply conflict atomic")
func _test_tree_and_flight() -> void:
	var chosen: Dictionary = {}; var nearby: Array = []
	for row in range(12000):
		var id := Catalog.tree_id(row)
		if id.is_empty(): continue
		var entity := Catalog.entity(id, base)
		if entity.is_empty() or base.hexes[Traversal.key(entity.hex)].ground_blocked: continue
		for direction in Traversal.DIRECTIONS:
			var from := [entity.hex[0]+direction[0], entity.hex[1]+direction[1]]
			if base.hexes.has(Traversal.key(from)) and not base.hexes[Traversal.key(from)].ground_blocked and Navigation.step(from, entity.hex).ok:
				chosen = entity; nearby = from; break
		if not chosen.is_empty(): break
	check(not chosen.is_empty(), "find real source tree with dry legal neighboring ground")
	if chosen.is_empty(): return
	# Explicit test positioning, not a shipped spawn or a claim that navigation occurred.
	var positioned := base.duplicate(true); positioned.actors.actor_player.hex = nearby
	var engine := make(positioned); var focus := Catalog.make_reference(chosen.id, positioned)
	var reply := start(engine, "fell", focus); var before := C.bytes(engine.state_copy())
	var bad := reply.duplicate(true); bad.bindings.target_entity_id = "tree:invented:0"
	check(not engine.prepare_assessment(bad).ok and C.bytes(engine.state_copy()) == before, "invented source entity rejected")
	bad = reply.duplicate(true); bad.bindings.operation = "execute_code"
	check(not engine.prepare_assessment(bad).ok, "unknown environment operation rejected")
	var conflicting := make(positioned, true); var conflicting_reply := start(conflicting, "fell", focus)
	check(not conflicting.prepare_assessment(conflicting_reply).ok and C.bytes(conflicting.state_copy()) == before, "conflicting duplicate effect rejects entire branch and cost")
	finish(engine, reply)
	var state: Dictionary = engine.state_copy(); var key := Traversal.key(chosen.hex)
	check(state.environment_entities[chosen.id].state.posture == "fallen" and state.hexes[key].ground_blocked, "fallen actual object persists owning groundblock")
	check(not Traversal.can_enter(state, state.actors.actor_player, chosen.hex), "walking rejects fallen-tree cell")
	check(not Navigation.plan_route(state, "actor_player", chosen.hex, 8).ok, "new route planner rejects fallen ground")
	var result: Dictionary = engine.authoritative_result(reply.action_id)
	check(result.public_effects[-1].type == "environment_fell" or _contains_effect(result.public_effects, "environment_fell"), "public result includes factual environment consequence")
	var restored := make(); check(restored.load_data(engine.save_data()).ok, "fallen entity save load")
	check(C.bytes(restored.state_copy()) == C.bytes(state), "fallen load is exact")
	engine = restored; finish(engine, start(engine, "flight")); state = engine.state_copy()
	check(Traversal.can_enter(state, state.actors.actor_player, chosen.hex), "flight capability bypasses only groundblock")
	check(Navigation.plan_route(state, "actor_player", chosen.hex, 5).ok, "dry route planner honors actual flight")
	var air: Dictionary = state.duplicate(true); air.hexes[key].air_blocked = true
	check(not Traversal.can_enter(air, air.actors.actor_player, chosen.hex), "flight cannot bypass air block")
	var all: Dictionary = state.duplicate(true); all.hexes[key].all_blocked = true
	check(not Traversal.can_enter(all, all.actors.actor_player, chosen.hex), "flight cannot bypass all block")
	var begun: Dictionary = engine.begin_intent("尝试飞越倒下的树，移动到它的归属格。", Catalog.make_reference(chosen.id, state))
	check(begun.ok and not engine.roll_once(begun.request.action_id).ok, "flight move still requires an assessment")
	var request: Dictionary = begun.request
	var movement_reply := {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "人工离线评估：借飞行跨过地面树干。", "interpretation": "有限飞行移动，目标仍是干燥落脚点。", "resolver_id": "coast_move_path_v2", "bindings": {"actor_id": "actor_player", "target_hex": chosen.hex}, "components": [{"id": "move", "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "certain", "fact_ref_ids": ["actor", "ground"]}], "fact_refs": [{"id": "actor", "path": "/actors/actor_player", "expected": request.context.facts.actors.actor_player}, {"id": "ground", "path": "/hexes/"+key, "expected": request.context.facts.hexes[key]}], "provenance": {"provider": "manual offline movement assessment", "live": false, "kind": "model_reply"}}
	finish(engine, movement_reply)
	check(engine.state_copy().actors.actor_player.hex == chosen.hex and engine.state_copy().actors.actor_player.statuses.condition_flight.remaining_turns == 2, "assessed flight movement commits and ticks once")
	restored = make(); check(restored.load_data(engine.save_data()).ok and C.bytes(restored.state_copy()) == C.bytes(engine.state_copy()), "post-fall historical focus and flight state reload exactly")
	evidence["environment"] = {"entity_id": chosen.id, "source": chosen.source, "owner_hex": chosen.hex, "test_actor_start": nearby, "positioning": "explicit test setup on actual source geography", "groundblock_persistent": true, "assessed_flight_bypass": true}
static func _contains_effect(effects: Array, kind: String) -> bool:
	for effect in effects:
		if effect.type == kind: return true
	return false
