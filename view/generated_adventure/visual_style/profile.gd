extends Node
## Presentation only for generated_macro_renderer/v1. Never edits source or mesh data.
const ID := "generated_macro_matte/v1"
const GROUND := preload("res://view/generated_adventure/visual_style/ground.gdshader")
const WATER := preload("res://view/generated_adventure/visual_style/water.gdshader")
const PROP := preload("res://view/generated_adventure/visual_style/prop.gdshader")
const CONTACT := preload("res://view/integrated_ecology_world/tabs_style/contact.gdshader")
var board: Node3D
var enabled := true
var tracked: Dictionary = {}
var materials: Dictionary = {}
var light_states: Array = []
var environment_states: Array = []
var revision := -1
static func attach_to(target: Node3D) -> Node:
	var profile: Node=load("res://view/generated_adventure/visual_style/profile.gd").new()
	profile.name="GeneratedMatteVisualProfile";target.add_child(profile);profile.initialize(target)
	return profile
func initialize(target: Node3D) -> void:
	board=target
	for child in board.get_children():
		if child is DirectionalLight3D:
			light_states.append({"node":child,"color":child.light_color,"energy":child.light_energy,"rotation":child.rotation_degrees,"shadow":child.shadow_enabled})
		elif child is WorldEnvironment:
			var e: Environment=child.environment
			environment_states.append({"environment":e,"ambient":e.ambient_light_energy,"color":e.ambient_light_color,"background":e.background_color})
	refresh_materials()
func _material(key: String,shader_: Shader,tint:=Color.WHITE,faceted:=false) -> ShaderMaterial:
	if not materials.has(key):
		var mat:=ShaderMaterial.new();mat.shader=shader_
		if shader_==PROP:
			mat.set_shader_parameter("base_color",tint);mat.set_shader_parameter("facet_existing_triangles",faceted)
		materials[key]=mat
	return materials[key]
func _track(mi: MeshInstance3D,styled: Material) -> void:
	if mi.is_queued_for_deletion() or tracked.has(mi.get_instance_id()):return
	tracked[mi.get_instance_id()]={"node":mi,"original":mi.material_override,"styled":styled}
	if enabled:mi.material_override=styled
func _track_props(root_: Node3D,is_actor:=false) -> void:
	if not is_instance_valid(root_):return
	for node in root_.find_children("*","MeshInstance3D",true,false):
		var mi: MeshInstance3D=node
		if mi.is_queued_for_deletion() or mi.mesh==null or tracked.has(mi.get_instance_id()):continue
		var source: Material=mi.get_active_material(0)
		if not source is StandardMaterial3D or source.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
		var tint: Color=source.albedo_color
		var leaf:=not is_actor and tint.g>tint.r*1.10 and tint.g>tint.b*1.09
		if leaf:
			# Existing crown colors retain evergreen/tropical differences.
			var tropical:=tint.r<.33
			tint=Color("54a172") if tropical else Color("86af53")
			tint=tint*(.92+clampf(source.albedo_color.g,.0,1.0)*.18);tint.a=1.0
		var key:=tint.to_html()+str(leaf)
		_track(mi,_material(key,PROP,tint,leaf))
func refresh_materials() -> void:
	if not is_instance_valid(board):return
	# Prune replaced scenery; ordinary actor refresh never rebuilds terrain.
	for key in tracked.keys():
		if not is_instance_valid(tracked[key].node) or tracked[key].node.is_queued_for_deletion():tracked.erase(key)
	if is_instance_valid(board.terrain_root):
		for node in board.terrain_root.find_children("*","MeshInstance3D",true,false):
			var mi: MeshInstance3D=node;var label:=str(mi.name)
			for layer in ["land","bank","skirt","water"]:
				if label!=layer and not label.ends_with("_"+layer):continue
				var mat: ShaderMaterial=_material(layer,WATER if layer=="water" else GROUND)
				if layer!="water":mat.set_shader_parameter("surface_kind",["land","bank","skirt"].find(layer))
				_track(mi,mat);break
	_track_props(board.static_root)
	for actor in board.token_nodes.values():_track_props(actor,true)
	for contact in board.contact_shadows.values():_track(contact,_material("contact",CONTACT))
	if is_instance_valid(board.tabletop):_track(board.tabletop,_material("tabletop",PROP,Color("bddfe4")))
	revision=board.terrain_revision
	set_enabled(enabled)
func refresh_water() -> void:
	if not is_instance_valid(board):return
	for layer in board.water_layers:
		if not is_instance_valid(layer):continue
		if enabled and materials.has("water"):layer.material_override=materials.water
		else:layer.material_override=board.water_overview_material if board.overview_mode else board.water_near_material
func set_enabled(value: bool) -> void:
	enabled=value
	for row in tracked.values():
		if is_instance_valid(row.node):row.node.material_override=row.styled if value else row.original
	refresh_water()
	for old in light_states:
		var light: DirectionalLight3D=old.node
		light.light_color=Color("fff4dd") if value else old.color
		light.light_energy=1.0 if value else old.energy
		light.shadow_enabled=false if value else old.shadow
	for old in environment_states:
		var e: Environment=old.environment
		e.ambient_light_energy=.28 if value else old.ambient
		e.ambient_light_color=Color("c7def2") if value else old.color
		e.background_color=Color("bddfe4") if value else old.background
func report() -> Dictionary:
	return {"id":ID,"enabled":enabled,"styled_mesh_instances":tracked.size(),"materials":materials.size(),"source_palette":"original COLOR.rgb and UV2 soil/alpine weights","ground_texture_samples":0,"vertex_displacement":false,"source_geometry_changed":false,"source_navigation_changed":false,"river_shape_changed":false,"forest_distinction":"existing source canopy placement and crown palette","faceted_crowns":"existing mesh triangle face normals only","target_hardware_tested":false}
