extends RefCounted
## Original physical UI material hierarchy. Does not touch 3D materials or state.
const ROOT := "res://assets/ui/"
static var _textures: Dictionary = {}
static var _fonts: Dictionary = {}
# Native CJK typography: complete sans for arbitrary content; small OFL serif
# subsets for editorial titles and important actions. No system font fallback.
static func font(role: String = "body") -> Font:
	if _fonts.is_empty():
		var full: FontFile = load("res://assets/NotoSansCJK-Regular.ttc").duplicate()
		full.allow_system_fallback = false
		var body := FontVariation.new()
		body.base_font = full
		body.variation_face_index = 2 # Simplified Chinese, not TTC's default JP face.
		_fonts["body"] = body
		for pair in [["display", "Regular"], ["action", "Bold"]]:
			var face: FontFile = load("res://assets/fonts/MistbankSerifUI-" + pair[1] + ".otf").duplicate()
			face.allow_system_fallback = false
			face.fallbacks = [body]
			_fonts[pair[0]] = face
	return _fonts.get(role, _fonts["body"])
static func dropdown_icon() -> Texture2D:
	if not _textures.has("dropdown_native"):
		var img := Image.new()
		img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><path d="m3 4.5 3 3 3-3" fill="none" stroke="#f2ead7" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',2.0)
		img.resize(12,12,Image.INTERPOLATE_LANCZOS)
		_textures["dropdown_native"] = ImageTexture.create_from_image(img)
	return _textures["dropdown_native"]
static func text_style(control: Control, role: String = "body") -> void:
	control.add_theme_font_override("font", font(role))
	control.add_theme_constant_override("outline_size", 0)
	control.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	if control is Label:
		control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		control.language = "zh_CN"

static func texture(name_: String) -> Texture2D:
	if not _textures.has(name_): _textures[name_] = load(ROOT + name_ + ".png")
	return _textures[name_]
static func surface(kind: String, pad: float = 4.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = texture(kind)
	var edge := 6.0
	if kind == "map_mount": edge = 4.0
	elif kind == "journal": edge = 14.0
	elif kind == "rail": edge = 8.0
	elif kind.begins_with("writing"): edge = 4.0
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, edge)
		s.set_content_margin(side, pad)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	if kind in ["journal","document","writing","writing_focus","writing_readonly"] or kind.begins_with("primary") or kind.begins_with("secondary") or kind.begins_with("tool"):
		s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return s
static func button_style(role: String, state: String, pad: float = 4.0) -> StyleBoxTexture:
	var s := surface(role + "_" + state, pad)
	# Horizontal clearance protects the cut corners and separates icon / label.
	# CJK font height already includes its em-square side bearings; an extra
	# bottom pixel optically centers the face rather than copying Latin metrics.
	var inset := 12.0 if pad <= 4.0 else 16.0
	var top := 2.0 if pad <= 4.0 else 5.0
	s.set_content_margin(SIDE_LEFT, inset)
	s.set_content_margin(SIDE_RIGHT, inset)
	s.set_content_margin(SIDE_TOP, top)
	s.set_content_margin(SIDE_BOTTOM, top + 1.0)
	return s
static func focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = Color("ceb98a")
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s
static func apply_button(b: Button, role: String = "secondary", pad: float = 4.0) -> void:
	text_style(b, "action" if role == "primary" else "body")
	b.add_theme_constant_override("h_separation", 7)
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, button_style(role, state, pad))
	b.add_theme_stylebox_override("focus", focus_style())
	var dark := role == "secondary"
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color("283c34") if dark else Color("f8f0d9"))
	b.add_theme_color_override("font_disabled_color", Color("74796b") if dark else Color("b1b6a0"))
	b.add_theme_color_override("icon_disabled_color", Color(0.7,0.7,0.65,0.55))
