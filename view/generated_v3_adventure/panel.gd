extends "res://view/ai_gm_playtest/panel.gd"
signal sample_requested(kind:String)
var sample_buttons:Array[Button]=[]
func _ready() -> void:
	super._ready()
	var banner:Label=get_child(0).get_child(0)
	banner.text="新地形探索 · 离线演示，尚未接入实时AI"
	banner.tooltip_text="移动、观察和休息由固定规则结算。河流、城镇与物品互动尚未开放。"
	var row:=HFlowContainer.new();row.add_theme_constant_override("h_separation",6);add_child(row);move_child(row,1)
	for pair in [["move","前往关注地格"],["observe","观察关注地格"],["rest","原地休息"]]:
		var b:=Button.new();b.text=pair[1];b.pressed.connect(func():sample_requested.emit(pair[0]));Craft.apply_button(b,"secondary",4.0);row.add_child(b);sample_buttons.append(b)
	reset_button.text="重新开始这张地图"
func update_adapter(adapter:RefCounted) -> void:
	super.update_adapter(adapter)
	fixture_button.text="应用预设裁定";fixture_button.disabled=not adapter.fixture_available()
	fixture_button.tooltip_text="这些示例的判断由作者预先编写，尚未接入实时AI。行动成本和结果仍由游戏规则结算。"
	for b in sample_buttons:b.disabled=adapter.phase()!="idle";b.tooltip_text="只填写行动描述；结束回合并取得裁定后才会行动。"
