extends Node
## Optional reversible visual profile. Never touches source/cache geometry or game state.
const ROOT:="res://artifacts/integrated_ecology_world_20261002/lighting_profile/"
const MANIFEST_SHA:="4c24e15b8ab9339d1d27b73a069a930d220135fbf70e0fdd15980a92c9359809"
const GROUND:=preload("res://view/integrated_ecology_world/lighting_profile/ground_contact.gdshader")
const VEGETATION:=preload("res://view/integrated_ecology_world/lighting_profile/vegetation_contact.gdshader")
var view:Node3D
var enabled:=false
var last_error:=""
var field:Texture2D
var field_manifest:Dictionary={}
var ground_shaders:Dictionary={}
var tree_shaders:Dictionary={}
var lights:Array=[]
var environment_states:Array=[]
var previous_tree_visibility:=true
var style:="subtle"
var contact_strength:=.36
static func attach_to(world_view:Node3D,style_name:String="subtle")->Node:
	var existing:=world_view.get_node_or_null("MiniatureVisualProfile")
	if existing!=null:existing.style=style_name;existing.set_enabled(true);return existing
	var profile:Node=load("res://view/integrated_ecology_world/lighting_profile/miniature_profile.gd").new();profile.name="MiniatureVisualProfile";profile.style=style_name;world_view.add_child(profile)
	if not profile.initialize(world_view):return profile
	profile.set_enabled(true);return profile
func initialize(world_view:Node3D)->bool:
	view=world_view
	if FileAccess.get_sha256(ROOT+"manifest.json")!=MANIFEST_SHA:last_error="Visual contact field manifest changed";return false
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"manifest.json"))
	if not parsed is Dictionary:last_error="Visual contact field manifest missing";return false
	field_manifest=parsed
	if not is_instance_valid(view.whole_canopies) or view.whole_canopies.manifest.runtime.sha256!=field_manifest.source_instance_sha256:last_error="Visual contact field needs matching natural_v2 instances";return false
	if FileAccess.get_sha256(ROOT+str(field_manifest.file))!=field_manifest.sha256:last_error="Visual contact field SHA mismatch";return false
	var packed:=FileAccess.get_file_as_bytes(ROOT+str(field_manifest.file));var raw:=packed.decompress(int(field_manifest.decoded_bytes),FileAccess.COMPRESSION_GZIP)
	if raw.size()!=int(field_manifest.width)*int(field_manifest.height):last_error="Visual contact field decoded size mismatch";return false
	var im:=Image.create_from_data(int(field_manifest.width),int(field_manifest.height),false,Image.FORMAT_R8,raw);im.generate_mipmaps();field=ImageTexture.create_from_image(im)
	for mat in view.compact_materials:ground_shaders[mat]=mat.shader
	ground_shaders[view.ground_material]=view.ground_material.shader
	_refresh_tree_materials()
	view.whole_canopies_changed.connect(_canopies_changed)
	for node in view.get_children():
		if node is DirectionalLight3D:lights.append({"node":node,"color":node.light_color,"energy":node.light_energy,"rotation":node.rotation_degrees})
		elif node is WorldEnvironment:
			var e:Environment=node.environment;environment_states.append({"environment":e,"ambient":e.ambient_light_energy,"color":e.ambient_light_color,"background":e.background_color})
	return true
func _refresh_tree_materials()->void:
	var current:Dictionary={}
	for root_ in [view.whole_canopies,view.vegetation_root]:
		if not is_instance_valid(root_):continue
		for node in root_.get_children():
			if node is MultiMeshInstance3D and node.material_override is ShaderMaterial:
				var material:ShaderMaterial=node.material_override
				current[material]=tree_shaders.get(material,material.shader)
	# Restore and release retired material keys before their canopy root is freed.
	for material in tree_shaders:
		if not current.has(material):material.shader=tree_shaders[material]
	tree_shaders=current
func _canopies_changed()->void:
	_refresh_tree_materials()
	var strength:=contact_strength
	set_enabled(enabled)
	# Entity changes may have disabled the static field; don't resurrect it while
	# rebinding shaders. The selection consumer will reapply its sparse state.
	contact_strength=strength
	for material in ground_shaders:material.set_shader_parameter("canopy_contact_strength",strength if enabled and view.trees_enabled else 0.0)
func set_enabled(value:bool)->void:
	if not last_error.is_empty() or field==null:return
	enabled=value;contact_strength=.54 if style=="miniature" else .36
	for mat in ground_shaders:
		mat.shader=GROUND if value else ground_shaders[mat]
		if value:
			mat.set_shader_parameter("canopy_contact_field",field);mat.set_shader_parameter("contact_field_min",Vector2(field_manifest.world_min_xz[0],field_manifest.world_min_xz[1]));mat.set_shader_parameter("contact_field_extent",Vector2(field_manifest.world_extent_xz[0],field_manifest.world_extent_xz[1]));mat.set_shader_parameter("canopy_contact_strength",contact_strength if view.trees_enabled else 0.0)
	for mat in tree_shaders:mat.shader=VEGETATION if value else tree_shaders[mat]
	var setup:=[[Color("fff0d5"),1.14,Vector3(-42,-38,0)],[Color("9dbbeb"),.20,Vector3(-24,128,0)],[Color("d8eeff"),.30,Vector3(-28,-130,0)]]
	if style=="miniature":setup=[[Color("ffeacb"),1.34,Vector3(-48,-38,0)],[Color("9cb9ee"),.15,Vector3(-24,128,0)],[Color("c7e5ff"),.28,Vector3(-28,-130,0)]]
	for i in range(lights.size()):
		var old:Dictionary=lights[i];var l:DirectionalLight3D=old.node
		l.light_color=setup[i][0] if value and i<3 else old.color;l.light_energy=setup[i][1] if value and i<3 else old.energy;l.rotation_degrees=setup[i][2] if value and i<3 else old.rotation
	for old in environment_states:
		var e:Environment=old.environment;e.ambient_light_energy=(.20 if style=="miniature" else .29) if value else old.ambient;e.ambient_light_color=Color("c5d2ed") if value else old.color;e.background_color=Color("788f9b") if value else old.background
	previous_tree_visibility=view.trees_enabled
func _process(_delta:float)->void:
	if not enabled or not is_instance_valid(view):return
	if previous_tree_visibility!=view.trees_enabled:
		previous_tree_visibility=view.trees_enabled
		for mat in ground_shaders:mat.set_shader_parameter("canopy_contact_strength",contact_strength if previous_tree_visibility else 0.0)
func report()->Dictionary:
	return {"enabled":enabled,"error":last_error,"visual_contact_field_bytes":field_manifest.get("bytes",0),"source_masks_or_heights_changed":false,"lighting":"WARM_KEY_COOL_FILL_PALE_RIM","realtime_shadow_maps":false,"screen_space_ambient_occlusion":false,"contact_field_is_static_visual_approximation":true,"max_contact_ground_attenuation":contact_strength,"style":style}
