extends RefCounted
## Active lake/ocean/retained river geometry, interval-union observations only.
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const CONTACT_TOLERANCE_WORLD:=0.000002
var ready:=false
var last_error:=""
var bundle_id:=""
var polygons:Array=[]
var buckets:Dictionary={}
func load_active()->bool:
	ready=false;polygons.clear();buckets.clear()
	if not Bundle.ready():last_error=Bundle.last_error;return false
	return load_data(Bundle.document("physical_water"),Bundle.bundle_id())
func load_data(data:Dictionary,expected_bundle_id:String)->bool:
	ready=false;polygons.clear();buckets.clear()
	if data.get("schema")!="active-world-physical-water/v1" or data.get("bundle_id")!=expected_bundle_id or not expected_bundle_id.begins_with("natural-shore-v03-"):
		last_error="Unknown/mismatched physical water bundle";return false
	bundle_id=expected_bundle_id
	for source in data.get("polygons",[]):
		var row:Dictionary=source.duplicate();var points:Array=row.polygon_xz
		if points.size()<3:last_error="Degenerate physical water polygon";return false
		var area:=0.0;var minx:=INF;var maxx:=-INF;var minz:=INF;var maxz:=-INF
		for i in range(points.size()):
			var p:Array=points[i];var q:Array=points[(i+1)%points.size()];area+=p[0]*q[1]-p[1]*q[0]
			minx=minf(minx,p[0]);maxx=maxf(maxx,p[0]);minz=minf(minz,p[1]);maxz=maxf(maxz,p[1])
		if absf(area)<1e-18:continue
		row.orientation=1.0 if area>0 else -1.0
		var ix:=polygons.size();polygons.append(row)
		for x in range(floori(minx-CONTACT_TOLERANCE_WORLD),floori(maxx+CONTACT_TOLERANCE_WORLD)+1):
			for z in range(floori(minz-CONTACT_TOLERANCE_WORLD),floori(maxz+CONTACT_TOLERANCE_WORLD)+1):
				var k:=Vector2i(x,z)
				if not buckets.has(k):buckets[k]=[]
				buckets[k].append(ix)
	ready=true;last_error="";return true
func _interval(a:Vector2,b:Vector2,row:Dictionary)->Array:
	var lo:=0.0;var hi:=1.0;var pp:Array=row.polygon_xz
	for i in range(pp.size()):
		var p:Array=pp[i];var q:Array=pp[(i+1)%pp.size()];var dx:float=q[0]-p[0];var dz:float=q[1]-p[1];var length:=sqrt(dx*dx+dz*dz)
		if length<1e-14:continue
		var s:float=row.orientation*(dx*(a.y-p[1])-dz*(a.x-p[0]))/length+CONTACT_TOLERANCE_WORLD
		var t:float=row.orientation*(dx*(b.y-p[1])-dz*(b.x-p[0]))/length+CONTACT_TOLERANCE_WORLD
		if s<0 and t<0:return []
		if s<0:lo=maxf(lo,s/(s-t))
		if t<0:hi=minf(hi,s/(s-t))
		if lo>hi:return []
	return [lo,hi]
func segment_intersects_water(a:Vector2,b:Vector2)->Dictionary:
	if not ready:return {"ok":false,"error":last_error}
	var candidates:Dictionary={}
	for x in range(floori(minf(a.x,b.x)-CONTACT_TOLERANCE_WORLD),floori(maxf(a.x,b.x)+CONTACT_TOLERANCE_WORLD)+1):
		for z in range(floori(minf(a.y,b.y)-CONTACT_TOLERANCE_WORLD),floori(maxf(a.y,b.y)+CONTACT_TOLERANCE_WORLD)+1):
			for index in buckets.get(Vector2i(x,z),[]):candidates[index]=true
	var intervals:Array=[];var kinds:Dictionary={};var hits:Array=[]
	for index in candidates:
		var row:Dictionary=polygons[index];var interval:=_interval(a,b,row)
		if interval.is_empty():continue
		intervals.append(interval);kinds[row.kind]=true
		hits.append({"new_source_face_index":row.new_source_face_index,"legacy_parent_face_index":row.legacy_parent_face_index,"original_hex_id":row.original_hex_id,"body_id":row.body_id})
	intervals.sort_custom(func(x,y):return x[0]<y[0])
	var merged:Array=[]
	for interval in intervals:
		if merged.is_empty() or interval[0]>merged[-1][1]+1e-9:merged.append(interval.duplicate())
		else:merged[-1][1]=maxf(merged[-1][1],interval[1])
	var length:=0.0
	for interval in merged:length+=(interval[1]-interval[0])*a.distance_to(b)
	return {"ok":true,"intersects":not intervals.is_empty(),"length_inside":length,"intervals":merged,"source_faces":hits,"water_kinds":kinds.keys(),"bundle_id":bundle_id,"movement_result_decided":false}
func water_endpoint_context(p:Vector2)->Dictionary:
	var result:=segment_intersects_water(p,p)
	result["is_water"]=result.get("intersects",false)
	return result
