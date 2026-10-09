extends "res://view/integrated_ecology_world/world_view.gd"
const Compact:=preload("res://view/integrated_ecology_world/performance_variant/compact_adapter.gd")
var compact_root:Node3D
var compact_manifest:Dictionary={}
var compact_sha:=""
var compact_enabled:=false
var luminance_enabled:=false
var compact_triangles:=0
var compact_vertices:=0
var variant_build_ms:=0.0
var luma_sha:=""
func _ready()->void:
	super._ready()
	ground_material.shader=preload("res://view/integrated_ecology_world/performance_variant/ground_luma.gdshader")
	ground_material.set_shader_parameter("soil_albedo",load("res://assets/materials/polyhaven/leafy_grass_diff_1k.jpg"));ground_material.set_shader_parameter("rock_albedo",load("res://assets/materials/polyhaven/rock_face_diff_1k.jpg"))
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
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vs;arrays[Mesh.ARRAY_NORMAL]=ns;arrays[Mesh.ARRAY_COLOR]=cs;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_INDEX]=indices;var me:=ArrayMesh.new();me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var mi:=MeshInstance3D.new();mi.name="Compact_"+str(chunk.key);mi.mesh=me;mi.material_override=ground_material;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;compact_root.add_child(mi);compact_vertices+=count;compact_triangles+=indices.size()/3
	compact_root.hide();variant_build_ms=float(Time.get_ticks_usec()-start)/1000.0
func set_compact(value:bool)->void:
	if not is_instance_valid(compact_root):return
	compact_enabled=value;ground_root.visible=not value;compact_root.visible=value
	if value:set_blend(true)
func set_luminance(value:bool)->void:luminance_enabled=value;ground_material.set_shader_parameter("use_baked_luminance",1.0 if value else 0.0)
func set_blend(value:bool)->void:
	if compact_enabled and not value:set_compact(false)
	super.set_blend(value)
func set_hex_scope(id:String)->void:
	var qr:=id.trim_prefix("hex:").split(",");var q:=int(qr[0]);var r:=int(qr[1]);var x:=sqrt(3.0)*(q+r*.5);var z:=r*1.5;target=Vector3(x,_height_at_xz(Vector2(x,z)),z);scope_name=id.replace(":","_").replace(",","_");overview=false;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.0;distance=8;pitch=.92;yaw=0;_update_camera()
func metrics()->Dictionary:
	var m:Dictionary=super.metrics();m.compact_geometry=compact_enabled;m.luminance_shader=luminance_enabled;m.compact_manifest_sha256=compact_sha;m.luma_manifest_sha256=luma_sha;m.compact_ground_vertices=compact_vertices;m.compact_ground_triangles=compact_triangles;m.variant_build_ms=variant_build_ms;m.actual_dry_geometry_omitted=false;m.logical_masks_modified=false;m.source_picking="FROZEN_BASELINE_ORIGINAL_FACE_BARY_PL_SAME_SUPPORT";return m
