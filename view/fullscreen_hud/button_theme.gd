extends RefCounted
## Shallow original fantasy tablets. Borders are sized for the actual 36–44px
## control, so decorative corners cannot collapse into the text band.
const Craft = preload("res://view/ui_craft.gd")
const INK := Color("2c423b")
const MUTED := Color("667064")
static var _textures: Dictionary = {}
static var _strong: FontVariation

static func strong_font() -> Font:
	if _strong == null:
		_strong = FontVariation.new()
		_strong.base_font = Craft.font("body")
		_strong.variation_embolden = 0.5
	return _strong

static func apply(button: Button, role: String = "secondary") -> void:
	var round_ := role in ["round", "compact_round", "turn"]
	var primary := role in ["primary", "turn"]
	var compact := role in ["compact", "compact_round"]
	button.add_theme_font_override("font", strong_font())
	button.add_theme_font_size_override("font_size", 18 if role == "turn" else (15 if compact else 16))
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_constant_override("shadow_outline_size", 0)
	button.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	button.add_theme_constant_override("h_separation", 8)
	button.add_theme_constant_override("icon_max_width", 18 if compact else 20)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if round_ else HORIZONTAL_ALIGNMENT_LEFT
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.expand_icon = button.icon != null
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var minimum := 36.0 if compact else 42.0
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, minimum)
	if round_:
		var diameter := 88.0 if role == "turn" else minimum
		button.custom_minimum_size = Vector2.ONE * diameter
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, surface(role, state))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color("fff6dd") if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color("d7d3b8") if primary else Color("677267"))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("376f69")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(64 if round_ else 5)
	focus.expand_margin_left = 2; focus.expand_margin_right = 2
	focus.expand_margin_top = 2; focus.expand_margin_bottom = 2
	button.add_theme_stylebox_override("focus", focus)
	button.set_meta(&"hud_button_role", role)

static func surface(role: String, state: String = "normal") -> StyleBoxTexture:
	var kind := "turn" if role=="turn" else ("round" if role in ["round","compact_round"] else ("primary" if role=="primary" else "button"))
	var box := preload("res://view/adventure_fieldbook/skin.gd").surface(kind,0 if kind in ["turn","round"] else 10,state)
	return box

static func writing_surface(focused := false, readonly := false) -> StyleBoxTexture:
	var box := preload("res://view/adventure_fieldbook/skin.gd").surface("writing_focus" if focused else "writing",12,"disabled" if readonly else "normal")
	if focused: box.modulate_color=Color(1.025,1.02,1)
	return box
