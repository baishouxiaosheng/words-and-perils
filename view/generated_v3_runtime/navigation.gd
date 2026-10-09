extends RefCounted
## Navigation samples the actual painted ArrayMesh, not source-center shortcuts.
## Spatial bins are built from geometry, without relying on face-owner metadata.
const ID="v3_native_mesh_sea_clearance/v1"
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const CLEARANCE=0.0001
const COVERAGE_TOLERANCE=0.00001
const ROOT3=1.7320508075688772
const DIRS=[[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]
var source_hash=""
var geometry_hash=""
var renderer_profile=""
var allowed: Dictionary={}
var supported: Dictionary={}
var support_heights: Dictionary={}
var diagnostics: Dictionary={}
var _cells: Dictionary={}
var _vertices=PackedVector3Array()
var _indices=PackedInt32Array()
var _faces: Array=[]
var _bins: Dictionary={}
var _edge_points: Dictionary={}

func build(source: Dictionary,built: Dictionary) -> Dictionary:
	allowed.clear();supported.clear();support_heights.clear();_bins.clear();_faces.clear();_edge_points.clear()
	if not built.get("ok",false) or built.get("source_hash","")!=source.get("content_hash","") or not built.get("ground_mesh") is ArrayMesh:
		return C.fail("V3_NAV_SOURCE","Navigation requires the native mesh for this exact source.")
	var started=Time.get_ticks_usec()
	var arrays=built.ground_mesh.surface_get_arrays(0)
	_vertices=arrays[Mesh.ARRAY_VERTEX];_indices=arrays[Mesh.ARRAY_INDEX]
	if _indices.size()%3!=0 or _indices.is_empty():return C.fail("V3_NAV_GEOMETRY","Native triangle indices are incomplete.")
	var expanded=PackedVector3Array()
	for index in _indices:
		if index<0 or index>=_vertices.size():return C.fail("V3_NAV_GEOMETRY","Native triangle index is out of bounds.")
		expanded.append(_vertices[index])
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(expanded.to_byte_array())
	geometry_hash=hash.finish().hex_encode()
	if geometry_hash!=built.get("geometry_hash",""):return C.fail("V3_NAV_GEOMETRY_HASH","Native geometry does not match its declared identity.")
	_cells=source.cells;source_hash=source.content_hash;renderer_profile=built.renderer_profile
	for i in range(0,_indices.size(),3):
		var face=[_vertices[_indices[i]],_vertices[_indices[i+1]],_vertices[_indices[i+2]]]
		var area=cross2(Vector2(face[1].x-face[0].x,face[1].z-face[0].z),Vector2(face[2].x-face[0].x,face[2].z-face[0].z))
		if not is_finite(area) or area<=0.00000000000001:return C.fail("V3_NAV_GEOMETRY","Native face is inverted or degenerate.")
		var id=_faces.size();_faces.append(face)
		var low_x=floori(minf(face[0].x,minf(face[1].x,face[2].x)))
		var high_x=floori(maxf(face[0].x,maxf(face[1].x,face[2].x)))
		var low_z=floori(minf(face[0].z,minf(face[1].z,face[2].z)))
		var high_z=floori(maxf(face[0].z,maxf(face[1].z,face[2].z)))
		for x in range(low_x,high_x+1):
			for z in range(low_z,high_z+1):
				var key="%d,%d"%[x,z]
				if not _bins.has(key):_bins[key]=[]
				_bins[key].append(id)
	var keys=_cells.keys();keys.sort()
	for key in keys:
		var c: Dictionary=_cells[key];var p=raw_center([c.q,c.r])
		var hit=height_at_xz(Vector2(p.x,p.z))
		if not hit.ok:return C.fail("V3_NAV_ANCHOR","An original source center lacks native triangle coverage: "+key)
		support_heights[key]=hit.height
		supported[key]=not c.ocean and float(hit.height)>CLEARANCE
		allowed[key]=[]
	var checked_edges=0;var dry_edges=0;var unsupported_edges=0
	for key in keys:
		var c: Dictionary=_cells[key]
		for direction in DIRS:
			var next="%d,%d"%[int(c.q)+direction[0],int(c.r)+direction[1]]
			if not _cells.has(next) or key>=next:continue
			checked_edges+=1
			if not supported[key] or not supported[next]:unsupported_edges+=1;continue
			var a=raw_center([c.q,c.r]);var n: Dictionary=_cells[next];var b=raw_center([n.q,n.r])
			var path=_segment(Vector2(a.x,a.z),Vector2(b.x,b.z))
			if not path.ok:unsupported_edges+=1;continue
			allowed[key].append(next);allowed[next].append(key);dry_edges+=1
			_edge_points[key+"|"+next]=path.points
			var reverse: Array=path.points.duplicate();reverse.reverse();_edge_points[next+"|"+key]=reverse
	for key in allowed:allowed[key].sort()
	diagnostics={"navigation_id":ID,"source_hash":source_hash,"geometry_hash":geometry_hash,"renderer_profile":renderer_profile,"cells":_cells.size(),"triangles":_faces.size(),"checked_undirected_edges":checked_edges,"dry_undirected_edges":dry_edges,"blocked_undirected_edges":unsupported_edges,"clearance":CLEARANCE,"coverage_tolerance":COVERAGE_TOLERANCE,"water_authority":"actual ground-clipped sea at y=0; rivers are not rendered/admitted","union_interval_coverage":true,"face_owner_metadata_used":false,"build_ms":(Time.get_ticks_usec()-started)/1000.0}
	return {"ok":true,"diagnostics":diagnostics.duplicate(true)}

static func raw_center(hex: Array) -> Vector3:
	return Vector3(ROOT3*(float(hex[0])+float(hex[1])*0.5),0.0,1.5*float(hex[1]))
func cell_center(hex: Array) -> Vector3:
	if hex.size()!=2 or not C.integer(hex[0]) or not C.integer(hex[1]):return Vector3.INF
	var key="%d,%d"%[int(hex[0]),int(hex[1])]
	if not support_heights.has(key):return Vector3.INF
	var p=raw_center(hex);p.y=float(support_heights[key]);return p
func cell_at_xz(p: Vector2) -> Dictionary:
	if not p.is_finite():return {"ok":false,"code":"V3_POINT"}
	var qf=p.x/ROOT3-p.y/3.0;var rf=p.y/1.5;var sf=-qf-rf
	var q=roundi(qf);var r=roundi(rf);var s=roundi(sf)
	var dq=absf(q-qf);var dr=absf(r-rf);var ds=absf(s-sf)
	if dq>dr and dq>ds:q=-r-s
	elif dr>ds:r=-q-s
	var key="%d,%d"%[q,r]
	return {"ok":true,"key":key,"hex":[q,r]} if _cells.has(key) else {"ok":false,"code":"V3_OUTSIDE_DOMAIN"}
func height_at_xz(p: Vector2) -> Dictionary:
	if not p.is_finite():return {"ok":false,"code":"V3_POINT"}
	var key="%d,%d"%[floori(p.x),floori(p.y)]
	var found=false;var height=-INF;var chosen=-1
	for id in _bins.get(key,[]):
		var face: Array=_faces[id]
		if not contains(p,face):continue
		var value=triangle_height(p,face)
		if not is_finite(value):continue
		if not found or value>height:found=true;height=value;chosen=id
	return {"ok":true,"height":height,"triangle_id":chosen,"water_level":0.0} if found else {"ok":false,"code":"V3_NO_TRIANGLE"}
func _segment(start: Vector2,end: Vector2) -> Dictionary:
	var candidates: Dictionary={}
	for x in range(floori(minf(start.x,end.x)),floori(maxf(start.x,end.x))+1):
		for z in range(floori(minf(start.y,end.y)),floori(maxf(start.y,end.y))+1):
			for id in _bins.get("%d,%d"%[x,z],[]):candidates[id]=true
	var intervals: Array=[]
	for id in candidates:
		var face: Array=_faces[id];var interval=triangle_interval(start,end,face)
		if interval.is_empty() or interval[1]-interval[0]<=0.0000001:continue
		for t in interval:
			if triangle_height(start.lerp(end,t),face)<=CLEARANCE:return {"ok":false,"code":"V3_WET_EDGE"}
		intervals.append({"lo":interval[0],"hi":interval[1],"face":id})
	if intervals.is_empty():return {"ok":false,"code":"V3_NO_COVERAGE"}
	intervals.sort_custom(func(a,b):return a.lo<b.lo if a.lo!=b.lo else a.hi<b.hi)
	var covered=0.0;var breakpoints: Array=[0.0,1.0]
	for item in intervals:
		if item.lo>covered+COVERAGE_TOLERANCE:return {"ok":false,"code":"V3_COVERAGE_GAP"}
		covered=maxf(covered,item.hi);breakpoints.append(item.lo);breakpoints.append(item.hi)
	if covered<1.0-COVERAGE_TOLERANCE:return {"ok":false,"code":"V3_INCOMPLETE_EDGE"}
	breakpoints.sort()
	var points: Array=[];var previous=-1.0
	for t in breakpoints:
		if t-previous<=0.000001:continue
		previous=t
		var p=start.lerp(end,t);var best=-INF
		for interval in intervals:
			if t>=interval.lo-0.000001 and t<=interval.hi+0.000001:best=maxf(best,triangle_height(p,_faces[interval.face]))
		if not is_finite(best) or best<=CLEARANCE:return {"ok":false,"code":"V3_EDGE_SAMPLE"}
		points.append(Vector3(p.x,best,p.y))
	# Near-coincident clipping breaks may be coalesced, but route endpoints are
	# always the exact admitted anchors rather than a nearly-one interpolation.
	var first=height_at_xz(start);var last=height_at_xz(end)
	if not first.ok or not last.ok or points.size()<2:return {"ok":false,"code":"V3_EDGE_ENDPOINT"}
	points[0]=Vector3(start.x,first.height,start.y);points[-1]=Vector3(end.x,last.height,end.y)
	return {"ok":true,"points":points}
func route_points(route: Array) -> Array:
	if route.is_empty():return []
	var start=cell_center(route[0])
	if not start.is_finite():return []
	var result: Array=[start]
	for i in range(1,route.size()):
		var a="%d,%d"%[int(route[i-1][0]),int(route[i-1][1])];var b="%d,%d"%[int(route[i][0]),int(route[i][1])]
		if not _edge_points.has(a+"|"+b):return []
		var path: Array=_edge_points[a+"|"+b]
		for j in range(1,path.size()):result.append(path[j])
	return result
func step(from: Array,to: Array) -> Dictionary:
	var a="%d,%d"%[int(from[0]),int(from[1])];var b="%d,%d"%[int(to[0]),int(to[1])]
	if not supported.get(a,false) or not supported.get(b,false):return C.fail("NO_DRY_SUPPORT","The native mesh anchor is wet or unsupported.")
	if not b in allowed.get(a,[]):return C.fail("CROSS_WATER_ASSESSMENT","No complete sea-clear native triangle route exists; no movement was performed.")
	return {"ok":true}
func plan(state: Dictionary,target: Variant,budget: int) -> Dictionary:
	var identity: Dictionary=state.get("generated_world",{})
	if identity.get("content_hash","")!=source_hash or identity.get("geometry_hash","")!=geometry_hash or identity.get("renderer_profile","")!=renderer_profile or identity.get("source_contract","")!="generated_v3_source/v1":
		return C.fail("BUNDLE_MISMATCH","Navigation belongs to another exact v3 source or native mesh.")
	return Policy.plan(state,"actor_player",target,budget,func(a,b):return step(a,b))
func export_data(spawn: Array=[]) -> Dictionary:
	return {"source_hash":source_hash,"geometry_hash":geometry_hash,"renderer_profile":renderer_profile,"supported":supported.duplicate(true),"support_heights":support_heights.duplicate(true),"allowed":allowed.duplicate(true),"spawn":spawn.duplicate(),"diagnostics":diagnostics.duplicate(true)}
static func cross2(a: Vector2,b: Vector2) -> float:return a.x*b.y-a.y*b.x
static func contains(p: Vector2,face: Array) -> bool:
	for i in range(3):
		var a=Vector2(face[i].x,face[i].z);var b=Vector2(face[(i+1)%3].x,face[(i+1)%3].z)
		if cross2(b-a,p-a)<-0.000002:return false
	return true
static func triangle_height(p: Vector2,face: Array) -> float:
	var a=Vector2(face[0].x,face[0].z);var b=Vector2(face[1].x,face[1].z);var c=Vector2(face[2].x,face[2].z)
	var denominator=cross2(b-a,c-a)
	var v=cross2(p-a,c-a)/denominator;var w=cross2(b-a,p-a)/denominator
	return float(face[0].y)*(1.0-v-w)+float(face[1].y)*v+float(face[2].y)*w
static func triangle_interval(start: Vector2,end: Vector2,face: Array) -> Array:
	var p=[Vector2(face[0].x,face[0].z),Vector2(face[1].x,face[1].z),Vector2(face[2].x,face[2].z)]
	var lo=0.0;var hi=1.0
	for i in range(3):
		var edge=p[(i+1)%3]-p[i];var f0=cross2(edge,start-p[i]);var f1=cross2(edge,end-p[i])
		if f0<-0.00000001 and f1<-0.00000001:return []
		if absf(f1-f0)<0.000000000001:continue
		var t=-f0/(f1-f0)
		if f1>f0:lo=maxf(lo,t)
		else:hi=minf(hi,t)
		if lo>hi+0.00000001:return []
	return [clampf(lo,0.0,1.0),clampf(hi,0.0,1.0)]
