extends SceneTree
## Native text, font fallback and measured spacing. These are layout checks,
## never a substitute for inspecting actual GL pixels at the intended sizes.
const Main = preload("res://main.tscn")
const Craft = preload("res://view/ui_craft.gd")
var checks := 0
var failures: Array[String] = []
var scene
func _initialize() -> void: call_deferred("run")
func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok: failures.append(note)
func settle() -> void:
	for i in range(5): await process_frame
func fits(c: Control) -> bool:
	return Rect2(Vector2.ZERO,Vector2(root.size)).encloses(c.get_global_rect())
func button_clearance(b: Button) -> void:
	var s: StyleBox = b.get_theme_stylebox("normal")
	var f: Font = b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var ink_width := f.get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	if b.icon: ink_width += b.icon.get_width() + b.get_theme_constant("h_separation")
	check(s.get_content_margin(SIDE_LEFT) >= 12 and s.get_content_margin(SIDE_RIGHT) >= 12, b.text+" clears button cut corners")
	check(b.size.x + 0.5 >= ink_width + s.get_content_margin(SIDE_LEFT)+s.get_content_margin(SIDE_RIGHT),b.text+" native label and icon fit padded width")
	check(b.size.y + 0.5 >= f.get_height(fs) + s.get_content_margin(SIDE_TOP)+s.get_content_margin(SIDE_BOTTOM),b.text+" font line box fits vertically")
func run() -> void:
	root.size = Vector2i(1440,900)
	scene = Main.instantiate();root.add_child(scene);await settle()
	check(Craft.font("body") is FontVariation and Craft.font("body").variation_face_index == 2,"sans uses Simplified Chinese TTC face")
	check(not Craft.font("body").base_font.allow_system_fallback,"body does not depend on installed fonts")
	for role in ["display","action"]:
		check(Craft.font(role).get_font_name().contains("Mistbank"),role+" uses renamed project-local OFL serif subset")
		check(Craft.font(role).fallbacks.size()==1 and Craft.font(role).fallbacks[0]==Craft.font("body"),role+" has explicit complete CJK fallback")
		check(not Craft.font(role).allow_system_fallback,role+" has no hidden OS font dependency")
		check(Craft.font(role).has_char("霁".unicode_at(0)),role+" can render arbitrary uncommon Chinese through fallback")
	check(scene.submit_button.get_theme_font("font")==Craft.font("action"),"primary action has characterful serif face")
	check(scene.submit_button.get_theme_font_size("font_size")==16,"primary action retains legible native 16px type")
	check(scene.goal.get_theme_font("font")==Craft.font("body"),"long intent remains complete sans")
	check(scene.journal.get_theme_font("normal_font")==Craft.font("body"),"dynamic narrative remains complete sans")
	var skin: StyleBox = scene.journal_panel.get_theme_stylebox("panel")
	check(skin.get_content_margin(SIDE_LEFT)==22 and skin.get_content_margin(SIDE_RIGHT)==16,"journal has optical spine and outside gutters")
	check(skin.get_content_margin(SIDE_TOP)==14 and skin.get_content_margin(SIDE_BOTTOM)==14,"journal heading and footer clear page edge")
	var input_skin:StyleBox=scene.goal.get_theme_stylebox("normal")
	check(input_skin.get_content_margin(SIDE_LEFT)==12 and input_skin.get_content_margin(SIDE_TOP)==8,"intent text clears inset paper edge")
	check(scene.journal.get_theme_constant("line_separation")==2,"16px narrative has measured 26px line rhythm")
	check(scene.tools_menu.get_popup().get_theme_constant("v_separation")==12,"menu entries have deliberate vertical rhythm")
	for b in [scene.submit_button,scene.intent_expand_button,scene.clear_target_button,scene.journal_toggle,scene.tools_menu]: button_clearance(b)
	scene.goal.text="我先系紧绳索，再沿木桥走向守卫，询问：‘古墙后是否允许通行？’\n若遭拒绝，就停在桥头；物品与移动均等待最终裁定。"
	scene.toggle_intent();await settle()
	check(scene.goal.size.y>=132 and fits(scene.goal),"long Chinese expanded intent fits without font shrinking")
	scene.toggle_intent();scene.submit_action();await settle()
	check(not scene.goal.editable and scene.goal.text.contains("绳索"),"pending state preserves native long Chinese intent")
	for b in [scene.export_button,scene.import_button,scene.cancel_button]:button_clearance(b)
	scene.apply_decision({"schema_version":1,"action_id":scene.active_action,"state_version":0,"phase":"planning","narration":"你准备靠近桥头，尚未执行。","context":"Typography fixture, not a model result.","needs_roll":true,"difficulty":12});await settle()
	button_clearance(scene.roll_button)
	check(scene.phase_label.is_visible_in_tree() and fits(scene.phase_label),"long phase label remains visible")
	check(scene.next_step_label.is_visible_in_tree() and fits(scene.next_step_label),"next step remains visible")
	scene.cancel_pending();scene.restart_game();await settle()
	for pair in [[Vector2i(1440,900),0.5596],[Vector2i(1280,720),0.6310],[Vector2i(1920,1080),0.6382]]:
		root.size=pair[0];await settle()
		var fraction:float=scene.board_container.get_global_rect().get_area()/float(root.size.x*root.size.y)
		print("TYPE MAP ",root.size," ",scene.board_container.size," ",fraction)
		check(absf(fraction-pair[1])<=0.01,"approved map area remains within one percentage point at "+str(root.size))
		check(fits(scene.submit_button) and fits(scene.goal) and fits(scene.phase_label),"critical controls fit at "+str(root.size))
	root.size=Vector2i(1280,720);await settle();scene.toggle_journal();await settle()
	check(scene.journal_drawer.visible and scene.journal_drawer.size.y<=root.size.y-60,"first journal open fits 720p")
	check(scene.journal_drawer.get_ok_button().position.y+scene.journal_drawer.get_ok_button().size.y<=scene.journal_drawer.size.y,"padded return button remains reachable")
	scene.journal_drawer.hide();scene.journal_drawer.canceled.emit();scene.show_inventory();await settle()
	check(scene.inventory_dialog.size.x<=root.size.x-40 and scene.inventory_dialog.size.y<=root.size.y-60,"larger item descriptions and padding fit 720p")
	scene.inventory_dialog.hide();scene.show_import();await settle()
	scene.import_text.text="{invalid 中文";scene.import_decision();await settle()
	check(not scene.import_error_label.text.is_empty() and scene.import_error_label.get_theme_font_size("font_size")==14,"parse errors stay native and legible")
	check(scene.import_dialog.size.y<=root.size.y-40,"first import and error remain within 720p")
	scene.queue_free();await settle()
	if failures.is_empty():print("TYPOGRAPHY PASSED: %d assertions" % checks);quit(0)
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
