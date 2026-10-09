extends "res://view/generated_v3_npc/panel.gd"
var attack_button:Button
func _ready()->void:
	super._ready()
	attack_button=Button.new();attack_button.text="木杖近战示例";attack_button.pressed.connect(func():sample_requested.emit("attack"));Craft.apply_button(attack_button,"secondary",4.0);get_child(1).add_child(attack_button);sample_buttons.append(attack_button)
func update_adapter(adapter:RefCounted)->void:
	super.update_adapter(adapter)
	if is_instance_valid(attack_button):attack_button.disabled=adapter.phase()!="idle" or adapter.enemy_response_available() or adapter.state_copy().actors.actor_player.health.current<=0
