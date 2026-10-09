extends SceneTree
const Main=preload("res://main.tscn")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var n:=0
var failures:Array[String]=[]
func check(value:bool,label_:String)->void:
	n+=1
	if not value:failures.append(label_);printerr("FAIL: "+label_)
func _initialize()->void:call_deferred("run")
func run()->void:
	# Process-local rejected readiness, no on-disk bundle or user data is changed.
	# WorldBundle's own tests cover literal missing/hash-mismatched files.
	Bundle.cache={"test_readiness":true};Bundle.accepted_manifest_sha="invalid-for-test"
	var scene=Main.instantiate();root.add_child(scene);await process_frame
	check(not scene.coast_mode,"rejected startup does not activate empty coast")
	check(scene.game.state.get("actors",{}).has("actor_player"),"current valid starting world retained")
	check(scene.dialogue_speaker.text=="海岸无法载入","visible normal-dialogue load error")
	check(scene.status_label.text.contains("Active world changed"),"exact bundle error remains in advanced detail")
	Bundle.reset();scene.switch_coast();await process_frame;await process_frame
	check(scene.coast_mode and scene.playtest.engine.ready().ok,"valid bundle activates normally")
	var state:=C.bytes(scene.playtest.state_copy());var board_id:int=scene.board.get_instance_id()
	scene.goal.text="保留这段草稿"
	Bundle.accepted_manifest_sha="invalid-for-reset-test"
	scene.reset_playtest()
	check(C.bytes(scene.playtest.state_copy())==state,"failed reset preserves authoritative state")
	check(scene.board.get_instance_id()==board_id,"failed reset preserves current renderer")
	check(scene.goal.text=="保留这段草稿","failed reset preserves draft")
	check(scene.dialogue_speaker.text=="海岸无法载入","failed reset has visible explanation")
	print("WORLD_LOAD_GUARD ",n-failures.size(),"/",n)
	scene.free();Bundle.reset();quit(0 if failures.is_empty() else 1)
