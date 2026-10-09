extends RefCounted
## Physical-pixel HUD layout. World rendering remains full-window, at 1:1.
const BASELINE_META := &"responsive_hud_baseline"
const SCALE_META := &"responsive_hud_scale"

static func scale_for(bounds: Vector2) -> float:
	# Extra ultrawide width reveals world rather than inflating the HUD.
	return clampf(minf(bounds.y / 1080.0, bounds.x / 1600.0), 1.0, 1.5)

static func apply(scene: Control) -> void:
	preload("res://view/fullscreen_hud/readability.gd").configure(scene)
	var bounds: Vector2 = scene.get_viewport_rect().size
	var factor := scale_for(bounds)
	var previous: float = scene.get_meta(SCALE_META, -1.0)
	if not is_equal_approx(previous, factor):
		for group in [scene.area_panel, scene.hero_panel, scene.action_panel, scene.journal_panel, scene.dialogue_restore_button]:
			_scale_tree(group, factor)
		for child in scene.map_cluster.get_children():
			if child != scene.minimap: _scale_tree(child, factor)
		scene.theme.default_font_size = roundi(18.0 * factor)
		scene.theme.set_font_size("title_font_size", "Window", roundi(20.0 * factor))
		scene.set_meta(SCALE_META, factor)
	scene.compact_layout = bounds.x < 1400.0 * factor
	var pad := (18.0 if scene.compact_layout else 26.0) * factor
	var logical_width := bounds.x / factor
	var dialogue_width := minf(840.0, logical_width - 600.0) if logical_width >= 1400.0 else minf(700.0, logical_width - 580.0)
	dialogue_width = maxf(540.0, dialogue_width)
	if logical_width < 1000.0: dialogue_width = logical_width - 32.0
	dialogue_width *= factor
	scene.goal.custom_minimum_size.y = (144.0 if scene.intent_expanded else 80.0) * factor
	var dock_height := (270.0 if scene.intent_expanded else 198.0) * factor
	scene.action_panel.size = Vector2(dialogue_width, dock_height)
	var measured: float = maxf(dock_height, scene.action_panel.get_combined_minimum_size().y)
	scene.action_panel.size.y = measured
	scene.action_panel.position = Vector2((bounds.x - dialogue_width) * 0.5, bounds.y - measured - pad)
	scene.hero_panel.size = Vector2.ZERO
	var hero_size: Vector2 = scene.hero_panel.get_combined_minimum_size()
	scene.hero_panel.position = Vector2(pad, bounds.y - hero_size.y - pad)
	if logical_width < 1200.0: scene.hero_panel.position = Vector2(pad, 100.0 * factor)
	scene.area_panel.position = Vector2(pad, pad)
	# Reserve only occupied title width for action framing.
	var title_width: float = maxf(scene.map_title.get_minimum_size().x, scene.turn_counter.get_minimum_size().x)
	if scene.quest_label.visible:
		var quest_font: Font = scene.quest_label.get_theme_font("font")
		var quest_width := quest_font.get_string_size(scene.quest_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, scene.quest_label.get_theme_font_size("font_size")).x
		title_width = maxf(title_width, minf(500.0 * factor, quest_width))
	scene.area_panel.size = Vector2(minf(title_width, bounds.x - 300.0 * factor), scene.area_panel.get_combined_minimum_size().y)
	scene.map_cluster.scale = Vector2.ONE
	scene.map_cluster.size = Vector2(230.0, 260.0) * factor
	scene.map_cluster.position = Vector2(bounds.x - scene.map_cluster.size.x - pad, pad)
	scene.minimap.position = Vector2(0, 5.0) * factor
	scene.minimap.size = Vector2(206, 206)
	scene.minimap.scale = Vector2.ONE * factor
	for child in scene.map_cluster.get_children():
		if child == scene.minimap: continue
		if not child.has_meta(&"responsive_map_position"):
			child.set_meta(&"responsive_map_position", child.position)
		child.position = child.get_meta(&"responsive_map_position") * factor
		child.size = child.get_combined_minimum_size()
	var history_height := maxf(120.0 * factor, minf(320.0 * factor, scene.action_panel.position.y - 90.0 * factor))
	scene.journal_panel.position = Vector2(scene.action_panel.position.x, scene.action_panel.position.y - history_height - 10.0 * factor)
	scene.journal_panel.size = Vector2(dialogue_width, history_height)
	scene.journal_panel.visible = scene.journal_open and not scene.dialogue_hidden_for_map
	if is_instance_valid(scene.dialogue_restore_button):
		scene.dialogue_restore_button.position = Vector2((bounds.x - 42.0 * factor) * 0.5, bounds.y - 58.0 * factor)

static func _scale_tree(node: Node, factor: float) -> void:
	if node is Control:
		var control := node as Control
		if not control.has_meta(BASELINE_META):
			var data: Dictionary = {"minimum": control.custom_minimum_size, "fonts": {}, "constants": {}, "styles": {}}
			if control is Label or control is Button or control is TextEdit:
				data.fonts["font_size"] = control.get_theme_font_size("font_size")
			elif control is RichTextLabel:
				for font_key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
					data.fonts[font_key] = control.get_theme_font_size(font_key)
			for key in ["separation", "h_separation", "v_separation", "line_spacing", "line_separation", "icon_max_width"]:
				if control.has_theme_constant_override(key): data.constants[key] = control.get_theme_constant(key)
			for key in ["panel", "normal", "hover", "pressed", "hover_pressed", "disabled", "focus", "read_only"]:
				if control.has_theme_stylebox_override(key): data.styles[key] = control.get_theme_stylebox(key).duplicate()
			control.set_meta(BASELINE_META, data)
		var baseline: Dictionary = control.get_meta(BASELINE_META)
		control.custom_minimum_size = baseline.minimum * factor
		if control is Button:
			control.custom_minimum_size = control.custom_minimum_size.max(Vector2.ONE * 32.0 * factor)
			if control.icon != null:
				control.expand_icon = true
				var width: int = int(baseline.constants.get("icon_max_width", control.icon.get_width()))
				control.add_theme_constant_override("icon_max_width", roundi(width * factor))
		for key in baseline.fonts: control.add_theme_font_size_override(key, roundi(baseline.fonts[key] * factor))
		for key in baseline.constants: control.add_theme_constant_override(key, roundi(baseline.constants[key] * factor))
		for key in baseline.styles:
			var style: StyleBox = baseline.styles[key].duplicate()
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				style.set_content_margin(side, baseline.styles[key].get_content_margin(side) * factor)
				if style is StyleBoxTexture: style.set_texture_margin(side, baseline.styles[key].get_texture_margin(side) * factor)
			control.add_theme_stylebox_override(key, style)
	for child in node.get_children():
		if child is Control: _scale_tree(child, factor)
