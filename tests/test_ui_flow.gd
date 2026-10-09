extends SceneTree
## UI integration fixtures exercise protocol wiring, not local gameplay adjudication.
const Main=preload("res://main.tscn")
var scene
var checks:=0
var failures:Array=[]
func _initialize() -> void:
	call_deferred("run_tests")
func check(condition:bool, description:String) -> void:
	checks+=1
	if not condition: failures.append(description)
func plan(needs_roll:bool) -> Dictionary:
	return {"schema_version":1,"action_id":scene.active_action,"state_version":scene.game.state.state_version,"phase":"planning","narration":"协议接线测试；这是拟议行动，尚未执行。","context":"Testing-only protocol fixture, not an AI adjudication.","needs_roll":needs_roll,"difficulty":12}
func run_tests() -> void:
	scene=Main.instantiate();root.add_child(scene)
	await process_frame
	check(scene.board.tiles.size()==61,"61 valid hexes rendered")
	check(scene.game.state.actors.size()==2,"player and enemy token state")
	var out_of_range=scene.board.preview_to(Vector2i(4,0))
	check(out_of_range.cost>3,"far target is outside ordinary preview")
	scene.on_hex_selected(Vector2i(4,0))
	check(scene.selected==Vector2i(4,0),"outside range still selectable")
	var click_only:Dictionary=scene.game.state.duplicate(true)
	scene.goal.text="";scene.submit_action()
	check(scene.active_action.is_empty() and scene.current_request.is_empty(),"selection-only submission asks for intent, never fabricates an action")
	check(scene.game.state==click_only,"selection-only submission leaves exact world/pending/dialogue/die unchanged")
	scene.goal.text="观察所关注的地格";scene.submit_action()
	check(scene.current_request.target_binding=="unbound" and scene.current_request.target_hex==[-2,1],"selected attention is not a movement destination")
	check(scene.current_request.attention_focus.id=="hex_4_0","explicit intent carries canonical selected attention")
	check(scene.current_request.snapshot.items.item_mist_draught.description is String,"natural-language item description in request")
	scene.cancel_pending()
	check(scene.active_action.is_empty() and scene.game.state.state_version==0,"cancel keeps numerical state")
	scene.clear_target();scene.goal.text="观察河岸";scene.submit_action()
	check(scene.current_request.target_hex==[-2,1],"text-only uses current actor hex context")
	check(scene.current_request.goal=="观察河岸","text-only goal exact")
	var planning=plan(false)
	check(scene.apply_decision(planning),"no-roll planning accepted")
	check(scene.current_request.phase=="resolution","no-roll still needs final model decision")
	check(scene.roll_button.disabled,"no-roll does not manufacture a die")
	scene.cancel_pending()
	scene.goal.text="协议测试";scene.submit_action()
	check(scene.apply_decision(plan(true)),"rolling planning accepted")
	scene.save_game();scene.restart_game();scene.load_game()
	check(not scene.roll_button.disabled and not scene.active_action.is_empty(),"pending GM-requested roll survives save/load")
	scene.roll_dice()
	var retained_roll=scene.current_request.context.player_roll.value
	check(retained_roll>=1 and retained_roll<=20,"fresh live-mode player die in range")
	check(scene.current_request.context.player_roll.source=="player_random_roll","fresh player roll truthful provenance")
	scene.save_game();scene.restart_game();scene.load_game()
	check(scene.current_request.context.player_roll.value==retained_roll,"exact recorded roll restored")
	check(scene.roll_button.disabled,"restored action cannot reroll")
	var before=scene.game.state.duplicate(true)
	scene.import_text.text="{broken JSON";scene.import_decision()
	check(scene.game.state==before,"invalid JSON leaves state unchanged")
	scene.cancel_pending();scene.restart_game();scene.start_demo()
	check(not scene.roll_button.disabled,"genuine recorded planning enables replay")
	check(scene.roll_button.text.contains("回放") and scene.roll_button.text.contains("9"),"fixed test die visibly labelled")
	scene.roll_dice()
	check(scene.game.state.state_version==1,"genuine recorded final commits once")
	check(scene.game.state.actors.actor_player.hex==[1,-1],"model canonical position rendered")
	check(scene.game.state.items.item_mist_draught.quantity==0,"model canonical item quantity rendered")
	check(scene.game.state.events[0].provenance.live==false,"recorded event never claimed live API")
	scene.save_game();scene.restart_game();scene.load_game()
	check(scene.game.state.state_version==1,"committed save/restart/load restores exact version")
	check(scene.journal.get_parsed_text().contains("涉水"),"load restores recent narrative")
	if failures.is_empty(): print("UI INTEGRATION PASSED: %d assertions"%checks);quit(0)
	else:
		for failure in failures: printerr("FAIL: ",failure)
		quit(1)
