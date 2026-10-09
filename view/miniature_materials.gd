extends RefCounted
## Shared original PBR texture library. Geometry stays untouched.
## Intended for Godot 4.6 Compatibility; neutral maps preserve semantic color.
const ROOT := "res://assets/materials/"
const RANGE_SHADER = preload("res://view/shaders/miniature_range.gdshader")
static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var _frames: Dictionary = {}

static func texture(name_: String) -> Texture2D:
	if not _textures.has(name_):
		_textures[name_] = load(ROOT + name_ + ".png")
	return _textures[name_]

static func _pbr(kind: String, color: Color, metallic: float, roughness: float, scale_: float, normal_strength: float, world: bool = true) -> StandardMaterial3D:
	var key := "%s:%s:%s:%s:%s:%s:%s" % [kind,color.to_html(),metallic,roughness,scale_,normal_strength,world]
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture(kind + "_albedo")
	mat.metallic = metallic
	mat.roughness = roughness
	mat.roughness_texture = texture(kind + "_roughness")
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.normal_enabled = true
	mat.normal_texture = texture(kind + "_normal")
	mat.normal_scale = normal_strength
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = world
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3.ONE * scale_
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = mat
	return mat

static func ground_material() -> StandardMaterial3D:
	var mat := _pbr("earth",Color.WHITE,0.0,1.0,0.72,0.48)
	# TerrainField writes linear vertex colors explicitly. Never convert twice.
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic_specular = 0.26
	return mat

static func stone_material(color: Color = Color("b7ad94")) -> StandardMaterial3D:
	var mat := _pbr("limestone",color,0.0,1.0,1.12,0.56)
	mat.metallic_specular = 0.32
	return mat

static func wood_material(color: Color = Color("a38c67")) -> StandardMaterial3D:
	var mat := _pbr("oak",color,0.0,1.0,1.3,0.38,false)
	mat.metallic_specular = 0.3
	return mat

static func token_stone_material(color: Color, rough: float = 0.43) -> StandardMaterial3D:
	# High-range microvariation map is calibrated around 0.93.
	var mat := _pbr("marble",color,0.025,clampf(rough / 0.93,0.05,1.0),2.0,0.25,false)
	mat.metallic_specular = 0.44
	return mat

static func metal_material(color: Color, metallic: float = 0.63, rough: float = 0.37) -> StandardMaterial3D:
	if metallic < 0.25:
		# Enamel, dark recesses and felt are not brushed metal.
		var key := "enamel:%s:%s:%s" % [color.to_html(),metallic,rough]
		if not _materials.has(key):
			var dielectric := StandardMaterial3D.new()
			dielectric.albedo_color = color
			dielectric.metallic = metallic
			dielectric.roughness = rough
			_materials[key] = dielectric
		return _materials[key]
	var mat := _pbr("brass",color,metallic,clampf(rough / 0.93,0.05,1.0),2.0,0.23,false)
	mat.metallic_specular = 0.5
	return mat

static func parchment_texture() -> Texture2D:
	return texture("parchment")

static func frame_style(color: Color, border: Color = Color("a48b5b"), pad: float = 12.0, kind: String = "parchment") -> StyleBoxTexture:
	var key := color.to_html() + ":" + border.to_html() + ":" + kind
	if not _frames.has(key):
		var source_name := "panel_parchment"
		match kind:
			"dark": source_name = "panel_dark"
			"pressed": source_name = "panel_pressed"
			"button": source_name = "panel_button"
			"button_pressed": source_name = "panel_button_pressed"
			"field": source_name = "panel_field"
		var source := texture(source_name)
		var image := source.get_image()
		image.convert(Image.FORMAT_RGBA8)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x,y)
				var edge := mini(mini(x,y),mini(image.get_width()-1-x,image.get_height()-1-y))
				var tint := color
				var trim_width := 1 if kind == "field" else (2 if kind.begins_with("button") else 3)
				if edge < trim_width:
					# Border is independently tinted. Preserve bevel's direction and luminance.
					var luminance := pixel.r * 0.30 + pixel.g * 0.59 + pixel.b * 0.11
					var highlight := clampf(luminance / 0.53,0.64,1.18)
					tint = Color(border.r*highlight,border.g*highlight,border.b*highlight,color.a)
					pixel = Color(1.0,1.0,1.0,pixel.a)
				image.set_pixel(x,y,Color(pixel.r*tint.r,pixel.g*tint.g,pixel.b*tint.b,pixel.a*tint.a))
		_frames[key] = ImageTexture.create_from_image(image)
	var style := StyleBoxTexture.new()
	style.texture = _frames[key]
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,3.0 if kind == "field" else (4.0 if kind.begins_with("button") else 12.0))
		style.set_content_margin(side,pad)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style

static func range_material(color: Color = Color(0.32,0.79,0.66,0.14)) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RANGE_SHADER
	mat.set_shader_parameter("range_color",color)
	return mat

static func lighting_recipe() -> Dictionary:
	return {
		"background":Color("18252a"),
		"ambient_color":Color("98b6cb"),
		"ambient_energy":0.42,
		"sun_color":Color("ffe1aa"),
		"sun_energy":1.1,
		"sun_rotation":Vector3(-48,-34,0),
		"shadow_normal_bias":0.16,
		"shadow_bias":0.045,
		"shadow_max_distance":30.0,
		"glow_intensity":0.32,
		"ssao_radius":0.4,
		"ssao_intensity":0.6,
	}
