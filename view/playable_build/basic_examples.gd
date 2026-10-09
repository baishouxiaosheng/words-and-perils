extends RefCounted
## Explicit authored offline examples. Exact complete goals only, never keyword parsing.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Actions = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const AUTHOR := "项目作者 · 明确署名基础战斗与物品样例 basic_actions/v1"
const KINDS := ["attack", "pickup", "equip", "drop", "transfer", "equip_bow", "equip_wand"]
static func install_new_game(state: Dictionary) -> void:
	# NEW worlds only. Never used by save migration.
	var player: Dictionary = state.actors.actor_player
	player.combat_profile = Basic.combatant(["coast_raider"])
	player.equipment = {}
	state.combat_turn = {"schema_version": "coast_encounter_turn/v1", "phase": "player", "enemy_actor_id": "", "round": 0}
	var occupied: Array = []
	for actor in state.actors.values(): occupied.append(actor.hex)
	var destination: Array = []
	var keys: Array = state.hexes.keys(); keys.sort()
	for key in keys:
		var cell: Dictionary = state.hexes[key]; var hex: Array = [cell.q, cell.r]
		var distance: int = Effects.distance(player.hex, hex)
		if cell.scene_id != player.scene_id or cell.ground_blocked or cell.all_blocked or hex in occupied or distance < 3 or distance > 5: continue
		if Effects.distance(state.actors.actor_keeper.hex, hex) < 3 or hex in state.actors.actor_scout.patrol.route: continue
		destination = hex; break
	if destination.is_empty(): return
	state.actors.actor_raider = {"id": "actor_raider", "name": "潮滩劫掠者", "hex": destination, "scene_id": player.scene_id, "role": "hostile", "faction": "coast_raider", "health": {"current": 5, "max": 5}, "stamina": {"current": 6, "max": 6}, "inventory": ["item_raider_blade"], "equipment": {"weapon": "item_raider_blade"}, "statuses": {}, "hooks": ["status_tick"], "combat_profile": Basic.combatant(["traveler"]), "observed_dialogue": ["劫掠者守着岸边的破箱。你可以绕开；他不会介入修灯。"]}
	state.items.item_coast_staff = _item("item_coast_staff", "潮岸木杖", "可选战斗补给：相邻攻击消耗一点体力；命中3伤害，擦伤1。先拾取并装备。", 1)
	state.items.item_coast_staff.hex = player.hex.duplicate(); state.items.item_coast_staff.scene_id = player.scene_id
	state.items.item_coast_staff.weapon_profile = Basic.weapon(3)
	state.items.item_coast_staff.interaction_profile = Basic.interaction("weapon")
	state.items.item_raider_blade = _item("item_raider_blade", "苦叶短刃", "劫掠者的近战短刃：命中2，擦伤1；完整命中可附加两回合每回合1点毒，不叠加。击倒后可拾取。", 1)
	state.items.item_raider_blade.owner_actor_id = "actor_raider"; state.items.item_raider_blade.weapon_profile = Basic.weapon(2, true); state.items.item_raider_blade.interaction_profile = Basic.interaction("weapon")
	for row in [["item_coast_bow", "岸行短铳", "ranged", "item_coast_arrows"], ["item_coast_wand", "潮光杖", "magic", "item_coast_charges"]]:
		state.items[row[0]] = _item(row[0], row[1], "可选原型补给：每次攻击消耗一点体力和一份明示弹药/晶能；均经过准确与冲击评估。", 1)
		state.items[row[0]].owner_actor_id = player.id; state.items[row[0]].interaction_profile = Basic.interaction("weapon"); state.items[row[0]].weapon_profile = Basic.weapon(3, false, row[2], row[3]); player.inventory.append(row[0])
		state.items[row[3]] = _item(row[3], "短铳弹药" if row[2] == "ranged" else "潮光晶能", "仅为对应已编写攻击能力提供消耗资源，不会自动施放。", 3)
		state.items[row[3]].owner_actor_id = player.id; player.inventory.append(row[3])
static func _item(id: String, name_: String, description: String, quantity: int) -> Dictionary:
	return {"id": id, "name": name_, "description": description, "quantity": quantity, "interaction_profile": Basic.interaction()}
static func bindings(kind: String, facts: Dictionary, focus: Dictionary = {}, actor_id: String = "actor_player") -> Dictionary:
	if not facts.actors.has(actor_id): return {}
	var actor: Dictionary = facts.actors[actor_id]
	if kind in ["attack", "enemy_response"]:
		var target: String = "actor_player" if kind == "enemy_response" else "actor_raider"
		if kind == "attack" and focus.get("kind", "") == "actor": target = focus.get("id", target)
		var weapon_id: String = actor.get("equipment", {}).get("weapon", "")
		if weapon_id.is_empty() or not facts.actors.has(target): return {}
		return {"actor_id": actor_id, "target_actor_id": target, "weapon_item_id": weapon_id}
	var item_id := "item_coast_staff"
	if kind == "pickup" and facts.items.has("item_raider_blade") and facts.actors.get("actor_raider", {}).get("health", {}).get("current", 1) == 0: item_id = "item_raider_blade"
	elif kind == "equip" and "item_raider_blade" in actor.inventory: item_id = "item_raider_blade"
	elif kind == "equip_bow": item_id = "item_coast_bow"
	elif kind == "equip_wand": item_id = "item_coast_wand"
	elif kind in ["drop", "transfer"]: item_id = actor.get("equipment", {}).get("weapon", "item_coast_staff")
	if kind in ["pickup","equip","drop","transfer"] and focus.get("kind")=="item" and facts.items.has(focus.get("id","")): item_id=focus.id
	if not facts.items.has(item_id): return {}
	var result := {"actor_id": actor_id, "item_id": item_id}
	if kind == "transfer": result.target_actor_id = "actor_keeper"
	return result
static func goal(kind: String, facts: Dictionary, focus: Dictionary = {}, actor_id: String = "actor_player") -> String:
	var b := bindings(kind, facts, focus, actor_id)
	if b.is_empty(): return ""
	if kind in ["attack", "enemy_response"]:
		return "【署名%s样例】%s用%s攻击%s（%s）。" % ["NPC反击" if kind == "enemy_response" else "战斗", facts.actors[actor_id].name, facts.items[b.weapon_item_id].name, facts.actors[b.target_actor_id].name, b.target_actor_id]
	var verb: String = {"pickup": "拾取", "equip": "装备", "equip_bow": "装备", "equip_wand": "装备", "drop": "放下", "transfer": "交给芦灯"}.get(kind, "")
	return "【署名物品样例】%s%s（%s），操作整份现有物品。" % [verb, facts.items[b.item_id].name, b.item_id] if not verb.is_empty() else ""
static func assessment(request: Dictionary, kind: String) -> Dictionary:
	var facts: Dictionary = request.context.facts
	var b := bindings(kind, facts, request.context.attention_focus, request.context.actor_id)
	if b.is_empty() or request.context.goal != goal(kind, facts, request.context.attention_focus, request.context.actor_id): return C.fail("FIXTURE_SCOPE", "This exact authored basic example does not match the frozen goal.")
	var resolver_kind: String = "basic_attack" if kind in ["attack", "enemy_response"] else ({"equip_bow": "equip_item", "equip_wand": "equip_item"}.get(kind, kind + "_item"))
	var paths: Array = ["/actors/" + b.actor_id, "/items/" + b.get("weapon_item_id", b.get("item_id", ""))]
	if b.has("target_actor_id"): paths.append("/actors/" + b.target_actor_id)
	var item: Dictionary = facts.items[b.get("weapon_item_id", b.get("item_id", ""))]
	if kind == "pickup" and not item.get("owner_actor_id", "").is_empty(): paths.append("/actors/" + item.owner_actor_id)
	var ammo: String = item.get("weapon_profile", {}).get("cost_item_id", "")
	if not ammo.is_empty(): paths.append("/items/" + ammo)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found := C.pointer(facts, path)
		if not found.ok: return C.fail("FIXTURE_FACT", "Required public item capability/source fact is absent.")
		var id := "fact_" + str(refs.size()); refs.append({"id": id, "path": path, "expected": found.value}); ids.append(id)
	var components: Array = []
	for id in (["accuracy", "impact"] if resolver_kind == "basic_attack" else ["interact"]):
		components.append({"id": id, "parameters": {"A": 3, "D": 1, "P": 0}, "disposition": "possible", "fact_ref_ids": ids.duplicate()})
	return {"ok": true, "assessment": {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "明确署名离线评估已提交，结果尚未发生。", "interpretation": "只接受完整署名目标；不进行文本关键词裁决。", "resolver_id": "coast_" + resolver_kind + "_v1", "bindings": b, "components": components, "fact_refs": refs, "provenance": {"provider": AUTHOR, "live": false, "kind": "fixture"}}}
