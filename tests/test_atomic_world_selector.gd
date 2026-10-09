extends SceneTree
const Main=preload("res://main.tscn")
const Generator=preload("res://core/world_generator.gd")
var checks:=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func ui_snapshot(scene)->Dictionary:
	return {"active":scene.active_action,"request":scene.current_request.duplicate(true),"goal":scene.goal.text,"selected":scene.selected,"board_selected":scene.board.selected_hex,"die":scene.die_label.text,"phase":scene.phase_label.text,"target":scene.target_label.text,"journal":scene.journal.text,"roll_disabled":scene.roll_button.disabled,"submit_disabled":scene.submit_button.disabled,"revision":scene.board.terrain_revision}
func run()->void:
	var scene=Main.instantiate();root.add_child(scene);await process_frame
	check(scene.game.state.hexes.size()==61 and not scene.game.state.has("generated_world"),"Launch remains original61")
	check(scene.radius_input.value==7 and scene.radius_input.max_value==24,"Default7, explicit larger experiment supported")
	scene.on_hex_selected(Vector2i(1,-1));scene.goal.text="保留已掷骰的行动和文字";scene.submit_action()
	var req:Dictionary=scene.current_request.duplicate(true)
	check(scene.apply_decision({"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"planning","narration":"测试夹具等待骰子。","context":"Test-only atomic selector fixture.","needs_roll":true,"difficulty":10}),"Pending planning exists")
	scene.roll_dice();scene.goal.text="尚未提交的新草稿"
	var before=scene.game.state.duplicate(true);var before_ui=ui_snapshot(scene)
	var world:Dictionary=Generator.generate(726381,4,{"generator_version":Generator.BIOMES_VERSION})
	for raw in [{},"invalid"]:
		var prepared=scene.prepare_world_candidate(raw)
		check(not prepared.ok,"Malformed generated candidate rejected")
		check(scene.game.state==before and ui_snapshot(scene)==before_ui,"Preparation failure preserves state, die, draft, target and UI")
	for property in ["generator_version","macro_landscape","actor_spawn_hexes"]:
		var invalid=world.duplicate(true)
		if property=="generator_version":invalid[property]="unsupported_future_version"
		elif property=="macro_landscape":invalid[property]={}
		else:invalid[property]={"actor_player":[999,999]}
		var prepared=scene.prepare_world_candidate(invalid)
		check(not prepared.ok,"Invalid/unsupported canonical world rejected before UI changes: "+property)
		check(scene.game.state==before and ui_snapshot(scene)==before_ui,"All old state and pending UI survive candidate rejection: "+property)
	var bad=before.duplicate(true);bad.actors.actor_player.hex=[999,999]
	check(not scene.commit_world_candidate(bad).ok,"Invalid direct commit rejected")
	check(scene.game.state==before and ui_snapshot(scene)==before_ui,"Failed commit only changes status, retaining everything else")
	var prepared=scene.prepare_world_candidate(world)
	check(prepared.ok,"Valid opt-in v2 candidate accepted")
	check(scene.game.state==before and ui_snapshot(scene)==before_ui,"Successful preparation is still detached")
	var revision=scene.board.terrain_revision
	check(scene.commit_world_candidate(prepared.candidate).ok,"Valid candidate committed atomically")
	check(scene.board.terrain_revision==revision+1,"Success rebuilds terrain once, no intermediate61 rebuild")
	check(scene.game.state.pending_actions.is_empty() and scene.active_action.is_empty() and scene.goal.text.is_empty(),"Explicit commit resets pending/request/draft together")
	check(scene.selected==Vector2i(99,99) and scene.die_label.text=="D20  /  —" and scene.clear_target_button.disabled,"Explicit commit resets die and target controls")
	check(scene.game.state.generated_world.generator_version==Generator.BIOMES_VERSION and scene.board.terrain_field.biomes_v2,"Model and renderer use same v2 version")
	check(scene.map_title.text.contains("726381"),"V2 title is generated world, not original fixture")
	var v2_before=scene.game.state.duplicate(true);scene.start_demo();scene._begin_demo()
	check(scene.game.state==v2_before and scene.demo_step==0,"Recorded replay cannot overwrite a generated world")
	scene.goal.text="保存多地貌行动";scene.submit_action();req=scene.current_request.duplicate(true)
	check(req.snapshot.generated_world.generator_version==Generator.BIOMES_VERSION,"GM receives v2 exact metadata")
	check(scene.apply_decision({"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"planning","narration":"测试夹具等待骰子。","context":"Test-only save fixture.","needs_roll":true,"difficulty":10}),"V2 pending planning accepted")
	scene.roll_dice();var pending=scene.game.state.duplicate(true);var die=scene.die_label.text;scene.save_game();scene.restart_game();scene.load_game()
	check(scene.game.state==pending and scene.current_request.phase=="resolution" and scene.current_request.roll.d20==pending.pending_actions[scene.active_action].roll.value and scene.die_label.text.ends_with(str(scene.current_request.roll.d20)),"V2 rolled save reload preserves exact world and die")
	check(scene.roll_button.disabled,"Reloaded pending die cannot reroll")
	var v1=Generator.generate(726381,4);prepared=scene.prepare_world_candidate(v1)
	check(prepared.ok and scene.commit_world_candidate(prepared.candidate).ok,"Existing v1 remains consumable")
	var old=scene.game.state.duplicate(true);scene.save_game();scene.restart_game();scene.load_game()
	check(scene.game.state==old and not scene.board.terrain_field.biomes_v2,"Existing v1 save still loads via unchanged material path")
	prepared=scene.prepare_world_candidate();revision=scene.board.terrain_revision
	check(scene.commit_world_candidate(prepared.candidate).ok and scene.board.terrain_revision==revision+1,"Explicit original61 return uses one refresh")
	scene.start_demo();check(scene.demo_step==1 and not scene.roll_button.disabled,"Original recorded planning still works")
	scene.cancel_pending();scene.restart_game();scene.world_build_busy=true;scene.goal.text="重复生成保护";before=scene.game.state.duplicate(true);before_ui=ui_snapshot(scene)
	scene.request_world_build(true);scene.begin_world_build();scene.submit_action();scene.load_game()
	check(scene.game.state==before and ui_snapshot(scene)==before_ui,"Busy duplicate generation/submission/load cannot mutate prior world")
	scene.world_build_busy=false;scene.queue_free();await process_frame;await process_frame
	for failure in failures:printerr("FAIL: ",failure)
	print("ATOMIC WORLD SELECTOR: %d/%d passed"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
