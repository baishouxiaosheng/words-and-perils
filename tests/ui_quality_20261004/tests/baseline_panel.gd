extends "res://view/ai_gm_playtest/panel.gd"
signal sample_requested(kind: String)
var sample_buttons: Array[Button] = []
func _ready() -> void:
	super._ready()
	var banner: Label = get_child(0).get_child(0)
	banner.text = "真实 r24 海岸 · 离线评估 / 署名样例 · 临时规则 · 未接实时AI"
	banner.tooltip_text = "真实地图与角色已接同一个游戏。样例只是有限演示；任意自由文字要导入DecisionModel评估JSON。"
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation",6); row.add_theme_constant_override("v_separation",6); add_child(row); move_child(row,1)
	var tip := Label.new(); tip.text = "只填文字："; tip.add_theme_color_override("font_color",Color.WHITE); row.add_child(tip)
	for pair in [["move","步行样例"],["observe","观察样例"],["talk","交涉样例"],["rest","休息样例"],["repair","修灯样例"],["fell","倒树样例"],["poison","中毒样例"],["flight","飞行样例"],["pickup","拾取样例"],["equip","装备木杖"],["drop","放下物品"],["transfer","交给芦灯"],["equip_bow","装备短铳"],["equip_wand","装备潮光杖"],["attack","攻击样例"],["move_attack","移动并攻击"],["brace_plank","长板卡窄口"],["brace_oar","木桨卡窄口"],["brace_bar","铁杆卡窄口"],["remove_brace","解除支撑"],["open_gate","开启围寨东门"],["close_gate","关闭围寨东门"],["enter_scene","进入测试室"],["return_scene","返回海岸"]]:
		var b := Button.new(); b.text = pair[1]; b.set_meta("sample_kind",pair[0]); b.pressed.connect(func(): sample_requested.emit(pair[0])); Craft.apply_button(b,"secondary",4.0); row.add_child(b); sample_buttons.append(b)
	var note := Label.new(); note.text="倒树需选择附近仍直立的树；攻击需装备武器并选择敌人。拾取、装备、交接与药剂使用均遵守现有物品能力。窄口支撑需走到公开支座格；完整成功阻挡地面，部分成功物件落在旁边，解除后可选择物件再拾取。按钮只填文字，仍需结束回合并取得有效评估。"; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x=600; add_child(note); move_child(note,2)
	reset_button.text = "重置海岸冒险"
	authority.custom_minimum_size.y = 95
func update_adapter(adapter: RefCounted) -> void:
	super.update_adapter(adapter)
	fixture_button.text = "采用署名样例评估"
	fixture_button.disabled = not adapter.fixture_available()
	for b in sample_buttons:
		b.disabled = adapter.phase() != "idle" or (b.text == "修灯样例" and adapter.story_complete())
		if b.get_meta("sample_kind","") in ["enter_scene","return_scene"]:
			b.visible=adapter.state_copy().has("scene_transitions"); b.disabled=b.disabled or adapter.sample_goal(str(b.get_meta("sample_kind"))).is_empty()
		if b.get_meta("sample_kind","") in ["brace_plank","brace_oar","brace_bar","remove_brace"]:
			b.visible=adapter.state_copy().has("physical_catalog")
		if b.get_meta("sample_kind","") in ["open_gate","close_gate"]:
			b.visible=adapter.state_copy().has("settlement_state")
		if b.text == "修灯样例": b.tooltip_text = "旧灯已经重燃，这段冒险已完成。" if adapter.story_complete() else adapter.story_goal()
