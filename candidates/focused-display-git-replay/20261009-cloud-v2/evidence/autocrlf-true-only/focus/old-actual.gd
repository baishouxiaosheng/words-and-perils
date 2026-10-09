extends RefCounted
## Read-only player wording, kept separate from exact protocol IDs and provenance.
const StatusDetails = preload("res://view/status_gameplay/details.gd")

static func adapt_actor(world: Dictionary, actor: Dictionary) -> Dictionary:
	return StatusDetails.adapt_actor(world, actor)

static func has_statuses(actor: Dictionary) -> bool:
	return StatusDetails.has_statuses(actor)

static func status_lines(actor: Dictionary) -> Array[String]:
	return StatusDetails.status_lines(actor)

static func focus_status_lines(actor: Dictionary) -> Array[String]:
	return StatusDetails.focus_status_lines(actor)

static func status_caption(actor: Dictionary) -> String:
	return StatusDetails.status_caption(actor)

static func ground_description(cell: Dictionary) -> String:
	if cell.get("all_blocked", false): return "此处无法通行"
	if cell.get("ground_blocked", false): return "此处地面已阻挡，步行需要绕行"
	return "地面未被阻挡；是否有通路仍以路线评估为准"

static func caption(focus: Dictionary, prefix := "目标") -> String:
	if focus.is_empty(): return "未选中目标"
	if focus.get("catalog_version")=="source-static-focus/v1":return "%s：%s"%[prefix.replace("关注","目标"),str(focus.get("facts",{}).get("descriptor",{}).get("name","沿途目标"))]
	var kind: String = focus.get("kind", "")
	var facts: Dictionary = focus.get("facts", {})
	var entity: Dictionary = facts.get("entity", {})
	var name_: String = {"tile":"地面", "tree":"树", "mountain":"山地", "settlement":"聚落", "district":"分区", "actor":"角色", "prop":"物件"}.get(kind, "目标")
	if kind == "item": name_ = facts.get("item", {}).get("name", "物品")
	elif kind == "passage_edge": name_ = facts.get("passage_target", {}).get("name", "窄口")
	elif not entity.is_empty(): name_ = entity.get("name", name_)
	elif kind in ["actor", "settlement"]: name_ = facts.get("name", name_)
	elif kind == "mountain" and facts.get("supporting_cell", {}).get("landform", "") == "plateau": name_ = "高原"
	elif kind == "tree" and facts.get("observable_feature", {}).has("slot"): name_ += " · 第%d棵" % (int(facts.observable_feature.slot)+1)
	var note := ""
	if kind == "passage_edge": note = " · 已架挡" if facts.get("state", {}).get("ground_blocking", false) else " · 可直接通过"
	elif kind == "item":
		var posture: String = facts.get("placement", {}).get("posture", "")
		note = " · 携带" if facts.get("item", {}).has("owner_actor_id") else {"braced":" · 架挡中", "loose":" · 松放在窄口旁"}.get(posture, " · 落地")
	elif entity.get("state", {}).get("posture") == "fallen": note = " · 已倒下 · 地面阻挡"
	elif kind == "tree" and not entity.is_empty(): note = " · 直立"
	elif kind == "prop" and entity.get("public_facts", {}).has("lit"): note = " · 已点亮" if entity.public_facts.lit else " · 已熄灭"
	elif kind == "settlement" and entity.get("state",{}).get("posture") in ["open","closed"]: note=" · 城门已开启" if entity.state.posture=="open" else " · 城门关闭"
	elif kind == "tile" and facts.get("ground_blocked", false): note = " · 地面阻挡"
	elif kind == "actor" and not status_caption(facts).is_empty(): note = " · "+status_caption(facts)
	return "%s：%s%s" % [prefix.replace("关注", "目标"), name_, note]

static func description(focus: Dictionary) -> String:
	if focus.is_empty(): return "点击地图上的角色、树、山地或旧灯，可以查看当前事实。"
	var facts: Dictionary = focus.get("facts", {})
	var entity: Dictionary = facts.get("entity", {})
	var lines: Array[String] = [caption(focus)]
	if focus.get("catalog_version")=="source-static-focus/v1":
		var descriptor:Dictionary=facts.get("descriptor",{})
		lines.append(str(descriptor.get("description","沿途的固定景物。")))
		lines.append("所在地图位置：（%d，%d）"%focus.hex)
		lines.append("房屋占据的路线需要绕行；道路不减少体力消耗。")
		lines.append("可以选择查看并描述行动；暂无人物、进屋、交易、城门或拆建能力。")
		lines.append("点击只选择目标，不会移动或改变世界。")
		return "\n".join(lines)
	var hex: Variant = focus.get("hex")
	if focus.kind != "passage_edge" and hex is Array and hex.size() == 2 and hex[0] is int and hex[1] is int:
		lines.append("选中地格：（%d，%d）" % [hex[0], hex[1]])
	if focus.kind == "item":
		var item: Dictionary = facts.get("item", {}); var physical: Dictionary = item.get("physical_traits", {})
		lines.append(str(item.get("description", "")))
		if not physical.is_empty():
			lines.append("长度%d毫米 · 最大截面%d毫米 · 质量%d克" % [physical.length_mm, physical.section_mm, physical.mass_g])
			lines.append("实心刚性物体 · 刚性等级%d · 承力等级%d；不可凭名称变成武器或桥。" % [physical.rigidity, physical.bearing])
		if focus.get("catalog_version")=="source-entity-focus/v1":
			if item.get("owner_actor_id")=="actor_player":lines.append("当前由你携带；整件放下仍需先评估。")
			elif item.has("owner_actor_id"):lines.append("当前由其他角色携带；查看不会转移物品。")
			else:lines.append("物品留在地上；须在同格或直接连通的干地邻格，经评估后才能拾回。")
			lines.append("此版本仅支持整件放下和拾回；没有拆分、装备、转交或特殊效果。")
		elif focus.get("catalog_version")=="generated-inventory-focus/v1":
			lines.append("当前随身携带，可在评估后整件放下。" if item.has("owner_actor_id") else "这件行礼包留在地上；须站在同格或相连的干地邻格，评估后才能拾回。")
			lines.append("只有放下和拾回能力；不能拆分、装备或凭名字获得其他效果。")
		elif facts.get("placement", {}).get("posture") == "braced": lines.append("正在阻断对应窄口的地面通路。须先评估取下，再另行拾取；取下后仍留在窄口旁。")
		elif item.has("owner_actor_id"): lines.append("当前由角色携带。横置前须站在该窄口的操作落脚点；每次操作消耗1体力。")
		else: lines.append("当前没有持有者。松放物品没有阻断窄口；拾取仍须取得有效评估。")
	elif focus.kind == "passage_edge":
		var target: Dictionary = facts.get("passage_target", {})
		if not target.is_empty():
			lines.append("真实石墩窄口，净宽%d毫米；可接受%d至%d毫米截面、承力等级至少%d的物件。" % [target.width_mm, target.min_section_mm, target.max_section_mm, target.required_bearing])
			lines.append("操作落脚点：(%d,%d)。只限制两端落脚点间的直接地面通行；可以另寻路径绕行。" % target.support_hex)
			lines.append("架挡不提供掩体、伤害、视线遮挡或跨水能力。失手保留原物品；仅摆放成功会松放在通道旁。")
	elif focus.kind == "actor":
		if facts.has("health"): lines.append("生命 %d/%d · 体力 %d/%d" % [facts.health.current, facts.health.max, facts.stamina.current, facts.stamina.max])
		var statuses := focus_status_lines(facts)
		lines.append_array(statuses)
		if statuses.is_empty(): lines.append("没有持续状态")
	elif not entity.is_empty():
		var visible: Dictionary = entity.get("public_facts", {})
		if focus.kind == "tree":
			lines.append("树已倒在原处，所在的地面被阻挡。" if entity.get("state", {}).get("posture") == "fallen" else "这株植物仍直立在地面上。砍倒它须先提出行动并取得有效裁定。")
		elif focus.kind == "mountain": lines.append("当前点击的是这片山群。山面外形与落脚地面一并提供给主持人；点击本身不会攀爬。")
		elif focus.kind in ["settlement","district"]:
			lines.append(str(visible.get("description","")))
			lines.append("有墙聚落须从开启的城门步行通过；飞行可越过地面墙，但不能直接跨水。墙与关闭的门采用简化直线遮挡，不模拟抛射弹道或掩体加成。")
		elif focus.kind == "prop": lines.append("旧灯正在发光。" if visible.get("lit", false) else str(visible.get("description", "场景中的物件。")))
	var cell: Dictionary = facts if focus.kind == "tile" else facts.get("supporting_cell", {})
	if not cell.is_empty(): lines.append(ground_description(cell))
	lines.append("点击只选择目标，不会移动、使用物品或改变世界。")
	return "\n".join(lines)
