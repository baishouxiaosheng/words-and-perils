extends SceneTree
const Main=preload("res://main.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
func _initialize() -> void:
	var carried:Dictionary={"items":{"item_travel_bundle":{"owner_actor_id":"actor_player"}}}
	var ground:Dictionary={"items":{"item_travel_bundle":{"hex":[-2,0],"scene_id":"scene_generated"}}}
	var before:String=C.bytes([carried,ground])
	assert(Main.generated_inventory_intro(carried).begins_with("行礼包目前随身携带。"))
	assert(Main.generated_inventory_intro(ground).begins_with("行礼包留在（-2，0）。"))
	assert(not Main.generated_inventory_intro(ground).contains("随身携带"))
	assert(Main.generated_inventory_intro(ground).contains("查看行礼包") and Main.generated_inventory_intro(ground).contains("有效裁定"))
	assert(C.bytes([carried,ground])==before)
	print("PACK_CUSTODY_INTRO_PASS 5/5 read-only correct carried/ground text")
	quit(0)
