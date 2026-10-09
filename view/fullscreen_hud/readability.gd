extends RefCounted
## A small type ramp and comfortable content bounds, applied before responsive
## baselines are cached. Does not alter world-name typography or font AA imports.
const Craft = preload("res://view/ui_craft.gd")
const Buttons = preload("res://view/fullscreen_hud/button_theme.gd")
const BODY_SIZE := 18
const BODY_LINE := 28
const META := &"readable_hud_configured"

static func configure(scene: Control) -> void:
	if scene.has_meta(META): return
	scene.set_meta(META, true)
	var body := Craft.font("body")
	var strong := Buttons.strong_font()
	scene.theme.default_font = body
	scene.theme.default_font_size = BODY_SIZE
	scene.theme.set_font("normal_font", "RichTextLabel", body)
	scene.theme.set_font("bold_font", "RichTextLabel", strong)
	scene.theme.set_font("title_font", "Window", strong)
	scene.theme.set_font_size("title_font_size", "Window", 20)
	for type_ in ["TextEdit", "LineEdit"]:
		scene.theme.set_stylebox("normal", type_, Buttons.writing_surface())
		scene.theme.set_stylebox("focus", type_, Buttons.writing_surface(true))
		scene.theme.set_stylebox("read_only", type_, Buttons.writing_surface(false, true))
		scene.theme.set_font("font", type_, body)
		scene.theme.set_color("font_color", type_, Buttons.INK)
		scene.theme.set_color("font_placeholder_color", type_, Color("66705f"))
		scene.theme.set_color("font_readonly_color", type_, Color("596759"))
		scene.theme.set_constant("line_spacing", type_, maxi(2, BODY_LINE - ceili(body.get_height(BODY_SIZE))))
	_font(scene.latest_dialogue, body, BODY_SIZE)
	scene.latest_dialogue.add_theme_constant_override("line_spacing", maxi(2, BODY_LINE - ceili(body.get_height(BODY_SIZE))))
	scene.latest_dialogue.custom_minimum_size.y = BODY_LINE
	_font(scene.dialogue_speaker, strong, 17)
	scene.dialogue_speaker.add_theme_color_override("font_color", Color("75553d"))
	_font(scene.target_label, body, 14)
	_font(scene.phase_label, strong, 14)
	_font(scene.next_step_label, body, 14)
	_font(scene.hero_label, strong, 21)
	_font(scene.hero_subtitle, body, 13)
	for secondary in [scene.hero_subtitle, scene.target_label, scene.next_step_label]:
		secondary.add_theme_color_override("font_color", Color("526150"))
	_font(scene.map_title, strong, 25)
	_font(scene.turn_counter, body, 15)
	_font(scene.quest_label, body, 15)
	_font(scene.history_title, strong, 20)
	_font(scene.goal, body, BODY_SIZE)
	scene.goal.add_theme_stylebox_override("normal", Buttons.writing_surface())
	scene.goal.add_theme_stylebox_override("focus", Buttons.writing_surface(true))
	scene.goal.add_theme_stylebox_override("read_only", Buttons.writing_surface(false, true))
	scene.goal.add_theme_constant_override("line_spacing", maxi(2, BODY_LINE - ceili(body.get_height(BODY_SIZE))))
	scene.journal.add_theme_font_override("normal_font", body)
	scene.journal.add_theme_font_override("bold_font", strong)
	scene.journal.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	scene.journal.add_theme_font_size_override("bold_font_size", BODY_SIZE)
	scene.journal.add_theme_constant_override("line_separation", maxi(2, BODY_LINE - ceili(body.get_height(BODY_SIZE))))
	# Distinct alignment: prose is left anchored; action labels are centered.
	scene.latest_dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Buttons.apply(scene.journal_toggle, "compact")
	scene.journal_toggle.toggle_mode = true
	scene.journal_toggle.custom_minimum_size.x = 100
	Buttons.apply(scene.intent_expand_button, "compact_round")
	for child in scene.target_row.get_children():
		if child is Button: Buttons.apply(child, "compact_round")
	var history_head: Node = scene.history_title.get_parent()
	for child in history_head.get_children():
		if child is Button: Buttons.apply(child, "compact_round")
	Buttons.apply(scene.submit_button, "turn")
	scene.submit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scene.submit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scene.submit_button.custom_minimum_size = Vector2(88, 88)
	var header: HBoxContainer = scene.dialogue_speaker.get_parent()
	header.add_theme_constant_override("separation", 10)
	var prose: VBoxContainer = header.get_parent()
	prose.add_theme_constant_override("separation", 7)
	var speech: StyleBox = scene.speech_panel.get_theme_stylebox("panel").duplicate()
	speech.set_content_margin(SIDE_LEFT, 58); speech.set_content_margin(SIDE_RIGHT, 58)
	speech.set_content_margin(SIDE_TOP, 18); speech.set_content_margin(SIDE_BOTTOM, 30)
	scene.speech_panel.add_theme_stylebox_override("panel", speech)
	# The clear writing face must sit inside the shaped frame, not paint over it.
	var base: StyleBox = scene.action_base.get_theme_stylebox("panel").duplicate()
	base.set_content_margin(SIDE_LEFT, 44); base.set_content_margin(SIDE_RIGHT, 24)
	base.set_content_margin(SIDE_TOP, 32); base.set_content_margin(SIDE_BOTTOM, 32)
	scene.action_base.add_theme_stylebox_override("panel", base)
	var history: StyleBox = scene.journal_panel.get_theme_stylebox("panel").duplicate()
	history.set_content_margin(SIDE_LEFT, 58); history.set_content_margin(SIDE_RIGHT, 58)
	scene.journal_panel.add_theme_stylebox_override("panel", history)
	var action_column: VBoxContainer = scene.speech_panel.get_parent()
	action_column.add_theme_constant_override("separation", 8)
	var input_row: HBoxContainer = scene.goal.get_parent()
	input_row.add_theme_constant_override("separation", 12)

	preload("res://view/adventure_fieldbook/skin.gd").configure(scene)

static func _font(control: Control, face: Font, size_: int) -> void:
	control.add_theme_font_override("font", face)
	control.add_theme_font_size_override("font_size", size_)
