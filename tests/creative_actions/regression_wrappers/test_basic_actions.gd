extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Actions = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const Rule = preload("res://view/playable_build/rule_release_v1.gd")
const TestRule = preload("res://tests/core_gameplay/test_release_rule.gd")
const Examples = preload("res://view/playable_build/basic_examples.gd")
const Legacy = preload("res://view/playable_build/rule.gd")
var failures: Array = []
var checks := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func _initialize() -> void:
	call_deferred("run")
func world() -> Dictionary:
	var state := Story.world()
	state.actors.actor_player.combat_profile = Basic.combatant(["harbor_watch"])
	state.actors.actor_player.hooks = ["status_tick"]
	state.actors.actor_player.equipment = {"weapon": "item_staff"}
	state.actors.actor_guard_a.combat_profile = Basic.combatant(["traveler"])
	state.actors.actor_guard_a.hooks = ["status_tick"]
	state.items.item_staff = {"id": "item_staff", "name": "测试短刃", "description": "明示能力", "quantity": 1, "owner_actor_id": "actor_player", "interaction_profile": Basic.interaction("weapon"), "weapon_profile": Basic.weapon(3, true)}
	state.actors.actor_player.inventory.append("item_staff")
	state.items.item_loot = {"id": "item_loot", "name": "测试遗留杖", "description": "明示能力", "quantity": 1, "owner_actor_id": "actor_guard_a", "interaction_profile": Basic.interaction("weapon"), "weapon_profile": Basic.weapon(2)}
	state.actors.actor_guard_a.inventory.append("item_loot"); state.actors.actor_guard_a.equipment = {"weapon": "item_loot"}
	return C.normalized(state)
func registry() -> Dictionary:
	var result: Dictionary = {}
	for kind in Actions.KINDS:
		var resolver := Actions.new(kind); result[resolver.resolver_id()] = resolver
	return result
func engine(state: Dictionary = {}, seed: int = 42, production: bool = false) -> RefCounted:
	var r := registry()
	return GMEngine.new(world() if state.is_empty() else C.normalized(state), Rule.new(r) if production else TestRule.new(r), r, {"npc_secret_allowlist": [], "public_flag_ids": []}, null if production else seed)
func reply(e: RefCounted, kind: String, bindings: Dictionary, disposition: String = "certain") -> Dictionary:
	var start: Dictionary = e.begin_intent("明确人工评估测试", {}, bindings.actor_id)
	if not start.ok: return start
	var req: Dictionary = start.request; var refs: Array = []; var ids: Array = []
	for collection in ["actors", "items"]:
		for id in req.context.facts[collection]:
			var ref_id: String = collection + "_" + id; refs.append({"id": ref_id, "path": "/" + collection + "/" + id, "expected": req.context.facts[collection][id]}); ids.append(ref_id)
	var components: Array = []
	for id in (["accuracy", "impact"] if kind == "basic_attack" else ["interact"]): components.append({"id": id, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": disposition, "fact_ref_ids": ids.duplicate()})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": req.action_id, "state_version": req.state_version, "context_hash": req.context_hash, "narration": "人工离线评估，尚无结果", "interpretation": "指定稳定目标与能力", "resolver_id": "coast_" + kind + "_v1", "bindings": bindings, "components": components, "fact_refs": refs, "provenance": {"provider": "manual_offline_assessment", "live": false, "kind": "model_reply"}}
func finish(e: RefCounted, assessment: Dictionary) -> Dictionary:
	var prepared: Dictionary = e.prepare_assessment(assessment)
	if not prepared.ok: return prepared
	var rolled: Dictionary = e.roll_once(assessment.action_id)
	if not rolled.ok: return rolled
	var staged: Dictionary = e.stage(assessment.action_id)
	if not staged.ok: return staged
	return e.commit(assessment.action_id, staged.stage_hash)
func attack_b() -> Dictionary: return {"actor_id": "actor_player", "target_actor_id": "actor_guard_a", "weapon_item_id": "item_staff"}
func run() -> void:
	expect(World.validate(world()).ok, "authored world validates")
	var prod := engine({}, 42, true); expect(prod.ready().ok, "production rule initializes")
	var assessment := reply(prod, "basic_attack", attack_b(), "certain")
	var before := C.bytes(prod.state_copy()); var prepared: Dictionary = prod.prepare_assessment(assessment)
	expect(prepared.ok, "production attack freezes")
	if not prepared.ok: print(prepared); quit(1); return
	expect(C.bytes(prod.state_copy()) == before, "assessment does not change state")
	for check in prepared.checks:
		expect(check.method == "random" and check.success_at_most == 6500, "certain cannot bypass trusted contested probability")
	var pending: Dictionary = prod.save_data(); var reloaded := engine({}, 42, true)
	expect(reloaded.load_data(pending).ok, "production pending reload rederives identical plan")
	var fake: Dictionary = pending.duplicate(true); fake.rule_id = "ai_gm_test_coast_actions/v1"
	expect(not reloaded.load_data(fake).ok, "different historical rule not reinterpreted")
	var seen: Dictionary = {}; var full_hit_seed := 0
	for seed in range(1, 80):
		var e := engine({}, seed); var a := reply(e, "basic_attack", attack_b(), "impossible")
		var p: Dictionary = e.prepare_assessment(a)
		if not p.ok: failures.append("prepare " + str(p)); break
		expect(p.checks[0].method == "random", "impossible advisory cannot force failure")
		var roll: Dictionary = e.roll_once(a.action_id)
		var mask: int = (1 if roll.outcomes.accuracy else 0) + (2 if roll.outcomes.impact else 0)
		if seen.has(mask): continue
		seen[mask] = true
		if mask == 3: full_hit_seed = seed
		var state_before: Dictionary = e.state_copy(); var stage: Dictionary = e.stage(a.action_id)
		expect(stage.ok, "each compound branch stages")
		var result: Dictionary = e.commit(a.action_id, stage.stage_hash)
		expect(result.ok, "each compound branch commits")
		var damage: int = 0 if mask in [0, 2] else (1 if mask == 1 else 3)
		expect(e.state_copy().actors.actor_guard_a.health.current == 12 - damage, "miss/graze/full bounded damage " + str(mask))
		expect(e.state_copy().actors.actor_player.stamina.current == 7, "fixed cost on every attack branch")
		expect(e.state_copy().actors.actor_guard_a.statuses.has("weapon_poison") == (mask == 3), "optional full-hit condition only")
		var events := Actions.committed_events(result.receipt, state_before)
		expect(not events.is_empty() and events.back().target_actor_id == "actor_guard_a", "committed event includes actual target including miss")
		var saved: Dictionary = e.save_data(); var restored := engine()
		expect(restored.load_data(saved).ok and C.bytes(restored.state_copy()) == C.bytes(e.state_copy()), "committed state save/load exact")
		var duplicate: Dictionary = e.commit(a.action_id, stage.stage_hash)
		expect(duplicate.ok and duplicate.already_committed and C.bytes(e.save_data()) == C.bytes(saved), "duplicate commit atomic")
		if seen.size() == 4: break
	expect(seen.size() == 4, "all four meaningful compound outcomes exercised")
	for invalid in ["range", "friendly", "stamina", "weapon", "downed_target", "line"]:
		var state := world()
		match invalid:
			"range": state.actors.actor_guard_a.hex = [2, 0]
			"friendly": state.actors.actor_guard_a.faction = "traveler"
			"stamina": state.actors.actor_player.stamina.current = 0
			"weapon": state.actors.actor_player.equipment = {}
			"downed_target": state.actors.actor_guard_a.health.current = 0
			"line": state.hexes["0,0"].all_blocked = true
		# Friendly target now cannot name its own faction as hostile.
		if invalid == "friendly": state.actors.actor_guard_a.combat_profile = Basic.combatant([])
		var e := engine(state); var a := reply(e, "basic_attack", attack_b()); var bytes := C.bytes(e.state_copy())
		expect(not e.prepare_assessment(a).ok and C.bytes(e.state_copy()) == bytes, "denied " + invalid + " is atomic")
	for malformed_kind in ["out_of_bounds", "extra_parameter", "stale", "missing_target_fact"]:
		var e := engine(); var bad := reply(e, "basic_attack", attack_b()); var bytes := C.bytes(e.state_copy())
		match malformed_kind:
			"out_of_bounds": bad.components[0].parameters.A = 5
			"extra_parameter": bad.components[0].parameters["damage"] = 999
			"stale": bad.state_version += 1
			"missing_target_fact":
				for component in bad.components: component.fact_ref_ids.erase("actors_actor_guard_a")
		expect(not e.prepare_assessment(bad).ok and C.bytes(e.state_copy()) == bytes, "invalid numeric/reference assessment atomic " + malformed_kind)
	var down := world(); down.actors.actor_player.health.current = 0
	expect(not engine(down).begin_intent("即使观察也不可发起行动").ok, "downed actor global action gate")
	var item_engine := engine(); var a := reply(item_engine, "drop_item", {"actor_id": "actor_player", "item_id": "item_staff"}, "impossible")
	var p: Dictionary = item_engine.prepare_assessment(a)
	expect(p.ok and p.checks[0].method == "direct_success", "safe direct ignores impossible advisory")
	item_engine.roll_once(a.action_id); var st: Dictionary = item_engine.stage(a.action_id); var dropped: Dictionary = item_engine.commit(a.action_id, st.stage_hash)
	expect(dropped.ok and not item_engine.state_copy().actors.actor_player.equipment.has("weapon") and not "item_staff" in item_engine.state_copy().actors.actor_player.inventory, "drop clears custody+equipment atomically")
	a = reply(item_engine, "drop_item", {"actor_id": "actor_player", "item_id": "item_staff"})
	expect(not item_engine.prepare_assessment(a).ok, "duplicate drop denied")
	item_engine.cancel_intent(a.action_id)
	a = reply(item_engine, "pickup_item", {"actor_id": "actor_player", "item_id": "item_staff"}); expect(finish(item_engine, a).ok, "pickup ground stack")
	a = reply(item_engine, "equip_item", {"actor_id": "actor_player", "item_id": "item_staff"}); expect(finish(item_engine, a).ok, "equip picked-up item")
	var loot := world(); loot.actors.actor_guard_a.health.current = 0
	var le := engine(loot); a = reply(le, "pickup_item", {"actor_id": "actor_player", "item_id": "item_loot"}); expect(finish(le, a).ok, "downed hostile loot transfer")
	expect(le.state_copy().items.item_loot.owner_actor_id == "actor_player" and not "item_loot" in le.state_copy().actors.actor_guard_a.inventory and le.state_copy().actors.actor_guard_a.equipment.is_empty(), "loot no duplicated owner/equipment")
	a = reply(le, "equip_item", {"actor_id": "actor_player", "item_id": "item_loot"}); expect(finish(le, a).ok, "equip looted weapon")
	var enemy := world(); var ne := engine(enemy); a = reply(ne, "basic_attack", {"actor_id": "actor_guard_a", "target_actor_id": "actor_player", "weapon_item_id": "item_loot"})
	expect(finish(ne, a).ok, "NPC attack uses same assessment/calculator/dice/commit contract")
	for style in ["ranged", "magic"]:
		var state := world(); state.items.item_ammo = {"id": "item_ammo", "name": "明示弹药晶能", "description": "不可免费施放", "quantity": 2, "owner_actor_id": "actor_player", "interaction_profile": Basic.interaction()}; state.actors.actor_player.inventory.append("item_ammo")
		state.items.item_staff.weapon_profile = Basic.weapon(3, false, style, "item_ammo"); state.actors.actor_guard_a.hex = [1, 0]
		var e := engine(state); a = reply(e, "basic_attack", attack_b()); var result := finish(e, a)
		expect(result.ok and e.state_copy().items.item_ammo.quantity == 1, style + " pays authored resource on every outcome")
		state.items.item_ammo.quantity = 0; e = engine(state); a = reply(e, "basic_attack", attack_b())
		expect(not e.prepare_assessment(a).ok, style + " insufficient resource denied")
	var phased := world(); phased["combat_turn"] = {"schema_version": "coast_encounter_turn/v1", "phase": "player", "enemy_actor_id": "", "round": 0}
	var pe := engine(phased, 7); a = reply(pe, "basic_attack", attack_b()); var player_result := finish(pe, a)
	expect(player_result.ok and pe.state_copy().combat_turn.phase == "enemy", "living engaged hostile owns next authoritative phase")
	var enemy_idle: Dictionary = pe.save_data(); var pr := engine(phased)
	expect(pr.load_data(enemy_idle).ok and pr.state_copy().combat_turn.phase == "enemy", "save/load cannot skip idle enemy phase")
	expect(not pe.begin_intent("player skips enemy").ok, "player cannot skip enemy phase")
	var before_phase := C.bytes(pe.save_data()); var repeated: Dictionary = pe.commit(a.action_id, player_result.receipt.stage_hash)
	expect(repeated.ok and repeated.already_committed and C.bytes(pe.save_data()) == before_phase, "double submit cannot advance phase twice")
	a = reply(pe, "drop_item", {"actor_id": "actor_guard_a", "item_id": "item_loot"})
	expect(not pe.prepare_assessment(a).ok, "enemy cannot replace required bounded response with item action")
	pe.cancel_intent(a.action_id)
	expect(pe.state_copy().combat_turn.phase == "enemy", "canceling enemy draft cannot skip phase")
	a = reply(pe, "basic_attack", {"actor_id": "actor_guard_a", "target_actor_id": "actor_player", "weapon_item_id": "item_loot"})
	expect(pe.prepare_assessment(a).ok, "NPC assessment freezes under its phase")
	var npc_pending: Dictionary = pe.save_data(); pr = engine(phased)
	expect(pr.load_data(npc_pending).ok, "NPC pending plan roundtrips exact")
	pe.roll_once(a.action_id); var npc_stage: Dictionary = pe.stage(a.action_id)
	expect(pe.commit(a.action_id, npc_stage.stage_hash).ok and pe.state_copy().combat_turn.phase == "player", "NPC result restores player phase")
	var cannot := phased.duplicate(true); cannot.actors.actor_guard_a.stamina.current = 0
	pe = engine(cannot); a = reply(pe, "basic_attack", attack_b())
	expect(finish(pe, a).ok and pe.state_copy().combat_turn.phase == "player", "incapable enemy scheduler skips without fabricated attack")
	var lethal := phased.duplicate(true); lethal.actors.actor_guard_a.health.current = 1
	for seed in range(1, 20):
		pe = engine(lethal, seed); a = reply(pe, "basic_attack", attack_b()); var outcome := finish(pe, a)
		if outcome.ok and pe.state_copy().actors.actor_guard_a.health.current == 0:
			expect(pe.state_copy().combat_turn.phase == "player", "downed enemy never receives action phase")
			break
	var conditioned := phased.duplicate(true)
	conditioned.items["item_test_poison"] = {"id": "item_test_poison", "name": "毒源", "description": "明示毒源", "quantity": 1, "owner_actor_id": "actor_player", "condition_source": preload("res://core/ai_gm_rebuilt/generic_effects.gd").source_profile("poison")}
	conditioned.actors.actor_player.inventory.append("item_test_poison")
	var condition_registry := registry(); var condition_family := preload("res://core/ai_gm_rebuilt/generic_actions.gd").new("apply_condition")
	condition_registry[condition_family.resolver_id()] = condition_family
	var ce := GMEngine.new(C.normalized(conditioned), TestRule.new(condition_registry), condition_registry, {"npc_secret_allowlist": [], "public_flag_ids": []}, 7)
	a = reply(ce, "apply_condition", {"actor_id": "actor_player", "target_actor_id": "actor_guard_a", "source_item_id": "item_test_poison"})
	a.components[0].id = "delivery"; var effect_component: Dictionary = a.components[0].duplicate(true); effect_component.id = "effect"; effect_component.parameters["duration"] = 2; effect_component.parameters["magnitude"] = 1; a.components.append(effect_component)
	expect(finish(ce, a).ok and ce.state_copy().combat_turn.phase == "enemy", "hostile poison attempt cannot bypass required enemy response")
	var journey := phased.duplicate(true); journey.actors.actor_guard_a.health.current = 5
	var je := engine(journey, full_hit_seed)
	a = reply(je, "basic_attack", attack_b()); expect(finish(je, a).ok and je.state_copy().combat_turn.phase == "enemy", "continuous journey player hit engages enemy")
	a = reply(je, "basic_attack", {"actor_id": "actor_guard_a", "target_actor_id": "actor_player", "weapon_item_id": "item_loot"}); expect(finish(je, a).ok and je.state_copy().combat_turn.phase == "player", "continuous journey assessed enemy response")
	a = reply(je, "basic_attack", attack_b()); expect(finish(je, a).ok and je.state_copy().actors.actor_guard_a.health.current == 0 and je.state_copy().combat_turn.phase == "player", "continuous journey hit or existing poison downs hostile")
	a = reply(je, "pickup_item", {"actor_id": "actor_player", "item_id": "item_loot"}); expect(finish(je, a).ok, "continuous journey loots actual defeated hostile")
	a = reply(je, "equip_item", {"actor_id": "actor_player", "item_id": "item_loot"}); expect(finish(je, a).ok and je.state_copy().actors.actor_player.equipment.weapon == "item_loot", "continuous journey equips actual loot")
	var journey_restored := engine(journey)
	expect(journey_restored.load_data(je.save_data()).ok and C.bytes(journey_restored.state_copy()) == C.bytes(je.state_copy()), "continuous attack NPCresponse downed loot equip save/load exact")
	var malformed := world(); malformed.items.item_staff.weapon_profile.damage = 100
	expect(not World.validate(malformed).ok, "authored damage bound rejects malformed capability")
	var mutable := world(); var changed := mutable.duplicate(true); changed.items.item_staff.weapon_profile.damage = 4
	expect(not World.stable(mutable, changed), "weapon capability immutable across transaction")
	var public: Dictionary = prod.model_request(assessment.action_id).context.facts
	expect(not C.bytes(public).contains("low_tide"), "attack assessment public facts exclude hidden secrets")
	var inspect_before := C.bytes(prod.save_data()); var inspected := Actions.inspect_item(public, "item_staff")
	expect(inspected.ok and inspected.readonly and C.bytes(prod.save_data()) == inspect_before, "item inspection readonly no turn mutation")
	print("BASIC ACTIONS ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
