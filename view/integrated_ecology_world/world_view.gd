extends Node3D
## All content shares this sole, identity-scale parent and original source XZ.
const Adapter:=preload("res://view/integrated_ecology_world/cache_adapter.gd")
const Trees:=preload("res://view/ecology_preview/vegetation_meshes.gd")
var content_root:Node3D
var ground_root:Node3D
var water_root:Node3D
var grid_root:Node3D
var vegetation_root:Node3D
var camera:Camera3D
var manifest:Dictionary={}
var ground_material:ShaderMaterial
var water_material:ShaderMaterial
var grid_material:ShaderMaterial
var target:=Vector3.ZERO
var distance:=14.0
var pitch:=.72
var yaw:=0.0
var overview:=true
var grid_enabled:=false
var trees_enabled:=true
var shared_ground:=true
var bands_enabled:=true
var visual_blend:=false
var bounds:AABB
var build_ms:=0.0
var picks:Array=[]
var tree_groups:Array=[]
var source_topology:Dictionary={}
var manifest_sha:=""
var total_instances:=0
var visible_instances:=0
var budget:=12000
var scope_name:="whole"
func _ready()->void:
	content_root=Node3D.new();content_root.name="SharedIdentitySourceTransform_1x";add_child(content_root)
	for name_ in ["Ground","ExactSourceWetFootprints","OriginalCompleteHexGrid","DecorativeAnchoredVegetation"]:
		var n:=Node3D.new();n.name=name_;content_root.add_child(n)
	ground_root=content_root.get_child(0);water_root=content_root.get_child(1);grid_root=content_root.get_child(2);vegetation_root=content_root.get_child(3)
	camera=Camera3D.new();camera.near=.05;camera.far=512;camera.keep_aspect=Camera3D.KEEP_HEIGHT;add_child(camera);camera.current=true
	var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("758e97");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("c4d6dc");e.ambient_light_energy=.38;e.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	var en:=WorldEnvironment.new();en.environment=e;add_child(en)
	for light in [[Color("fff0cf"),1.06,Vector3(-35,-34,0)],[Color("b5d1f2"),.32,Vector3(-22,125,0)],[Color("ffdbb6"),.27,Vector3(-20,-140,0)]]:
		var l:=DirectionalLight3D.new();l.light_color=light[0];l.light_energy=light[1];l.rotation_degrees=light[2];l.shadow_enabled=false;add_child(l)
	ground_material=ShaderMaterial.new();ground_material.shader=preload("res://view/integrated_ecology_world/ground.gdshader")
	ground_material.set_shader_parameter("soil_albedo",load("res://assets/materials/polyhaven/leafy_grass_diff_1k.jpg"));ground_material.set_shader_parameter("rock_albedo",load("res://assets/materials/polyhaven/rock_face_diff_1k.jpg"))
	water_material=ShaderMaterial.new();water_material.shader=preload("res://view/integrated_ecology_world/water.gdshader")
	grid_material=ShaderMaterial.new();grid_material.shader=preload("res://view/integrated_ecology_world/grid.gdshader")
func show_cache(data:Dictionary)->void:
	var t:=Time.get_ticks_usec();manifest=data.manifest;manifest_sha=data.manifest_sha256
	var a:Array=manifest.bounds_min;var b:Array=manifest.bounds_max;bounds=AABB(Vector3(a[0],a[1],a[2]),Vector3(b[0]-a[0],b[1]-a[1],b[2]-a[2]))
	ground_material.set_shader_parameter("world_min",Vector2(a[0],a[2]));ground_material.set_shader_parameter("world_extent",Vector2(b[0]-a[0],b[2]-a[2]))
	for row in manifest.chunks:
		if row.has("ground"):_add_chunk(ground_root,row,row.ground,ground_material,false)
		if row.has("water"):_add_chunk(water_root,row,row.water,water_material,true)
	if manifest.has("grid"):_add_grid()
	if manifest.has("anchors"):_add_cover()
	if manifest.has("visual_weights"):
		var im:=Image.new();im.load_png_from_buffer(FileAccess.get_file_as_bytes(Adapter.ROOT+manifest.visual_weights.path));ground_material.set_shader_parameter("visual_weights",ImageTexture.create_from_image(im));
		if manifest.visual_weights.has("details"):
			var di:=Image.new();di.load_png_from_buffer(FileAccess.get_file_as_bytes(Adapter.ROOT+manifest.visual_weights.details));ground_material.set_shader_parameter("visual_details",ImageTexture.create_from_image(di))
		set_blend(true)
	# Source topology is loaded once for source face/bary inspection, not gameplay facts.
	var top:Variant=Adapter.read_json(manifest,str(manifest.get("source_face_table","")))
	if top is Dictionary:source_topology=top
	set_grid(false);set_scope("whole");build_ms=float(Time.get_ticks_usec()-t)/1000.0
func _add_chunk(parent:Node3D,chunk:Dictionary,row:Dictionary,mat:Material,wet:bool)->void:
	var values:=Adapter.bytes(manifest,row.vertices).to_float32_array();var indices:=Adapter.bytes(manifest,row.indices).to_int32_array()
	var n:int=row.vertex_count
	if values.size()!=n*14:push_error("bad cache stride "+str(row.vertices));return
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array()
	vertices.resize(n);normals.resize(n);colors.resize(n);uv.resize(n);uv2.resize(n)
	for i in range(n):
		var j:=i*14;vertices[i]=Vector3(values[j],values[j+1],values[j+2]);normals[i]=Vector3(values[j+3],values[j+4],values[j+5]);colors[i]=Color(values[j+6],values[j+7],values[j+8],values[j+9]);uv[i]=Vector2(values[j+10],values[j+11]);uv2[i]=Vector2(values[j+12],values[j+13])
	var ar:=[];ar.resize(Mesh.ARRAY_MAX);ar[Mesh.ARRAY_VERTEX]=vertices;ar[Mesh.ARRAY_NORMAL]=normals;ar[Mesh.ARRAY_COLOR]=colors;ar[Mesh.ARRAY_TEX_UV]=uv;ar[Mesh.ARRAY_TEX_UV2]=uv2;ar[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,ar)
	var mi:=MeshInstance3D.new();mi.name=("Water_" if wet else "Ground_")+str(chunk.key);mi.mesh=mesh;mi.material_override=mat;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(mi)
	var prov:=Adapter.bytes(manifest,row.faces).to_int32_array()
	var bary_bytes:=Adapter.bytes(manifest,row.get("vertex_provenance",""))
	picks.append({"vertices":vertices,"indices":indices,"provenance":prov,"bary_bytes":bary_bytes,"water":wet,"key":chunk.key,"bounds_min":chunk.bounds_min,"bounds_max":chunk.bounds_max})
func _add_grid()->void:
	var vals:=Adapter.bytes(manifest,manifest.grid.vertices).to_float32_array();var verts:=PackedVector3Array();var uvs:=PackedVector2Array();var normals:=PackedVector3Array()
	for j in range(0,vals.size()-5,6):
		var a:=Vector3(vals[j],vals[j+1]+.013,vals[j+2]);var b:=Vector3(vals[j+3],vals[j+4]+.013,vals[j+5]);var off:=Vector3(-(b.z-a.z),0,b.x-a.x).normalized()*.006
		var ps:=[a-off,a+off,b+off,a-off,b+off,b-off];var signs:=[-1,1,1,-1,1,-1]
		for k in range(6):verts.append(ps[k]);normals.append(Vector3.UP);uvs.append(Vector2(off.x,off.z)*signs[k])
	var ar:=[];ar.resize(Mesh.ARRAY_MAX);ar[Mesh.ARRAY_VERTEX]=verts;ar[Mesh.ARRAY_NORMAL]=normals;ar[Mesh.ARRAY_TEX_UV2]=uvs
	var me:=ArrayMesh.new();me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,ar);var mi:=MeshInstance3D.new();mi.mesh=me;mi.material_override=grid_material;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;grid_root.add_child(mi)
func _add_cover()->void:
	var raw:Variant=Adapter.read_json(manifest,manifest.anchors.path)
	var rows:Array=[]
	if raw is Array:rows=raw
	elif raw is Dictionary:rows=raw.get("anchors",raw.get("canopies",[]))
	var groups:={};var materials:=ShaderMaterial.new();materials.shader=preload("res://view/ecology_preview/vegetation_surface.gdshader")
	for p in rows:
		var pp:Array=p.get("position",p.get("pos",[0,0,0]));var kind:String=p.get("kind","temperate");var key:="%s_%d_%d"%[kind,floori(float(pp[0])/6),floori(float(pp[2])/6)]
		if not groups.has(key):groups[key]={"kind":kind,"plants":[],"center":Vector3.ZERO}
		groups[key].plants.append(p);groups[key].center+=Vector3(pp[0],pp[1],pp[2])
	for key in groups:
		var g:Dictionary=groups[key];var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=Trees.make(g.kind);mm.instance_count=g.plants.size()
		for i in range(mm.instance_count):
			var p:Dictionary=g.plants[i];var pp:Array=p.get("position",p.get("pos",[0,0,0]));var radius_:float=p.get("radius",.16);var height_:float=p.get("height",.6);var basis_:=Basis(Vector3.UP,-float(p.get("yaw",0))).scaled(Vector3(radius_,height_,radius_));mm.set_instance_transform(i,Transform3D(basis_,Vector3(pp[0],pp[1],pp[2])));var f:float=p.get("color_factor",1);mm.set_instance_color(i,Color(f,f,f,1))
		var mi:=MultiMeshInstance3D.new();mi.name=key;mi.multimesh=mm;mi.material_override=materials;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;vegetation_root.add_child(mi);tree_groups.append({"instance":mi,"count":mm.instance_count,"center":g.center/mm.instance_count});total_instances+=mm.instance_count
func set_trees(enabled:bool)->void:trees_enabled=enabled;vegetation_root.visible=enabled;_update_budget()
func set_grid(enabled:bool)->void:grid_enabled=enabled;grid_root.visible=enabled
func set_shared_ground(enabled:bool)->void:shared_ground=enabled;ground_material.set_shader_parameter("shared_woodland_ground",1.0 if enabled else 0.0)
func set_bands(enabled:bool)->void:bands_enabled=enabled;ground_material.set_shader_parameter("shore_bands",1.0 if enabled else 0.0);water_material.set_shader_parameter("shore_bands",1.0 if enabled else 0.0)
func set_blend(enabled:bool)->void:
	if not manifest.has("visual_weights"):return
	visual_blend=enabled;ground_material.set_shader_parameter("visual_blend",1.0 if enabled else 0.0)
func set_scope(name_:String)->void:
	scope_name=name_;overview=name_=="whole";camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	if overview:
		target=bounds.get_center();target.y=0;var size:=get_viewport().get_visible_rect().size;var aspect:=size.x/maxf(1,size.y);camera.size=maxf(bounds.size.z,bounds.size.x/aspect)*1.045;camera.position=Vector3(target.x,bounds.end.y+100,target.z);camera.look_at(target,Vector3(0,0,-1));distance=100
	else:
		var key:String="ocean" if name_=="coast" else "coastal" if name_=="lake" else name_
		var scope:Dictionary=manifest.get("cameras",{}).get(key,{})
		var tt:Array=scope.get("target",[])
		if tt.size()==3:target=Vector3(tt[0],tt[1],tt[2])
		else:
			var xz:Array=scope.get("target_xz",[-2.8052,-22.5971]);target=Vector3(xz[0],0,xz[1]);target.y=_height_at_xz(Vector2(xz[0],xz[1]))
		camera.size=float(scope.get("size",10));distance=float(scope.get("distance",14));pitch=.72;yaw=float(scope.get("yaw",0));_update_camera()
	_update_budget();_update_grid()
func _height_at_xz(p:Vector2)->float:
	var h:float=-INF
	for chunk in picks:
		var lo:Array=chunk.bounds_min;var hi:Array=chunk.bounds_max
		if p.x<float(lo[0]) or p.x>float(hi[0]) or p.y<float(lo[2]) or p.y>float(hi[2]):continue
		var vs:PackedVector3Array=chunk.vertices;var ids:PackedInt32Array=chunk.indices
		for j in range(0,ids.size(),3):
			var a:=vs[ids[j]];var b:=vs[ids[j+1]];var c:=vs[ids[j+2]];var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var rel:=p-Vector2(a.x,a.z);var det:=u.cross(v)
			if absf(det)<1e-12:continue
			var wb:=rel.cross(v)/det;var wc:=u.cross(rel)/det
			if wb>=-1e-6 and wc>=-1e-6 and wb+wc<=1.000001:h=maxf(h,a.y*(1-wb-wc)+b.y*wb+c.y*wc)
	return h if h>-INF else 0.0
func orbit(dx:float,dy:float)->void:
	if overview:scope_name="free";overview=false;camera.size=12;distance=16
	yaw-=dx;pitch=clampf(pitch+dy,.3,1.42);_update_camera()
func zoom(delta:float)->void:
	camera.size=clampf(camera.size*exp(delta*.12),4,100);if not overview:distance=clampf(distance*exp(delta*.12),7,45);_update_camera()
	_update_grid();_update_budget()
func pan(dx:float,dy:float)->void:
	var scale_:float=camera.size/maxf(1,get_viewport().get_visible_rect().size.y);target+=Vector3(-dx,0,-dy)*scale_
	if overview:camera.position.x=target.x;camera.position.z=target.z
	else:_update_camera()
	_update_budget()
func _update_camera()->void:camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance;camera.look_at(target,Vector3.UP);_update_budget();_update_grid()
func _update_grid()->void:
	var px:=camera.size/maxf(1,get_viewport().get_visible_rect().size.y);grid_material.set_shader_parameter("width_scale",clampf(px*.7/.012,1,15))
func _update_budget()->void:
	visible_instances=0;var ordered:=tree_groups.duplicate();ordered.sort_custom(func(a,b):return a.center.distance_squared_to(target)<b.center.distance_squared_to(target))
	for group in ordered:
		var count:int=group.count;var center:Vector3=group.center;var limit:=camera.size*.9 if overview else maxf(10,camera.size*1.2)
		var wanted:=ceili(count*.125) if overview else count
		if center.distance_to(target)>limit:wanted=0
		wanted=mini(wanted,maxi(0,budget-visible_instances));group.instance.multimesh.visible_instance_count=wanted;group.instance.visible=wanted>0;visible_instances+=wanted
	if not trees_enabled:visible_instances=0
func inspect(screen:Vector2)->Dictionary:
	var inv:=content_root.global_transform.affine_inverse();var origin:=inv*camera.project_ray_origin(screen);var dir:Vector3=(inv.basis*camera.project_ray_normal(screen)).normalized();var nearest:=INF;var answer:={"ok":false}
	for chunk in picks:
		var lo:Array=chunk.bounds_min;var hi:Array=chunk.bounds_max;var box:=AABB(Vector3(lo[0]-.001,lo[1]-.02,lo[2]-.001),Vector3(hi[0]-lo[0]+.002,hi[1]-lo[1]+.04,hi[2]-lo[2]+.002))
		if box.intersects_ray(origin,dir)==null:continue
		var vs:PackedVector3Array=chunk.vertices;var ids:PackedInt32Array=chunk.indices
		for j in range(0,ids.size(),3):
			var a:=vs[ids[j]];var b:=vs[ids[j+1]];var c:=vs[ids[j+2]];var e1:=b-a;var e2:=c-a;var h:=dir.cross(e2);var det:=e1.dot(h)
			if absf(det)<1e-10:continue
			var s:=origin-a;var u:=s.dot(h)/det;if u<0 or u>1:continue
			var q:=s.cross(e1);var v:=dir.dot(q)/det;if v<0 or u+v>1:continue
			var t:=e2.dot(q)/det;if t<0 or t>=nearest:continue
			nearest=t;var p:=origin+dir*t;var tri:=j/3;var fi:int=chunk.provenance[tri*3];answer={"ok":true,"face_index":fi,"position":[p.x,p.y,p.z],"height":p.y,"water":chunk.water,"mask_type":chunk.provenance[tri*3+1],"source_row":chunk.provenance[tri*3+2],"canonical_hex":canonical_hex(p),"cache_chunk":chunk.key}
			var barys:=Vector3.ZERO
			for k in range(3):
				var byte_idx:int=ids[j+k]*16;var bb:PackedByteArray=chunk.bary_bytes;var weight:float=[1-u-v,u,v][k]
				if bb.size()>byte_idx+15:barys+=Vector3(bb.decode_float(byte_idx+4),bb.decode_float(byte_idx+8),bb.decode_float(byte_idx+12))*weight
			answer.barycentric=[barys.x,barys.y,barys.z]
			var faces:Variant=source_topology.get("faces",[])
			if faces is Array and fi<faces.size():answer.source_face=faces[fi]
	return answer
static func canonical_hex(p:Vector3)->String:
	var qf:=p.x/sqrt(3)-p.z/3;var rf:=p.z*2/3;var sf:=-qf-rf;var q:=roundi(qf);var r:=roundi(rf);var s:=roundi(sf);var dq:=absf(q-qf);var dr:=absf(r-rf);var ds:=absf(s-sf)
	if dq>dr and dq>ds:q=-r-s
	elif dr>ds:r=-q-s
	return "hex:%d,%d"%[q,r]
func metrics()->Dictionary:
	return {"diagnostic_status":manifest.get("status","NOT_LOADED"),"manifest_sha256":manifest_sha,"scope":scope_name,"height_scale":1,"shared_transform":content_root.transform,"ground_chunks":ground_root.get_child_count(),"water_chunks":water_root.get_child_count(),"total_cached_instances":total_instances,"visible_instances":visible_instances,"camera_range_budget":budget,"whole_lod_fraction":.125,"cover_status":"ACTUAL_CACHED_CANOPY_REQUIRES_LEDGER_NOT_ELIGIBLE_AS_COVER","trees":trees_enabled,"grid":grid_enabled,"B1_shared_ground":shared_ground,"B2_visual_blend":visual_blend,"shore_bands":bands_enabled,"build_ms":build_ms,"camera_size":camera.size,"camera_position":[camera.position.x,camera.position.y,camera.position.z],"camera_target":[target.x,target.y,target.z],"camera_forward":[-camera.global_basis.z.x,-camera.global_basis.z.y,-camera.global_basis.z.z],"device":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"target_1660ti_tested":false}

func make_merged_diagnostic_geometry()->Node3D:
	var root_:=Node3D.new();root_.name="DiagnosticSameGeometryMergedBatches";content_root.add_child(root_)
	for source_root in [ground_root,water_root]:
		var verts:=PackedVector3Array();var norms:=PackedVector3Array();var colors:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array();var ids:=PackedInt32Array()
		for mi in source_root.get_children():
			var a:Array=mi.mesh.surface_get_arrays(0);var offset:=verts.size();verts.append_array(a[Mesh.ARRAY_VERTEX]);norms.append_array(a[Mesh.ARRAY_NORMAL]);colors.append_array(a[Mesh.ARRAY_COLOR]);uv.append_array(a[Mesh.ARRAY_TEX_UV]);uv2.append_array(a[Mesh.ARRAY_TEX_UV2]);var chunk_ids:PackedInt32Array=a[Mesh.ARRAY_INDEX]
			for idx in chunk_ids:ids.append(idx+offset)
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_NORMAL]=norms;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_INDEX]=ids
		var me:=ArrayMesh.new();me.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);var instance:=MeshInstance3D.new();instance.mesh=me;instance.material_override=ground_material if source_root==ground_root else water_material;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root_.add_child(instance)
	return root_
