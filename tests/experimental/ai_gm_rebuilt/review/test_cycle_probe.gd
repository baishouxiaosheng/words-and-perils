extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
func _initialize() -> void:
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	print("START_CYCLE")
	print("SAFE_RESULT ", C.safe(cyclic))
	cyclic.clear()
	print("END_CYCLE")
	quit()
