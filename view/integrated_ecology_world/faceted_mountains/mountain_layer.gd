extends Node3D
## Read-only original display sculpture, NOT authoritative terrain or a collider.
## Strictly inside frozen actual dry rawrelief=mountain polygons; river corridor out.
const ROOT:="res://artifacts/faceted_mountains_20261002/"
const SHADER:=preload("res://view/integrated_ecology_world/faceted_mountains/mountains.gdshader")
var last_error:=""
var manifest:Dictionary={}
var triangles:=0
var vertices:=0
var build_ms:=0.0
var pick_groups:Array=[]
var height_cells:Dictionary={}
var loaded_cache_root:=""
func load_cache(source_sha:String,source_material:ShaderMaterial,cache_root:String=ROOT)->bool:
	var start:=Time.get_ticks_usec()
	var data=JSON.parse_string(FileAccess.get_file_as_string(cache_root+"manifest.json"))
	if not data is Dictionary:last_error="Mountain visual manifest unreadable";return false
	manifest=data
	if manifest.has("new_source_cache_manifest_sha256"):
		var source_manifest_path:="res://artifacts/natural_shorelines_v03_20261002/cache/manifest.json"
		var active=JSON.parse_string(FileAccess.get_file_as_string(source_manifest_path))
		if not active is Dictionary or active.get("source_mesh_sha256","")!=manifest.new_source_mesh_sha256 or active.get("source_drainage_sha256","")!=manifest.new_source_drainage_sha256 or active.get("dry_support_sha256","")!=manifest.new_source_dry_support_sha256:last_error="Mountain new shoreline geometry binding mismatch";return false
		# The world bundle separately pins the complete render manifest. Additional
		# atlas/canopy receipts may change it without changing this geometry.
		manifest["active_render_cache_sha256"]=FileAccess.get_sha256(source_manifest_path)
	if manifest.get("base_manifest_sha256","")!=source_sha or manifest.get("schema","")!="faceted-mountain-visual-layer/v1":last_error="Mountain visual source binding mismatch";return false
	var path:=cache_root+str(manifest.binary)
	if FileAccess.get_sha256(path)!=manifest.binary_sha256:last_error="Mountain visual mesh SHA mismatch";return false
	var raw:=FileAccess.get_file_as_bytes(path).decompress_dynamic(-1,FileAccess.COMPRESSION_GZIP).to_float32_array()
	if raw.size()!=int(manifest.vertices)*8:last_error="Mountain visual stride mismatch";return false
	var mat:=ShaderMaterial.new();mat.shader=SHADER
	for key in ["visual_weights","world_min","world_extent"]:mat.set_shader_parameter(key,source_material.get_shader_parameter(key))
	for row in manifest.groups:
		var vs:=PackedVector3Array();var ns:=PackedVector3Array();var cs:=PackedColorArray()
		for i in range(int(row.first_vertex),int(row.first_vertex)+int(row.vertices)):
			var j:=i*8;vs.append(Vector3(raw[j],raw[j+1],raw[j+2]));ns.append(Vector3(raw[j+3],raw[j+4],raw[j+5]));cs.append(Color(raw[j+6],raw[j+7],0,1))
		var a:=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=vs;a[Mesh.ARRAY_NORMAL]=ns;a[Mesh.ARRAY_COLOR]=cs
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
		var mi:=MeshInstance3D.new();mi.name="VisualRidgeGroup_"+str(get_child_count());mi.mesh=mesh;mi.material_override=mat;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("decorative_mountain_surface",true);mi.set_meta("source_region",row.region);add_child(mi)
		var group_index:=pick_groups.size()
		pick_groups.append({"vertices":vs,"bounds":mesh.get_aabb(),"source_region":str(row.region)})
		for t in range(0,vs.size(),3):
			var a_:Vector3=vs[t];var b_:Vector3=vs[t+1];var c_:Vector3=vs[t+2]
			for x in range(floori(minf(a_.x,minf(b_.x,c_.x))),floori(maxf(a_.x,maxf(b_.x,c_.x)))+1):
				for z in range(floori(minf(a_.z,minf(b_.z,c_.z))),floori(maxf(a_.z,maxf(b_.z,c_.z)))+1):
					var key:=Vector2i(x,z)
					if not height_cells.has(key):height_cells[key]=[]
					height_cells[key].append(Vector2i(group_index,t))
	loaded_cache_root=cache_root;triangles=int(manifest.triangles);vertices=int(manifest.vertices);build_ms=float(Time.get_ticks_usec()-start)/1000.0
	return true
func report()->Dictionary:
	return {"enabled":visible,"error":last_error,"loaded_cache_root":loaded_cache_root,"new_source_cache_sha256":manifest.get("new_source_cache_manifest_sha256",""),"triangles":triangles,"vertices":vertices,"groups":get_child_count(),"summits":manifest.get("summits",[]).size(),"build_ms":build_ms,"source_height_mutation":false,"source_identity_mutation":false,"visual_picking_aligned":true,"visual_pick_mapping":"VISIBLE_TRIANGLE_XZ_TO_FROZEN_SOURCE_FACE_HEX_AND_HEIGHT","collision_added":false,"flat_face_normals":true,"photographic_texture":false,"exact_dry_mountain_support_only":true,"max_outside_mountain_area":manifest.get("max_triangle_outside_actual_dry_mountain_area",-1),"max_river_overlap_area":manifest.get("max_triangle_river_corridor_overlap_area",-1)}

func inspect_visual(view:Node3D,screen:Vector2)->Dictionary:
	if not visible:return {"ok":false}
	var inv:=global_transform.affine_inverse()
	var origin:Vector3=inv*view.camera.project_ray_origin(screen)
	var dir:Vector3=(inv.basis*view.camera.project_ray_normal(screen)).normalized()
	var nearest:=INF;var hit:=Vector3.ZERO;var region:=""
	for group in pick_groups:
		var box:AABB=group.bounds
		if box.grow(.001).intersects_ray(origin,dir)==null:continue
		var vs:PackedVector3Array=group.vertices
		for i in range(0,vs.size(),3):
			var a:=vs[i];var b:=vs[i+1];var c:=vs[i+2]
			var e1:=b-a;var e2:=c-a;var h:=dir.cross(e2);var det:=e1.dot(h)
			if absf(det)<1e-10:continue
			var delta:=origin-a;var u:=delta.dot(h)/det
			if u < -.0001 or u>1.0001:continue
			var q:=delta.cross(e1);var v:=dir.dot(q)/det
			if v < -.0001 or u+v>1.0001:continue
			var t:=e2.dot(q)/det
			if t<0 or t>=nearest:continue
			# Clipped contour slivers can be ill-conditioned in float32. Require
			# the ray point to agree with its barycentric point on the actual face.
			var on_face:=a+e1*u+e2*v;var on_ray:=origin+dir*t
			if on_face.distance_squared_to(on_ray)>.000001:continue
			nearest=t;hit=on_face;region=group.source_region
	if nearest==INF:return {"ok":false}
	# Resolve the visible XZ through immutable original dry-triangle provenance.
	# Return original gameplay height/position, with separate visual hit position.
	var answer:=source_context_at_xz(view,Vector2(hit.x,hit.z))
	if not answer.get("ok",false):return answer
	answer.visual_position=[hit.x,hit.y,hit.z]
	answer.visual_surface="faceted_mountain"
	answer.visual_mountain_region=region
	answer.visual_height_is_gameplay_height=false
	return answer

func source_context_at_xz(view:Node3D,p:Vector2)->Dictionary:
	if is_instance_valid(view.natural_shorelines) and view.natural_shorelines.visible:
		var active:Dictionary=view.natural_shorelines.source_context_at_xz(p)
		if active.get("ok",false):active.water=false
		return active
	var answer:={"ok":false};var highest:=-INF
	for chunk in view.picks:
		if chunk.water:continue
		var lo:Array=chunk.bounds_min;var hi:Array=chunk.bounds_max
		if p.x<float(lo[0])-.000001 or p.x>float(hi[0])+.000001 or p.y<float(lo[2])-.000001 or p.y>float(hi[2])+.000001:continue
		var vs:PackedVector3Array=chunk.vertices;var ids:PackedInt32Array=chunk.indices
		for j in range(0,ids.size(),3):
			var a:=vs[ids[j]];var b:=vs[ids[j+1]];var c:=vs[ids[j+2]]
			var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var rel:=p-Vector2(a.x,a.z);var det:=u.cross(v)
			if absf(det)<1e-12:continue
			var wb:=rel.cross(v)/det;var wc:=u.cross(rel)/det
			if wb < -.00001 or wc < -.00001 or wb+wc>1.00001:continue
			var wa:=1.0-wb-wc;var source_y:=a.y*wa+b.y*wb+c.y*wc
			if source_y<=highest:continue
			var tri:=j/3;var fi:int=chunk.provenance[tri*3]
			if view.retired_river_faces.has(fi):continue
			highest=source_y
			var source_pos:=Vector3(p.x,source_y,p.y)
			answer={"ok":true,"face_index":fi,"position":[p.x,source_y,p.y],"height":source_y,"water":false,"mask_type":chunk.provenance[tri*3+1],"source_row":chunk.provenance[tri*3+2],"canonical_hex":view.canonical_hex(source_pos),"cache_chunk":chunk.key}
			var barys:=Vector3.ZERO
			for k in range(3):
				var byte_idx:int=ids[j+k]*16;var bb:PackedByteArray=chunk.bary_bytes;var weight:float=[wa,wb,wc][k]
				if bb.size()>byte_idx+15:barys+=Vector3(bb.decode_float(byte_idx+4),bb.decode_float(byte_idx+8),bb.decode_float(byte_idx+12))*weight
			answer.barycentric=[barys.x,barys.y,barys.z]
			var faces:Variant=view.source_topology.get("faces",[])
			if faces is Array and fi<faces.size():answer.source_face=faces[fi]
	return answer

func height_at_xz(p:Vector2)->float:
	if not visible:return -INF
	var highest:=-INF
	var refs:Array=height_cells.get(Vector2i(floori(p.x),floori(p.y)),[])
	for ref:Vector2i in refs:
		var vs:PackedVector3Array=pick_groups[ref.x].vertices
		var a:=vs[ref.y];var b:=vs[ref.y+1];var c:=vs[ref.y+2]
		var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var delta:=p-Vector2(a.x,a.z);var det:=u.cross(v)
		if absf(det)<1e-10:continue
		var wb:=delta.cross(v)/det;var wc:=u.cross(delta)/det
		if wb < -.000001 or wc < -.000001 or wb+wc>1.000001:continue
		highest=maxf(highest,a.y*(1-wb-wc)+b.y*wb+c.y*wc)
	return highest
