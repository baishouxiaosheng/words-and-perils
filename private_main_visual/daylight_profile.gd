extends "res://view/integrated_ecology_world/lighting_profile/miniature_profile.gd"
## Reversible rendering-only profile. All geometry and source identity stay unchanged.
## The recipe is original; TABS reference images inform appearance, not exact shaders.
const TABS_GROUND:=preload("res://view/integrated_ecology_world/tabs_style/ground.gdshader")
const TABS_VEGETATION:=preload("res://view/integrated_ecology_world/tabs_style/vegetation.gdshader")
const TABS_WATER:=preload("res://view/integrated_ecology_world/tabs_style/water.gdshader")
const TABS_PROP:=preload("res://view/integrated_ecology_world/tabs_style/prop.gdshader")
const TABS_CONTACT:=preload("res://view/integrated_ecology_world/tabs_style/contact.gdshader")
var water_shaders:Dictionary={}
var contact_overrides:Array=[]
var tracked_contacts:Dictionary={}
var prop_overrides:Array=[]
var tracked_props:Dictionary={}
var prop_materials:Dictionary={}
var pending_refresh:=false
var ownership_suspended:=false
var refresh_epoch:=0
var refresh_dirty:=false
var suspended_process:=false
static func attach_to(world_view:Node3D,style_name:String="clear_daylight")->Node:
	var existing:=world_view.get_node_or_null("ClearDaylightVisualProfile")
	if existing!=null:existing.set_enabled(true);return existing
	var profile:Node=load("res://private_main_visual/daylight_profile.gd").new()
	profile.name="ClearDaylightVisualProfile";profile.style=style_name;world_view.add_child(profile)
	if not profile.initialize(world_view):return profile
	profile.set_enabled(true);return profile
func initialize(world_view:Node3D)->bool:
	if not super.initialize(world_view):return false
	water_shaders[view.water_material]=view.water_material.shader
	view.content_root.child_entered_tree.connect(_content_added)
	refresh_materials()
	return true
func _content_added(_node:Node)->void:
	if ownership_suspended:refresh_dirty=true;return
	if pending_refresh:return
	pending_refresh=true;_refresh_deferred.call_deferred(refresh_epoch)
func _refresh_deferred(epoch:int)->void:
	if epoch!=refresh_epoch or ownership_suspended:return
	refresh_materials()
func refresh_materials()->void:
	if ownership_suspended:refresh_dirty=true;return
	pending_refresh=false
	if not is_instance_valid(view):return
	if is_instance_valid(view.river_overlay):
		for mi in view.river_overlay.mesh_views:
			var kind:String=mi.get_meta("river_surface_kind")
			var mat:Material=mi.get_active_material(0)
			if kind=="water" and mat is ShaderMaterial and not water_shaders.has(mat):
				water_shaders[mat]=mat.shader
				mat.set_shader_parameter("river_surface",1.0)
			elif kind in ["bank","bed"]:_track_prop(mi,Color("c8aa71") if kind=="bank" else Color("769b82"))
	for child in view.content_root.get_children():
		if str(child.name).begins_with("ContactShadow_") and child is MeshInstance3D and not tracked_contacts.has(child.get_instance_id()):
			tracked_contacts[child.get_instance_id()]=true
			var contact_mat:=ShaderMaterial.new();contact_mat.shader=TABS_CONTACT
			contact_overrides.append({"node":child,"original":child.material_override,"scale":child.scale,"styled":contact_mat})
		if not child.has_meta("chess_piece"):continue
		for mi in child.find_children("*","MeshInstance3D",true,false):_track_prop(mi)
	if enabled:_apply_materials(true)
func _track_prop(mi:MeshInstance3D,color:Color=Color(-1,-1,-1))->void:
	if mi.is_queued_for_deletion() or tracked_props.has(mi.get_instance_id()) or mi.mesh==null:return
	var source:Material=mi.get_active_material(0)
	if not source is StandardMaterial3D or source.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:return
	tracked_props[mi.get_instance_id()]=true
	var original:Material=mi.material_override
	var tint:Color=source.albedo_color if color.r<0.0 else color
	var key:=tint.to_html()
	if not prop_materials.has(key):
		var mat:=ShaderMaterial.new();mat.shader=TABS_PROP;mat.set_shader_parameter("base_color",tint);prop_materials[key]=mat
	prop_overrides.append({"node":mi,"original":original,"styled":prop_materials[key]})
func _apply_materials(value:bool)->void:
	if ownership_suspended:refresh_dirty=true;return
	for mat in ground_shaders:
		mat.shader=TABS_GROUND if value else ground_shaders[mat]
		if value:
			mat.set_shader_parameter("canopy_contact_field",field)
			mat.set_shader_parameter("contact_field_min",Vector2(field_manifest.world_min_xz[0],field_manifest.world_min_xz[1]))
			mat.set_shader_parameter("contact_field_extent",Vector2(field_manifest.world_extent_xz[0],field_manifest.world_extent_xz[1]))
			mat.set_shader_parameter("canopy_contact_strength",contact_strength if view.trees_enabled else 0.0)
	for mat in tree_shaders:mat.shader=TABS_VEGETATION if value else tree_shaders[mat]
	for mat in water_shaders:mat.shader=TABS_WATER if value else water_shaders[mat]
	for row in prop_overrides:
		if is_instance_valid(row.node):row.node.material_override=row.styled if value else row.original
	for row in contact_overrides:
		if not is_instance_valid(row.node):continue
		row.node.material_override=row.styled if value else row.original
		row.node.scale=row.scale
func set_enabled(value:bool)->void:
	if ownership_suspended:refresh_dirty=true;return
	if not last_error.is_empty() or field==null:return
	enabled=value;contact_strength=1.15
	_apply_materials(value)
	var setup:=[[Color("fff4dd"),1.0,Vector3(-48,-35,0)],[Color("a8c9f4"),.12,Vector3(-25,130,0)],[Color("d3efff"),.12,Vector3(-26,-130,0)]]
	for i in range(lights.size()):
		var old:Dictionary=lights[i];var l:DirectionalLight3D=old.node
		l.light_color=setup[i][0] if value and i<3 else old.color
		l.light_energy=setup[i][1] if value and i<3 else old.energy
		l.rotation_degrees=setup[i][2] if value and i<3 else old.rotation
	for old in environment_states:
		var e:Environment=old.environment
		e.ambient_light_energy=.28 if value else old.ambient
		e.ambient_light_color=Color("c7def2") if value else old.color
		e.background_color=Color("bddfe4") if value else old.background
	previous_tree_visibility=view.trees_enabled
func report()->Dictionary:
	return {"enabled":enabled,"error":last_error,"style":"ORIGINAL_CLEAR_DAYLIGHT_TABS_INSPIRED","shading":"TWO_BROAD_NORMAL_BASED_GROUPS_WITH_COOL_SHADOW_TINT","photographic_ground_detail":false,"shadow_maps":false,"ssao":false,"ssr":false,"raytracing":false,"canopy_contact_field_is_static_approximation":true,"canopy_contact_field_bytes":field_manifest.get("bytes",0),"canopy_contact_strength":contact_strength,"props_styled":prop_overrides.size(),"pawn_contacts":contact_overrides.size(),"geometry_changed":false,"decorative_contact_meshes_scaled":true,"source_masks_or_heights_changed":false,"target_hardware_tested":false}

func suspend_ownership()->bool:
	if ownership_suspended:return false
	refresh_dirty=refresh_dirty or pending_refresh
	refresh_epoch+=1;ownership_suspended=true;pending_refresh=false
	suspended_process=is_processing();set_process(false)
	return true
func resume_ownership()->void:
	if not ownership_suspended:return
	refresh_epoch+=1;ownership_suspended=false;pending_refresh=false
	set_process(suspended_process)
	if refresh_dirty:
		refresh_dirty=false;pending_refresh=true
		_refresh_deferred.call_deferred(refresh_epoch)
func _canopies_changed()->void:
	if ownership_suspended:refresh_dirty=true;return
	super._canopies_changed()
func _process(delta:float)->void:
	if ownership_suspended:return
	super._process(delta)
