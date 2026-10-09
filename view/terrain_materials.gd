extends RefCounted
## Continuous, physically lit CC0 terrain. This does not alter terrain geometry.
## Call set_software_preview() to update the material already held by board meshes.
const ROOT := "res://assets/materials/polyhaven/"
const SURFACE_SHADER = preload("res://view/shaders/terrain_surface.gdshader")
static var _ground: ShaderMaterial
static var _software_preview := false

static func ground_material(software_preview: bool = false) -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = SURFACE_SHADER
		for kind in ["grass", "rock"]:
			var asset: String = "leafy_grass" if kind == "grass" else "rock_face"
			_ground.set_shader_parameter(kind + "_albedo", load(ROOT + asset + "_diff_1k.jpg"))
			_ground.set_shader_parameter(kind + "_normal", load(ROOT + asset + "_nor_gl_1k.png"))
			_ground.set_shader_parameter(kind + "_roughness", load(ROOT + asset + "_rough_1k.jpg"))
	set_software_preview(software_preview)
	return _ground

static func set_software_preview(enabled: bool) -> void:
	_software_preview = enabled
	if _ground != null:
		_ground.set_shader_parameter("software_preview", enabled)
		_ground.resource_name = "Terrain · software preview PBR" if enabled else "Terrain · detailed PBR"

static func quality_label() -> String:
	return "Software preview PBR (reduced rock normal projections)" if _software_preview else "Detailed PBR (triplanar rock normals)"

static func material_metadata() -> Dictionary:
	return {
		"source": ROOT + "provenance.json",
		"license": "CC0-1.0",
		"grass_patch_m": 2.0,
		"rock_patch_m": 2.4,
		"normal_convention": "OpenGL +Y, no green-channel inversion",
		"quality": quality_label(),
		"geometry_changed": false,
	}
