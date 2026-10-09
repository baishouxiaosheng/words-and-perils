extends SceneTree
## Independent finite authority fixtures. Detached states are not save histories.
## No provider, transport, credential, RNG override, or production mutation.
const Adapter = preload("res://view/generated_v3_equipment/adapter.gd")
const Resolver = preload("res://view/generated_v3_equipment/resolver.gd")
const Examples = preload("res://view/generated_v3_equipment/assessments.gd")
const PublicProjection = preload("res://view/generated_v3_equipment/projection.gd")
const Catalog = preload("res://core/source_equipment/catalog.gd")
const Policy = preload("res://view/generated_v3_enemy/policy.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
var checks: int = 0
var failures: Array = []
var rows: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label_: String) -> bool:
	checks += 1
	if not value: failures.append(label_); printerr("EQUIPMENT_INDEPENDENT_FAIL ",label_)
	return value
func answer(state: Dictionary, kind: String) -> Dictionary:
	return Examples.build({"action_id":state.world_id+":action_"+str(int(state.turn)+1),"state_version":state.state_version,"context_hash":"independent-detached-gear-fixture","context":{"facts":PublicProjection.facts(state),"goal":Examples.goal(kind),"actor_id":"actor_player"}})
func plan(source: RefCounted, state: Dictionary, kind: String) -> Dictionary:
	var made: Dictionary = answer(state,kind)
	if not made.get("ok",false): return made
	return Resolver.new(source,"pickup_blade" if kind=="pickup_blade" else "equip_weapon").freeze(state,made.assessment)
func apply_branch(source: RefCounted, before: Dictionary, branch: Dictionary, label_: String) -> Dictionary:
	var candidate: Dictionary = before.duplicate(true)
	for patch in branch.patches:
		var applied: Dictionary = World.apply(candidate,patch)
		if not check(applied.ok,label_+" patch applies "+str(applied)): return {}
	var hooks: Dictionary = Hooks.freeze(before,candidate)
	if not check(hooks.ok,label_+" hook applies"): return {}
	candidate.turn += 1; candidate.state_version += 1
	if not check(source.validate_state(candidate).ok,label_+" resulting state admitted"): return {}
	var encoded: String = C.bytes(candidate)
	check(source.validate_state(JSON.parse_string(encoded)).ok,label_+" JSON state admitted")
	check(C.bytes(JSON.parse_string(encoded))==encoded,label_+" JSON state exact")
	check(C.bytes(candidate)==encoded,label_+" validation read-only")
	rows.append({"label":label_,"turn":candidate.turn,"blade_owner":candidate.items[Catalog.BLADE].owner_actor_id,"weapon":candidate.actors.actor_player.equipment.weapon,"health":candidate.actors.actor_player.health.current,"hook_patches":hooks.patches})
	return candidate
func success(source: RefCounted, before: Dictionary, kind: String) -> Dictionary:
	var frozen: Dictionary = plan(source,before,kind)
	if not check(frozen.get("ok",false),kind+" freezes "+str(frozen.get("code",""))): return {}
	for branch in frozen.branches:
		if branch.requires.interact: return apply_branch(source,before,branch,kind)
	check(false,kind+" success branch exists"); return {}
func poison(turns: int) -> Dictionary:
	return {"weapon_poison":{"id":"weapon_poison","kind":"poison","remaining_turns":turns,"magnitude":1}}
func rejected(source: RefCounted, state: Dictionary, label_: String) -> void:
	var before: String = C.bytes(state)
	check(not source.validate_state(state).ok,label_+" rejected")
	check(C.bytes(state)==before,label_+" rejection read-only")
func run() -> void:
	var raw: Dictionary = Generator.generate(726381,4,"coastal_range")
	if not check(raw.get("ok",false),"finite source generated"): finish(); return
	var a: RefCounted = Adapter.new()
	var admitted: Dictionary = a.start_source(raw.source)
	if not check(admitted.get("ok",false),"new source admitted "+str(admitted)): finish(); return
	var live: String = C.bytes(a.save_data())
	var source: RefCounted = a.source
	var living: Dictionary = a.state_copy()
	living.actors.actor_player.hex = source.enemy_placement_result.attack_anchor_hex.duplicate()
	if not check(source.validate_state(living).ok,"detached anchor state valid"): finish(); return
	check(not plan(source,living,"pickup_blade").ok,"living-owner theft denied")
	check(not plan(source,living,"equip_blade").ok,"unowned blade equip denied")
	check(not plan(source,living,"equip_staff").ok,"same current staff equip denied")
	var dead: Dictionary = living.duplicate(true); dead.actors[Catalog.ENEMY].health.current=0
	if not check(source.validate_state(dead).ok,"detached downed owner valid"): finish(); return
	check(Policy.melee_range(dead,"actor_player",Catalog.ENEMY,source.base_navigation),"corpse loot uses exact original edge")
	check(not source.navigation.step(dead.actors.actor_player.hex,dead.actors[Catalog.ENEMY].hex).ok,"same corpse edge cannot be movement")
	check(source.navigation.route_points([dead.actors[Catalog.ENEMY].hex]).is_empty(),"downed singleton route blocked")
	var far: Dictionary = dead.duplicate(true)
	var found_far: bool = false
	for key in source.spawn_component:
		var fields: PackedStringArray = str(key).split(",")
		var hex: Array = [int(fields[0]),int(fields[1])]
		if Basic._distance(hex,dead.actors[Catalog.ENEMY].hex)>1:
			far.actors.actor_player.hex=hex; found_far=true; break
	check(found_far and source.validate_state(far).ok and not plan(source,far,"pickup_blade").ok,"out-of-range downed loot denied")
	var same: Dictionary = dead.duplicate(true);same.actors.actor_player.hex=same.actors[Catalog.ENEMY].hex.duplicate()
	check(not source.validate_state(same).ok and not plan(source,same,"pickup_blade").ok,"same occupied cell denied")
	for kind in ["pickup_blade","equip_blade"]:
		var made: Dictionary = answer(dead,kind)
		for item_id in [Catalog.BUNDLE,"invented_loot"]:
			var reply: Dictionary = made.assessment.duplicate(true);reply.bindings.item_id=item_id
			check(not Resolver.new(source,"pickup_blade" if kind=="pickup_blade" else "equip_weapon").freeze(dead,reply).ok,"closed item scope "+kind+" "+item_id)
		var wrong_actor: Dictionary = made.assessment.duplicate(true);wrong_actor.bindings.actor_id=Catalog.ENEMY
		check(not Resolver.new(source,"pickup_blade" if kind=="pickup_blade" else "equip_weapon").freeze(dead,wrong_actor).ok,"wrong turn owner denied "+kind)
	var zero: Dictionary = dead.duplicate(true);zero.actors.actor_player.stamina.current=0
	check(plan(source,zero,"pickup_blade").get("ok",false),"pickup does not invent stamina cost")
	var looted: Dictionary = success(source,dead,"pickup_blade")
	if looted.is_empty(): finish();return
	check(looted.items[Catalog.BLADE].owner_actor_id=="actor_player" and looted.items[Catalog.BLADE].quantity==1,"one existing blade conserved")
	check(looted.actors[Catalog.ENEMY].inventory.is_empty() and looted.actors[Catalog.ENEMY].equipment.is_empty(),"old inventory and slot cleared together")
	check(looted.actors.actor_player.inventory.count(Catalog.BLADE)==1 and looted.actors.actor_player.inventory.count(Catalog.STAFF)==1,"each existing weapon present exactly once")
	check(looted.actors.actor_player.equipment.weapon==Catalog.STAFF,"pickup does not auto-equip")
	check(looted.items[Catalog.BLADE].custody_revision==1 and looted.items[Catalog.STAFF].custody_revision==0,"pickup revision counts one event")
	check(looted.actors.actor_player.stamina.current==dead.actors.actor_player.stamina.current,"pickup stamina unchanged")
	check(looted.combat_turn.phase=="player" and Policy.occupied(looted,looted.actors[Catalog.ENEMY].hex,"actor_player"),"looted corpse occupied without enemy deadlock")
	check(not plan(source,looted,"pickup_blade").ok,"duplicate pickup rejected")
	var equipped: Dictionary = success(source,looted,"equip_blade")
	if equipped.is_empty():finish();return
	check(equipped.actors.actor_player.equipment.weapon==Catalog.BLADE and equipped.items[Catalog.BLADE].custody_revision==2,"separate equip commits new slot and revision")
	check(equipped.actors.actor_player.inventory.size()==looted.actors.actor_player.inventory.size(),"swapping keeps prior weapon")
	check(equipped.actors.actor_player.statuses.is_empty(),"owning poisonous blade does not self-poison")
	check(C.bytes(equipped.items[Catalog.BLADE].weapon_profile)==C.bytes(dead.items[Catalog.BLADE].weapon_profile),"poison capability preserved exactly")
	check(not plan(source,equipped,"equip_blade").ok,"duplicate equip rejected")
	var swapped: Dictionary = success(source,equipped,"equip_staff")
	if swapped.is_empty():finish();return
	check(swapped.items[Catalog.STAFF].custody_revision==1 and swapped.items[Catalog.BLADE].custody_revision==2,"staff revision counts equip rather than ownership parity")
	var reequipped: Dictionary = success(source,swapped,"equip_blade")
	if reequipped.is_empty():finish();return
	check(reequipped.items[Catalog.BLADE].custody_revision==3 and reequipped.items[Catalog.STAFF].custody_revision==1,"repeated alternating equips preserve independent revisions")
	var facts: Dictionary = PublicProjection.facts(reequipped)
	check(facts.items[Catalog.BLADE].owner_actor_id=="actor_player" and facts.actors.actor_player.equipment.weapon==Catalog.BLADE and facts.actors[Catalog.ENEMY].equipment.is_empty(),"current owner/equipped public facts exact")
	check(a.item_reference(Catalog.BLADE).is_empty() and a.item_reference(Catalog.STAFF).is_empty(),"weapons do not forge bundle selection identities")
	check(C.bytes(dead.generated_world.entity_catalog.entries.keys())==C.bytes([Catalog.BUNDLE]),"only genuine bundle participates in item renderer catalog")
	var poisoned: Dictionary = dead.duplicate(true);poisoned.actors.actor_player.statuses=poison(2)
	var poisoned_loot: Dictionary = success(source,poisoned,"pickup_blade")
	if not poisoned_loot.is_empty():
		check(poisoned_loot.actors.actor_player.health.current==11 and poisoned_loot.actors.actor_player.statuses.weapon_poison.remaining_turns==1,"pickup ticks preexisting poison exactly once")
		var poisoned_equip: Dictionary = success(source,poisoned_loot,"equip_blade")
		if not poisoned_equip.is_empty():check(poisoned_equip.actors.actor_player.health.current==10 and poisoned_equip.actors.actor_player.statuses.is_empty(),"equip ticks and expires final poison exactly once")
	for kind in ["pickup_blade","equip_blade"]:
		var lethal: Dictionary = (dead if kind=="pickup_blade" else looted).duplicate(true)
		lethal.actors.actor_player.health.current=1;lethal.actors.actor_player.statuses=poison(1)
		var after: Dictionary = success(source,lethal,kind)
		if after.is_empty():continue
		check(after.actors.actor_player.health.current==0 and after.actors.actor_player.statuses.is_empty(),"lethal poison accepted once on "+kind)
		check(after.items[Catalog.BLADE].owner_actor_id=="actor_player" and after.actors[Catalog.ENEMY].inventory.is_empty(),"lethal poison keeps committed custody "+kind)
		check(after.combat_turn.phase=="player" and not plan(source,after,"equip_staff" if kind=="equip_blade" else "equip_blade").ok,"downed player cannot take further turn "+kind)
	var frozen: Dictionary = plan(source,poisoned,"pickup_blade")
	if frozen.get("ok",false):
		for branch in frozen.branches:
			if branch.requires.interact:continue
			var after: Dictionary = apply_branch(source,poisoned,branch,"detached impossible direct-failure branch")
			if not after.is_empty():check(after.actors.actor_player.health.current==11 and after.items[Catalog.BLADE].owner_actor_id==Catalog.ENEMY,"every frozen committed branch ticks once without forged custody")
	for mutation in ["quantity","capability","duplicate","ground","living_owner","revision_fraction","revision_future","missing_slot","wrong_slot","npc_owner"]:
		var bad: Dictionary = reequipped.duplicate(true)
		match mutation:
			"quantity":bad.items[Catalog.BLADE].quantity=2
			"capability":bad.items[Catalog.BLADE].weapon_profile.damage=99
			"duplicate":bad.actors.actor_player.inventory.append(Catalog.BLADE)
			"ground":bad.items[Catalog.BLADE].hex=bad.actors.actor_player.hex.duplicate()
			"living_owner":bad.actors[Catalog.ENEMY].health.current=1
			"revision_fraction":bad.items[Catalog.BLADE].custody_revision=1.5
			"revision_future":bad.items[Catalog.BLADE].custody_revision=999
			"missing_slot":bad.actors.actor_player.equipment={}
			"wrong_slot":bad.actors.actor_player.equipment.weapon=Catalog.BUNDLE
			"npc_owner":bad.items[Catalog.BLADE].owner_actor_id=source.npc_id
		rejected(source,bad,mutation)
	for path in ["user://generated_v3_village_enemy_v1.json","user://generated_v3_village_enemy_request_v1.json","user://generated_v3_village_npc_v1.json","user://generated_v3_village_npc_request_v1.json","user://generated_v3_village_inventory_v1.json"]:
		check(not a._check_destination(path).ok,"old save/request protected "+path)
	check(C.bytes(a.save_data())==live,"detached authority probes preserve real adapter/RNG/pending state")
	finish()
func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_equipment")
	var report: Dictionary = {"ok":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"mock_only":true,"network_calls":0,"scope":"finite seed726381/r4 detached authority transitions and canonical JSON states; not real history, native mouse or whole-map coverage"}
	FileAccess.open("res://artifacts/generated_v3_equipment/independent_contract_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EQUIPMENT_INDEPENDENT_CONTRACT ",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
