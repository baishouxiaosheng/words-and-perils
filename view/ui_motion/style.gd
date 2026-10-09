extends RefCounted
const UIPresets=preload("res://view/ui_motion/presets.gd")
## Presentation-only type ramp. Never traverses 3D, changes save data or adds fonts.
## One existing Noto Sans CJK family, with regular and synthetic strong weights.
const BODY := 18
const FIELD := 17
const LABEL := 16
const HELP := 15
const HEADING := 20
const TITLE := 24
const INK := Color("334439")
const MUTED := Color("59684f")
const ERROR := Color("843a2b")
const META := &"unified_type_ramp_v1"

static func strong(face: Font) -> Font:
	var result: FontVariation = face.duplicate() if face is FontVariation else FontVariation.new()
	if not face is FontVariation: result.base_font = face
	result.variation_embolden = 0.45
	return result

static func theme_fonts(theme: Theme, face: Font) -> void:
	var bold := strong(face)
	theme.default_font = face; theme.default_font_size = BODY
	for type_ in ["Label", "TextEdit", "LineEdit", "OptionButton", "PopupMenu", "CheckBox", "CheckButton", "TooltipLabel", "Tree", "ItemList", "SpinBox"]:
		theme.set_font("font", type_, face)
		theme.set_font_size("font_size", type_, FIELD if type_ != "TooltipLabel" else HELP)
	theme.set_font("font", "Button", bold); theme.set_font_size("font_size", "Button", FIELD)
	for key in ["normal_font", "italics_font", "mono_font"]: theme.set_font(key, "RichTextLabel", face)
	for key in ["bold_font", "bold_italics_font"]: theme.set_font(key, "RichTextLabel", bold)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]: theme.set_font_size(key, "RichTextLabel", BODY)
	theme.set_font("title_font", "Window", bold); theme.set_font_size("title_font_size", "Window", HEADING)
	theme.set_constant("line_spacing", "Label", 4)
	theme.set_constant("line_spacing", "TextEdit", 4)
	theme.set_constant("line_separation", "RichTextLabel", 6)
	theme.set_constant("v_separation", "PopupMenu", 12)
	theme.set_constant("h_separation", "PopupMenu", 14)
	# AcceptDialog owns its internal button minima and resets Control overrides.
	theme.set_constant("buttons_min_height", "AcceptDialog", 44)
	theme.set_constant("buttons_min_width", "AcceptDialog", 96)
	theme.set_constant("buttons_separation", "AcceptDialog", 14)
	for type_ in ["Label", "TextEdit", "LineEdit", "PopupMenu", "TooltipLabel", "Tree", "ItemList"]:
		theme.set_color("font_color", type_, INK)
		theme.set_color("font_shadow_color", type_, Color.TRANSPARENT)
		theme.set_constant("outline_size", type_, 0)
	theme.set_color("default_color", "RichTextLabel", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("font_placeholder_color", "TextEdit", MUTED)

static func text(control: Control, size_: int, face: Font, bold: bool = false, color: Color = INK) -> void:
	control.add_theme_font_override("font", strong(face) if bold else face)
	control.add_theme_font_size_override("font_size", size_)
	control.add_theme_color_override("font_color", color)
	control.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	control.add_theme_constant_override("outline_size", 0)
	if control is Label:
		control.language = "zh_CN"; control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		control.add_theme_constant_override("line_spacing", 4)

static func paper_button(button_: Button, face: Font, small: bool = false) -> void:
	var primary: bool = button_.get_meta(&"hud_button_role", "") in ["primary", "turn"]
	text(button_, HELP if small else FIELD, face, true, Color("fff8e8") if primary else INK)
	for key in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button_.add_theme_color_override(key, Color("fff8e8") if primary else INK)
	button_.add_theme_color_override("font_disabled_color", Color("c5c6ad") if primary else MUTED)
	if button_.get_meta(&"hud_button_role", "") in ["turn", "round", "compact_round"]: return
	button_.custom_minimum_size.y = maxf(button_.custom_minimum_size.y, 36 if small else 44)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBox = button_.get_theme_stylebox(state).duplicate()
		box.set_content_margin(SIDE_LEFT, 16); box.set_content_margin(SIDE_RIGHT, 16)
		box.set_content_margin(SIDE_TOP, 6); box.set_content_margin(SIDE_BOTTOM, 6)
		button_.add_theme_stylebox_override(state, box)

static func rich_text(control: RichTextLabel, face: Font, size_: int = BODY) -> void:
	for key in ["normal_font", "italics_font", "mono_font"]: control.add_theme_font_override(key, face)
	for key in ["bold_font", "bold_italics_font"]: control.add_theme_font_override(key, strong(face))
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]: control.add_theme_font_size_override(key, size_)
	control.add_theme_color_override("default_color", INK)
	control.add_theme_constant_override("line_separation", 6)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.scroll_active = true

static func paper_tree(node: Node, face: Font) -> void:
	if node is Node3D or node is SubViewport: return
	if node is Label:
		var current: int = node.get_theme_font_size("font_size")
		text(node, HEADING if current >= HEADING else (BODY if current >= BODY else HELP), face, current >= HEADING)
		if node.autowrap_mode != TextServer.AUTOWRAP_OFF: node.custom_minimum_size.x = 0
	elif node is Button: paper_button(node, face, node.get_meta(&"hud_button_role", "") == "compact")
	elif node is RichTextLabel: rich_text(node, face)
	elif node is LineEdit or node is TextEdit:
		text(node, FIELD if node is LineEdit else BODY, face)
		if node is TextEdit: node.add_theme_constant_override("line_spacing", 4)
	for child in node.get_children(): paper_tree(child, face)

static func prepare_scene(scene: Control) -> void:
	if scene.has_meta(META): return
	# Apply the existing C art/spacing first, then one final typography pass,
	# before the original responsive module freezes its physical-pixel baseline.
	var face: Font = scene.hud_font
	theme_fonts(scene.theme, face)
	for group in [scene.hero_panel, scene.action_panel, scene.journal_panel]: paper_tree(group, face)
	text(scene.map_title, TITLE, face, true, Color.WHITE)
	text(scene.turn_counter, HELP, face, false, Color.WHITE)
	text(scene.quest_label, HELP, face, false, Color.WHITE)
	text(scene.hero_label, HEADING, face, true)
	scene.hero_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scene.hero_label.max_lines_visible = 2
	scene.hero_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text(scene.hero_subtitle, HELP, face, false, MUTED)
	text(scene.dialogue_speaker, BODY, face, true)
	text(scene.latest_dialogue, BODY, face)
	for control in [scene.target_label, scene.next_step_label, scene.route_preview_label]: text(control, HELP, face, false, MUTED)
	text(scene.phase_label, HELP, face, true)
	text(scene.history_title, HEADING, face, true)
	text(scene.goal, BODY, face)
	text(scene.submit_button, HEADING, face, true, Color("fff8e8"))
	rich_text(scene.journal, face)
	var veil: StyleBox = scene.journal.get_theme_stylebox("normal").duplicate()
	if veil is StyleBoxFlat: veil.bg_color = Color("f2e6bfee")
	scene.journal.add_theme_stylebox_override("normal", veil)
	for node in scene.get_children():
		if node is AcceptDialog or (node is Window and node.has_meta(&"ui_motion_modal")): install_dialog(node, scene, face)
	for menu in [scene.tools_menu.get_popup(), scene.adventure_menu, scene.advanced_menu, scene.display_menu, scene.focus_choice_popup]:
		menu.theme = scene.theme
	scene.set_meta(META, true)

static func install_dialog(dialog, scene: Control, face: Font) -> void:
	if dialog.has_meta(META): return
	dialog.set_meta(META, true)
	if dialog == scene.v3_setup_dialog: dialog.set_meta(&"preferred_type_extent", Vector2(600, 570))
	dialog.theme = scene.theme.duplicate()
	theme_fonts(dialog.theme, face)
	var paper: StyleBox = dialog.get_theme_stylebox("panel", "AcceptDialog").duplicate()
	paper.set_content_margin(SIDE_LEFT, 24); paper.set_content_margin(SIDE_RIGHT, 24)
	paper.set_content_margin(SIDE_TOP, 20); paper.set_content_margin(SIDE_BOTTOM, 20)
	dialog.add_theme_stylebox_override("panel", paper)
	paper_tree(dialog, face)
	dialog.dialog_autowrap = true
	var content: Array[Control] = []
	for node in dialog.get_children():
		if node is Control and node != dialog.get_label() and node != dialog.get_ok_button().get_parent(): content.append(node)
	# Long form/control containers need an outer scroll lane; existing scroll
	# and self-scrolling text controls keep their native behavior.
	if content.size() == 1 and content[0] is BoxContainer:
		var original: Control = content[0]
		var scroll := ScrollContainer.new(); scroll.name = "TypographyDialogScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		dialog.add_child(scroll); original.reparent(scroll)
		original.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		original.size_flags_vertical = Control.SIZE_EXPAND_FILL
		original.custom_minimum_size.x = 0
		dialog.set_meta(&"type_scroll", scroll)
	if dialog == scene.import_dialog and dialog.has_meta(&"type_scroll"):
		dialog.set_meta(&"type_error_label", scene.import_error_label)
		scene.import_error_label.minimum_size_changed.connect(func():
			if dialog.visible and not scene.import_error_label.text.is_empty(): reveal_after_layout(dialog.get_meta(&"type_scroll"), scene.import_error_label))
	dialog.about_to_popup.connect(func(): fit_dialog(dialog, scene.get_viewport_rect().size, face))

static func fit_dialog(dialog, bounds: Vector2, face: Font) -> void:
	paper_tree(dialog, face)
	var desired := Vector2(minf(dialog.size.x, bounds.x - 48), minf(dialog.size.y, bounds.y - 80))
	desired = desired.max(Vector2(320, 240))
	var content_width := maxf(240, desired.x - 56)
	var content_height := maxf(120, desired.y - 124)
	_fit_content(dialog, content_width, content_height)
	dialog.min_size = Vector2i(0, 0)
	dialog.size = Vector2i(desired)
	settle_dialog_size(dialog, desired, bounds)
	paper_button(dialog.get_ok_button(), face)
	if dialog is ConfirmationDialog: paper_button(dialog.get_cancel_button(), face)
	if dialog.has_meta(&"type_error_label") and not dialog.get_meta(&"type_error_label").text.is_empty():
		reveal_after_layout(dialog.get_meta(&"type_scroll"), dialog.get_meta(&"type_error_label"))

static func settle_dialog_size(dialog: Window, desired: Vector2, bounds: Vector2) -> void:
	# Container minimum sizes settle after the popup notification. Apply the
	# bounded window size again then, rather than accepting the stale old minimum.
	await dialog.get_tree().process_frame
	if not is_instance_valid(dialog): return
	await dialog.get_tree().process_frame
	if not is_instance_valid(dialog) or not dialog.visible: return
	# popup_centered(size) applies its requested extent after about_to_popup.
	# Read that settled size now rather than reinstating the previous window size.
	var settled := Vector2(dialog.size)
	if dialog.has_meta(&"preferred_type_extent"): settled = settled.max(dialog.get_meta(&"preferred_type_extent"))
	if dialog.has_meta(&"ui_motion_kind"):
		settled=UIPresets.geometry(dialog.get_meta(&"ui_motion_kind"),bounds,settled,dialog.get_meta(&"ui_motion_options",{})).size
	else:settled = settled.min(bounds - Vector2(48, 80)).max(Vector2(320, 240))
	if dialog.is_embedded() and dialog.has_meta(&"ui_motion_before_layout"):dialog.get_meta(&"ui_motion_before_layout").call()
	dialog.size = Vector2i(settled)
	if dialog.is_embedded(): dialog.position = Vector2i((bounds - Vector2(dialog.size)) * 0.5)
	if dialog.is_embedded() and dialog.has_meta(&"ui_motion_after_layout"):dialog.get_meta(&"ui_motion_after_layout").call()

static func reveal_after_layout(scroll: ScrollContainer, control: Control) -> void:
	await scroll.get_tree().process_frame
	if not is_instance_valid(scroll) or not is_instance_valid(control): return
	await scroll.get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(control): scroll.ensure_control_visible(control)


static func _fit_content(node: Node, width: float, height: float) -> void:
	for child in node.get_children():
		if child is Control:
			var c: Control = child
			c.custom_minimum_size.x = minf(c.custom_minimum_size.x, width)
			if c is ScrollContainer:
				c.custom_minimum_size = Vector2(minf(c.custom_minimum_size.x, width), minf(maxf(c.custom_minimum_size.y, 120), height))
			elif c is RichTextLabel or c is TextEdit:
				c.custom_minimum_size = Vector2(minf(c.custom_minimum_size.x, width), minf(maxf(c.custom_minimum_size.y, 120), height))
			elif c is Label:
				# Fixed captions in horizontal rows must keep a real text width;
				# wrapping every Label collapses seed/timeout captions into columns.
				if c.get_parent() is HBoxContainer and (c.size_flags_horizontal & Control.SIZE_EXPAND) == 0:
					c.autowrap_mode = TextServer.AUTOWRAP_OFF
				else:
					c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					c.custom_minimum_size.x = 0
			_fit_content(c, width, height)

static func finish_layout(scene: Control) -> void:
	var bounds: Vector2 = scene.get_viewport_rect().size
	if scene.get_meta(&"dialog_layout_bounds", Vector2.ZERO) != bounds:
		scene.set_meta(&"dialog_layout_bounds", bounds)
		for child in scene.get_children():
			if (child is AcceptDialog or (child is Window and child.has_meta(&"ui_motion_modal"))) and child.visible and child.name != "DualAPISettings": fit_dialog(child, bounds, scene.hud_font)
	var narrow: bool = bounds.x < 1100
	scene.minimap.visible = not narrow
	if not narrow:
		if scene.journal_panel.has_meta(&"regular_paper_margin"):
			scene.journal_panel.add_theme_stylebox_override("panel", scene.journal_panel.get_meta(&"regular_paper_margin"))
		return
	# A short desktop window gets a left character column and a right writing
	# column. Keep full-size type and four32+px tools; only the decorative map
	# is folded while every navigation action remains available.
	var pad := 18.0
	var hero_width: float = scene.hero_panel.get_combined_minimum_size().x
	var width: float = minf(bounds.x - pad * 2, maxf(540, bounds.x - hero_width - pad * 3))
	scene.action_panel.size.x = width
	scene.action_panel.position.x = bounds.x - width - pad
	scene.hero_panel.position = Vector2(pad, bounds.y - scene.hero_panel.get_combined_minimum_size().y - pad)
	var tools: Array[Control] = []
	for child in scene.map_cluster.get_children():
		if child is Control and child != scene.minimap: tools.append(child)
	var tool_width := float(tools.size()) * 42.0 + float(maxi(0, tools.size()-1)) * 10.0
	scene.map_cluster.size = Vector2(tool_width, 44)
	scene.map_cluster.position = Vector2(bounds.x - tool_width - pad, pad)
	for index in tools.size(): tools[index].position = Vector2(index * 52.0, 0)
	scene.journal_panel.size.x = width
	var top := 78.0
	var history_height: float = maxf(96, scene.action_panel.position.y - top - 12)
	scene.journal_panel.position = Vector2(scene.action_panel.position.x, top)
	scene.journal_panel.size.y = history_height
	if not scene.journal_panel.has_meta(&"regular_paper_margin"):
		scene.journal_panel.set_meta(&"regular_paper_margin", scene.journal_panel.get_theme_stylebox("panel").duplicate())
	var paper: StyleBox = scene.journal_panel.get_meta(&"regular_paper_margin").duplicate()
	paper.set_content_margin(SIDE_TOP, 12);paper.set_content_margin(SIDE_BOTTOM, 12)
	paper.set_content_margin(SIDE_LEFT, 28);paper.set_content_margin(SIDE_RIGHT, 28)
	scene.journal_panel.add_theme_stylebox_override("panel", paper)
