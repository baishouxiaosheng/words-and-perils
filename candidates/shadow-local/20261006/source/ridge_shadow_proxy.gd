extends RefCounted
## Decorative, shadow-only approximation. Never mutate source mesh or physics.
const FOOT_U := 0.025

static func terrain_y(p: Vector3, ground: PackedVector3Array) -> float:
	var height := -INF
	for i in range(0,ground.size(),3):
		var a:=ground[i];var b:=ground[i+1];var c:=ground[i+2]
		var ab:=Vector2(b.x-a.x,b.z-a.z);var ac:=Vector2(c.x-a.x,c.z-a.z)
		var det:=ab.cross(ac)
		if absf(det)<1e-12:continue
		var ap:=Vector2(p.x-a.x,p.z-a.z)
		var wb:=ap.cross(ac)/det;var wc:=ab.cross(ap)/det
		if wb < -0.00001 or wc < -0.00001 or wb+wc > 1.00001:continue
		height=maxf(height,a.y*(1.0-wb-wc)+b.y*wb+c.y*wc)
	return height

static func build(vertices: PackedVector3Array, colors: PackedColorArray, ground: PackedVector3Array) -> Dictionary:
	if vertices.size()%3!=0 or vertices.size()!=colors.size():return {"ok":false,"error":"Invalid source triangle attributes"}
	var output:=PackedVector3Array();var contact_edges:Array=[]
	var removed:=0;var crossed:=0;var inserted:=0;var retained:=0
	for i in range(0,vertices.size(),3):
		var polygon:Array=[]
		for k in range(3):polygon.append({"p":vertices[i+k],"u":colors[i+k].g*4.0,"contact":false})
		var clipped:Array=[]
		for k in range(3):
			var a:Dictionary=polygon[k];var b:Dictionary=polygon[(k+1)%3]
			var ia:bool=a.u>=FOOT_U;var ib:bool=b.u>=FOOT_U
			if ia:clipped.append(a);retained+=1
			if ia!=ib:
				var point:Vector3=a.p.lerp(b.p,(FOOT_U-a.u)/(b.u-a.u))
				var h:=terrain_y(point,ground)
				if not is_finite(h):return {"ok":false,"error":"No frozen ground triangle at clipped contact","triangle":i/3}
				point.y=h
				clipped.append({"p":point,"u":FOOT_U,"contact":true});inserted+=1
		if clipped.size()<3:removed+=1;continue
		if clipped.any(func(v:Dictionary)->bool:return v.contact):crossed+=1
		for k in range(clipped.size()):
			var a:Dictionary=clipped[k];var b:Dictionary=clipped[(k+1)%clipped.size()]
			if a.contact and b.contact:contact_edges.append([a.p,b.p])
		for k in range(1,clipped.size()-1):
			var a:Vector3=clipped[0].p;var b:Vector3=clipped[k].p;var c:Vector3=clipped[k+1].p
			if (b-a).cross(c-a).length_squared()>1e-16:output.append_array(PackedVector3Array([a,b,c]))
	var max_edge_gap:=0.0
	for edge in contact_edges:
		for sample in range(1,16):
			var point:Vector3=edge[0].lerp(edge[1],float(sample)/16.0)
			var h:=terrain_y(point,ground)
			if is_finite(h):max_edge_gap=maxf(max_edge_gap,absf(point.y-h))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=output
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var high_count:=0;var missing_high:=0;var missing_retained:=0
	for i in range(vertices.size()):
		if colors[i].g*4.0>=FOOT_U and not output.has(vertices[i]):missing_retained+=1
		if colors[i].g*4.0>=0.14:
			high_count+=1
			if not output.has(vertices[i]):missing_high+=1
	if missing_high>0 or missing_retained>0:return {"ok":false,"error":"Retained source vertex was lost","missing_high":missing_high,"missing_retained":missing_retained}
	return {"ok":true,"mesh":mesh,"report":{"source_triangles":vertices.size()/3,"proxy_triangles":output.size()/3,"fully_removed":removed,"crossed_triangles":crossed,"new_contact_vertices":inserted,"retained_original_vertex_occurrences":retained,"verified_high_u_vertex_occurrences":high_count,"missing_high_u_vertices":missing_high,"missing_retained_vertices":missing_retained,"contact_edges":contact_edges.size(),"max_sampled_contact_edge_gap_world":max_edge_gap,"cut_u":FOOT_U,"all_retained_original_vertices_unchanged":true,"high_peak_and_retained_crop_endpoints_unchanged":true,"exact_terrain_conformity_claimed":false,"closed_volume_claimed":false}}
