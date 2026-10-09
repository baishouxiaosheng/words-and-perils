extends "res://view/generated_v3_inventory/panel.gd"
signal notes_requested
func _ready() -> void:
	super._ready()
	var banner:Label=get_child(0).get_child(0);banner.text="村庄冒险 · 离线演示，尚未接入实时AI"
	banner.tooltip_text="交谈需先靠近村民、写下意图并取得评估；点击仅查看。"
	var row:HFlowContainer=get_child(1)
	var b:=Button.new();b.text="询问村落入口";b.pressed.connect(func():sample_requested.emit("talk"));Craft.apply_button(b,"secondary",4.0);row.add_child(b);sample_buttons.append(b)
	var notes:=Button.new();notes.text="旅途笔记";notes.pressed.connect(func():notes_requested.emit());Craft.apply_button(notes,"secondary",4.0);row.add_child(notes)
