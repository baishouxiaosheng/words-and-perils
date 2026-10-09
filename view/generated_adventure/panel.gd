extends "res://view/ai_gm_playtest/panel.gd"
signal sample_requested(kind: String)
var sample_buttons: Array[Button]=[]
func _ready() -> void:
	super._ready()
	var banner: Label=get_child(0).get_child(0)
	banner.text="多地貌玩法原型 · 旧宏观地形显示 · 固定规则 / 离线评估"
	banner.tooltip_text="已接通移动、邻格观察、休息与精确存档。树木、桥梁、聚落、战斗与海岸故事尚未迁移。"
	var row:=HFlowContainer.new();row.add_theme_constant_override("h_separation",6);add_child(row);move_child(row,1)
	for pair in [["move","移动到关注地格"],["observe","观察关注地格"],["rest","原地休息"],["drop_item","放下行礼包"],["pickup_item","拾回行礼包"]]:
		var b:=Button.new();b.text=pair[1];b.set_meta("sample_kind",pair[0]);b.pressed.connect(func():sample_requested.emit(pair[0]));Craft.apply_button(b,"secondary",4.0);row.add_child(b);sample_buttons.append(b)
	reset_button.text="重置此生成冒险"
func update_adapter(adapter: RefCounted) -> void:
	super.update_adapter(adapter)
	fixture_button.text="采用署名样例评估";fixture_button.disabled=not adapter.fixture_available()
	var with_inventory: bool=adapter.state_copy().get("generated_world",{}).get("inventory_profile")=="generated_inventory/v1"
	for b in sample_buttons:
		b.visible=with_inventory or b.get_meta("sample_kind") in ["move","observe","rest"]
		b.disabled=adapter.phase()!="idle"
		b.tooltip_text="只填写署名样例文字；结束回合后仍须取得有效评估，不会直接执行行动。"
