extends Node3D
## Every far LOD keeps the same actual source-contained crown footprint.
const Trees:=preload("res://view/ecology_preview/vegetation_meshes.gd")
const ROOT:="res://artifacts/integrated_ecology_world_20261002/performance_variant/world_canopies/"
const MANIFEST_SHA:="9bbe323fc338d5b693e6753878fad5c3646f75fee630299c844dd3863f7db0fb"
const NATURAL_ROOT:="res://artifacts/integrated_ecology_world_20261002/performance_variant/world_canopies_v2/"
const NATURAL_SHA:="347a77a9e009f88696653024202bcb53404adad9f43af09e3afbebd97656f2ca"
var cache_root:=ROOT
var selected_variant:="v1"
var manifest:Dictionary={}
var groups:Array=[]
var total_count:=0
var visible_count:=0
var visible_triangles:=0
var last_error:=""
var lod_mode:=""
var river_excluded:Dictionary={}
var instance_rows:PackedFloat32Array
func load_cache(base:Dictionary,variant:String="v1")->bool:
	selected_variant=variant;cache_root=NATURAL_ROOT if variant=="natural_v2" else ROOT
	var expected_sha:=NATURAL_SHA if variant=="natural_v2" else MANIFEST_SHA
	if FileAccess.get_sha256(cache_root+"manifest.json")!=expected_sha:last_error="Whole-world canopy manifest changed";return false
	var p:=JSON.new()
	if p.parse(FileAccess.get_file_as_string(cache_root+"manifest.json"))!=OK or not p.data is Dictionary:last_error="Whole-world canopy manifest missing";return false
	manifest=p.data
	if manifest.get("source_ecology_sha256","")!=base.source_identity.ecology_pending.sha256 or manifest.get("source_mesh_sha256","")!=base.source_identity.mesh.sha256:last_error="Whole-world canopy source identity mismatch";return false
	var row:Dictionary=manifest.runtime
	if FileAccess.get_sha256(cache_root+str(row.file))!=row.sha256:last_error="Whole-world canopy cache SHA mismatch";return false
	var f:=FileAccess.get_file_as_bytes(cache_root+str(row.file));instance_rows=f.decompress(int(row.decoded_bytes),FileAccess.COMPRESSION_GZIP).to_float32_array()
	if instance_rows.size()!=int(manifest.instances)*10:last_error="Whole-world canopy cache stride mismatch";return false
	var materials:=ShaderMaterial.new();materials.shader=preload("res://view/ecology_preview/vegetation_surface.gdshader")
	var buckets:={};var kinds:Array=row.kinds
	for i in range(int(manifest.instances)):
		var j:=i*10;var pp:=Vector3(instance_rows[j],instance_rows[j+1],instance_rows[j+2]);var kind:String=kinds[int(instance_rows[j+7])];var key:="%s_%d_%d"%[kind,floori(pp.x/6),floori(pp.z/6)]
		if not buckets.has(key):buckets[key]={"kind":kind,"rows":[],"center":Vector3.ZERO}
		buckets[key].rows.append(i);buckets[key].center+=pp
	var full_meshes:={};var low_meshes:={}
	for kind in kinds:full_meshes[kind]=Trees.make(kind);low_meshes[kind]=_low_crown(kind)
	for key in buckets:
		var g:Dictionary=buckets[key];var center:Vector3=g.center/g.rows.size();var entries:=[]
		for low in [false,true]:
			var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=low_meshes[g.kind] if low else full_meshes[g.kind];mm.instance_count=g.rows.size()
			for k in range(g.rows.size()):
				var j:int=g.rows[k]*10;var pos:=Vector3(instance_rows[j],instance_rows[j+1],instance_rows[j+2]);var radius:float=instance_rows[j+3];var height_:float=instance_rows[j+4];var yaw_:float=instance_rows[j+5];var factor:float=instance_rows[j+6]
				mm.set_instance_transform(k,Transform3D(Basis(Vector3.UP,-yaw_).scaled(Vector3(radius,height_,radius)),pos));mm.set_instance_color(k,Color(factor,factor,factor,1))
			var mi:=MultiMeshInstance3D.new();mi.name=key+("_far_same_crown" if low else "_near_full_tree");mi.multimesh=mm;mi.material_override=materials;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mi);entries.append(mi)
		groups.append({"center":center,"count":g.rows.size(),"active_count":g.rows.size(),"near":entries[0],"far":entries[1],"rows":g.rows,"near_triangles":full_meshes[g.kind].get_faces().size()/3});total_count+=g.rows.size()
	return true
func _low_crown(kind:String)->ArrayMesh:
	var colors:={"temperate":Color("66854b"),"tropical":Color("3f765b"),"sapling":Color("a1ac56"),"shrub":Color("a48b55")};var data:={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()};var ring_y:=.81 if kind=="tropical" else .69;var color:Color=colors[kind].srgb_to_linear()
	for i in range(7):
		var a:=Vector3(cos(TAU*i/7.0),ring_y,sin(TAU*i/7.0));var b:=Vector3(cos(TAU*(i+1)/7.0),ring_y,sin(TAU*(i+1)/7.0));Trees._tri(data,a,b,Vector3(0,1.01,0),color*(1.02 if i%2 else 1.08))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=data.vertices;arrays[Mesh.ARRAY_NORMAL]=data.normals;arrays[Mesh.ARRAY_COLOR]=data.colors;var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
func update_lod(camera:Camera3D,target:Vector3,overview:bool,enabled:bool)->void:
	visible=enabled;visible_count=0;visible_triangles=0
	var low:=overview or camera.size>=22.0;lod_mode="FAR_ALL_SOURCE_CROWNS_7_TRIANGLES" if low else "NEAR_FULL_TREE_GEOMETRY"
	var aspect:=camera.get_viewport().get_visible_rect().size.x/maxf(1,camera.get_viewport().get_visible_rect().size.y);var range_:float=maxf(12,camera.size*maxf(1,aspect)*.8+6)
	for group in groups:
		var in_range:bool=overview or group.center.distance_to(target)<range_
		group.near.visible=in_range and not low;group.far.visible=in_range and low
		if in_range and enabled:visible_count+=int(group.active_count);visible_triangles+=int(group.active_count)*(7 if low else int(group.near_triangles))
func exclude_river(overlay:Node3D)->int:
	# Crown rejection uses the exact river footprint, not a center-only rule.
	var c:Dictionary=overlay.get_integration_contract();var footprint:=PackedVector2Array()
	for p in c.footprint_polygon_xz:footprint.append(Vector2(p[0],p[1]))
	var bounds_:Array=c.footprint_bounds_xz;var removed:=0
	for group in groups:
		for k in range(group.rows.size()):
			if river_excluded.has(int(group.rows[k])):continue
			var j:int=group.rows[k]*10;var x:float=instance_rows[j];var z:float=instance_rows[j+2];var radius:float=instance_rows[j+3]
			if x+radius<bounds_[0] or x-radius>bounds_[2] or z+radius<bounds_[1] or z-radius>bounds_[3]:continue
			var yaw_:float=instance_rows[j+5];var crown:=PackedVector2Array()
			for n in range(7):crown.append(Vector2(x+radius*cos(yaw_+TAU*n/7.0),z+radius*sin(yaw_+TAU*n/7.0)))
			if Geometry2D.intersect_polygons(crown,footprint).is_empty():continue
			for mi in [group.near,group.far]:
				var tr:Transform3D=mi.multimesh.get_instance_transform(k);tr.basis=Basis().scaled(Vector3.ZERO);mi.multimesh.set_instance_transform(k,tr)
			removed+=1;group.active_count-=1;river_excluded[int(group.rows[k])]=true
	return removed
