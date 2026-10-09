extends SceneTree
## Real Main walk-through of the current build: startup, tile selection, mode
## round trip, intent submission, save, and reopen in a fresh Main.
## Uses the project's isolated user:// directory; no API key is read or needed.
const MainScene=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	print(("BASELINE_OK " if ok else "BASELINE_FAIL ")+label)
	if not ok:failures.append(label)
func _initialize()->void:run.call_deferred()
func frames(n:=8)->void:
	for i in range(n):await process_frame
func run()->void:
	for path in ["user://r24_coast_adventure_save.json","user://r24_coast_adventure_save.json.narration.json"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var main=MainScene.instantiate();root.add_child(main);await frames(20)
	check(main.coast_mode and main.playtest_mode,"startup opens the coast adventure")
	check(main.board!=null and str(main.board.get("load_error")).is_empty(),"coast board loads without error")
	check(main.playtest.phase()=="idle","startup phase is idle")
	print("BASELINE_INFO submit_caption=",main.submit_button.text.replace("\n",""))
	var state:Dictionary=main.playtest.state_copy()
	var player:Dictionary=state.actors.actor_player
	var hex:=Vector2i(int(player.hex[0]),int(player.hex[1])) if player.get("hex") is Array else Vector2i.ZERO
	main.on_hex_selected(hex);await frames()
	check(not main.selected_focus.is_empty() and str(main.selected_focus.get("kind",""))=="tile","selecting the player's tile sets a tile focus")
	main._switch_mode_to("laboratory");await frames(12)
	check(not main.coast_mode,"switch to laboratory leaves coast mode")
	main._switch_mode_to("coast");await frames(12)
	check(main.coast_mode and main.playtest.phase()=="idle","switch back restores the coast adventure")
	check(C.bytes(main.playtest.state_copy()).sha256_text()==C.bytes(state).sha256_text(),"mode round trip keeps the world state")
	main.goal.text="我仔细观察周围的环境";main.end_turn();await frames(12)
	var phase:String=main.playtest.phase()
	check(phase!="idle","submitting an intent leaves the idle phase ("+phase+")")
	check(not main.playtest.request().is_empty(),"submission produces a model request")
	main.save_game();await frames()
	check(main.last_save_result.get("ok",false),"save succeeds "+str(main.last_save_result.get("code","")))
	var saved_state:=C.bytes(main.playtest.state_copy()).sha256_text()
	var saved_action:=C.bytes(main.playtest.action_copy()).sha256_text()
	main.queue_free();await frames(4)
	var reopened=MainScene.instantiate();root.add_child(reopened);await frames(20)
	reopened.load_game();await frames()
	check(reopened.last_load_result.get("ok",false),"fresh Main loads the save "+str(reopened.last_load_result.get("code","")))
	check(reopened.playtest.phase()==phase,"reopened phase matches ("+reopened.playtest.phase()+")")
	check(C.bytes(reopened.playtest.state_copy()).sha256_text()==saved_state,"reopened world state matches")
	check(C.bytes(reopened.playtest.action_copy()).sha256_text()==saved_action,"reopened pending action matches")
	reopened.queue_free();await frames(4)
	print("BASELINE_RESULT %d/%d"%[checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
