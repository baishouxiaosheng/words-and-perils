extends "res://view/recovered_terrain_view.gd"
const GROUND := preload("res://view/real_shore_preview/shore_ground.gdshader")
const WATER := preload("res://view/real_shore_preview/shore_water.gdshader")
var shore_ground:ShaderMaterial
var shore_water_materials:Array[ShaderMaterial]=[]
var scope:Dictionary={}
var local:Dictionary={}
var manifest:Dictionary={}
var baseline:=false
var local_faces:=0
var local_water_triangles:=0
var mesh_vertices:=0
var local_bounds:=AABB()
func _ready()->void:
	super._ready()
	for n in get_children():
		if n is WorldEnvironment:
			n.environment.background_color=Color("7c939a")
			n.environment.ambient_light_color=Color("c4d6dc")
			n.environment.ambient_light_energy=.38
	var lights:Array=[]
	for n in get_children():
		if n is DirectionalLight3D:lights.append(n)
	if lights.size()>=3:
		lights[0].light_energy=1.06;lights[1].light_energy=.32;lights[2].light_energy=.27
func _data()->Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray(),"uv":PackedVector2Array()}
func _mesh(parent:Node3D,data:Dictionary,mat:Material,label:String)->void:
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_COLOR]=data.colors;arrays[Mesh.ARRAY_TEX_UV]=data.uv
	var m:=ArrayMesh.new();m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var n:=MeshInstance3D.new();n.name=label;n.mesh=m;n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(n)
	mesh_vertices+=data.vertices.size()
func show_shore(admitted:Dictionary)->void:
	clear_world();var start:=Time.get_ticks_usec()
	world=admitted.world;water=admitted.water;scope=admitted.scope;local=admitted.local;manifest=admitted.manifest
	terrain_root=Node3D.new();terrain_root.name="FrozenOriginalPLFaces";content_root.add_child(terrain_root)
	water_root=Node3D.new();water_root.name="ExactFrozenSourceFootprints";content_root.add_child(water_root)
	grid_root=Node3D.new();grid_root.name="CanonicalHexGrid";content_root.add_child(grid_root)
	mesh_vertices=0;shore_water_materials.clear()
	var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://"+scope.texture.path));var texture:=ImageTexture.create_from_image(image)
	shore_ground=ShaderMaterial.new();shore_ground.shader=GROUND
	shore_ground.set_shader_parameter("soil_albedo",load("res://assets/materials/polyhaven/leafy_grass_diff_1k.jpg"))
	shore_ground.set_shader_parameter("rock_albedo",load("res://assets/materials/polyhaven/rock_face_diff_1k.jpg"))
	_bind(shore_ground,texture)
	# Display normals only: area-weighted source PL adjacency, no geometry change.
	var vertex_set:={};var normals:={}
	for row in local.source_faces:
		for vi in row.vertices:vertex_set[int(vi)]=true;normals[int(vi)]=Vector3.ZERO
	for fi in range(world.face_ids.size()):
		var ia:int=world.indices[fi*3];var ib:int=world.indices[fi*3+1];var ic:int=world.indices[fi*3+2]
		if not vertex_set.has(ia) and not vertex_set.has(ib) and not vertex_set.has(ic):continue
		var a:Vector3=world.positions[ia];var b:Vector3=world.positions[ib];var c:Vector3=world.positions[ic];var face_normal:Vector3=(c-a).cross(b-a)
		for vi in [ia,ib,ic]:
			if normals.has(vi):normals[vi]+=face_normal
	for vi in normals:normals[vi]=normals[vi].normalized()
	var td:=_data();local_faces=local.source_faces.size();var first:=true
	for row in local.source_faces:
		var fi:int=row.index
		var a:Vector3=world.positions[world.indices[fi*3]];var b:Vector3=world.positions[world.indices[fi*3+1]];var c:Vector3=world.positions[world.indices[fi*3+2]]
		# A single neutral ground study, not a biome/color from original hex domain.
		var tint:Color=Color("8d9b65").srgb_to_linear()
		for vi in [world.indices[fi*3],world.indices[fi*3+2],world.indices[fi*3+1]]:
			var p:Vector3=world.positions[vi];var norm:Vector3=normals[vi];var slope:float=length_xz(norm)/maxf(.000001,absf(norm.y));var stone:float=clampf((slope-.18)/.85,0,1)
			td.vertices.append(p);td.normals.append(norm);td.colors.append(tint);td.uv.append(Vector2(stone,0))
			if first:local_bounds=AABB(p,Vector3.ZERO);first=false
			else:local_bounds=local_bounds.expand(p)
	_mesh(terrain_root,td,shore_ground,"LocalOriginalFacesNoSubdivision")
	var groups:={};local_water_triangles=0
	for idx in local.source_footprint_indices:
		var fp:Dictionary=water.footprints[int(idx)];var kind:String=fp.kind
		if not groups.has(kind):groups[kind]=_data()
		var poly:PackedVector2Array=fp.polygon
		for j in range(1,poly.size()-1):
			local_water_triangles+=1
			for k in [0,j+1,j]:
				var p:Vector2=poly[k]
				groups[kind].vertices.append(Vector3(p.x,fp.level,p.y));groups[kind].normals.append(Vector3.UP);groups[kind].colors.append(Color.WHITE)
				groups[kind].uv.append(Vector2(maxf(0.0,fp.level-_face_height(fp.face,p)),0))
	for kind in groups:
		var mat:=ShaderMaterial.new();mat.shader=WATER;_bind(mat,texture);mat.set_shader_parameter("ocean",1.0 if kind=="ocean" else 0.0)
		shore_water_materials.append(mat);_mesh(water_root,groups[kind],mat,kind)
	# Reuse the tested source-PL/water-conforming grid. Restrict only display edges.
	var source_edges=world.edges;var edges:=[]
	for edge in source_edges:
		var a:Vector3=world.positions[edge[0]];var b:Vector3=world.positions[edge[4]]
		if maxf(a.x,b.x)<local_bounds.position.x or minf(a.x,b.x)>local_bounds.end.x or maxf(a.z,b.z)<local_bounds.position.z or minf(a.z,b.z)>local_bounds.end.z:continue
		edges.append(edge)
	world.edges=edges;_build_grid();world.edges=source_edges
	chunk_count=1+groups.size();set_grid_visible(grid_enabled);set_baseline(baseline);set_scope_camera(false)
	build_ms=float(Time.get_ticks_usec()-start)/1000.0
func _bind(mat:ShaderMaterial,texture:Texture2D)->void:
	var b:Array=scope.bounds_xz
	mat.set_shader_parameter("shore_field",texture);mat.set_shader_parameter("bounds_min",Vector2(b[0],b[1]));mat.set_shader_parameter("bounds_extent",Vector2(b[2]-b[0],b[3]-b[1]));mat.set_shader_parameter("distance_cap",manifest.distance_cap_xz)
func set_baseline(value:bool)->void:
	baseline=value
	if shore_ground!=null:shore_ground.set_shader_parameter("bands_enabled",0.0 if baseline else 1.0)
	for mat in shore_water_materials:mat.set_shader_parameter("bands_enabled",0.0 if baseline else 1.0)
func set_scope_camera(close:bool)->void:
	if world.is_empty():return
	var p:Array=scope.camera.target_xz;var h:=Loader.height_at(world,Vector2(p[0],p[1]));target=Vector3(p[0],h.get("height",0.0),p[1])
	overview=not close
	if close:
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5.5;camera.fov=46.0;distance=12.0;pitch=.85;yaw=scope.camera.yaw;_update_camera()
	else:
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=scope.camera.top_size;camera.position=Vector3(target.x,32,target.z);camera.look_at(target,Vector3(0,0,-1));_update_grid_width()
func fit_overview()->void:set_scope_camera(false)
func focus_close()->void:set_scope_camera(true)
func metrics()->Dictionary:
	var r:Dictionary=super.metrics();r.display_normal_mode="AREA_WEIGHTED_SOURCE_PL_ADJACENCY_ONLY";r.neutral_ground_not_original_hex_domain_color=true;r.local_source_faces=local_faces;r.local_water_triangles=local_water_triangles;r.local_original_hexes=local.get("cells",[]).size();r.mesh_vertices=mesh_vertices;r.vertex_attribute_bytes=mesh_vertices*48;r.shore_atlas_gpu_bytes=scope.get("texture",{}).get("resolution",[0,0])[0]*scope.get("texture",{}).get("resolution",[0,0])[1]*4;r.materials=1+shore_water_materials.size()+1;r.baseline=baseline;r.geometry_changed=world.get("diagnostic_candidate",false);r.water_footprint_changed=water.get("diagnostic_candidate",false);r.zone_authority_loaded=false;r.river_available=false;return r

func _update_grid_width()->void:
	if grid_material==null:return
	var pixel_world:float=camera.size/maxf(1.0,get_viewport().get_visible_rect().size.y)
	grid_material.set_shader_parameter("width_scale",clampf(pixel_world*.8/.012,1.0,15.0))
func zoom(delta:float)->void:
	if world.is_empty():return
	camera.size=clampf(camera.size*exp(delta*.12),4.8,10.0);_update_grid_width()

func length_xz(v:Vector3)->float:return sqrt(v.x*v.x+v.z*v.z)
