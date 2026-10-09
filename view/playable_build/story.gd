extends RefCounted
## Authored, finite offline chapter. This does not interpret arbitrary player text.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const FLAG="lamp_restored"
const GOAL="【署名样例】在芦灯身旁，按岸线线索扶正旧灯的挡风罩，换上干灯芯，重新点亮引航灯。"
static func complete(state:Dictionary)->bool:return state.get("flags",{}).get(FLAG,false)==true
static func near_keeper(state:Dictionary)->bool:
	var a:Array=state.actors.actor_player.hex;var b:Array=state.actors.actor_keeper.hex
	return maxi(absi(a[0]-b[0]),maxi(absi(a[1]-b[1]),absi(a[0]-b[0]+a[1]-b[1])))<=1
static func goal(state:Dictionary)->String:
	if complete(state):return "旧灯重燃 · 本段冒险完成。船队的去向留待下一段调查（尚未制作）。"
	if not state.flags.get("coast_observed",false):return "目标：观察岸线，找出旧灯熄灭的线索。"
	if not near_keeper(state):return "目标：沿干燥岸坡走近芦灯，再修复她身旁的旧灯。"
	if state.flags.get("keeper_trust",false):return "目标：芦灯愿意协助，修复旧灯只需 1 点体力。"
	return "目标：修复旧灯需 2 点体力；也可用果酒争取芦灯协助。"
static func repair_branches(state:Dictionary)->Dictionary:
	if not state.flags.has(FLAG):return C.fail("STORY_UPGRADE_PENDING","先完成或取消旧版存档中的待处理回合，再开始修灯。")
	if complete(state):return C.fail("CHAPTER_COMPLETE","旧灯已经重燃；这段冒险已完成，不会再次扣费。")
	if not state.flags.get("coast_observed",false):return C.fail("CLUE_REQUIRED","先观察岸线，确认旧灯的损坏原因。")
	if not near_keeper(state):return C.fail("LAMP_DISTANCE","旧灯在芦灯身旁；先走到她附近一格内。")
	var cost:=1 if state.flags.get("keeper_trust",false) else 2
	if state.actors.actor_player.stamina.current<cost:return C.fail("STAMINA_REQUIRED","修灯需要%d点体力，可先休息。"%cost)
	var spend=[{"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-cost}]
	var success=spend.duplicate(true);success.append({"type":"flag_set","flag_id":FLAG,"value":true})
	return {"ok":true,"success":success,"failure":spend}
static func feedback(result:Dictionary,state:Dictionary)->String:
	if result.is_empty():return ""
	var outcomes:Dictionary=result.get("outcomes",{});var words:Array[String]=[]
	if outcomes.has("observe") and complete(state):
		words.append("旧灯仍在发光，引航信号没有再熄灭。本段已完成，尚没有新的船队线索。")
	elif outcomes.has("observe"):
		words.append("你发现挡风罩被海风掀歪，灯芯受潮；扶正挡风罩、换上干灯芯，就能修复旧灯。" if outcomes.observe else "这次未找到新的线索，可以换个角度再观察。")
	elif outcomes.has("talk"):
		if outcomes.talk:words.append("芦灯接受了果酒，答应帮你扶稳挡风罩；修灯所需体力降为 1。")
		elif state.flags.get("keeper_trust",false):words.append("这次交涉没有带来新消息。芦灯仍愿意协助，之前的信任没有丢失。")
		else:words.append("芦灯收下果酒，仍对你的来意存疑。交涉未成功；有岸线线索仍可自行修灯，需 2 点体力。")
	elif outcomes.has("repair"):
		if outcomes.repair:words.append("旧灯重新亮起，桐岸确认岸线恢复了引航信号。旧灯重燃：本段冒险完成。船队去向仍待后续调查（尚未制作）。")
		else:words.append("灯芯没能点燃，旧灯仍然熄灭。已付出修理体力；休息后可继续尝试。")
	elif outcomes.has("rest"):words.append("你在干燥岸坡休息，整理好行囊。" if outcomes.rest else "这次未能安稳休息，体力没有恢复。")
	elif outcomes.has("move"):
		var steps := 0
		for patch in result.get("public_effects",[]):
			if patch.type == "actor_move" and patch.actor_id == "actor_player": steps += 1
		words.append("你沿可通行路线走过%d格，到达选定的落脚处。" % steps if outcomes.move else "这条路线未能完成，你留在原地。")
	elif outcomes.has("placement") and outcomes.has("stability"):
		words.append("物件已卡入窄口支座，这条地面通道被阻挡。" if outcomes.placement and outcomes.stability else "物件已放在窄口旁，未卡稳；通道仍可通过。" if outcomes.placement else "未能把物件放入支座，它仍保持原来的位置与归属。")
	elif outcomes.has("release"):
		words.append("这一根支撑已解除；同一物件留在窄口旁，可另行拾取。其他地形阻挡保持有效。" if outcomes.release else "支撑未解除。")
	elif outcomes.has("control") and outcomes.has("force"):
		words.append("树已倒下，挡住它所在的地面；之后的步行需要绕行。" if outcomes.control and outcomes.force else "这次没能把树放倒，它仍直立在原处。")
	elif outcomes.has("delivery") and outcomes.has("effect"):
		var new_status:bool=state.has("status_gameplay") or result.get("public_effects",[]).any(func(effect):return effect.type=="status_v2_event")
		if new_status:words.append("这次来源行动已结算。" if outcomes.delivery and outcomes.effect else "递送或效果未通过；目标状态未按本次来源更新。")
		else:words.append("物品已经使用，持续效果生效。" if outcomes.delivery and outcomes.effect else "物品已经使用，但递送或效果未通过，持续效果没有生效。")
	for effect in result.get("public_effects",[]):
		if effect.type == "actor_scene_transition":
			words.append("你从入口回到南潮海岸。" if effect.scene_id=="scene_coast" else "你穿过入口，来到场景切换测试室。这里仅验证框架，正式室内内容尚未制作。")
		elif effect.type == "combat_event":
			var source: String=_actor_name(state,effect.actor_id)
			var target: String=_actor_name(state,effect.target_actor_id)
			var outcome: String={"miss":"没有命中", "graze":"造成擦伤", "hit":"命中"}.get(str(effect.outcome),"完成攻击")
			words.append("%s用%s攻击%s，%s。" % [source,_item_name(state,effect.weapon_item_id),target,outcome])
		elif effect.type == "item_relocate":
			if str(effect.owner_actor_id).is_empty(): words.append("%s被放在地上。" % _item_name(state,effect.item_id))
			elif effect.owner_actor_id=="actor_player": words.append("你拾起了%s。" % _item_name(state,effect.item_id))
			else: words.append("你把%s交给了%s。" % [_item_name(state,effect.item_id),_actor_name(state,effect.owner_actor_id)])
		elif effect.type == "item_equip": words.append("%s装备了%s。" % [_actor_name(state,effect.actor_id),_item_name(state,effect.item_id)])
		elif effect.type == "actor_pool_delta" and effect.pool=="health" and effect.actor_id!="actor_player" and int(effect.delta)!=0:
			words.append("%s生命%s%d。" % [_actor_name(state,effect.actor_id),"+" if effect.delta>0 else "",int(effect.delta)])
		elif effect.type == "status_v2_event" and effect.owner_kind=="actor":
			var who:String=_actor_name(state,effect.owner_id)
			if effect.change=="removed":words.append("%s的%s已结束。" % [who,effect.name])
			else:
				var unit:String="次自身行动" if effect.clock=="owner_action" else "个世界时间步"
				words.append("%s的%s%s，剩余%d%s。" % [who,effect.name,"已生效" if effect.change=="applied" else "持续中",effect.remaining,unit])
		elif effect.type == "actor_status_set":
			var status: Dictionary=effect.status
			var who: String="你" if effect.actor_id=="actor_player" else str(state.get("actors",{}).get(effect.actor_id,{}).get("name",{"actor_keeper":"芦灯","actor_scout":"桐岸"}.get(effect.actor_id,"对方")))
			if status.kind=="poison": words.append("%s中毒，剩余%d回合，每回合损失%d生命。" % [who,status.remaining_turns,status.magnitude])
			elif status.kind=="flight": words.append("%s可以飞行，剩余%d回合；地面阻挡可越过，跨水仍需评估。" % [who,status.remaining_turns])
		elif effect.type == "actor_status_remove":
			var who: String="你的" if effect.actor_id=="actor_player" else str({"actor_keeper":"芦灯的","actor_scout":"桐岸的"}.get(effect.actor_id,"对方的"))
			words.append(who+("毒性消退。" if effect.status_id in ["condition_poison","weapon_poison"] else "飞行效果结束。" if effect.status_id=="condition_flight" else "持续效果结束。"))
	var stamina:=0;var wine:=0;var health:=0;var poison:=0;var feather:=0;var patrol:=false
	var other_items: Array[String]=[]
	for effect in result.get("public_effects",[]):
		if effect.type=="actor_pool_delta" and effect.actor_id=="actor_player" and effect.pool=="stamina":stamina+=int(effect.delta)
		elif effect.type=="actor_pool_delta" and effect.actor_id=="actor_player" and effect.pool=="health":health+=int(effect.delta)
		elif effect.type=="item_quantity_delta" and effect.item_id=="item_wine":wine+=int(effect.delta)
		elif effect.type=="item_quantity_delta" and effect.item_id=="item_poison_vial":poison+=int(effect.delta)
		elif effect.type=="item_quantity_delta" and effect.item_id=="item_feather_vial":feather+=int(effect.delta)
		elif effect.type=="item_quantity_delta" and int(effect.delta)!=0: other_items.append("%s%s%d" % [_item_name(state,effect.item_id),"+" if effect.delta>0 else "",int(effect.delta)])
		elif effect.type=="actor_move" and effect.actor_id=="actor_scout":patrol=true
	var costs:Array[String]=[]
	if stamina!=0:costs.append("体力%s%d"%["+" if stamina>0 else "",stamina])
	if health!=0:costs.append("生命%s%d"%["+" if health>0 else "",health])
	if poison!=0:costs.append("苦叶毒剂%s%d"%["+" if poison>0 else "",poison])
	if feather!=0:costs.append("轻羽药剂%s%d"%["+" if feather>0 else "",feather])
	if wine!=0:costs.append("果酒%s%d"%["+" if wine>0 else "",wine])
	costs.append_array(other_items)
	if not costs.is_empty():words.append("、".join(costs)+"。")
	if patrol:words.append("桐岸继续沿岸巡视。")
	return " ".join(words)

static func _actor_name(state: Dictionary, id: String) -> String:
	if id=="actor_player": return "你"
	return str(state.get("actors",{}).get(id,{}).get("name",{"actor_keeper":"芦灯","actor_scout":"桐岸","actor_raider":"潮滩劫掠者"}.get(id,"对方")))

static func _item_name(state: Dictionary, id: String) -> String:
	return str(state.get("items",{}).get(id,{}).get("name",{"item_coast_staff":"潮岸木杖","item_raider_blade":"苦叶短刃","item_coast_bow":"岸行短铳","item_coast_wand":"潮光杖","item_coast_arrows":"短铳弹药","item_coast_charges":"潮光晶能"}.get(id,"物品")))
