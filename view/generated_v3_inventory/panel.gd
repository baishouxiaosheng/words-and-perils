extends "res://view/generated_v3_adventure/panel.gd"
func _ready() -> void:
	super._ready()
	var banner:Label=get_child(0).get_child(0);banner.text="新地形行囊探索 · 离线演示，尚未接入实时AI"
	banner.tooltip_text="行礼包可经评估整件放下或拾回；没有消耗、拆分、装备、转交或特殊效果。"
	var row:HFlowContainer=get_child(1)
	for pair in [["drop_item","放下行礼包"],["pickup_item","拾回行礼包"]]:
		var b:=Button.new();b.text=pair[1];b.pressed.connect(func():sample_requested.emit(pair[0]));Craft.apply_button(b,"secondary",4.0);row.add_child(b);sample_buttons.append(b)
