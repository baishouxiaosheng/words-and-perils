extends RefCounted
## C fieldbook art adapter. All textures are original vector art rasterized at 2x.
## Fixed fasteners stay in 9-slice corners; typography remains native, never baked.
const ROOT := "res://assets/adventure_fieldbook/"
static var _textures: Dictionary = {}
static var _component_factory
static func texture(name_: String) -> Texture2D:
	if not _textures.has(name_):
		var source: Texture2D = load(ROOT + name_ + ".png")
		assert(source != null, "Missing imported fieldbook texture: " + name_)
		var im := source.get_image()
		var t := ImageTexture.create_from_image(im)
		t.set_size_override(im.get_size() / 2)
		_textures[name_] = t
	return _textures[name_]
static func surface(kind: String, pad: float=12.0, state: String="normal") -> StyleBoxTexture:
	var slot: String={"dock":"intent_base","speech":"dialogue_base","history":"history_base","status":"status_base","turn":"turn_button","round":"tool_button","writing":"paper_input","writing_focus":"paper_focus","well":"paper_input","panel":"intent_base","button":"button_base","primary":"button_primary"}.get(kind,"button_base")
	var cut: Array={"intent_base":[42,42,42,42],"dialogue_base":[42,42,42,42],"history_base":[46,46,46,46],"status_base":[22,48,24,25],"paper_input":[8,8,8,8],"paper_focus":[8,8,8,8],"button_base":[12,12,12,12],"button_primary":[12,12,12,12]}.get(slot,[0,0,0,0])
	if _component_factory==null:_component_factory=preload("res://view/adventure_fieldbook/components.gd").new()
	var box:StyleBoxTexture=_component_factory.style(slot,{slot:texture(slot)},state,1.0,{slot:{"slice":cut,"padding":[pad,pad,pad,pad]}}) as StyleBoxTexture
	for i in range(4):box.set_texture_margin(i,float(cut[i]));box.set_content_margin(i,pad)
	if slot not in ["turn_button","tool_button"]:
		box.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		box.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	if slot in ["turn_button","tool_button"]:
		for i in range(4):box.set_content_margin(i,0.0)
	if state=="hover":box.modulate_color=Color(1.055,1.035,1.0)
	elif state in ["pressed","hover_pressed"]:box.modulate_color=Color(.90,.88,.82)
	elif state=="disabled":box.modulate_color=Color(.79,.79,.72)
	return box
static func focus() -> StyleBoxFlat:
	var f:=StyleBoxFlat.new();f.bg_color=Color.TRANSPARENT;f.border_color=Color("7ba193");f.set_border_width_all(1);f.set_corner_radius_all(5);return f
static func configure(scene: Control) -> void:
	# Called once after the baseline type ramp, before responsive metrics cache.
	var Craft=preload("res://view/ui_craft.gd")
	scene.hero_label.add_theme_font_override("font",Craft.font("display"))
	scene.history_title.add_theme_font_override("font",Craft.font("display"))
	scene.submit_button.add_theme_font_override("font",Craft.font("action"))
	scene.submit_button.custom_minimum_size=Vector2(108,108)
	scene.submit_button.add_theme_font_size_override("font_size",20)
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:scene.submit_button.add_theme_stylebox_override(state,surface("turn",0,state))
	var base:=surface("dock",20);base.content_margin_left=40;base.content_margin_right=18
	scene.action_base.add_theme_stylebox_override("panel",base)
	var speech:=surface("speech",20);speech.content_margin_left=32;speech.content_margin_right=32;speech.content_margin_top=17;speech.content_margin_bottom=18
	scene.speech_panel.add_theme_stylebox_override("panel",speech)
	var history:=surface("history",30);history.content_margin_left=46;history.content_margin_right=38;history.content_margin_top=30
	scene.journal_panel.add_theme_stylebox_override("panel",history)
	# Continuous weak paper veil in the prose viewport; no per-line backgrounds.
	var veil:=StyleBoxFlat.new();veil.bg_color=Color("f2e6bf70");veil.set_corner_radius_all(3)
	veil.content_margin_left=12;veil.content_margin_right=19;veil.content_margin_top=7;veil.content_margin_bottom=8
	scene.journal.add_theme_stylebox_override("normal",veil)
	scene.journal.add_theme_color_override("default_color",Color("354236"))
	var bar:VScrollBar=scene.journal.get_v_scroll_bar();bar.custom_minimum_size.x=8
	var rail:=StyleBoxFlat.new();rail.bg_color=Color("b39a6266");rail.content_margin_left=2;rail.content_margin_right=2
	bar.add_theme_stylebox_override("scroll",rail)
	for state in ["grabber","grabber_highlight","grabber_pressed"]:
		var thumb:=StyleBoxFlat.new();thumb.bg_color=Color("927345");thumb.set_corner_radius_all(2);thumb.content_margin_left=3;thumb.content_margin_right=3;bar.add_theme_stylebox_override(state,thumb)
	var col:VBoxContainer=scene.speech_panel.get_parent();col.add_theme_constant_override("separation",14)
	var row:HBoxContainer=scene.goal.get_parent();row.add_theme_constant_override("separation",10)
	var stamp:=TextureRect.new();stamp.name="FieldbookCompassStamp";stamp.texture=texture("compass_stamp")
	stamp.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;stamp.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stamp.custom_minimum_size=Vector2(64,64);stamp.size_flags_vertical=Control.SIZE_SHRINK_CENTER;stamp.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_child(stamp);row.move_child(stamp,scene.submit_button.get_index())
	# Decorative quill is pointer-transparent and fixed-aspect, never a copied image.
	var decor:Control=load("res://view/adventure_fieldbook/decor.gd").new();decor.scene=scene;scene.add_child(decor)
