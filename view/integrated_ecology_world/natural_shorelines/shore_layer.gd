extends Node3D
## Actual separately-versioned terrain and solved water, never a shoreline decal.
const ROOT:="res://artifacts/natural_shorelines_v03_20261002/cache/"
var manifest:Dictionary={}
var last_error:=""
var source_view:Node3D
var triangles:=0
var build_ms:=0.0
var canopy_adjustments:Array=[]
var canopy_group_counts:Array=[]
var old_picks:Array=[]
var new_picks:Array=[]
func _bytes(name_:String)->PackedByteArray:
	var info:Dictionary=manifest.files[name_]
	var bytes:=FileAccess.get_file_as_bytes(ROOT+name_)
	return bytes.decompress(int(info.decoded_bytes),FileAccess.COMPRESSION_GZIP)
func install(view:Node3D)->bool:
	var start:=Time.get_ticks_usec();source_view=view
	var json:=JSON.new()
	if json.parse(FileAccess.get_file_as_string(ROOT+"manifest.json"))!=OK:last_error="New shoreline cache not ready";return false
	manifest=json.data
	if not preload("res://view/playable_build/world_bundle.gd").source_matches(str(manifest.source_mesh_sha256),str(manifest.source_drainage_sha256),FileAccess.get_sha256(ROOT+"manifest.json")):
		last_error="Active source bundle mismatch";return false
	for key in manifest.files:
		if FileAccess.get_sha256(ROOT+key)!=manifest.files[key].sha256:last_error="New shoreline cache hash mismatch: "+str(key);return false
	_load_source_topology()
	if not _load_canopy_bindings():return false
	var atlas:=Image.new();atlas.load_png_from_buffer(FileAccess.get_file_as_bytes(ROOT+"visual_weights_v03.png"));var atlas_texture:=ImageTexture.create_from_image(atlas)
	for row in manifest.chunks:
		var values:=_bytes(row.vertices).to_float32_array();var count:int=row.vertex_count
		var vs:=PackedVector3Array();var ns:=PackedVector3Array();var cs:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var ids:=PackedInt32Array()
		vs.resize(count);ns.resize(count);cs.resize(count);uv.resize(count);uv2.resize(count);ids.resize(count)
		for i in range(count):
			var j:=i*14;vs[i]=Vector3(values[j],values[j+1],values[j+2]);ns[i]=Vector3(values[j+3],values[j+4],values[j+5]);cs[i]=Color(values[j+6],values[j+7],values[j+8],values[j+9]);uv[i]=Vector2(values[j+10],values[j+11]);uv2[i]=Vector2(values[j+12],values[j+13]);ids[i]=i
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vs;arrays[Mesh.ARRAY_NORMAL]=ns;arrays[Mesh.ARRAY_COLOR]=cs;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_INDEX]=ids
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var mi:=MeshInstance3D.new();mi.name="NaturalSource_"+row.kind+"_"+row.key;mi.mesh=mesh;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat:ShaderMaterial=view.water_material if row.kind=="water" else view.ground_material.duplicate()
		if row.kind=="ground":
			mat.set_shader_parameter("use_shore_tile",0.0)
			mat.set_shader_parameter("visual_weights",atlas_texture)
		mi.material_override=mat;add_child(mi);triangles+=row.triangle_count
		var faces:=_bytes(row.provenance).to_int32_array();var prov:=PackedInt32Array();var bary:=PackedByteArray();bary.resize(count*16)
		for t in range(row.triangle_count):
			prov.append(faces[t*2]);prov.append(4);prov.append(faces[t*2+1])
			for k in range(3):
				var idx:=t*3+k;var p:Vector3=vs[idx];var bc:Array=preload("res://view/integrated_ecology_world/performance_variant/river_bridge.gd").source_bary(view,faces[t*2],p);bary.encode_u32(idx*16,faces[t*2]);bary.encode_float(idx*16+4,bc[0]);bary.encode_float(idx*16+8,bc[1]);bary.encode_float(idx*16+12,bc[2])
		new_picks.append({"vertices":vs,"indices":ids,"provenance":prov,"bary_bytes":bary,"water":row.kind=="water","key":"natural_v03_"+row.key,"bounds_min":row.bounds_min,"bounds_max":row.bounds_max})
	old_picks=view.picks;view.natural_shorelines=self;set_active(true);build_ms=float(Time.get_ticks_usec()-start)/1000.;return true
func set_active(value:bool)->void:
	visible=value
	if not is_instance_valid(source_view):return
	source_view.compact_root.visible=not value;source_view.water_root.visible=not value;source_view.ground_root.hide();source_view.picks=new_picks if value else old_picks
	if is_instance_valid(source_view.river_overlay):
		for mi in source_view.river_overlay.mesh_views:
			if mi.get_meta("river_surface_kind")=="ground":mi.visible=not value
	_apply_canopy_bindings(value)
	source_view._update_budget()
	if is_instance_valid(source_view.natural_shorelines):source_view.apply_faceted_mountains()
	source_view.canopy_support_changed.emit()
func report()->Dictionary:
	return {"enabled":visible,"triangles":triangles,"build_ms":build_ms,"source_mesh_sha256":manifest.get("source_mesh_sha256",""),"source_drainage_sha256":manifest.get("source_drainage_sha256",""),"old_science_acceptance_inherited":false,"scope":"NEW_SHARED_SOURCE_NATIVE_REVIEW","error":last_error}
var topology := preload("res://view/integrated_ecology_world/natural_shorelines/packed_topology.gd").new()
var source_spatial:Dictionary={}
func _load_source_topology()->void:
	var parser:=JSON.new();parser.parse(_bytes("source_topology_v03.json.gz").get_string_from_utf8());topology.load_data(parser.data)
	# JSON retains its parsed Dictionary too; release it before building the index.
	parser.data = null
	for fi in range(topology.face_count):
		var center:=Vector3.ZERO
		for corner in range(3):
			center+=topology.vertex_position(topology.vertex_index(fi,corner))/3.0
		var key:=Vector2i(floori(center.x/2.0),floori(center.z/2.0))
		if not source_spatial.has(key):source_spatial[key]=[]
		source_spatial[key].append(fi)
func _source_bary(fi:int,p:Vector3)->Vector3:
	var ps:Array=[]
	for corner in range(3):
		var v:Vector3=topology.vertex_position(topology.vertex_index(fi,corner));ps.append(Vector2(v.x,v.z))
	var u:Vector2=ps[1]-ps[0];var v:Vector2=ps[2]-ps[0];var rel:Vector2=Vector2(p.x,p.z)-ps[0];var det:=u.cross(v)
	var b:float=rel.cross(v)/det;var c:float=u.cross(rel)/det;return Vector3(1-b-c,b,c)
func decorate_hit(hit:Dictionary)->Dictionary:
	if not hit.get("ok",false) or not str(hit.get("cache_chunk","")).begins_with("natural_v03_"):return hit
	var fi:int=hit.source_row;var p:Array=hit.position;var bary:=_source_bary(fi,Vector3(p[0],p[1],p[2]))
	hit.legacy_face_index=hit.face_index;hit.face_index=fi;hit.new_source_face_index=fi;hit.source_face=topology.face(fi);hit.barycentric=[bary.x,bary.y,bary.z];hit.source_barycentric=hit.barycentric;hit.source_mesh_sha256=manifest.source_mesh_sha256;hit.height_provenance="V03_NEW_TERRAIN_OR_SOLVED_BODY_LEVEL";return hit
func source_context_at_xz(p:Vector2)->Dictionary:
	var cell:=Vector2i(floori(p.x/2.0),floori(p.y/2.0))
	for dx in range(-1,2):
		for dz in range(-1,2):
			for fi in source_spatial.get(cell+Vector2i(dx,dz),[]):
				var b:=_source_bary(fi,Vector3(p.x,0,p.y))
				if minf(b.x,minf(b.y,b.z))<-.00001:continue
				var f:Dictionary=topology.face(fi);var h:=0.0
				for j in range(3):h+=topology.vertex_height(topology.vertex_index(fi,j))*b[j]
				return {"ok":true,"face_index":fi,"new_source_face_index":fi,"legacy_face_index":f.legacy_parent_face_index,"position":[p.x,h,p.y],"height":h,"barycentric":[b.x,b.y,b.z],"source_barycentric":[b.x,b.y,b.z],"source_face":f,"canonical_hex":source_view.canonical_hex(Vector3(p.x,h,p.y)),"source_mesh_sha256":manifest.source_mesh_sha256,"height_provenance":"V03_NEW_TERRAIN_PLANE"}
	return {"ok":false}
func _load_canopy_bindings()->bool:
	if not is_instance_valid(source_view.whole_canopies):return true
	var bindings:=prepare_canopy_bindings(source_view.whole_canopies)
	if not bindings.get("ok",false):last_error=str(bindings.error);return false
	commit_canopy_bindings(bindings,false)
	return true
func prepare_canopy_bindings(crowns:Node3D)->Dictionary:
	# Build a replacement index without publishing it or mutating live transforms.
	# Support rows belong to one exact anchor manifest, not arbitrary row numbers.
	var file:="canopy_support_v03.json.gz"
	if not manifest.files.has(file):return {"ok":false,"error":"Shoreline canopy support missing"}
	if FileAccess.get_sha256(ROOT+file)!=manifest.files[file].sha256:return {"ok":false,"error":"Shoreline canopy support changed"}
	var parser:=JSON.new()
	if parser.parse(_bytes(file).get_string_from_utf8())!=OK or not parser.data is Dictionary:return {"ok":false,"error":"Invalid shoreline canopy support"}
	var data:Dictionary=parser.data
	if data.get("source_mesh_sha256")!=manifest.source_mesh_sha256 or data.get("legacy_anchor_manifest_sha256")!=crowns.manifest_sha256 or int(data.get("original_anchor_count",-1))!=crowns.total_count:
		return {"ok":false,"error":"Whole-world canopy replacement does not match active shoreline source"}
	var updates:Variant=data.get("updates")
	if not updates is Array or updates.size()!=crowns.total_count:return {"ok":false,"error":"Shoreline canopy support count mismatch"}
	var adjustments:Array=[];var counts:Array=[]
	for group in crowns.groups:
		var removed:=0
		for k in range(group.rows.size()):
			var index:int=group.rows[k]
			if index<0 or index>=updates.size() or not updates[index] is Dictionary:return {"ok":false,"error":"Shoreline canopy support row mismatch"}
			var change:Dictionary=updates[index]
			if change.get("row")!=index or not change.get("hide") is bool or not (change.get("height") is float or change.get("height") is int):return {"ok":false,"error":"Invalid shoreline canopy support row"}
			if not is_finite(float(change.height)):return {"ok":false,"error":"Invalid shoreline canopy support height"}
			if change.hide and not crowns.river_excluded.has(index):removed+=1
			for mi in [group.near,group.far]:
				var original:Transform3D=mi.multimesh.get_instance_transform(k);var current:=original;current.origin.y=change.height
				if change.hide:current.basis=Basis().scaled(Vector3.ZERO)
				adjustments.append({"mi":mi,"index":k,"original":original,"current":current})
		counts.append({"group":group,"original":group.active_count,"current":maxi(0,group.active_count-removed)})
	return {"ok":true,"adjustments":adjustments,"counts":counts}
func commit_canopy_bindings(bindings:Dictionary,apply_now:bool=true)->void:
	canopy_adjustments=bindings.adjustments;canopy_group_counts=bindings.counts
	if apply_now:_apply_canopy_bindings(visible)
func _apply_canopy_bindings(active:bool)->void:
	for row in canopy_adjustments:row.mi.multimesh.set_instance_transform(row.index,row.current if active else row.original)
	for row in canopy_group_counts:row.group.active_count=row.current if active else row.original
