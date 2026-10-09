extends SceneTree
## Independent QA. Explicit detached states and authored/mock replies only.
## No transport, provider, credentials or production mutations.
const Adapter = preload("res://view/generated_v3_enemy/adapter.gd")
const Resolver = preload("res://view/generated_v3_enemy/resolver.gd")
const Examples = preload("res://view/generated_v3_enemy/assessments.gd")
const PublicProjection = preload("res://view/generated_v3_enemy/projection.gd")
const History = preload("res://view/generated_v3_enemy/history.gd")
const Catalog = preload("res://core/source_enemy/catalog.gd")
const Policy = preload("res://view/generated_v3_enemy/policy.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
var checks: int = 0
var failures: Array = []
var metrics: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		printerr("INDEPENDENT_FAIL ", label)
	return value

func answer(state: Dictionary, enemy: bool = false) -> Dictionary:
	var actor_id: String = Catalog.ENEMY if enemy else "actor_player"
	var kind: String = "enemy_attack" if enemy else "attack"
	return Examples.build({"action_id":state.world_id + ":action_1", "state_version":state.state_version, "context_hash":"independent-frozen-branch-probe", "context":{"facts":PublicProjection.facts(state), "goal":Examples.goal(kind), "actor_id":actor_id}})

func attack_plan(source: RefCounted, state: Dictionary, enemy: bool = false) -> Dictionary:
	var made: Dictionary = answer(state, enemy)
	if not made.get("ok", false): return made
	return Resolver.new(source, "attack").freeze(state, made.assessment)

func after_branch(before: Dictionary, branch: Dictionary) -> Dictionary:
	var candidate: Dictionary = before.duplicate(true)
	for patch in branch.patches:
		var result: Dictionary = World.apply(candidate, patch)
		if not result.ok: return result
	var hooks: Dictionary = Hooks.freeze(before, candidate)
	if not hooks.ok: return hooks
	return {"ok":true, "state":candidate, "hook_patches":hooks.patches}

func poison(remaining: int) -> Dictionary:
	return {"weapon_poison":{"id":"weapon_poison", "kind":"poison", "remaining_turns":remaining, "magnitude":1}}

func run() -> void:
	var seed_: int = 726381
	var radius_: int = 4
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1: seed_ = int(args[0])
	if args.size() >= 2: radius_ = int(args[1])
	metrics = {"seed":seed_, "radius":radius_, "detached_branch_fixtures":true, "mock_only":true, "network_calls":0}
	var generated: Dictionary = Generator.generate(seed_, radius_, "coastal_range")
	if not check(generated.get("ok", false), "source generator"): finish(); return
	var a: RefCounted = Adapter.new()
	var admitted: Dictionary = a.start_source(generated.source)
	if not check(admitted.get("ok", false), "same-source enemy admission " + str(admitted)): finish(); return
	var untouched: String = C.bytes(a.save_data())
	var source: RefCounted = a.source
	var state: Dictionary = a.state_copy()
	var anchor: Array = source.enemy_placement_result.attack_anchor_hex.duplicate()
	state.actors.actor_player.hex = anchor
	if not check(source.validate_state(state).ok, "detached actor at admitted attack anchor"): finish(); return
	check(Policy.melee_range(state, "actor_player", Catalog.ENEMY, source.base_navigation), "exact dry anchor is melee-reachable")
	check(Policy.melee_range(state, Catalog.ENEMY, "actor_player", source.base_navigation), "exact dry anchor reach is symmetric")
	check(not source.navigation.step(anchor, state.actors[Catalog.ENEMY].hex).ok, "living enemy cell blocks movement")
	check(source.navigation.route_points([state.actors[Catalog.ENEMY].hex]).is_empty(), "occupied singleton route is blocked")
	var dead: Dictionary = state.duplicate(true)
	dead.actors[Catalog.ENEMY].health.current = 0
	check(Policy.occupied(dead, dead.actors[Catalog.ENEMY].hex, "actor_player"), "downed enemy retains occupancy")
	check(not attack_plan(source, dead).ok, "downed enemy cannot be attacked")
	var empty: Dictionary = state.duplicate(true)
	empty.actors.actor_player.stamina.current = 0
	check(not attack_plan(source, empty).ok, "zero-stamina player attack denied")
	var same: Dictionary = state.duplicate(true)
	same.actors.actor_player.hex = same.actors[Catalog.ENEMY].hex.duplicate()
	check(not Policy.melee_range(same, "actor_player", Catalog.ENEMY, source.base_navigation), "same-cell melee not accepted as adjacency")
	var mismatched: Dictionary = state.duplicate(true)
	mismatched.generated_world.geometry_hash = "wrong-geometry"
	check(not Policy.melee_range(mismatched, "actor_player", Catalog.ENEMY, source.base_navigation), "cross-geometry range denied")
	var plan: Dictionary = attack_plan(source, state)
	if not check(plan.get("ok", false) and plan.branches.size() == 4, "four complete player attack branches"): finish(); return
	for branch in plan.branches:
		var result: Dictionary = after_branch(state, branch)
		if not check(result.ok, "player branch applies " + branch.id): continue
		var expected_damage: int = (3 if branch.requires.impact else 1) if branch.requires.accuracy else 0
		check(result.state.actors.actor_player.stamina.current == 7, "one player stamina on " + branch.id)
		check(result.state.actors[Catalog.ENEMY].health.current == 5 - expected_damage, "authored player damage on " + branch.id)
		check(result.state.combat_turn.phase == "enemy", "separate feasible enemy scheduled on " + branch.id)
		check(result.state.actors.actor_player.statuses.is_empty(), "player staff cannot poison on " + branch.id)
		check(result.state.actors[Catalog.ENEMY].stamina.current == 6, "scheduling does not spend enemy stamina on " + branch.id)
	var enemy: Dictionary = state.duplicate(true)
	enemy.combat_turn.phase = "enemy"
	var enemy_plan: Dictionary = attack_plan(source, enemy, true)
	if check(enemy_plan.get("ok", false) and enemy_plan.branches.size() == 4, "four complete separately assessed enemy branches"):
		for branch in enemy_plan.branches:
			var result: Dictionary = after_branch(enemy, branch)
			if not check(result.ok, "enemy branch applies " + branch.id): continue
			var full: bool = branch.requires.accuracy and branch.requires.impact
			var damage: int = (2 if branch.requires.impact else 1) if branch.requires.accuracy else 0
			check(result.state.actors[Catalog.ENEMY].stamina.current == 5, "one enemy stamina on " + branch.id)
			check(result.state.actors.actor_player.health.current == 12 - damage, "new poison does not tick on creation " + branch.id)
			check(result.state.actors.actor_player.statuses.has("weapon_poison") == full, "only full enemy hit creates poison " + branch.id)
			if full: check(result.state.actors.actor_player.statuses.weapon_poison.remaining_turns == 2, "new poison keeps two future commits")
			check(result.state.combat_turn.phase == "player", "enemy action returns ownership on " + branch.id)
		check(not attack_plan(source, enemy).ok, "player cannot steal an enemy phase")
	var poisoned: Dictionary = enemy.duplicate(true)
	poisoned.actors.actor_player.statuses = poison(2)
	var poison_plan: Dictionary = attack_plan(source, poisoned, true)
	if check(poison_plan.get("ok", false), "existing poison attack plan"):
		for branch in poison_plan.branches:
			var result: Dictionary = after_branch(poisoned, branch)
			if not check(result.ok, "existing poison branch " + branch.id): continue
			var damage: int = (2 if branch.requires.impact else 1) if branch.requires.accuracy else 0
			check(result.state.actors.actor_player.health.current == 11 - damage, "existing poison ticks once even on miss " + branch.id)
			check(result.state.actors.actor_player.statuses.weapon_poison.remaining_turns == 1, "poison does not stack or refresh " + branch.id)
	var lethal_poison: Dictionary = state.duplicate(true)
	lethal_poison.actors.actor_player.health.current = 1
	lethal_poison.actors.actor_player.statuses = poison(1)
	var lethal_plan: Dictionary = attack_plan(source, lethal_poison)
	if check(lethal_plan.get("ok", false), "lethal pre-existing poison plan"):
		for branch in lethal_plan.branches:
			var result: Dictionary = after_branch(lethal_poison, branch)
			if not check(result.ok, "lethal poison branch " + branch.id): continue
			check(result.state.actors.actor_player.health.current == 0 and result.state.combat_turn.phase == "player", "poison downing cannot strand enemy phase " + branch.id)
			check(result.state.actors.actor_player.statuses.is_empty(), "last poison tick expires " + branch.id)
	var low_enemy: Dictionary = state.duplicate(true)
	low_enemy.actors[Catalog.ENEMY].health.current = 1
	var low_plan: Dictionary = attack_plan(source, low_enemy)
	if check(low_plan.get("ok", false), "one-HP enemy plan"):
		for branch in low_plan.branches:
			var result: Dictionary = after_branch(low_enemy, branch)
			if not check(result.ok, "one-HP enemy branch " + branch.id): continue
			check(result.state.actors[Catalog.ENEMY].health.current == (0 if branch.requires.accuracy else 1), "damage clamps at zero " + branch.id)
			check(result.state.combat_turn.phase == ("player" if branch.requires.accuracy else "enemy"), "downed enemy cannot be scheduled " + branch.id)
	for target in ["garbage", "1", "1,2,3", "a,b", null, 17]:
		var receipt: Dictionary = {"branch_id":"observe_success", "actor_id":"actor_player", "action_id":state.world_id + ":action_1", "attention_focus":{}, "patches":[{"type":"flag_set", "flag_id":"last_observed_cell", "value":target}]}
		check(not History._assessment(receipt, state).get("ok", false), "malformed history observation target rejected " + str(target))
	for path in ["user://generated_v3_village_npc_v1.json", "user://generated_v3_village_npc_request_v1.json", "user://generated_v3_village_inventory_v1.json"]:
		check(not a._check_destination(path).ok, "old filename protected " + path)
	check(C.bytes(a.save_data()) == untouched, "all detached probes preserve live adapter, RNG and pending state")
	var request_rows: Array = []
	for focus in [{}, a.enemy_reference(), a.npc_reference(), a.item_reference()]:
		var result: Dictionary = a.begin_intent("\\\"".repeat(2048), focus)
		if result.ok:
			var bytes_: int = C.bytes(a.request()).to_utf8_buffer().size()
			check(bytes_ <= 65536, "maximal escaped goal admitted only within 64 KiB")
			check(a.request().context.goal.to_utf8_buffer().size() == 4096, "escaped goal not trimmed")
			request_rows.append({"focus_kind":focus.get("kind", "none"), "focus_id":focus.get("id", ""), "bytes":bytes_, "accepted":true})
			check(a.cancel().ok, "budget probe cancels without action")
		else:
			check(result.code == "V3_REQUEST_BUDGET", "oversize max goal fails specifically and safely")
			request_rows.append({"focus_kind":focus.get("kind", "none"), "focus_id":focus.get("id", ""), "accepted":false, "code":result.code})
		check(a.phase() == "idle" and a.state_copy().turn == 0, "budget probe never advances world or leaves pending action")
	metrics["request_rows"] = request_rows
	finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_enemy")
	var report: Dictionary = {"ok":failures.is_empty(), "checks":checks, "failures":failures, "metrics":metrics, "scope":"independent detached authority/policy branches and real adapter request boundary; not native mouse or complete save/restart coverage"}
	FileAccess.open("res://artifacts/generated_v3_enemy/independent_contract_report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("INDEPENDENT_ENEMY_CONTRACT ", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)
