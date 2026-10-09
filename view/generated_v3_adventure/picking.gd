extends RefCounted
## Exact native-triangle ray picks, spatially binned in world XZ.
## No height approximation, source mutation, or authority on selection.
const BUCKET:=2.0
var triangles:Array=[]
var bins:Dictionary={}
var bounds:=AABB()
var last_query:Dictionary={}
func build(ground:Mesh,water:Mesh) -> void:
	triangles.clear();bins.clear();var first:=true
	for pair in [[ground,"ground"],[water,"water"]]:
		if pair[0]==null:continue
		var faces:PackedVector3Array=pair[0].get_faces()
		for i in range(0,faces.size(),3):
			var box:=AABB(faces[i],Vector3.ZERO).expand(faces[i+1]).expand(faces[i+2]).grow(.00001)
			bounds=box if first else bounds.merge(box);first=false
			var id:int=triangles.size();triangles.append({"a":faces[i],"b":faces[i+1],"c":faces[i+2],"bounds":box,"surface":pair[1]})
			for x in range(floori(box.position.x/BUCKET),floori(box.end.x/BUCKET)+1):
				for z in range(floori(box.position.z/BUCKET),floori(box.end.z/BUCKET)+1):
					var key:String="%d,%d"%[x,z]
					if not bins.has(key):bins[key]=[]
					bins[key].append(id)
func raycast(origin:Vector3,direction:Vector3) -> Dictionary:
	var began:int=Time.get_ticks_usec();var interval:=ray_interval(bounds,origin,direction,1000.0)
	if triangles.is_empty() or interval.x<0.0:return {}
	var visited:=walk(origin,direction,interval.x,interval.y);var unique:Dictionary={}
	for key in visited:
		for id in bins.get(key,[]):unique[id]=true
	var best:=INF;var point:=Vector3.ZERO;var kind:="";var tests:=0
	for id in unique:
		var triangle:Dictionary=triangles[id]
		if ray_interval(triangle.bounds,origin,direction,minf(best,interval.y)).x<0.0:continue
		tests+=1
		var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,triangle.a,triangle.b,triangle.c)
		if not hit is Vector3:continue
		var distance:float=(hit-origin).dot(direction)
		if distance>=0.0 and distance<best:best=distance;point=hit;kind=triangle.surface
	last_query={"microseconds":Time.get_ticks_usec()-began,"buckets":visited.size(),"candidate_triangles":unique.size(),"triangle_tests":tests,"total_triangles":triangles.size()}
	return {"distance":best,"point":point,"surface":kind} if is_finite(best) else {}
static func ray_interval(box:AABB,origin:Vector3,direction:Vector3,maximum:float) -> Vector2:
	var low:=0.0;var high:=maximum
	for axis in range(3):
		if absf(direction[axis])<0.000000001:
			if origin[axis]<box.position[axis] or origin[axis]>box.end[axis]:return Vector2(-1,-1)
			continue
		var a:float=(box.position[axis]-origin[axis])/direction[axis];var b:float=(box.end[axis]-origin[axis])/direction[axis]
		low=maxf(low,minf(a,b));high=minf(high,maxf(a,b))
		if low>high:return Vector2(-1,-1)
	return Vector2(low,high)
static func walk(origin:Vector3,direction:Vector3,start:float,finish:float) -> Array[String]:
	var result:Array[String]=[];var p:=origin+direction*start;var end:=origin+direction*finish
	var cell:=Vector2i(floori(p.x/BUCKET),floori(p.z/BUCKET));var last:=Vector2i(floori(end.x/BUCKET),floori(end.z/BUCKET))
	var sx:=1 if direction.x>0.0 else -1 if direction.x<0.0 else 0
	var sz:=1 if direction.z>0.0 else -1 if direction.z<0.0 else 0
	var dx:float=BUCKET/absf(direction.x) if sx!=0 else INF;var dz:float=BUCKET/absf(direction.z) if sz!=0 else INF
	var tx:float=start+((cell.x+(1 if sx>0 else 0))*BUCKET-p.x)/direction.x if sx!=0 else INF
	var tz:float=start+((cell.y+(1 if sz>0 else 0))*BUCKET-p.z)/direction.z if sz!=0 else INF
	for i in range(absi(last.x-cell.x)+absi(last.y-cell.y)+4):
		result.append("%d,%d"%[cell.x,cell.y])
		if cell==last:break
		if tx==tz:
			result.append("%d,%d"%[cell.x+sx,cell.y]);result.append("%d,%d"%[cell.x,cell.y+sz]);cell+=Vector2i(sx,sz);tx+=dx;tz+=dz
		elif tx<tz:cell.x+=sx;tx+=dx
		else:cell.y+=sz;tz+=dz
	return result
