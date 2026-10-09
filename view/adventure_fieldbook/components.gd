extends RefCounted
## Assets are injected; no missing-file preloads. Caller owns texture logical size.
const Tokens = preload("tokens.gd")
const SIGNAL_MAP = {
	"submit_button": {"signal": "pressed", "callback": "end_turn", "press_mode": true},
	"journal_toggle": {"signal": "pressed", "callback": "toggle_journal"},
	"intent_expand_button": {"signal": "pressed", "callback": "toggle_intent"},
	"minimap": {"signal": "activated", "callback": "toggle_overview"},
	"dialogue_restore_button": {"signal": "pressed", "callback": "set_map_dialogue_hidden", "args": [false]},
}
var _cache: Dictionary = {}

func _flat_bg(state: String, slot: String) -> Color:
	if slot == "history_base": return Tokens.HISTORY_BG
	if state == "disabled": return Tokens.PARCHMENT_MID.darkened(0.10)
	var base: Color = Tokens.TEAL if slot == "turn_button" else Tokens.PARCHMENT
	if state == "hover": return base.lightened(0.08)
	if state in ["pressed", "hover_pressed"]: return base.darkened(0.10)
	return base

## slots is this slot's field overrides, not the entire slot registry.
## Texture history preserves its baked alpha; optional opacity applies once.
func style(slot: String, textures: Dictionary = {}, state: String = "normal", factor: float = 1.0, slots: Dictionary = {}) -> StyleBox:
	var definition: Dictionary = Tokens.new().merged_slot(slot, slots)
	var pad: Array = definition.get("padding", [8, 8, 8, 8])
	var cuts: Array = definition.get("slice", [0, 0, 0, 0])
	var tex: Texture2D = textures.get(slot + "_" + state, textures.get(slot, null))
	var texture_id: int = tex.get_instance_id() if tex != null else 0
	var key: Array = [slot, state, factor, texture_id, definition.hash()]
	if _cache.has(key): return (_cache[key] as StyleBox).duplicate()
	var result: StyleBox
	if tex != null:
		var box := StyleBoxTexture.new()
		box.texture = tex
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			box.set_texture_margin(side, 0.0 if bool(definition.get("uniform", false)) else float(cuts[side]))
		var tint := Color.WHITE
		if not textures.has(slot + "_" + state):
			if state == "hover": tint = Color(1.08, 1.05, 1.0)
			elif state in ["pressed", "hover_pressed"]: tint = Color(0.88, 0.84, 0.80)
			elif state == "disabled": tint = Color(0.82, 0.82, 0.82)
		tint.a = float(definition.get("opacity", 1.0))
		box.modulate_color = tint
		result = box
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = _flat_bg(state, slot)
		box.border_color = Tokens.BRASS_LIGHT if state == "hover" else Tokens.LEATHER
		box.set_border_width_all(maxi(1, roundi(Tokens.BORDER_WIDTH * factor)))
		box.set_corner_radius_all(roundi((72 if slot == "turn_button" else Tokens.BORDER_RADIUS) * factor))
		result = box
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_content_margin(side, float(pad[side]) * factor)
	_cache[key] = result
	return result.duplicate()

func focus_style(factor: float = 1.0) -> StyleBox:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.border_color = Tokens.FOCUS_RING
	box.set_border_width_all(maxi(1, ceili(2.0 * factor)))
	box.set_corner_radius_all(Tokens.BORDER_RADIUS + 1)
	return box

func panel(slot: String, textures: Dictionary = {}, state: String = "normal", factor: float = 1.0, slots: Dictionary = {}) -> PanelContainer:
	var control := PanelContainer.new()
	control.add_theme_stylebox_override("panel", style(slot, textures, state, factor, slots))
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	return control

## Styling only: never reconnect signals or change action_mode/text/disabled.
func decorate_button(button: Button, slot: String, textures: Dictionary = {}, factor: float = 1.0, slots: Dictionary = {}) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, style(slot, textures, state, factor, slots))
	button.add_theme_stylebox_override("focus", focus_style(factor))
	var ink: Color = Tokens.PARCHMENT if slot == "turn_button" else Tokens.INK
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", ink if textures.has(slot) else Tokens.INK_DISABLED)

func clear_cache() -> void:
	_cache.clear()

## Uniform noninteractive frames use this helper to preserve aspect in any bounds.
func decoration(slot: String, textures: Dictionary = {}, factor: float = 1.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = textures.get(slot, null)
	var definition: Dictionary = Tokens.new().merged_slot(slot)
	node.custom_minimum_size = Vector2(definition.get("size", Vector2i(32, 32))) * factor
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
