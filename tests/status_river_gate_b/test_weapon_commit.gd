extends "res://tests/status_river_gate_b/harness.gd"
## Standalone supplemental weapon-commit regression; AUTHOR HAS NOT RUN IT.
## Run only in a separately admitted serial full-resource slot after the current
## frozen batch. No changes to that batch, game, overlay or canonical are needed.
## Entry: --script res://tests/status_river_gate_b/test_weapon_commit.gd
## Use the same isolated gate_b_tests user-data profile and original resource guard.
## Real pinned1801 Coast data/navigation; turn0 author fixtures explicitly equip
## the existing staff, give it the already supported poison-on-full-hit recipe,
## and for Basic only place the player at a navigation-verified adjacent tile.
## Existing-poison variants are labelled authored initial conditions. These are
## NOT claims about default source-world equipment, location or prior gameplay.
## Eight bounded cases: Basic/Composite x fresh/existing typed/legacy poison.
## The test-only calculator selects player full-hit and NPC miss, after the real
## registered release resolver checks. It does not prove production hit odds or
## RNG probability; roll_once/stage/commit/idempotence use the actual Engine API.
const EngineCore = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const OldBasic = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const OldComposite = preload("res://core/ai_gm_rebuilt/composite_actions.gd")
const NewBasic = preload("res://core/status_gameplay/basic_actions.gd")
const NewComposite = preload("res://core/status_gameplay/composite_actions.gd")
const ENEMY = "actor_raider"
const STAFF = "item_coast_staff"
const BLADE = "item_raider_blade"
const RULE_ID = "ai_gm_test_status_weapon_commit/v1"
var case_reports: Array = []

class FixedBranchRule:
	extends "res://view/playable_build/rule_release_v1.gd"
	func rule_id() -> String: return "ai_gm_test_status_weapon_commit/v1"
	func rule_schema() -> Dictionary:
		var schema: Dictionary = super.rule_schema()
		schema.schema_version = rule_id()
		schema.balance_status = "offline_explicit_branch_fixture_NOT_production_probability"
		schema.formula = "After real registered resolver validation, fixed test-only player full-hit and NPC accuracy failure; no random success search"
		return schema
	func calculate(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
		# Real release validation checks ownership, range, hostility, route, costs,
		# bounded parameters and registered policy first. Only this named test
		# calculator's outcome selection is deliberately deterministic afterward.
		var checked: Dictionary = super.calculate(snapshot,assessment)
		if not checked.ok: return checked
		for row in checked.checks:
			var miss: bool = assessment.bindings.actor_id == "actor_raider" and row.id == "accuracy"
			var registered: Dictionary = row.derived_facts.duplicate(true)
			row.method = "direct_failure" if miss else "direct_success"
			row.roll_min = 0
			row.roll_max = 0
			row.success_at_most = 0
			row.explanation = "Explicit offline branch fixture: player full hit; NPC miss. Real resolver preconditions passed. Production dice probabilities are not tested."
			row.derived_facts = {"rule_version":rule_id(),"test_only":true,"registered_release_precondition_derivation":registered,"selected_outcome":not miss,"selection_rule":"NPC accuracy fails; all other registered checks succeed"}
		checked.rule_id = rule_id()
		return checked

func _initialize() -> void:
	case_name = "weapon_commit"
	if not storage_safe(): finish(); return
	if not check(FileAccess.get_sha256("res://core/ai_gm_rebuilt/basic_actions.gd") == "6eee6fc51bd88f7688a9751bcb9c48454e0b95d4271cdb270c269bd33b1e7afd","legacy Basic retains the accepted pre-isolation source identity"):
		finish(); return
	# Match test_weapon_plan_compatibility.gd's base authoring, with one actual
	# Coast construction shared as immutable source for eight isolated engines.
	var setup: RefCounted = F.Coast.new(2,true,false)
	if not check(setup.engine.ready().ok and F.world_check(setup.state_copy()).ok,"real full1801 source Coast fixture admitted with exact bundle hashes"):
		finish(); return
	var base: Dictionary = setup.state_copy()
	setup = null
	base.items[STAFF].erase("hex")
	base.items[STAFF].erase("scene_id")
	base.items[STAFF].owner_actor_id = F.PLAYER
	if not STAFF in base.actors.actor_player.inventory: base.actors.actor_player.inventory.append(STAFF)
	base.actors.actor_player.equipment = {"weapon":STAFF}
	base.items[STAFF].weapon_profile.on_full_hit = "poison"
	if not check(base.turn == 0 and base.state_version == 0 and World.validate(base).ok,"explicit turn0 owned/equipped poison-recipe staff fixture validates"):
		finish(); return
	var arrival: Array = []
	var planned: Dictionary = {}
	var enemy: Dictionary = base.actors[ENEMY]
	for offset in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]:
		var point: Array = [enemy.hex[0]+offset[0],enemy.hex[1]+offset[1]]
		var route: Dictionary = Navigation.plan_weighted_route(base,F.PLAYER,point,7)
		if route.ok and route.cost+1 <= base.actors.actor_player.stamina.current:
			arrival = point
			planned = route
			break
	if not check(not arrival.is_empty(),"at most six real source-neighbor routes yield affordable move-plus-attack arrival"):
		finish(); return
	report["source_identity"] = F.identity(base)
	report["authored_fixture"] = {"not_original_world_fact":true,"source_worlds_constructed":1,"weapon":STAFF,"changed_before_any_action":["staff custody/equipment","staff supported on_full_hit poison recipe","Basic-only player start at navigation-verified arrival","existing-case initial poison"],"unchanged_source_recipe_fields":["weapon damage","weapon graze_damage","weapon stamina_cost","weapon range","enemy initial health/stamina","source geometry/bundle/catalog"],"route":planned,"arrival":arrival,"scenario_bound":8,"max_commits_per_case":2,"seed_search":false}
	for mode in ["typed_fresh","typed_existing","legacy_fresh","legacy_existing"]:
		for composite in [false,true]:
			if not run_case(base,arrival,mode,composite):
				report["weapon_cases"] = case_reports
				finish(); return
	report["weapon_cases"] = case_reports
	report["boundaries"] = {"actual_engine_prepare_roll_stage_commit":true,"real_basic_composite_resolvers":true,"test_only_fixed_outcome_rule":true,"production_release_hit_probability_verified":false,"rng_random_draw_distribution_verified":false,"live_model_quality_verified":false,"adapter_ui_registry_selection_tested_here":false,"actual_main_or_fx_rendered":false,"save_restart_tested_here":false,"legacy_original_player_save_used":false,"multi_world_step_supported":false,"scope":"Full Coast authored initial fixtures plus real transaction/hook behavior; existing plan-compatibility and Main/resource gates remain separate"}
	completed = true
	finish()

func run_case(base: Dictionary, arrival: Array, mode: String, composite: bool) -> bool:
	var typed: bool = mode.begins_with("typed")
	var existing: bool = mode.ends_with("existing")
	var label: String = mode + ("_composite" if composite else "_basic")
	var state: Dictionary = base.duplicate(true)
	if not composite: state.actors.actor_player.hex = arrival.duplicate()
	if typed:
		var installed: Dictionary = F.Content.install_new_world(state)
		if not check(installed.ok,label + " enables new status rules only at turn0"): return false
		state = installed.world
		if existing:
			var added: Dictionary = F.Foundation.runtime().apply_status(state.status_foundation,"poison","actor",ENEMY,"offline_authored_existing_weapon_poison",{"intensity":1,"flat_damage":1,"max_health_bps":0})
			if not check(added.ok,label + " authored existing typed poison validates"): return false
			state.status_foundation = added.store
	elif existing:
		state.actors[ENEMY].statuses.offline_legacy_poison = {"id":"offline_legacy_poison","kind":"poison","remaining_turns":2,"magnitude":1}
	if not check(World.validate(state).ok and F.world_check(state).ok,label + " retains full source geography and valid authored initial state"): return false
	var registry: Dictionary = {}
	for kind in OldBasic.KINDS:
		var resolver: RefCounted = NewBasic.new(kind) if typed else OldBasic.new(kind)
		registry[resolver.resolver_id()] = resolver
	registry[OldComposite.ID] = NewComposite.new() if typed else OldComposite.new()
	check(registry.coast_basic_attack_v1.get_script().resource_path == ("res://core/status_gameplay/basic_actions.gd" if typed else "res://core/ai_gm_rebuilt/basic_actions.gd"),label + " chooses the actual mode-specific Basic class")
	check(registry[OldComposite.ID].get_script().resource_path == ("res://core/status_gameplay/composite_actions.gd" if typed else "res://core/ai_gm_rebuilt/composite_actions.gd"),label + " chooses the actual mode-specific Composite class")
	var game: RefCounted = EngineCore.new(state,FixedBranchRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["coast_observed","keeper_trust","lamp_restored"]},1)
	if not check(game.ready().ok and game.rule_id() == RULE_ID,label + " actual engine admits honestly test-only fixed calculator"): return false
	var before: Dictionary = game.state_copy()
	var prior_typed: Dictionary = poison_on(before,ENEMY)
	var bindings: Dictionary = {"actor_id":F.PLAYER,"target_actor_id":ENEMY,"weapon_item_id":STAFF}
	if composite: bindings.target_hex = arrival.duplicate()
	var attack: Dictionary = execute(game,OldComposite.ID if composite else "coast_basic_attack_v1",bindings,["move","accuracy","impact"] if composite else ["accuracy","impact"],label + " player attack")
	if not attack.ok: return false
	var after: Dictionary = game.state_copy()
	var receipt: Dictionary = attack.receipt
	check(receipt.outcomes.get("accuracy",false) and receipt.outcomes.get("impact",false) and (not composite or receipt.outcomes.get("move",false)),label + " fixed player full-hit branch actually committed")
	check(after.turn == before.turn+1 and after.state_version == before.state_version+1,label + " one action gives exactly one authoritative turn/version")
	check(after.actors.actor_player.hex == arrival,label + " Basic starts at or Composite actually reaches verified arrival")
	var movement_cost: int = 0
	if composite:
		var route: Dictionary = Navigation.plan_weighted_route(before,F.PLAYER,arrival,int(before.actors.actor_player.stamina.current))
		if not check(route.ok,label + " source route remains authoritative before commit"): return false
		movement_cost = int(route.cost)
	check(after.actors.actor_player.stamina.current == before.actors.actor_player.stamina.current-movement_cost-int(before.items[STAFF].weapon_profile.stamina_cost),label + " route and one attack cost paid exactly once")
	var expected_hp: int = int(before.actors[ENEMY].health.current)-int(before.items[STAFF].weapon_profile.damage)-(1 if not typed and existing else 0)
	check(after.actors[ENEMY].health.current == expected_hp,label + " only weapon impact plus historically due legacy tick affect target HP")
	if typed:
		var current: Dictionary = poison_on(after,ENEMY)
		check(not current.is_empty() and current.remaining == 3 and current.parameters.flat_damage == 1 and current.parameters.max_health_bps == 0,label + " typed weapon poison retains exact flat-one recipe and three owner actions")
		check(after.actors[ENEMY].statuses.is_empty() and count_patch(receipt.patches,"actor_status_set",ENEMY) == 0,label + " no legacy poison patch/state appears in new mode")
		check(count_patch(receipt.patches,"status_v2_apply",ENEMY) == (0 if existing else 1) and count_event(receipt,"applied",ENEMY) == (0 if existing else 1),label + " typed poison applies once only when absent")
		check(health_delta(receipt.hook_patches,ENEMY) == 0,label + " another actor's hit does not immediately tick target-owned typed poison")
		if existing:
			check(C.bytes(current) == C.bytes(prior_typed) and C.bytes(after.status_foundation) == C.bytes(before.status_foundation),label + " existing typed poison ID source potency remaining and whole store are not refreshed or reapplied")
		else:
			check(current.source_id == STAFF,label + " committed typed poison cites the actual equipped source weapon")
	else:
		check(not after.has("status_foundation") and not after.has("status_gameplay") and count_patch(receipt.patches,"status_v2_apply",ENEMY) == 0,label + " legacy world remains free of typed store and typed patches")
		var legacy: Dictionary = legacy_poison_on(after,ENEMY)
		check(legacy.get("remaining_turns") == (1 if existing else 2) and legacy.get("magnitude") == 1,label + " original legacy poison keeps its old turn clock and flat magnitude")
		check(count_patch(receipt.patches,"actor_status_set",ENEMY) == (0 if existing else 1),label + " legacy source applies once only when absent")
		if existing: check(legacy.get("id") == "offline_legacy_poison",label + " old poison identity is preserved instead of replaced")
	if not check(after.combat_turn.phase == "enemy" and after.combat_turn.enemy_actor_id == ENEMY,label + " actual combat scheduler authorizes the living adjacent target's response"): return false
	# An actual NPC-owned ordinary attack (fixed miss) advances only the NPC's
	# typed owner clock. It never fabricates damage to the player to test poison.
	var npc_before: Dictionary = game.state_copy()
	var response: Dictionary = execute(game,"coast_basic_attack_v1",{"actor_id":ENEMY,"target_actor_id":F.PLAYER,"weapon_item_id":BLADE},["accuracy","impact"],label + " NPC response")
	if not response.ok: return false
	var final: Dictionary = game.state_copy()
	check(not response.receipt.outcomes.accuracy and response.receipt.outcomes.impact,label + " fixed NPC miss is explicit and never rerolled")
	check(final.actors.actor_player.health == npc_before.actors.actor_player.health,label + " missed NPC response adds no player impact or poison")
	check(final.actors[ENEMY].health.current == maxi(0,int(npc_before.actors[ENEMY].health.current)-1) and health_delta(response.receipt.hook_patches,ENEMY) == -1,label + " ordinary poisoned-owner action ticks exactly one flat damage")
	if typed:
		check(poison_on(final,ENEMY).get("remaining") == 2 and count_event(response.receipt,"applied",ENEMY) == 0,label + " owner action decrements typed poison once without reapplication")
		check(count_event(response.receipt,"updated",ENEMY) == (0 if existing else 1),label + " only registered public poison source exposes its updated event; private source still ticks without disclosure")
	else:
		var old_final: Dictionary = legacy_poison_on(final,ENEMY)
		check(old_final.is_empty() if existing else old_final.get("remaining_turns") == 1,label + " legacy original countdown/expiry is unchanged")
	check(final.turn == 2 and final.state_version == 2 and game.save_data().receipts.size() == 2,label + " exactly two commits and receipts retained")
	case_reports.append({"case":label,"typed":typed,"initial_existing_poison":existing,"composite":composite,"calculator":game.rule_id(),"initial_digest":C.digest(before),"after_attack_digest":C.digest(after),"final_digest":C.digest(final),"player_attack_receipt":receipt,"npc_response_receipt":response.receipt,"final_target_health":final.actors[ENEMY].health,"final_typed_poison":poison_on(final,ENEMY),"final_legacy_poison":legacy_poison_on(final,ENEMY)})
	return true

func execute(game: RefCounted, resolver: String, bindings: Dictionary, components: Array, label: String) -> Dictionary:
	var before_state: Dictionary = game.state_copy()
	var before_rng: Dictionary = game.save_data().rng
	var started: Dictionary = game.begin_intent("【离线武器提交夹具】" + label + "；只验证登记动作事务，不代表模型或生产命中概率。",{},bindings.actor_id)
	if not check(started.ok,label + " begins through actual Engine"): return {"ok":false}
	var action_id: String = started.request.action_id
	var reply: Dictionary = assessment(started.request,resolver,bindings,components)
	if not check(not reply.is_empty(),label + " exact actor target weapon and route evidence exists"): return {"ok":false}
	var before_preview := C.digest(game.save_data())
	var preview: Dictionary = game.query_capability(reply)
	if not check(preview.get("available",false) and C.digest(game.save_data()) == before_preview,label + " real capability preview preserves state RNG pending ledger and receipts"): return {"ok":false}
	var prepared: Dictionary = game.prepare_assessment(reply)
	if not check(prepared.ok and prepared.get("test_only_rule",false),label + " actual Engine freezes trusted Basic/Composite branches"): return {"ok":false}
	check(C.bytes(game.state_copy()) == C.bytes(before_state) and C.bytes(game.save_data().rng) == C.bytes(before_rng),label + " preparation does not apply impact poison cost or a tick")
	check(prepared.checks.all(func(row): return row.method in ["direct_success","direct_failure"] and row.derived_facts.get("test_only",false)),label + " forced branch selection is honestly isolated in named test Rule")
	var rolled: Dictionary = game.roll_once(action_id)
	if not check(rolled.ok,label + " invokes actual once-only engine resolution"): return {"ok":false}
	check(game.action_copy(action_id).rolls.is_empty() and C.bytes(game.save_data().rng) == C.bytes(before_rng),label + " direct test calculator fabricates no random die or hidden draw")
	var locked := C.digest(game.save_data())
	check(game.roll_once(action_id).ok and C.digest(game.save_data()) == locked,label + " repeated roll API reuses identical locked result without a second draw")
	var staged: Dictionary = game.stage(action_id)
	if not check(staged.ok,label + " invokes actual engine stage"): return {"ok":false}
	check(C.bytes(game.state_copy()) == C.bytes(before_state),label + " staged impact poison and hook ticks remain unpublished")
	var staged_digest := C.digest(game.save_data())
	check(game.stage(action_id).ok and C.digest(game.save_data()) == staged_digest,label + " repeated stage cannot accumulate effects or ticks")
	var committed: Dictionary = game.commit(action_id,staged.stage_hash)
	if not check(committed.ok,label + " atomically commits actual engine receipt"): return {"ok":false}
	var committed_digest := C.digest(game.save_data())
	var duplicate: Dictionary = game.commit(action_id,staged.stage_hash)
	check(duplicate.get("already_committed",false) and C.digest(game.save_data()) == committed_digest,label + " duplicate commit cannot add poison spend damage ticks history or RNG")
	return committed

func assessment(request: Dictionary, resolver: String, bindings: Dictionary, components: Array) -> Dictionary:
	var paths: Array = ["/actors/" + str(bindings.actor_id),"/actors/" + str(bindings.target_actor_id),"/items/" + str(bindings.weapon_item_id)]
	if bindings.has("target_hex"): paths.append("/hexes/%d,%d" % bindings.target_hex)
	var refs: Array = []
	var ids: Array = []
	for path in paths:
		var found: Dictionary = C.pointer(request.context.facts,path)
		if not found.ok: return {}
		var id: String = "f" + str(refs.size())
		ids.append(id)
		refs.append({"id":id,"path":path,"expected":found.value})
	var parts: Array = []
	for id in components: parts.append({"id":id,"parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":ids.duplicate()})
	return {"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"离线武器事务评估，尚未执行；固定测试结果由专用测试规则选择。","interpretation":"Authored offline weapon commit regression; real trusted resolver and transaction pipeline, not live model or production probability evidence.","resolver_id":resolver,"bindings":bindings.duplicate(true),"components":parts,"fact_refs":refs,"provenance":{"provider":"offline_status_weapon_commit_fixture","live":false,"kind":"model_reply"}}

func poison_on(state: Dictionary, actor_id: String) -> Dictionary:
	for row in state.get("status_foundation",{}).get("instances",{}).values():
		if row.owner_kind == "actor" and row.owner_id == actor_id and row.definition_id == "poison": return row
	return {}

func legacy_poison_on(state: Dictionary, actor_id: String) -> Dictionary:
	for row in state.actors[actor_id].statuses.values():
		if row.kind == "poison": return row
	return {}

func count_patch(patches: Array, type_: String, actor_id: String) -> int:
	var count := 0
	for patch in patches:
		if patch.get("type") == type_ and patch.get("owner_id",patch.get("actor_id","")) == actor_id: count += 1
	return count

func count_event(receipt: Dictionary, change: String, actor_id: String) -> int:
	var count := 0
	for patch in receipt.hook_patches:
		if patch.get("type") == "status_v2_event" and patch.get("owner_kind") == "actor" and patch.get("owner_id") == actor_id and patch.get("definition_id") == "poison" and patch.get("change") == change: count += 1
	return count

func health_delta(patches: Array, actor_id: String) -> int:
	var delta := 0
	for patch in patches:
		if patch.get("type") == "actor_pool_delta" and patch.get("actor_id") == actor_id and patch.get("pool") == "health": delta += int(patch.delta)
	return delta
