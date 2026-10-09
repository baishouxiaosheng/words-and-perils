extends "res://view/recovered_terrain_view.gd"
const Trees := preload("res://view/ecology_preview/vegetation_meshes.gd")
const SURFACE_NEW := preload("res://view/ecology_preview/ecology_surface.gdshader")
const WATER_NEW := preload("res://view/ecology_preview/ecology_water.gdshader")
var ecology_root: Node3D
var vegetation_root: Node3D
var improved_water_root: Node3D
var cache: Dictionary = {}
var baseline := false
var ecology_material: ShaderMaterial
var environment_node: WorldEnvironment
var visible_cover := true
var ground_styles:Dictionary={}
var woodland_ground_shared:=false
var zone_visual_blend:=false
var zone_visual_organic:=false
var organic_styles:Dictionary={}
const ORGANIC_STYLE_MANIFEST:="res://artifacts/ecology_preview_20261002/fixture/organic_ground/manifest.json"
const GROUND_STYLE_MANIFEST:="res://artifacts/ecology_preview_20261002/fixture/ground_styles/manifest.json"

func _ready() -> void:
	super._ready()
	for node in get_children():
		if node is WorldEnvironment: environment_node = node
		ecology_material = ShaderMaterial.new()
	ecology_material.shader = SURFACE_NEW
	ecology_material.set_shader_parameter("soil_albedo",load("res://assets/materials/polyhaven/leafy_grass_diff_1k.jpg"))
	ecology_material.set_shader_parameter("rock_albedo",load("res://assets/materials/polyhaven/rock_face_diff_1k.jpg"))
	set_baseline(false)

func clear_world() -> void:
	for node in [ecology_root, vegetation_root, improved_water_root]:
		if is_instance_valid(node):
			content_root.remove_child(node);node.queue_free()
	ecology_root = null;vegetation_root = null;improved_water_root = null;cache = {}
	super.clear_world()

func _mesh_data() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray(),"uv":PackedVector2Array()}
func _new_mesh(parent: Node3D, data: Dictionary, mat: Material, label: String) -> void:
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals
	if data.has("colors"): arrays[Mesh.ARRAY_COLOR]=data.colors
	if data.has("uv"): arrays[Mesh.ARRAY_TEX_UV]=data.uv
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new();instance.name=label;instance.mesh=mesh;instance.material_override=mat
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
func show_ecology(data: Dictionary, water_data: Dictionary, render_cache: Dictionary = {}) -> void:
	var start := Time.get_ticks_usec()
	super.show_world(data,water_data)
	cache=render_cache
	ecology_root=Node3D.new();ecology_root.name="SameFacePLAcceptedMaskDisplay";content_root.add_child(ecology_root)
	vegetation_root=Node3D.new();vegetation_root.name="DecorativeCover_NOT_PATCHABLE_ENTITIES";content_root.add_child(vegetation_root)
	improved_water_root=Node3D.new();improved_water_root.name="ExactSourceWaterNormalOnly";content_root.add_child(improved_water_root)
	if not cache.is_empty(): _build_ecology()
	else: _build_material_study()
	_build_improved_water()
	if not cache.is_empty(): _build_cover()
	_bind_ground_styles()
	set_baseline(baseline)
	build_ms=float(Time.get_ticks_usec()-start)/1000.0
func _build_ecology() -> void:
	var chunks := {}
	var represented := {}
	for patch in cache.patches:
		var fi := int(patch.face);represented[fi]=true
		var cell: Dictionary=world.cells[world.face_owners[fi]]
		var key := Vector2i(floori(float(cell.q)/6.0),floori(float(cell.r)/6.0))
		if not chunks.has(key):chunks[key]=_mesh_data()
		var a:Vector3=world.positions[world.indices[fi*3]]
		var b:Vector3=world.positions[world.indices[fi*3+1]]
		var c:Vector3=world.positions[world.indices[fi*3+2]]
		var n:Vector3=(c-a).cross(b-a).normalized()
		for i in range(1,patch.bary.size()-1):
			for j in [0,i+1,i]:
				var bc:Array=patch.bary[j]
				var color:Array=patch.linear_colors[j]
				chunks[key].vertices.append(a*float(bc[0])+b*float(bc[1])+c*float(bc[2]))
				chunks[key].normals.append(n)
				chunks[key].colors.append(Color(color[0],color[1],color[2]))
				chunks[key].uv.append(Vector2(patch.detail[0],patch.detail[1]))
	# Source faces without a dry ecology patch are submerged, retain their PL.
	for fi in range(world.face_ids.size()):
		if represented.has(fi):continue
		var cell:Dictionary=world.cells[world.face_owners[fi]]
		var key:=Vector2i(floori(float(cell.q)/6.0),floori(float(cell.r)/6.0))
		if not chunks.has(key):chunks[key]=_mesh_data()
		var a:Vector3=world.positions[world.indices[fi*3]];var b:Vector3=world.positions[world.indices[fi*3+1]];var c:Vector3=world.positions[world.indices[fi*3+2]]
		var n:Vector3=(c-a).cross(b-a).normalized()
		for p in [a,c,b]:
			chunks[key].vertices.append(p);chunks[key].normals.append(n);chunks[key].colors.append(Color(.29,.20,.10));chunks[key].uv.append(Vector2(0,.05))
	for key in chunks: _new_mesh(ecology_root,chunks[key],ecology_material,"MaskChunk_%d_%d"%[key.x,key.y])
func _build_material_study() -> void:
	# No biome from height. A neutral material/light study on exact real PL only.
	var chunks := {}
	for fi in range(world.face_ids.size()):
		var cell:Dictionary=world.cells[world.face_owners[fi]]
		var key:=Vector2i(floori(float(cell.q)/6.0),floori(float(cell.r)/6.0))
		if not chunks.has(key):chunks[key]=_mesh_data()
		var a:Vector3=world.positions[world.indices[fi*3]];var b:Vector3=world.positions[world.indices[fi*3+1]];var c:Vector3=world.positions[world.indices[fi*3+2]]
		var n:Vector3=(c-a).cross(b-a).normalized()
		var slope_:float=sqrt(n.x*n.x+n.z*n.z)/maxf(.000001,absf(n.y))
		var rock:float=clampf((slope_-.12)/.7,0,1)
		var tint:Color=Color("8d9b65").srgb_to_linear() if cell.domain=="land" else Color("927446").srgb_to_linear()
		for p in [a,c,b]:
			chunks[key].vertices.append(p);chunks[key].normals.append(n);chunks[key].colors.append(tint);chunks[key].uv.append(Vector2(rock,.03*(1-rock)))
	for key in chunks:_new_mesh(ecology_root,chunks[key],ecology_material,"GenericMaterialStudy_NO_BIOME_%d_%d"%[key.x,key.y])
func _build_cover() -> void:
	var groups := {}
	for plant in cache.canopies:
		var cell:Dictionary=world.cells[plant.owner]
		var key: String="%s_%d_%d"%[plant.kind,floori(float(cell.q)/6.0),floori(float(cell.r)/6.0)]
		if not groups.has(key):groups[key]={"kind":plant.kind,"plants":[]}
		groups[key].plants.append(plant)
	var meshes := {}
	var leaf_material := ShaderMaterial.new()
	leaf_material.shader=preload("res://view/ecology_preview/vegetation_surface.gdshader")
	for key in groups:
		var kind:String=groups[key].kind
		if not meshes.has(kind):meshes[kind]=Trees.make(kind)
		var multi := MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_colors=true;multi.mesh=meshes[kind]
		multi.instance_count=groups[key].plants.size()
		for i in range(multi.instance_count):
			var p:Dictionary=groups[key].plants[i]
			var basis_:Basis=Basis(Vector3.UP,-float(p.yaw)).scaled(Vector3(float(p.radius),float(p.height),float(p.radius)))
			multi.set_instance_transform(i,Transform3D(basis_,Vector3(p.position[0],p.position[1],p.position[2])))
			var f:float=p.color_factor;multi.set_instance_color(i,Color(f,f,f,1))
		var instance := MultiMeshInstance3D.new();instance.name=key;instance.multimesh=multi;instance.material_override=leaf_material
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vegetation_root.add_child(instance)
func _build_improved_water() -> void:
	if water.is_empty():return
	var chunks := {}
	for footprint in water.footprints:
		var cell:Dictionary=world.cells[world.face_owners[footprint.face]]
		var key:String="%s_%d_%d"%[footprint.kind,floori(float(cell.q)/6.0),floori(float(cell.r)/6.0)]
		if not chunks.has(key):chunks[key]={"data":_mesh_data(),"kind":footprint.kind}
		var polygon:PackedVector2Array=footprint.polygon
		for j in range(1,polygon.size()-1):
			for idx in [0,j+1,j]:
				var p:Vector2=polygon[idx]
				chunks[key].data.vertices.append(Vector3(p.x,footprint.level,p.y))
				chunks[key].data.normals.append(Vector3.UP);chunks[key].data.colors.append(Color.WHITE)
				chunks[key].data.uv.append(Vector2(maxf(0.0,footprint.level-_face_height(footprint.face,p)),0))
	var materials := {}
	for kind in ["ocean","lake_candidate"]:
		var mat := ShaderMaterial.new();mat.shader=WATER_NEW
		mat.set_shader_parameter("deep_color",Color("286c7e") if kind=="ocean" else Color("337879"))
		mat.set_shader_parameter("shallow_color",Color("77b7b4") if kind=="ocean" else Color("80bcae"))
		materials[kind]=mat
	for key in chunks:_new_mesh(improved_water_root,chunks[key].data,materials[chunks[key].kind],key)
func _ground_texture(name:String) -> ImageTexture:
	var row:Dictionary=ground_styles.files[name]
	var image:=Image.load_from_file(row.path)
	return ImageTexture.create_from_image(image)
func _bind_ground_styles() -> void:
	ground_styles={};organic_styles={};woodland_ground_shared=false;zone_visual_blend=false;zone_visual_organic=false
	ecology_material.set_shader_parameter("zone_visual_organic",0.0)
	ecology_material.set_shader_parameter("woodland_ground_shared",0.0)
	ecology_material.set_shader_parameter("zone_visual_blend",0.0)
	if cache.is_empty() or not world.fixture or not FileAccess.file_exists(GROUND_STYLE_MANIFEST):return
	var file:=FileAccess.open(GROUND_STYLE_MANIFEST,FileAccess.READ)
	if file==null or file.get_length()>1024*1024:return
	var json:=JSON.new()
	if json.parse(file.get_as_text())!=OK:return
	file.close()
	var raw:Variant=json.data
	if not raw is Dictionary or raw.get("schema_version")!="ecology-visual-ground-styles-0.1.0":return
	if raw.get("mesh_sha256")!=world.file_sha256 or raw.get("water_sha256")!=water.file_sha256 or raw.get("zone_sha256")!=cache.zone_sha256:return
	if not cache.get("file_sha256") in [raw.get("regular_cache_sha256"),raw.get("cluster_cache_sha256")]:return
	if raw.get("source_sha256")!=FileAccess.get_sha256("res://tests/ecology_preview/bake_ground_styles.py"):return
	var needed:=["pure_weights_a.png","pure_weights_b.png","blend_weights_a.png","blend_weights_b.png","canopy_material_AO_regular.png","canopy_material_AO_clustered.png"]
	for name in needed:
		var row:Variant=raw.get("files",{}).get(name,{})
		if not row is Dictionary or not row.get("path") is String or not row.path.begins_with("res://artifacts/ecology_preview_20261002/fixture/ground_styles/") or row.path.contains(".."):return
		if FileAccess.get_sha256(row.path)!=row.get("sha256"):return
	ground_styles=raw
	ecology_material.set_shader_parameter("ground_bounds_min",Vector2(raw.bounds_min_xz[0],raw.bounds_min_xz[1]))
	ecology_material.set_shader_parameter("ground_extent",Vector2(raw.extent_xz[0],raw.extent_xz[1]))
	for name in cache.palette_linear_rgb:
		var col:Array=cache.palette_linear_rgb[name]
		ecology_material.set_shader_parameter("palette_"+name,Vector3(col[0],col[1],col[2]))
	for name in ["pure_weights_a","pure_weights_b","blend_weights_a","blend_weights_b"]:
		ecology_material.set_shader_parameter("ground_"+name,_ground_texture(name+".png"))
	_update_canopy_material_ao()
	_bind_organic_styles()
func _update_canopy_material_ao() -> void:
	if ground_styles.is_empty():return
	var name:="canopy_material_AO_clustered.png" if cache.get("layout","")=="constrained_clustered-v0.1.0" else "canopy_material_AO_regular.png"
	ecology_material.set_shader_parameter("canopy_material_ao",_ground_texture(name))
func _bind_organic_styles() -> void:
	if ground_styles.is_empty() or not FileAccess.file_exists(ORGANIC_STYLE_MANIFEST):return
	var json:=JSON.new()
	if json.parse(FileAccess.get_file_as_string(ORGANIC_STYLE_MANIFEST))!=OK:return
	var data:Variant=json.data
	if not data is Dictionary or data.get("schema")!="land-land-visual-warp-0.1.0" or data.get("base_style_manifest_sha256")!=FileAccess.get_sha256(GROUND_STYLE_MANIFEST):return
	if data.get("mesh_sha256")!=world.file_sha256 or data.get("water_sha256")!=water.file_sha256 or data.get("source_sha256")!=FileAccess.get_sha256("res://tests/ecology_preview/bake_organic_ground.py"):return
	for suffix in ["a","b"]:
		var row:Variant=data.get("files",{}).get("organic_weights_"+suffix+".png",{})
		if not row is Dictionary or not row.get("path") is String or not row.path.begins_with("res://artifacts/ecology_preview_20261002/fixture/organic_ground/") or row.path.contains(".."):return
		if FileAccess.get_sha256(row.path)!=row.get("sha256"):return
	organic_styles=data
	for suffix in ["a","b"]:
		var image:=Image.load_from_file(data.files["organic_weights_"+suffix+".png"].path)
		ecology_material.set_shader_parameter("ground_organic_weights_"+suffix,ImageTexture.create_from_image(image))
func set_zone_visual_organic(value:bool) -> bool:
	if organic_styles.is_empty():return false
	zone_visual_organic=value
	ecology_material.set_shader_parameter("zone_visual_organic",1.0 if value else 0.0)
	return true
func set_woodland_ground_shared(value:bool) -> bool:
	if ground_styles.is_empty():return false
	woodland_ground_shared=value
	ecology_material.set_shader_parameter("woodland_ground_shared",1.0 if value else 0.0)
	return true
func set_zone_visual_blend(value:bool) -> bool:
	if ground_styles.is_empty():return false
	zone_visual_blend=value
	ecology_material.set_shader_parameter("zone_visual_blend",1.0 if value else 0.0)
	return true
func set_cover_visible(value:bool) -> void:
	visible_cover=value
	if is_instance_valid(vegetation_root):vegetation_root.visible=value and not baseline
func set_baseline(value:bool) -> void:
	baseline=value
	if is_instance_valid(terrain_root):
		for node in terrain_root.get_children():
			if node.name.begins_with("Chunk_"):node.visible=baseline
	if is_instance_valid(ecology_root):ecology_root.visible=not baseline
	if is_instance_valid(vegetation_root):vegetation_root.visible=not baseline and visible_cover
	if is_instance_valid(water_root):water_root.visible=baseline
	if is_instance_valid(improved_water_root):improved_water_root.visible=not baseline
	if environment_node!=null:
		environment_node.environment.background_color=Color("263235") if baseline else Color("758e97")
		environment_node.environment.ambient_light_color=Color("99b3c7") if baseline else Color("c4d6dc")
		environment_node.environment.ambient_light_energy=.14 if baseline else .38
	var lights := []
	for node in get_children():
		if node is DirectionalLight3D:lights.append(node)
	if lights.size()>=3:
		lights[0].light_energy=1.2 if baseline else 1.06
		lights[1].light_energy=.18 if baseline else .32
		lights[2].light_energy=.22 if baseline else .27
func set_cover_variant(new_cache:Dictionary) -> bool:
	if cache.is_empty() or new_cache.get("zone_sha256")!=cache.get("zone_sha256") or new_cache.get("palette_linear_rgb")!=cache.get("palette_linear_rgb"):return false
	# Terrain/water/grid/camera/lighting stay exactly the same. Only transforms switch.
	if is_instance_valid(vegetation_root):
		for node in vegetation_root.get_children():vegetation_root.remove_child(node);node.queue_free()
	cache=new_cache
	_build_cover()
	_update_canopy_material_ao()
	set_cover_visible(visible_cover)
	return true
func metrics() -> Dictionary:
	var result:Dictionary=super.metrics()
	result.ecology_preview=true;result.baseline=baseline;result.decorative_cover_visible=visible_cover
	result.zone_mask_hash=cache.get("zone_sha256","")
	result.render_cache_hash=cache.get("file_sha256","")
	result.fixture=cache.get("fixture",false)
	result.cover_metrics=cache.get("cover_metrics",{}).duplicate()
	result.cover_metrics.erase("cells_detail")
	result.visual_organic_style={"available":not organic_styles.is_empty(),"enabled":zone_visual_organic,"effective":zone_visual_organic and zone_visual_blend,"manifest_sha256":FileAccess.get_sha256(ORGANIC_STYLE_MANIFEST) if not organic_styles.is_empty() else "","seed":organic_styles.get("seed",0),"maximum_xz_displacement_cap":organic_styles.get("maximum_vector_length_cap_xz",0),"physical_domain_ownership_changed":false,"only_land_land_material_appearance":true,"visual_quality_acceptance":"NOT_RUN"}
	result.whole_zone_authority_loaded=false
	result.cover_layout=cache.get("layout","regular_fixed_cell")
	result.visual_ground_styles={"available":not ground_styles.is_empty(),"B1_shared_woodland_ground":woodland_ground_shared,"B2_visible_distance_blend":zone_visual_blend,"manifest_sha256":FileAccess.get_sha256(GROUND_STYLE_MANIFEST) if not ground_styles.is_empty() else "","transition_10_90_width_xz":ground_styles.get("transition_10_90_width_xz",0),"full_support_width_xz":ground_styles.get("transition_full_support_width_xz",0),"biome_domain_height_ownership_unchanged":true,"visual_readability_acceptance":"NOT_RUN"}
	result.real_geometry_generic_material_study=cache.is_empty()
	return result
