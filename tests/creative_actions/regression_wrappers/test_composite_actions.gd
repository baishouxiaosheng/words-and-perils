extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Adapter = preload("res://view/playable_build/adapter.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const Composite = preload("res://core/ai_gm_rebuilt/composite_actions.gd")
const Rule = preload("res://tests/core_gameplay/test_release_rule.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
var failed: Array = []
var checks := 0
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failed.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func registry() -> Dictionary:
	var r := {Composite.ID: Composite.new()}
	for kind in Basic.KINDS:
		var family := Basic.new(kind); r[family.resolver_id()] = family
	return r
func make_engine(state: Dictionary, seed: int) -> RefCounted:
	var r := registry()
	return GMEngine.new(state, Rule.new(r), r, {"npc_secret_allowlist": [], "public_flag_ids": ["coast_observed", "keeper_trust", "lamp_restored"]}, seed)
func assessment(e: RefCounted, arrival: Array) -> Dictionary:
	var request: Dictionary = e.begin_intent("明确人工复合意图：先移动到指定格，再攻击指定劫掠者").request
	var facts: Dictionary = request.context.facts
	var paths: Array = ["/actors/actor_player", "/actors/actor_raider", "/items/item_coast_staff", "/hexes/%d,%d" % arrival]
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var id := "f" + str(refs.size()); refs.append({"id": id, "path": path, "expected": C.pointer(facts, path).value}); ids.append(id)
	var components: Array = []
	for id in ["move", "accuracy", "impact"]: components.append({"id": id, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "certain", "fact_ref_ids": ids.duplicate()})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "人工复合评估，尚无结果", "interpretation": "显式两项顺序操作，绝不忽略第三项", "resolver_id": Composite.ID, "bindings": {"actor_id": "actor_player", "target_hex": arrival.duplicate(), "target_actor_id": "actor_raider", "weapon_item_id": "item_coast_staff"}, "components": components, "fact_refs": refs, "provenance": {"provider": "manual_offline_assessment", "live": false, "kind": "model_reply"}}
func run() -> void:
	var setup := Adapter.new(2, true)
	for kind in ["pickup", "equip"]:
		setup.begin_intent(setup.sample_goal(kind)); var p: Dictionary = setup.prepare_fixture()
		if not p.ok: expect(false, "setup failed " + str(p)); quit(1); return
		setup.roll_once(); setup.stage(); setup.commit()
	var state: Dictionary = setup.state_copy(); var arrival: Array = []; var route: Dictionary = {}
	var enemy: Dictionary = state.actors.actor_raider
	for delta in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]:
		var point: Array = [enemy.hex[0] + delta[0], enemy.hex[1] + delta[1]]
		var plan := Navigation.plan_weighted_route(state, "actor_player", point, 7)
		if plan.ok: arrival = point; route = plan; break
	expect(not arrival.is_empty(), "authored encounter has reserved legal movement+attack route")
	if arrival.is_empty(): quit(1); return
	var seeds: Dictionary = {}
	for seed in range(1, 1000):
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		# Engine freezes and rolls components in sorted ID order.
		var accurate: bool = rng.randi_range(1,10000) <= 6500
		var forceful: bool = rng.randi_range(1,10000) <= 6500
		var moved: bool = rng.randi_range(1,10000) <= 6500
		var mask: int = (1 if moved else 0) + (2 if accurate else 0) + (4 if forceful else 0)
		if not seeds.has(mask): seeds[mask] = seed
		if seeds.size() == 8: break
	expect(seeds.size() == 8, "all eight deterministic genuine RNG outcomes available")
	for expected in seeds:
		var e := make_engine(state, seeds[expected]); var a := assessment(e, arrival)
		var before: String = C.bytes(e.state_copy()); var p: Dictionary = e.prepare_assessment(a)
		expect(p.ok, "composite plan freezes " + str(expected))
		if not p.ok: print(p); quit(1); return
		expect(C.bytes(e.state_copy()) == before and e.action_copy(a.action_id).branches.size() == 8, "no intermediate publication; eight full branches frozen")
		var restored := make_engine(state, 1)
		expect(restored.load_data(e.save_data()).ok, "composite frozen pending replay")
		var rolled: Dictionary = e.roll_once(a.action_id)
		var mask: int = (1 if rolled.outcomes.move else 0) + (2 if rolled.outcomes.accuracy else 0) + (4 if rolled.outcomes.impact else 0)
		expect(mask == expected and rolled.rolls.size() == 3, "three program dice once regardless of model certainty")
		var stage: Dictionary = e.stage(a.action_id); var result: Dictionary = e.commit(a.action_id, stage.stage_hash)
		expect(result.ok, "composite commit " + str(mask))
		var moved: bool = bool(mask & 1); var hit: bool = bool(mask & 2); var forceful: bool = bool(mask & 4)
		var expected_damage: int = (3 if forceful else 1) if moved and hit else 0
		expect(e.state_copy().actors.actor_player.hex == (arrival if moved else state.actors.actor_player.hex), "movement dependency exact")
		expect(e.state_copy().actors.actor_player.stamina.current == 8 - (int(route.cost) + 1 if moved else 0), "combined resources exact; no free attack")
		expect(e.state_copy().actors.actor_raider.health.current == 5 - expected_damage, "suppressed attack or bounded partial/full damage")
		expect(e.state_copy().turn == state.turn + 1, "two operations share one intentional-action hook tick")
		if not moved:
			expect(result.receipt.patches.is_empty() and e.state_copy().combat_turn.phase == "player", "move failure cannot emit attack or enemy phase")
		else: expect(e.state_copy().combat_turn.phase == "enemy", "arrival schedules hostile response even on attack miss")
	var short := state.duplicate(true); short.actors.actor_player.stamina.current = int(route.cost)
	var e := make_engine(short, 1); var a := assessment(e, arrival); var before: String = C.bytes(e.state_copy())
	expect(not e.prepare_assessment(a).ok and C.bytes(e.state_copy()) == before, "combined-cost shortfall rejects whole intent atomically")
	print("COMPOSITE ACTIONS ", checks - failed.size(), "/", checks, " ", JSON.stringify(failed))
	quit(0 if failed.is_empty() else 1)
