extends SceneTree
const Main=preload("res://main.tscn")
const Craft=preload("res://view/ui_craft.gd")
const Icons=preload("res://view/strategy_icons.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func settle()->void:
	for i in range(4):await process_frame
func run()->void:
	root.size=Vector2i(1440,900);var scene=Main.instantiate();root.add_child(scene);await settle()
	var skin:StyleBoxTexture=scene.journal_panel.get_theme_stylebox("panel")
	check(skin.get_content_margin(SIDE_LEFT)==22 and skin.get_content_margin(SIDE_RIGHT)==16,"bound page preserves breathing room beyond spine")
	check(scene.journal_panel.size.x==280,"journal external width remains 280 native pixels")
	check(scene.board_container.size==Vector2(1128,642),"1440 map preserves width and spends one vertical pixel on typography")
	check(scene.journal.custom_minimum_size.x==242,"page content minimum accounts for gutter without map growth")
	for role in ["primary","secondary","tool"]:
		var b=Button.new();scene.add_child(b);Craft.apply_button(b,role)
		for state in ["normal","hover","pressed","disabled"]:
			var s:StyleBoxTexture=b.get_theme_stylebox(state)
			check(s.texture!=null and s.texture.get_width()==96 and s.texture.get_height()==48,role+" "+state+" original skin is available")
		check(b.get_theme_stylebox("normal").texture!=b.get_theme_stylebox("pressed").texture,role+" pressed reverses the bevel")
		check(b.get_theme_stylebox("normal").texture!=b.get_theme_stylebox("disabled").texture,role+" disabled has its own surface")
		check(b.get_theme_stylebox("focus")!=null,role+" keyboard focus skin present")
		b.queue_free()
	check(scene.submit_button.icon.get_size()==Vector2(16,16) and not scene.submit_button.expand_icon,"primary icon has a true native minimum width")
	check(scene.intent_expand_button.icon.get_size()==Vector2(16,16),"writing shortcut uses native quill icon")
	check(Icons.menu_texture("radio_on").get_size()==Vector2(16,16),"custom selected marker stays native 16px")
	check(scene.tools_menu.get_popup().get_theme_icon("radio_checked")==Icons.menu_texture("radio_on"),"menu current selection uses original marker")
	check(scene.goal.get_theme_color("font_readonly_color").get_luminance()<0.45,"pending intent retains dark text on ivory")
	scene.goal.text="UI appearance fixture";scene.submit_action();await settle()
	check(not scene.goal.editable and scene.goal.text=="UI appearance fixture","read-only appearance does not alter pending intent")
	check(scene.phase_label.visible and scene.next_step_label.visible and scene.export_button.is_visible_in_tree(),"phase and relay next step preserved")
	root.size=Vector2i(1280,720);await settle();scene.toggle_journal();await settle()
	print("CRAFT DRAWER SIZE ",scene.journal_drawer.size)
	check(scene.journal_drawer.size.x<=root.size.x-40 and scene.journal_drawer.size.y<=root.size.y-60,"first journal open fits 720p")
	check(scene.journal_drawer.get_ok_button().position.y+scene.journal_drawer.get_ok_button().size.y<=scene.journal_drawer.size.y,"return button still reachable")
	scene.queue_free();await settle()
	if failures.is_empty():print("UI CRAFT PASSED: %d assertions"%checks);quit(0)
	else:
		for f in failures:printerr("FAIL: ",f)
		quit(1)
