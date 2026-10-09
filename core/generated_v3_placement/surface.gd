extends RefCounted
## Complete convex-footprint tests against actual native ground triangles.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Q=4096.0
const EPS=0.0000000001
var faces: Array=[]
var bins: Dictionary={}
var geometry_hash=""
func build(mesh: ArrayMesh,expected_hash: String) -> Dictionary:
	faces.clear();bins.clear()
	if mesh==null or mesh.get_surface_count()!=1:return C.fail("PLACEMENT_SURFACE","Expected one admitted native ground surface.")
	var arrays=mesh.surface_get_arrays(0);var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var expanded=PackedVector3Array()
	for i in range(0,indices.size(),3):
		var v=[vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]]
		expanded.append_array(PackedVector3Array(v))
		var p=[xz(v[0]),xz(v[1]),xz(v[2])];var d=cross2(p[1]-p[0],p[2]-p[0])
		if d<=0.00000000000001:return C.fail("PLACEMENT_SURFACE","Ground has an inverted or degenerate face.")
		var dh1=v[1].y-v[0].y;var dh2=v[2].y-v[0].y
		var gx=(dh1*(p[2].y-p[0].y)-dh2*(p[1].y-p[0].y))/d
		var gz=((p[1].x-p[0].x)*dh2-(p[2].x-p[0].x)*dh1)/d
		var id=faces.size();faces.append({"polygon":p,"gx":gx,"gz":gz,"k":v[0].y-gx*p[0].x-gz*p[0].y,"gradient":Vector2(gx,gz).length()})
		for key in bucket_keys(p):
			if not bins.has(key):bins[key]=[]
			bins[key].append(id)
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(expanded.to_byte_array());geometry_hash=hash.finish().hex_encode()
	if geometry_hash!=expected_hash:return C.fail("PLACEMENT_GEOMETRY_HASH","Placement mesh differs from its source geometry identity.")
	return {"ok":true}
static func xz(v: Vector3) -> Vector2:return Vector2(v.x,v.z)
static func cross2(a: Vector2,b: Vector2) -> float:return a.x*b.y-a.y*b.x
static func quantize(v: float) -> float:return roundf(v*Q)/Q
static func floor_q(v: float) -> float:return floorf(v*Q)/Q
static func ceil_q(v: float) -> float:return ceilf(v*Q)/Q
static func as_points(raw: Array) -> Array:
	var p: Array=[]
	for v in raw:p.append(v if v is Vector2 else Vector2(float(v[0]),float(v[1])))
	return p
static func as_json(p: Array) -> Array:
	var result: Array=[]
	for v in p:result.append([v.x,v.y])
	return result
static func signed_area(p: Array) -> float:
	var value=0.0
	for i in p.size():value+=cross2(p[i],p[(i+1)%p.size()])
	return value*.5
static func area(p: Array) -> float:return absf(signed_area(p)) if p.size()>=3 else 0.0
static func valid_polygon(p: Array) -> bool:
	if p.size()<3 or p.size()>128 or signed_area(p)<=EPS:return false
	for v in p:
		if not v.is_finite():return false
	for i in p.size():
		for v in p:
			if cross2(p[(i+1)%p.size()]-p[i],v-p[i])< -0.0000001:return false
	return true
static func hull(points: Array) -> Array:
	points=points.duplicate();points.sort_custom(func(a,b):return a.x<b.x if a.x!=b.x else a.y<b.y)
	var unique: Array=[]
	for p in points:
		if unique.is_empty() or p!=unique[-1]:unique.append(p)
	if unique.size()<3:return unique
	var lower: Array=[];var upper: Array=[]
	for p in unique:
		while lower.size()>1 and cross2(lower[-1]-lower[-2],p-lower[-1])<=0.0:lower.pop_back()
		lower.append(p)
	unique.reverse()
	for p in unique:
		while upper.size()>1 and cross2(upper[-1]-upper[-2],p-upper[-1])<=0.0:upper.pop_back()
		upper.append(p)
	lower.pop_back();upper.pop_back();lower.append_array(upper);return lower
static func quantized_enclosure(points: Array) -> Array:
	# Hull of tiny outward grid boxes contains every original point, including
	# transformed roof/eave bounds; rounding cannot shrink physical coverage.
	var enclosed: Array=[]
	for p in points:
		for x in [floor_q(p.x)-1.0/Q,ceil_q(p.x)+1.0/Q]:
			for z in [floor_q(p.y)-1.0/Q,ceil_q(p.y)+1.0/Q]:enclosed.append(Vector2(x,z))
	return hull(enclosed)
static func expanded(points: Array,radius: float) -> Array:
	var around: Array=[];var distance=radius/cos(PI/16.0)
	for p in points:
		for i in range(16):around.append(p+Vector2(cos(TAU*i/16.0),sin(TAU*i/16.0))*distance)
	return quantized_enclosure(around)
static func bucket_keys(p: Array) -> Array:
	var low=p[0];var high=p[0]
	for v in p:low=low.min(v);high=high.max(v)
	var result: Array=[]
	for x in range(floori(low.x),floori(high.x)+1):
		for z in range(floori(low.y),floori(high.y)+1):result.append("%d,%d"%[x,z])
	return result
static func clip(subject: Array,boundary: Array) -> Array:
	var poly=subject.duplicate()
	for i in boundary.size():
		if poly.is_empty():return []
		var a=boundary[i];var edge=boundary[(i+1)%boundary.size()]-a;var previous=poly[-1];var fp=cross2(edge,previous-a);var out: Array=[]
		for p in poly:
			var f=cross2(edge,p-a)
			if (fp>=0.0)!=(f>=0.0):out.append(previous.lerp(p,fp/(fp-f)))
			if f>=0.0:out.append(p)
			previous=p;fp=f
		poly=out
	return poly
static func halfplane(subject: Array,a: Vector2,b: Vector2,inside: bool) -> Array:
	if subject.is_empty():return []
	var sign_=1.0 if inside else -1.0;var edge=b-a;var previous=subject[-1];var fp=sign_*cross2(edge,previous-a);var result: Array=[]
	for p in subject:
		var f=sign_*cross2(edge,p-a)
		if (fp>=0.0)!=(f>=0.0):result.append(previous.lerp(p,fp/(fp-f)))
		if f>=0.0:result.append(p)
		previous=p;fp=f
	return result if area(result)>0.000000000001 else []
static func subtract(subject: Array,cutter: Array) -> Array:
	var result: Array=[];var remaining=subject.duplicate()
	for i in cutter.size():
		var outside=halfplane(remaining,cutter[i],cutter[(i+1)%cutter.size()],false)
		if not outside.is_empty():result.append(outside)
		remaining=halfplane(remaining,cutter[i],cutter[(i+1)%cutter.size()],true)
		if remaining.is_empty():break
	return result
func candidates(p: Array) -> Array:
	var found: Dictionary={}
	for key in bucket_keys(p):
		for id in bins.get(key,[]):found[id]=true
	var ids=found.keys();ids.sort();return ids
static func height(face: Dictionary,p: Vector2) -> float:return face.gx*p.x+face.gz*p.y+face.k
func clip_polygon(raw: Array) -> Array:
	var p=as_points(raw);var result: Array=[]
	if not valid_polygon(p):return result
	for id in candidates(p):
		var face: Dictionary=faces[id];var poly=clip(p,face.polygon)
		if area(poly)<=0.000000000001:continue
		var lifted: Array=[]
		for v in poly:lifted.append(Vector3(v.x,height(face,v),v.y))
		result.append({"polygon":lifted,"triangle_id":id})
	return result
func support(raw: Array,max_gradient: float,max_spread: float,dry_clearance: float=.01) -> Dictionary:
	var p=as_points(raw)
	if not valid_polygon(p):return C.fail("PLACEMENT_POLYGON","Footprint is malformed, degenerate or not convex.")
	var covered=0.0;var low=INF;var high=-INF;var slope=0.0;var touched=0;var uncovered: Array=[p]
	for id in candidates(p):
		var face: Dictionary=faces[id];var poly=clip(p,face.polygon);var size=area(poly)
		if size<=0.000000000001:continue
		covered+=size;touched+=1;slope=maxf(slope,face.gradient)
		var remainder: Array=[]
		for piece in uncovered:remainder.append_array(subtract(piece,face.polygon))
		uncovered=remainder
		for v in poly:
			var y=height(face,v);low=minf(low,y);high=maxf(high,y)
	var missing=0.0
	for piece in uncovered:missing+=area(piece)
	if touched==0 or missing>maxf(0.000001,area(p)*0.00001):return C.fail("PLACEMENT_COVERAGE","Full footprint is not covered by native ground; overlap cannot conceal a hole.")
	if low<=dry_clearance:return C.fail("PLACEMENT_WET","An interior footprint portion is wet or lacks dry clearance.")
	if slope>max_gradient+0.000001:return C.fail("PLACEMENT_SLOPE","A footprint crosses an excessive native triangle slope.")
	if high-low>max_spread+0.000001:return C.fail("PLACEMENT_SPREAD","Footprint relief exceeds its admitted foundation range.")
	return {"ok":true,"min_height":floor_q(low),"max_height":ceil_q(high),"max_gradient":ceil_q(slope),"height_spread":ceil_q(high-low),"area":quantize(area(p)),"uncovered_area_upper_bound":ceil_q(missing),"intersected_triangles":touched}
static func segment_interval(a: Vector2,b: Vector2,p: Array) -> Array:
	var lo=0.0;var hi=1.0
	for i in p.size():
		var edge=p[(i+1)%p.size()]-p[i];var f0=cross2(edge,a-p[i]);var f1=cross2(edge,b-p[i])
		if f0<0.0 and f1<0.0:return []
		if absf(f1-f0)<0.000000000001:continue
		var t=-f0/(f1-f0)
		if f1>f0:lo=maxf(lo,t)
		else:hi=minf(hi,t)
		if lo>hi:return []
	return [maxf(lo,0.0),minf(hi,1.0)]
static func segment_hits(a: Vector2,b: Vector2,p: Array) -> bool:return not segment_interval(a,b,p).is_empty()
func segment_points(raw_a: Array,raw_b: Array) -> Array:
	var a=Vector2(raw_a[0],raw_a[1]);var b=Vector2(raw_b[0],raw_b[1]);var intervals: Array=[];var breaks: Array=[0.0,1.0]
	for id in candidates([a,b]):
		var interval=segment_interval(a,b,faces[id].polygon)
		if interval.is_empty():continue
		intervals.append({"lo":interval[0],"hi":interval[1],"face":id});breaks.append_array(interval)
	breaks.sort();var result: Array=[];var previous=-1.0
	for t in breaks:
		if t-previous<0.00000001:continue
		previous=t;var p=a.lerp(b,t);var y=-INF
		for item in intervals:
			if t>=item.lo-0.0000001 and t<=item.hi+0.0000001:y=maxf(y,height(faces[item.face],p))
		if not is_finite(y):return []
		result.append(Vector3(p.x,y,p.y))
	return result
func plane_gaps(raw: Array,support_plane: Array) -> Dictionary:
	if support_plane.size()!=3:return C.fail("PLACEMENT_PLANE","Expected [dx,dz,constant] support plane.")
	for value in support_plane:
		if not (value is float or value is int) or not is_finite(float(value)):return C.fail("PLACEMENT_PLANE","Support plane must be finite.")
	var checked=support(raw,65536.0,65536.0,-65536.0)
	if not checked.ok:return checked
	var low=INF;var high=-INF
	for piece in clip_polygon(raw):
		for p: Vector3 in piece.polygon:
			var gap=float(support_plane[0])*p.x+float(support_plane[1])*p.z+float(support_plane[2])-p.y
			low=minf(low,gap);high=maxf(high,gap)
	return {"ok":true,"min_gap":floor_q(low),"max_gap":ceil_q(high),"coverage_verified":true}
