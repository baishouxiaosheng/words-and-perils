extends SceneTree
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var scene
var count:=0
var failures:Array[String]=[]
func check(value:bool,title:String)->void:
	count+=1
	if not value: failures.append(title); printerr("FAIL: "+title)
func settle()->void:
	for i in range(4): await process_frame
func _initialize()->void: call_deferred("run")
func run()->void:
	scene=Main.instantiate(); root.add_child(scene); await settle()
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution; await settle(); scene.apply_responsive_layout(); await settle()
		var screen:=Rect2(Vector2.ZERO,Vector2(resolution))
		check(scene.board_container.get_global_rect()==screen,"world occupies entire "+str(resolution))
		for panel in [scene.hero_panel,scene.action_panel]: check(screen.encloses(panel.get_global_rect()),panel.name+" fits "+str(resolution))
		check(not scene.hero_panel.get_global_rect().intersects(scene.action_panel.get_global_rect()),"status and dialogue do not overlap "+str(resolution))
		check(not scene.journal_open and not scene.journal_panel.visible,"history starts closed "+str(resolution))
		scene.toggle_journal(); await settle()
		check(screen.encloses(scene.journal_panel.get_global_rect()),"upward history fits "+str(resolution))
		check(scene.journal_panel.get_global_rect().end.y<=scene.action_panel.position.y,"history opens above dialogue "+str(resolution))
		scene.toggle_journal(); scene.toggle_journal(); scene.toggle_journal(); await settle()
		check(not scene.journal_panel.visible,"repeated history toggle stable")
		scene.toggle_intent(); await settle()
		check(screen.encloses(scene.action_panel.get_global_rect()),"expanded input fits "+str(resolution))
		scene.toggle_intent(); await settle()
	scene.toggle_journal()
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true
	scene.goal.grab_focus(); scene._input(escape)
	check(not scene.journal_open,"Escape closes history even with text focus")
	scene._apply_focus({"world_id":scene.playtest.state_copy().world_id,"kind":"actor","id":"actor_keeper","hex":scene.playtest.state_copy().actors.actor_keeper.hex})
	check(scene.clear_target_button.visible and not scene.clear_target_button.disabled,"selected target exposes clear control")
	scene.clear_target(); check(not scene.clear_target_button.visible,"clearing target removes irrelevant control")
	var before:=C.bytes(scene.playtest.state_copy())
	scene.goal.text="保留这段行动草稿"
	scene.minimap.activated.emit(); check(scene.board.world_view.overview,"minimap opens overview")
	check(not scene.action_panel.visible and scene.dialogue_restore_button.visible,"overview hides dialogue with explicit restore icon")
	scene.dialogue_restore_button.pressed.emit()
	check(scene.action_panel.visible and scene.board.world_view.overview,"chat icon restores dialogue without moving camera")
	check(scene.goal.text=="保留这段行动草稿","overview and restore preserve draft")
	scene.minimap.activated.emit(); check(not scene.board.world_view.overview,"minimap returns to traveller")
	check(C.bytes(scene.playtest.state_copy())==before,"map controls do not move actor")
	check(scene.tools_menu.get_popup().get_item_count()==4,"compact menu has four clear subdivisions")
	check(scene.coast_panel.get_parent().is_ancestor_of(scene.coast_panel) and not scene.coast_panel.is_visible_in_tree(),"samples hidden in advanced dialog")
	scene.goal.text="我向海岸眺望，寻找旧灯。"; scene.end_turn(); scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment","double end-turn waits for offline assessment")
	check(C.bytes(scene.playtest.state_copy())==before,"waiting cannot alter authoritative facts")
	check(scene.submit_button.disabled and scene.phase_label.text.contains("离线"),"waiting is visible and primary guarded")
	check(not scene.playtest.fixture_available(),"arbitrary text cannot silently use samples")
	check(not scene.apply_playtest_reply({"schema_version":"ai_gm_assessment/v1"}),"invalid assessment rejected")
	check(C.bytes(scene.playtest.state_copy())==before,"failed assessment leaves world intact")
	scene.cancel_pending(); check(scene.playtest.phase()=="idle" and not scene.end_turn_requested,"cancel clears default end-turn ownership")
	for kind in ["move","observe","rest"]:
		var turn:int=scene.playtest.state_copy().turn
		scene.fill_coast_sample(kind); scene.end_turn(); scene.end_turn()
		scene.playtest_fixture()
		check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==turn+1,kind+" accepted assessment completes one turn")
		var after:=C.bytes(scene.playtest.state_copy()); scene.end_turn(); scene.complete_requested_turn(); scene.playtest_fixture()
		check(C.bytes(scene.playtest.state_copy())==after,kind+" repeated press/import callback cannot duplicate commit")
		check(scene.board.world_state==scene.playtest.state_copy(),kind+" render and game facts match")
	# Manual intermediate saves remain compatible, with the same locked result.
	scene.fill_coast_sample("talk"); scene.submit_action(); scene.playtest_fixture(); scene.advance_playtest()
	var locked:=C.bytes(scene.playtest.action_copy())
	check(scene.playtest.phase()=="rolled","advanced manual roll stage retained")
	scene.save_game(); scene.load_game()
	check(C.bytes(scene.playtest.action_copy())==locked,"save/load preserves locked result")
	scene.end_turn(); check(scene.playtest.phase()=="idle","single primary can resume a locked saved turn")
	print("FULLSCREEN HUD ",count-failures.size(),"/",count)
	var result={"passed":count-failures.size(),"total":count,"failures":failures}
	var f:=FileAccess.open("res://artifacts/fullscreen_hud_20261002/interaction_results.json",FileAccess.WRITE); f.store_string(JSON.stringify(result,"\t")); f.close()
	scene.free(); quit(0 if failures.is_empty() else 1)
