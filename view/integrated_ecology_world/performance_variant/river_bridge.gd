extends RefCounted
## Local derived render replacement only. No whole-world ecology acceptance.
const Compact:=preload("res://view/integrated_ecology_world/performance_variant/compact66_adapter.gd")
const Base:=preload("res://view/integrated_ecology_world/cache_adapter.gd")
static func _filter(indices:PackedInt32Array,provenance:PackedInt32Array,retired:Dictionary)->Dictionary:
	var ids:=PackedInt32Array();var prov:=PackedInt32Array();var removed:=0
	for j in range(0,indices.size(),3):
		if retired.has(int(provenance[j])):removed+=1;continue
		for k in range(3):ids.append(indices[j+k]);prov.append(provenance[j+k])
	return {"indices":ids,"provenance":prov,"removed":removed}
static func _replace_mesh(mi:MeshInstance3D,indices:PackedInt32Array)->void:
	if indices.is_empty():mi.hide();return
	var arrays:=mi.mesh.surface_get_arrays(0);arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mi.mesh=mesh
static func install(view:Node3D,overlay:Node3D)->Dictionary:
	if not view.river_surfaces.is_empty():return {"ok":false,"error":"Local river is already installed"}
	if overlay.transform!=Transform3D.IDENTITY:return {"ok":false,"error":"Local river must use original identity transform"}
	var c:Dictionary=overlay.get_integration_contract();var identity:Dictionary=c.get("source_identity",{})
	if identity.get("source_mesh_sha256","")!=view.manifest.source_identity.mesh.sha256 or identity.get("ecology_pending_sha256","")!=view.manifest.source_identity.ecology_pending.sha256:return {"ok":false,"error":"River/base source identity mismatch"}
	var retired:={}
	for fi in c.get("retire_original_ground_face_indices",[]):retired[int(fi)]=true
	if retired.is_empty():return {"ok":false,"error":"River contract has no retired source faces"}
	var compact_removed:=0;var base_removed:=0
	for chunk in view.compact_manifest.chunks:
		if not chunk.has("ground"):continue
		var row:Dictionary=chunk.ground;var mi:=view.compact_root.get_node_or_null("Compact_"+str(chunk.key)) as MeshInstance3D
		if mi==null:return {"ok":false,"error":"Compact ground chunk missing"}
		var filtered:=_filter(Compact.bytes(view.compact_manifest,row.indices).to_int32_array(),Compact.bytes(view.compact_manifest,row.faces).to_int32_array(),retired)
		if filtered.removed>0:_replace_mesh(mi,filtered.indices);compact_removed+=int(filtered.removed)
	for chunk in view.picks:
		if chunk.water:continue
		var filtered:=_filter(chunk.indices,chunk.provenance,retired)
		if filtered.removed==0:continue
		chunk.indices=filtered.indices;chunk.provenance=filtered.provenance;base_removed+=int(filtered.removed)
		var mi:=view.ground_root.get_node_or_null("Ground_"+str(chunk.key)) as MeshInstance3D
		if mi!=null:_replace_mesh(mi,filtered.indices)
	var metadata_by_kind:={}
	for node in overlay.get_children():
		if node.has_meta("river_triangle_provenance"):metadata_by_kind[str(node.get_meta("river_surface_kind"))]=node.get_meta("river_triangle_provenance")
	for mi in overlay.mesh_views:
		var kind:String=mi.get_meta("river_surface_kind");var arrays:Array=mi.mesh.surface_get_arrays(0)
		view.river_surfaces.append({"vertices":arrays[Mesh.ARRAY_VERTEX],"metadata":metadata_by_kind[kind],"kind":kind})
	# Reuse the world's RGB terrain palette/atlas and exact old-shore tile for
	# the tiny remainder. River banks and water use separate visual materials.
	var b:Array=c.footprint_bounds_xz;var center:=Vector2((float(b[0])+float(b[2]))*.5,(float(b[1])+float(b[3]))*.5)
	var chunk_key:="%d_%d"%[floori(center.x/12.0),floori(center.y/12.0)]
	var source_mesh:=view.compact_root.get_node_or_null("Compact_"+chunk_key) as MeshInstance3D
	if source_mesh!=null:overlay.set_surface_material("ground",source_mesh.material_override)
	var river_water:=ShaderMaterial.new();river_water.shader=preload("res://view/integrated_ecology_world/performance_variant/river_water.gdshader");overlay.set_surface_material("water",river_water)
	view.river_overlay=overlay;view.retired_river_faces=retired
	return {"ok":true,"scope":"LOCAL_RIVER_RENDER_REPLACEMENT_NO_WHOLE_ECOLOGY_ACCEPTANCE","retired_source_faces":retired.size(),"retired_compact_ground_triangles":compact_removed,"retired_baseline_ground_triangles":base_removed,"added_river_triangles":overlay.draw_triangles,"existing_water_retained_once":true}
static func source_bary(view:Node3D,fi:int,p:Vector3)->Array:
	var face:Dictionary=view.source_topology.faces[fi];var ps:Array=[]
	for vi in face.vertices:
		var v:Array=view.source_topology.vertices[vi].position;ps.append(Vector2(v[0],v[2]))
	var u:Vector2=ps[1]-ps[0];var v:Vector2=ps[2]-ps[0];var rel:Vector2=Vector2(p.x,p.z)-ps[0];var det:=u.cross(v)
	var wb:float=rel.cross(v)/det;var wc:float=u.cross(rel)/det;return [1.0-wb-wc,wb,wc]
static func inspect(view:Node3D,screen:Vector2)->Dictionary:
	var origin:Vector3=view.camera.project_ray_origin(screen);var dir:Vector3=view.camera.project_ray_normal(screen);var nearest:=INF;var answer:={"ok":false}
	for surface in view.river_surfaces:
		var vs:PackedVector3Array=surface.vertices
		for j in range(0,vs.size(),3):
			var a:=vs[j];var b:=vs[j+1];var c:=vs[j+2];var e1:=b-a;var e2:=c-a;var h:=dir.cross(e2);var det:=e1.dot(h)
			if absf(det)<1e-10:continue
			var s:=origin-a;var u:=s.dot(h)/det
			if u<0 or u>1:continue
			var q:=s.cross(e1);var v:=dir.dot(q)/det
			if v<0 or u+v>1:continue
			var t:=e2.dot(q)/det
			if t<0 or t>=nearest:continue
			nearest=t;var p:=origin+dir*t;var meta:Dictionary=surface.metadata[j/3];var fi:int=meta.original_face
			answer={"ok":true,"face_index":fi,"position":[p.x,p.y,p.z],"height":p.y,"water":surface.kind=="water","mask_type":3,"source_row":-1,"canonical_hex":meta.original_hex_id,"cache_chunk":"local_river","barycentric":source_bary(view,fi,p),"source_face":view.source_topology.faces[fi],"surface_kind":surface.kind,"local_river_preview":true,"height_provenance":"LOCAL_DERIVED_RIVER_SURFACE_OR_ORIGINAL_GROUND_REMAINDER"}
	return answer
static func height_at_xz(view:Node3D,p:Vector2)->float:
	var result:float=-INF
	for surface in view.river_surfaces:
		var vs:PackedVector3Array=surface.vertices
		for j in range(0,vs.size(),3):
			var a:=vs[j];var b:=vs[j+1];var c:=vs[j+2];var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var rel:=p-Vector2(a.x,a.z);var det:=u.cross(v)
			if absf(det)<1e-12:continue
			var wb:float=rel.cross(v)/det;var wc:float=u.cross(rel)/det
			if wb>=-1e-6 and wc>=-1e-6 and wb+wc<=1.000001:result=maxf(result,a.y*(1-wb-wc)+b.y*wb+c.y*wc)
	return result
