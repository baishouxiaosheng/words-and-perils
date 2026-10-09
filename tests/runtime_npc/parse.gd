extends SceneTree
const Main=preload("res://main.tscn")
const Runtime=preload("res://view/runtime_ai/controller.gd")
const Full=preload("res://view/runtime_ai/bounded_profile_engine.gd")
const Session=preload("res://view/runtime_ai/village_session.gd")
func _initialize():
	print("RUNTIME_NPC_PARSE_OK");quit()
