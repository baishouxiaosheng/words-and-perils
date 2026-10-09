extends SceneTree
## Canonical commit stays authoritative; malformed cosmetic hints are ignored.
const Main=preload("res://main.tscn")
var scene
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:call_deferred("run")
func decision(presentation:Variant,patches:Array=[])->Dictionary:
	return {"schema_version":1,"action_id":scene.active_action,"state_version":scene.game.state.state_version,"phase":"resolution","narration":"QA protocol fixture, not a model response.","outcome":"QA","patches":patches,"presentation":presentation}
func begin()->void:
	scene.goal.text="QA presentation integrity";scene.submit_action()
	scene.apply_decision({"schema_version":1,"action_id":scene.active_action,"state_version":scene.game.state.state_version,"phase":"planning","narration":"QA provisional only.","needs_roll":false,"context":"Synthetic UI wiring test, no live model."})
func run()->void:
	scene=Main.instantiate();root.add_child(scene);await process_frame
	for metadata in [null,[],{"kind":{}},{"kind":"magic","source_actor_id":[]},{"kind":"magic","target_actor_id":{}},{"kind":"magic","target_hex":[{},[]]},{"kind":"magic","target_hex":[1.2,-1]},{"kind":"magic","target_hex":[10000000000,0]},{"kind":"magic","target_hex":[1000,0]},{"kind":"unknown","target_actor_id":"actor_sentinel"}]:
		begin();var reply=decision(metadata)
		var before:int=scene.game.state.state_version
		check(scene.apply_decision(reply),"Malformed cosmetic data does not reject canonical commit")
		check(scene.game.state.state_version==before+1,"Canonical version advances exactly once")
		check(scene.board.presentation.effects.is_empty(),"Malformed cosmetic data adds no visual effect")
		check(scene.apply_decision(reply) and scene.game.state.state_version==before+1,"Duplicate final commit is idempotent")
		check(scene.board.presentation.effects.is_empty(),"Duplicate produces no extra effects")
	begin();var valid=decision({"kind":"magic","source_actor_id":"actor_player","target_actor_id":"actor_sentinel"},[{"op":"set","path":"/actors/actor_sentinel/health/current","value":11}])
	check(scene.apply_decision(valid),"Valid final presentation metadata accepted")
	check(scene.board.presentation.effects.size()==2,"Canonical health loss produces hit; optional magic is separate")
	var count:int=scene.board.presentation.effects.size()
	check(scene.apply_decision(valid) and scene.board.presentation.effects.size()==count,"Repeated final never replays hit or magic")
	scene.queue_free();await process_frame
	if failures.is_empty():print("OPTIONAL PRESENTATION PASSED: %d assertions"%checks);quit(0)
	else:
		for f in failures:printerr("FAIL: ",f)
		quit(1)
