extends "res://view/generated_v3_enemy/panel.gd"
const Policy=preload("res://view/generated_v3_enemy/policy.gd")
var pickup_blade_button:Button
var equip_blade_button:Button
var equip_staff_button:Button
func _ready()->void:
	super._ready()
	pickup_blade_button=_gear_button("取走倒地敌人的短刃", "pickup_blade")
	equip_blade_button=_gear_button("换上短刃示例", "equip_blade")
	equip_staff_button=_gear_button("换回木杖示例", "equip_staff")
func _gear_button(title_:String,kind:String)->Button:
	var b:=Button.new();b.text=title_;b.tooltip_text="仅填写明确示例意图；结束回合后仍需有效评估。";b.pressed.connect(func():sample_requested.emit(kind));Craft.apply_button(b,"secondary",4.0);get_child(1).add_child(b);sample_buttons.append(b);return b
func update_adapter(adapter:RefCounted)->void:
	super.update_adapter(adapter)
	if not is_instance_valid(pickup_blade_button) or not adapter.ready().ok:return
	var state:Dictionary=adapter.state_copy();var player:Dictionary=state.actors.actor_player
	var enemy:Dictionary=state.actors[adapter.source.enemy_id];var blade:Dictionary=state.items.item_raider_blade
	var blocked:bool=adapter.phase()!="idle" or adapter.enemy_response_available() or player.health.current<=0
	pickup_blade_button.disabled=blocked or enemy.health.current>0 or blade.owner_actor_id!="actor_village_hostile" or not Policy.melee_range(state,"actor_player",adapter.source.enemy_id,adapter.source.base_navigation)
	pickup_blade_button.tooltip_text="敌人须已倒下，旅人须在真实干地连通的邻格。点击只填写示例意图；取走仍须评估，敌人原格仍被占据。"
	equip_blade_button.disabled=blocked or blade.owner_actor_id!="actor_player" or player.equipment.weapon=="item_raider_blade"
	equip_staff_button.disabled=blocked or player.equipment.weapon=="item_coast_staff"
	attack_button.text="近战示例（当前装备）"
