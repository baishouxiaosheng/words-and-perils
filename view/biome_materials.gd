extends RefCounted
## V2 only. Canonical biome weights arrive in COLOR/UV2, never from text labels.
## Existing v1 material/shader/lighting are deliberately not modified.
const Materials=preload("res://view/miniature_materials.gd")
const ROOT="res://assets/materials/polyhaven/"
const SHADER=preload("res://view/shaders/biome_terrain.gdshader")
static var _ground:ShaderMaterial
static var _software_preview:=false
static var _applied_preview:Variant=null
static func ground_material(software_preview:bool=false)->ShaderMaterial:
	if _ground==null:
		_ground=ShaderMaterial.new();_ground.shader=SHADER;_applied_preview=null
		for kind in ["grass","rock"]:
			var asset="leafy_grass" if kind=="grass" else "rock_face"
			_ground.set_shader_parameter(kind+"_albedo",load(ROOT+asset+"_diff_1k.jpg"))
			_ground.set_shader_parameter(kind+"_normal",load(ROOT+asset+"_nor_gl_1k.png"))
			_ground.set_shader_parameter(kind+"_roughness",load(ROOT+asset+"_rough_1k.jpg"))
		for map in ["albedo","normal","roughness"]:_ground.set_shader_parameter("soil_"+map,Materials.texture("earth_"+map))
	set_software_preview(software_preview)
	return _ground
static func set_software_preview(enabled:bool)->void:
	if enabled==_applied_preview and _ground!=null:return
	_software_preview=enabled
	if _ground!=null:
		_ground.set_shader_parameter("software_preview",enabled);_applied_preview=enabled
static func material_metadata()->Dictionary:
	return {"version":"macro_hex_biomes_v2_only","grass_patch_m":2.0,"soil_patch_m":1.6,"rock_patch_m":2.4,"weights":"linear COLOR.rgb palette; UV2.x soil; UV2.y exposed-rock","plateau_rule":"slope and canonical biome, no absolute-height rock rule","sources":"Poly Haven CC0 grass/rock and original CC0 procedural earth PBR maps","normal_convention":"OpenGL +Y; no source inversion","software_preview":_software_preview}
