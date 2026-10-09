extends SceneTree
const Adapter=preload("res://view/generated_v3_npc/adapter.gd")
const Main=preload("res://main.gd")
func _initialize():
	print("NPC_ADAPTER_PARSE_OK ",Adapter.NPC_SAVE_SCHEMA)
	quit(0)
