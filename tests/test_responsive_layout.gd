extends SceneTree
## Layout and recovery controls only. These fixtures do not judge the GM.
const Main=preload("res://main.tscn")
var scene
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures.append(text)
func settle()->void:
	for i in range(4):await process_frame
func control_fits(control:Control)->bool:
	return Rect2(Vector2.ZERO,Vector2(root.size)).encloses(control.get_global_rect())
func run()->void:
	root.size=Vector2i(1440,900);scene=Main.instantiate();root.add_child(scene);await settle()
	var board:Rect2=scene.board_container.get_global_rect()
	var fraction=board.get_area()/float(root.size.x*root.size.y)
	check(fraction>=0.55 and fraction<=0.65,"1440 map is 55–65% of actual pixels")
	check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_DISABLED,"small windows do not shrink Chinese typography")
	check(scene.tools_menu.get_popup().item_count>=10,"secondary tools and both quality presets preserved")
	check(scene.tools_menu.get_theme_color("font_color").get_luminance()>0.5,"tools readable on dark strip")
	scene.toggle_journal();await settle()
	check(not scene.journal_panel.visible and scene.board_container.size.x>board.size.x,"journal collapse frees map width")
	scene.toggle_journal();await settle()
	check(scene.journal_panel.visible,"journal can reopen")
	scene.on_hex_selected(Vector2i(1,-1));scene.goal.text="布局协议测试";scene.submit_action();await settle()
	check(scene.relay_row.is_visible_in_tree() and scene.cancel_button.is_visible_in_tree(),"pending relay and cancel stay on writing desk")
	scene.toggle_journal();await settle()
	check(scene.export_button.is_visible_in_tree() and scene.import_button.is_visible_in_tree(),"journal collapse never hides recovery controls")
	check(scene.phase_label.is_visible_in_tree() and scene.next_step_label.is_visible_in_tree(),"phase and next action remain visible without journal")
	scene.apply_decision({"schema_version":1,"action_id":scene.active_action,"state_version":0,"phase":"planning","narration":"拟议协议测试，尚未执行。","context":"Test fixture.","needs_roll":true,"difficulty":12});await settle()
	check(scene.roll_button.is_visible_in_tree() and control_fits(scene.roll_button) and control_fits(scene.cancel_button),"die and cancel fit together")
	check(scene.goal.get_theme_color("font_readonly_color").get_luminance()<0.45,"pending intent has legible dark text")
	scene.cancel_pending();scene.restart_game();root.size=Vector2i(1280,720);await settle()
	check(scene.compact_layout and not scene.journal_drawer.visible,"1280 switches to closed journal drawer")
	check(control_fits(scene.goal) and control_fits(scene.submit_button) and control_fits(scene.hero_label),"1280 native-size critical text and controls fit")
	scene.toggle_journal();await settle()
	check(scene.journal_drawer.visible and scene.journal_drawer.size.y<=root.size.y-60,"drawer fits 720p")
	scene.journal_drawer.get_ok_button().pressed.emit();scene.journal_drawer.confirmed.emit();scene.journal_drawer.hide();await settle()
	check(not scene.journal_open and scene.journal_toggle.text=="主持手记","drawer return resets toggle label")
	scene.toggle_journal();await settle();check(scene.journal_drawer.visible,"drawer reopens after return")
	scene.toggle_journal();scene.toggle_intent();await settle()
	check(scene.goal.size.y>=132 and control_fits(scene.goal),"expanded intent fits 720p")
	scene.toggle_intent();root.size=Vector2i(1920,1080);await settle()
	check(not scene.compact_layout and scene.journal_panel.get_parent()==scene.middle_row,"wide layout restores docked journal")
	check(scene.board_container.size.x>=1600 and scene.board_container.size.y>=800,"1080p adds useful board pixels")
	scene.queue_free();await process_frame
	root.size=Vector2i(1280,720);scene=Main.instantiate();root.add_child(scene);await settle()
	scene.toggle_journal();await settle()
	check(scene.journal_drawer.size.y<=root.size.y-60,"direct 1280 startup first journal popup fits")
	var return_button:Button=scene.journal_drawer.get_ok_button()
	check(return_button.position.y+return_button.size.y<=scene.journal_drawer.size.y,"direct-start first return button reachable")
	scene.journal_drawer.canceled.emit();scene.journal_drawer.hide();await settle()
	check(not scene.journal_open and scene.journal_toggle.text=="主持手记","drawer cancellation restores closed toggle")
	scene.on_hex_selected(Vector2i(1,-1));check(scene.selected==Vector2i(1,-1),"target selection resumes after drawer cancel")
	scene.queue_free();await process_frame
	if failures.is_empty():print("RESPONSIVE LAYOUT PASSED: %d assertions"%checks);quit(0)
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
