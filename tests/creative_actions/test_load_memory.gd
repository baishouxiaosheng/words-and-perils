extends SceneTree
const Adapter=preload("res://view/playable_build/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	OS.set_environment("FOGBANK_LOAD_PROFILE","1")
	var adapter:=Adapter.new(1,true);adapter._trace_load("initial_adapter")
	var path:="res://artifacts/creative_actions_20261003/native/attempt2_saved_game.json"
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded:Dictionary=adapter.load_file(path)
	print("CREATIVE_LOAD_MEMORY ",loaded," exact_state=",loaded.ok and C.bytes(raw.state)==C.bytes(adapter.state_copy()))
	adapter._trace_load("after_result_comparison")
	quit(0 if loaded.ok else 1)
