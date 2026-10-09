extends RefCounted
## Reconstruct every receipt from the registered resolver plus unchanged hooks.
## Never trusts forged hashes, outcome patches, phase ownership or prose as rules.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Hooks=preload("res://core/ai_gm_rebuilt/hooks.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Focus=preload("res://core/focus_contract.gd")
const PublicProjection=preload("res://view/generated_v3_enemy/projection.gd")
const Examples=preload("res://view/generated_v3_enemy/assessments.gd")
const Resolver=preload("res://view/generated_v3_enemy/resolver.gd")
const Inventory=preload("res://view/generated_v3_inventory/source.gd")
static func validate(source:RefCounted,engine_data:Dictionary)->Dictionary:
	if not engine_data.get("receipts") is Dictionary or engine_data.receipts.size()>Inventory.MAX_HISTORY_RECEIPTS or C.bytes(engine_data).to_utf8_buffer().size()>Inventory.MAX_HISTORY_BYTES:return C.fail("ENEMY_HISTORY","遭遇记录超出有界格式。")
	var receipts:Array=engine_data.receipts.values();receipts.sort_custom(func(a,b):return int(a.turn)<int(b.turn))
	var replay:Dictionary=source.world.duplicate(true);var focus:=Focus.new()
	for receipt in receipts:
		if receipt.before_version!=replay.state_version or receipt.after_version!=replay.state_version+1 or receipt.turn!=replay.turn+1 or receipt.actor_id!=Basic.authorized_actor(replay):return C.fail("ENEMY_HISTORY_TURN","历史回合缺失、重复或角色归属不一致。")
		if not focus.validate_frozen(C.normalized(receipt.attention_focus),replay).is_empty():return C.fail("ENEMY_HISTORY_FOCUS","历史目标不是当时的真实目标。")
		var inferred:Dictionary=_assessment(receipt,replay)
		if not inferred.ok:return inferred
		var resolver:=Resolver.new(source,inferred.kind)
		var plan:Dictionary=resolver.freeze(replay,inferred.assessment)
		if not plan.ok:return plan
		var found:Dictionary={}
		for branch in plan.branches:
			if branch.id==receipt.branch_id and C.bytes(branch.requires)==C.bytes(receipt.outcomes):found=branch;break
		if found.is_empty() or C.bytes(found.patches)!=C.bytes(receipt.patches):return C.fail("ENEMY_HISTORY_PATCHES","历史后果与登记规则的确切分支不一致。")
		if inferred.kind=="attack" and not _valid_rolls(receipt):return C.fail("ENEMY_HISTORY_ROLLS","历史攻击需要两个有界且未替换的程序骰子。")
		if inferred.kind!="attack" and (not receipt.rolls.is_empty() or false in receipt.outcomes.values()):return C.fail("ENEMY_HISTORY_DIRECT","安全行动不能注入失败或随机结果。")
		var before:Dictionary=replay.duplicate(true)
		for patch in found.patches:
			var applied:Dictionary=World.apply(replay,patch)
			if not applied.ok:return applied
		var hooks:Dictionary=Hooks.freeze(before,replay)
		if not hooks.ok:return hooks
		if C.bytes(hooks.patches)!=C.bytes(receipt.hook_patches):return C.fail("ENEMY_HISTORY_HOOKS","中毒或调度钩子不属于此回合，不能漏结算或重复结算。")
		replay.state_version+=1;replay.turn+=1
		var checked:Dictionary=source.validate_state(replay)
		if not checked.ok:return checked
	if C.bytes(replay)!=C.bytes(engine_data.get("state")):return C.fail("ENEMY_HISTORY","当前事实与已提交遭遇记录不一致。")
	return {"ok":true}
static func _assessment(receipt:Dictionary,state:Dictionary)->Dictionary:
	if not receipt.get("branch_id") is String or not receipt.get("patches") is Array:return C.fail("ENEMY_HISTORY","历史分支格式无效。")
	for patch in receipt.patches:
		if not patch is Dictionary:return C.fail("ENEMY_HISTORY","历史后果格式无效。")
	var branch:String=receipt.branch_id;var kind="";var sample="";var target:Array=[]
	if branch.begins_with("attack_"):kind="attack";sample="attack" if receipt.actor_id=="actor_player" else "enemy_attack"
	elif branch.begins_with("move_"):
		kind="move";sample=kind
		for patch in receipt.patches:
			if patch.get("type")=="actor_move":
				if not _valid_target(patch.get("hex"),state):return C.fail("ENEMY_HISTORY","历史移动目标无效。")
				target=patch.hex.duplicate()
	elif branch.begins_with("observe_"):
		kind="observe";sample=kind
		for patch in receipt.patches:
			if patch.get("type")=="flag_set" and patch.get("flag_id")=="last_observed_cell":
				if not patch.get("value") is String:return C.fail("ENEMY_HISTORY","历史观察地格无效。")
				var parts:PackedStringArray=patch.value.split(",")
				if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return C.fail("ENEMY_HISTORY","历史观察坐标无效。")
				target=[int(parts[0]),int(parts[1])]
				if not _valid_target(target,state) or "%d,%d"%target!=patch.value:return C.fail("ENEMY_HISTORY","历史观察坐标不是确切地格。")
	elif branch.begins_with("rest_"):kind="rest";sample=kind
	elif branch.begins_with("drop_item_"):kind="drop_item";sample=kind
	elif branch.begins_with("pickup_item_"):kind="pickup_item";sample=kind
	elif branch=="npc_talk_complete":kind="talk";sample=kind
	else:return C.fail("ENEMY_HISTORY_FAMILY","历史行动类型不属于此遭遇。")
	var request={"action_id":receipt.action_id,"state_version":state.state_version,"context_hash":"history_reconstruction","context":{"facts":PublicProjection.facts(state,receipt.attention_focus),"goal":Examples.goal(sample,target),"actor_id":receipt.actor_id}}
	var built:Dictionary=Examples.build(request)
	if not built.ok:return built
	return {"ok":true,"kind":kind,"assessment":built.assessment}

static func _valid_target(value:Variant,state:Dictionary)->bool:
	return value is Array and value.size()==2 and C.integer(value[0]) and C.integer(value[1]) and state.hexes.has("%d,%d"%value)
static func _valid_rolls(receipt:Dictionary)->bool:
	if receipt.rolls.size()!=2 or not C.exact_fields(receipt.outcomes,["accuracy","impact"]):return false
	var seen:Dictionary={}
	for roll in receipt.rolls:
		if not C.exact_fields(roll,["component_id","value","source","test_seeded"]) or roll.component_id not in ["accuracy","impact"] or seen.has(roll.component_id) or not C.integer(roll.value) or roll.value<1 or roll.value>10000 or roll.source!="program_rng" or not roll.test_seeded is bool:return false
		if receipt.outcomes[roll.component_id] and roll.value>9500:return false
		if not receipt.outcomes[roll.component_id] and roll.value<=500:return false
		seen[roll.component_id]=true
	return C.digest({"action_id":receipt.action_id,"plan_hash":receipt.plan_hash,"rolls":receipt.rolls,"outcomes":receipt.outcomes})==receipt.roll_hash
