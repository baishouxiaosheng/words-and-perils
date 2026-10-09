extends "res://view/integrated_ecology_world/world_view.gd"
const Compact:=preload("res://view/integrated_ecology_world/performance_variant/compact66_adapter.gd")
var natural_shorelines:Node3D
var natural_shorelines_enabled:=true
var compact_root:Node3D
var compact_manifest:Dictionary={}
var compact_sha:=""
var compact_enabled:=false
var luminance_enabled:=false
var compact_triangles:=0
var compact_vertices:=0
var variant_build_ms:=0.0
var luma_sha:=""
var compact_materials:Array[ShaderMaterial]=[]
var compact_load_error:=""
var compact_shore_tile_count:=0
var source_acceptance_receipt:Dictionary={}
var river_surfaces:Array=[]
var river_overlay:Node3D
var retired_river_faces:Dictionary={}
var river_integration_report:Dictionary={}
signal whole_canopies_changed
signal canopy_support_changed
var whole_canopies:Node3D
var whole_canopy_error:=""
var clear_daylight_enabled:=true
var clear_daylight_profile:Node
var faceted_mountains:Node3D
var faceted_mountains_enabled:=true
const RiverBridge:=preload("res://view/integrated_ecology_world/performance_variant/river_bridge.gd")
func _ready()->void:
	super._ready()
	ground_material.shader=preload("res://view/integrated_ecology_world/performance_variant/ground_shore66.gdshader")
	ground_material.set_shader_parameter("soil_albedo",load("res://assets/materials/polyhaven/leafy_grass_diff_1k.jpg"));ground_material.set_shader_parameter("rock_albedo",load("res://assets/materials/polyhaven/rock_face_diff_1k.jpg"))
func show_cache(data:Dictionary)->void:
	super.show_cache(data)
	source_acceptance_receipt=preload("res://view/integrated_ecology_world/performance_variant/source_receipt.gd").load_receipt(manifest)
	var compact:=Compact.load_compact()
	if not compact.ok:
		compact_load_error=str(compact.error);push_error(compact_load_error);return
	load_compact(compact);set_compact(true)
func load_luminance()->bool:
	var root_:="res://artifacts/integrated_ecology_world_20261002/performance_variant/luminance/";var path:=root_+"manifest.json";var p:=JSON.new()
	if p.parse(FileAccess.get_file_as_string(path))!=OK:return false
	for kind in ["soil","rock"]:
		var row:Dictionary=p.data.files[kind];var texture_path:="res://"+str(row.path)
		if FileAccess.get_sha256(texture_path)!=row.sha256 or FileAccess.get_sha256("res://"+str(row.source_path))!=row.source_sha256:return false
		var im:=Image.load_from_file(texture_path);im.convert(Image.FORMAT_R8);im.generate_mipmaps();ground_material.set_shader_parameter(kind+"_luminance",ImageTexture.create_from_image(im))
	luma_sha=FileAccess.get_sha256(path);return true
func load_compact(data:Dictionary)->void:
	var start:=Time.get_ticks_usec();compact_manifest=data.manifest;compact_sha=data.manifest_sha256;compact_root=Node3D.new();compact_root.name="SameActualDryOriginalPLCompactRendering";content_root.add_child(compact_root)
	for chunk in compact_manifest.chunks:
		if not chunk.has("ground"):continue
		var row:Dictionary=chunk.ground;var v:=Compact.bytes(compact_manifest,row.vertices).to_float32_array();var indices:=Compact.bytes(compact_manifest,row.indices).to_int32_array();var count:int=row.vertex_count
		assert(v.size()==count*14);var vs:=PackedVector3Array();var ns:=PackedVector3Array();var cs:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array();vs.resize(count);ns.resize(count);cs.resize(count);uv.resize(count);uv2.resize(count)
		for i in range(count):
			var j:=i*14;vs[i]=Vector3(v[j],v[j+1],v[j+2]);ns[i]=Vector3(v[j+3],v[j+4],v[j+5]);cs[i]=Color(v[j+6],v[j+7],v[j+8],v[j+9]);uv[i]=Vector2(v[j+10],v[j+11]);uv2[i]=Vector2(v[j+12],v[j+13])
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vs;arrays[Mesh.ARRAY_NORMAL]=ns;arrays[Mesh.ARRAY_COLOR]=cs;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_INDEX]=indices;var me:=ArrayMesh.new();me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var mi:=MeshInstance3D.new();mi.name="Compact_"+str(chunk.key);mi.mesh=me;mi.material_override=_chunk_material(chunk);mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;compact_root.add_child(mi);compact_vertices+=count;compact_triangles+=indices.size()/3
	compact_root.hide();variant_build_ms=float(Time.get_ticks_usec()-start)/1000.0
func _chunk_material(chunk:Dictionary)->ShaderMaterial:
	var mat:=ground_material.duplicate() as ShaderMaterial
	if chunk.has("shore_tile") and chunk.shore_tile.has("file"):
		var tile:Dictionary=chunk.shore_tile;var raw:=Compact.bytes(compact_manifest,tile.file)
		assert(raw.size()==int(tile.width)*int(tile.height))
		var im:=Image.create_from_data(int(tile.width),int(tile.height),false,Image.FORMAT_R8,raw)
		mat.set_shader_parameter("shore_distance_tile",ImageTexture.create_from_image(im))
		mat.set_shader_parameter("shore_tile_min",Vector2(tile.bounds_min_xz[0],tile.bounds_min_xz[1]))
		mat.set_shader_parameter("shore_tile_extent",Vector2(tile.extent_xz[0],tile.extent_xz[1]))
		mat.set_shader_parameter("shore_distance_cap",float(tile.distance_cap));mat.set_shader_parameter("use_shore_tile",1.0);compact_shore_tile_count+=1
	compact_materials.append(mat);return mat
func _sync_material_parameter(name_:String,value:Variant)->void:
	for mat in compact_materials:mat.set_shader_parameter(name_,value)
func set_shared_ground(value:bool)->void:
	super.set_shared_ground(value);_sync_material_parameter("shared_woodland_ground",1.0 if value else 0.0)
func set_bands(value:bool)->void:
	super.set_bands(value);_sync_material_parameter("shore_bands",1.0 if value else 0.0)
func set_compact(value:bool)->void:
	if not is_instance_valid(compact_root):return
	compact_enabled=value;ground_root.visible=not value;compact_root.visible=value
	if value:set_blend(true)
func set_luminance(value:bool)->void:luminance_enabled=value;ground_material.set_shader_parameter("use_baked_luminance",1.0 if value else 0.0);_sync_material_parameter("use_baked_luminance",1.0 if value else 0.0)
func set_blend(value:bool)->void:
	if compact_enabled and not value:set_compact(false)
	super.set_blend(value);_sync_material_parameter("visual_blend",1.0 if value else 0.0)
func set_hex_scope(id:String)->void:
	var qr:=id.trim_prefix("hex:").split(",");var q:=int(qr[0]);var r:=int(qr[1]);var x:=sqrt(3.0)*(q+r*.5);var z:=r*1.5;target=Vector3(x,_height_at_xz(Vector2(x,z)),z);scope_name=id.replace(":","_").replace(",","_");overview=false;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.0;distance=8;pitch=.92;yaw=0;_update_camera()
func metrics()->Dictionary:
	var m:Dictionary=super.metrics();m.compact_geometry=compact_enabled;m.whole_world_canopies=is_instance_valid(whole_canopies);
	if is_instance_valid(whole_canopies):m.canopy_variant=whole_canopies.selected_variant;m.canopy_lod=whole_canopies.lod_mode;m.canopy_visible_triangles=whole_canopies.visible_triangles;m.whole_lod_fraction=1.0;m.cover_status="ALL_WORLD_LEGAL_ANCHORS_NOT_DENSITY_ACCEPTANCE";
	m.faceted_mountains=faceted_mountains.report() if is_instance_valid(faceted_mountains) else {"enabled":false};m.clear_daylight_profile=clear_daylight_profile.report() if is_instance_valid(clear_daylight_profile) else {"enabled":false};m.compact_geometry=compact_enabled;m.local_river_integration=river_integration_report;m.source_acceptance_receipt=source_acceptance_receipt;m.compact_load_error=compact_load_error;m.shore_distance_tile_count=compact_shore_tile_count;m.shore_distance_texture_format="R8_NO_MIPMAPS_LINEAR";m.luminance_shader=luminance_enabled;m.compact_manifest_sha256=compact_sha;m.luma_manifest_sha256=luma_sha;m.compact_ground_vertices=compact_vertices;m.compact_ground_triangles=compact_triangles;m.variant_build_ms=variant_build_ms;m.actual_dry_geometry_omitted=false;m.logical_masks_modified=false;m.source_picking="FROZEN_BASELINE_ORIGINAL_FACE_BARY_PL_SAME_SUPPORT" if river_surfaces.is_empty() else "BASELINE_PLUS_LOCAL_RIVER_ORIGINAL_FACE_BARY_WITH_DERIVED_SURFACE_HEIGHT"
	if is_instance_valid(natural_shorelines) and natural_shorelines.visible:
		m.natural_shorelines=natural_shorelines.report();m.logical_masks_modified=true;m.original_hex_classifications_modified=false;m.source_picking="ACTIVE_V03_NEW_FACE_BARY_AND_LEGACY_PARENT_SEPARATELY"
		m.source_acceptance_receipt={"verified":false,"status":"OLD_RECEIPT_NOT_APPLICABLE_TO_ACTIVE_V03_GEOMETRY","old_source_receipt":source_acceptance_receipt}
		m.active_render_source="natural-shared-terrain-shore-v03"
	return m

func install_river_overlay(overlay:Node3D)->Dictionary:
	river_integration_report=RiverBridge.install(self,overlay)
	if river_integration_report.get("ok",false) and is_instance_valid(whole_canopies):river_integration_report.excluded_canopies=whole_canopies.exclude_river(overlay);_update_budget()
	if is_instance_valid(clear_daylight_profile):clear_daylight_profile.refresh_materials()
	return river_integration_report
func inspect(screen:Vector2)->Dictionary:
	var original:=inspect_original_surfaces(screen)
	if not is_instance_valid(faceted_mountains) or not faceted_mountains.visible:return original
	var mountain:Dictionary=faceted_mountains.inspect_visual(self,screen)
	if not mountain.get("ok",false):return original
	if not original.get("ok",false):return mountain
	var a:Array=original.position;var b:Array=mountain.visual_position;var origin:=camera.project_ray_origin(screen)
	return mountain if origin.distance_squared_to(Vector3(b[0],b[1],b[2]))<=origin.distance_squared_to(Vector3(a[0],a[1],a[2]))+.000001 else original
func inspect_original_surfaces(screen:Vector2)->Dictionary:
	var original:=super.inspect(screen)
	if is_instance_valid(natural_shorelines) and natural_shorelines.visible:original=natural_shorelines.decorate_hit(original)
	if river_surfaces.is_empty():return original
	var river:=RiverBridge.inspect(self,screen)
	if not river.ok:return original
	if not original.ok:return river
	var a:Array=original.position;var b:Array=river.position;var origin:=camera.project_ray_origin(screen)
	return river if origin.distance_squared_to(Vector3(b[0],b[1],b[2]))<origin.distance_squared_to(Vector3(a[0],a[1],a[2])) else original
func _height_at_xz(p:Vector2)->float:
	var original:=super._height_at_xz(p)
	if river_surfaces.is_empty():return original
	var river:=RiverBridge.height_at_xz(self,p)
	return maxf(original,river) if river>-INF else original

func presentation_height_at_xz(p:Vector2,source_height:float)->float:
	# Presentation-only support. Canonical movement, source height and permissions
	# never call this function; only rendered tokens, markers and contact shadows.
	if not is_instance_valid(faceted_mountains) or not faceted_mountains.visible:return source_height
	return maxf(source_height,faceted_mountains.height_at_xz(p))

func display_anchor_is_dry(p:Vector2,owner_hex:String,radius:float=.20)->bool:
	# Rare display-layout check, never a movement permission. Require the visible
	# token footprint to remain in its owning active dry cell and outside water.
	var probes:Array[Vector2]=[p]
	for i in range(6):probes.append(p+Vector2(cos(TAU*i/6.0),sin(TAU*i/6.0))*radius)
	for probe in probes:
		if canonical_hex(Vector3(probe.x,0,probe.y))!=owner_hex:return false
		var dry:=false
		for chunk in picks:
			var lo:Array=chunk.bounds_min;var hi:Array=chunk.bounds_max
			if probe.x<float(lo[0]) or probe.x>float(hi[0]) or probe.y<float(lo[2]) or probe.y>float(hi[2]):continue
			var vs:PackedVector3Array=chunk.vertices;var ids:PackedInt32Array=chunk.indices
			for j in range(0,ids.size(),3):
				if not _display_triangle_contains(probe,vs[ids[j]],vs[ids[j+1]],vs[ids[j+2]]):continue
				if chunk.water:return false
				dry=true;break
		if not dry:return false
		for surface in river_surfaces:
			if surface.kind!="water":continue
			var vs:PackedVector3Array=surface.vertices
			for j in range(0,vs.size(),3):
				if _display_triangle_contains(probe,vs[j],vs[j+1],vs[j+2]):return false
	return true
static func _display_triangle_contains(p:Vector2,a:Vector3,b:Vector3,c:Vector3)->bool:
	var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var d:=p-Vector2(a.x,a.z);var det:=u.cross(v)
	if absf(det)<1e-10:return false
	var wb:=d.cross(v)/det;var wc:=u.cross(d)/det
	return wb>=-.000001 and wc>=-.000001 and wb+wc<=1.000001

func _new_world_canopies()->Node3D:
	# Factory seam for deterministic lifecycle fixtures; production uses only the
	# hash-verified cache loader below. Candidates stay detached until accepted.
	return preload("res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd").new()
func enable_world_canopies(variant:String="v1")->bool:
	if is_instance_valid(whole_canopies) and whole_canopies.selected_variant==variant:
		whole_canopy_error="";return true
	var crowns:=_new_world_canopies();crowns.hide()
	if not crowns.load_cache(manifest,variant):
		whole_canopy_error=crowns.last_error;crowns.free();return false
	# Contact fields and playable source identities cannot be reused for another
	# instance source. A rejected candidate leaves every active consumer intact.
	for profile_name in ["MiniatureVisualProfile","ClearDaylightVisualProfile"]:
		var profile:=get_node_or_null(profile_name)
		if profile!=null and profile.field!=null and crowns.manifest.runtime.sha256!=profile.field_manifest.source_instance_sha256:
			whole_canopy_error="Whole-world canopy replacement does not match active contact field";crowns.free();return false
	if is_instance_valid(river_overlay):crowns.exclude_river(river_overlay)
	var bindings:Dictionary={}
	if is_instance_valid(natural_shorelines):
		bindings=natural_shorelines.prepare_canopy_bindings(crowns)
		if not bindings.get("ok",false):
			whole_canopy_error=str(bindings.get("error","Whole-world canopy shoreline binding failed"));crowns.free();return false
	var previous:=whole_canopies
	content_root.add_child(crowns);whole_canopies=crowns
	vegetation_root.hide();total_instances=crowns.total_count;whole_canopy_error=""
	if is_instance_valid(natural_shorelines):natural_shorelines.commit_canopy_bindings(bindings)
	if is_instance_valid(previous):previous.hide()
	# Synchronous observers replace material/picking references before retirement.
	whole_canopies_changed.emit()
	if is_instance_valid(previous):
		content_root.remove_child(previous);previous.queue_free()
	_update_budget()
	if clear_daylight_enabled and not is_instance_valid(clear_daylight_profile):call_deferred("apply_clear_daylight_profile")
	return true
func apply_clear_daylight_profile()->void:
	if not clear_daylight_enabled or not is_instance_valid(whole_canopies) or whole_canopies.selected_variant!="natural_v2":return
	clear_daylight_profile=preload("res://view/integrated_ecology_world/tabs_style/profile.gd").attach_to(self)
	if natural_shorelines_enabled:apply_natural_shorelines()
	apply_faceted_mountains()
func apply_natural_shorelines()->void:
	if is_instance_valid(natural_shorelines):return
	var layer:=preload("res://view/integrated_ecology_world/natural_shorelines/shore_layer.gd").new();layer.name="CanonicalNaturalShorelineSourceV03";content_root.add_child(layer)
	if not layer.install(self):
		compact_load_error=layer.last_error;push_error(compact_load_error);layer.queue_free();compact_root.hide();ground_root.hide();water_root.hide()
func apply_faceted_mountains()->void:
	var cache_root:="res://artifacts/faceted_mountains_20261002/"
	var material:ShaderMaterial=ground_material
	if is_instance_valid(natural_shorelines) and natural_shorelines.visible:
		cache_root+="shore_v03/"
		for child in natural_shorelines.get_children():
			if child is MeshInstance3D and str(child.name).begins_with("NaturalSource_ground_"):
				material=child.material_override;break
	if is_instance_valid(faceted_mountains) and faceted_mountains.loaded_cache_root!=cache_root:
		faceted_mountains.hide();faceted_mountains.queue_free();faceted_mountains=null
	if not is_instance_valid(faceted_mountains):
		var layer:=preload("res://view/integrated_ecology_world/faceted_mountains/mountain_layer.gd").new()
		layer.name="OriginalDecorativeFacetedMountainRanges";content_root.add_child(layer)
		if not layer.load_cache(manifest_sha,material,cache_root):push_error(layer.last_error);layer.queue_free();return
		faceted_mountains=layer
	faceted_mountains.visible=faceted_mountains_enabled and clear_daylight_enabled
func set_faceted_mountains(value:bool)->void:
	faceted_mountains_enabled=value
	if is_instance_valid(faceted_mountains):faceted_mountains.visible=value and clear_daylight_enabled
	elif value and clear_daylight_enabled:apply_faceted_mountains()
func set_clear_daylight(value:bool)->void:
	clear_daylight_enabled=value
	if is_instance_valid(faceted_mountains):faceted_mountains.visible=value and faceted_mountains_enabled
	if is_instance_valid(clear_daylight_profile):clear_daylight_profile.set_enabled(value)
	elif value:apply_clear_daylight_profile()
func _update_budget()->void:
	if is_instance_valid(whole_canopies):
		# Keep the original layer available for load failure/fallback, but never
		# duplicate/sort or mutate its hidden MultiMeshes on camera/budget changes.
		vegetation_root.hide();whole_canopies.update_lod(camera,target,overview,trees_enabled);visible_instances=whole_canopies.visible_count
	else:
		super._update_budget()
func set_trees(enabled:bool)->void:
	super.set_trees(enabled)
	if is_instance_valid(whole_canopies):vegetation_root.hide();whole_canopies.visible=enabled
