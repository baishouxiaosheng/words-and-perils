extends RefCounted
## Exact nearest channel search, conservatively pruned by world-space bounds.
## Stable source order breaks exact ties; this does not alter the river graph.
const LEAF_SIZE:=6
var entries:Array[Dictionary]=[]
var nodes:Array[Dictionary]=[]
var queries:=0
var candidate_checks:=0
var visited_nodes:=0
func configure(channels:Array[Dictionary])->void:
	entries.clear();nodes.clear();queries=0;candidate_checks=0;visited_nodes=0
	var ids:Array[int]=[]
	for i in range(channels.size()):
		var source:Dictionary=channels[i]
		var a:Vector3=source.a;var b:Vector3=source.b
		var flat_a=Vector2(a.x,a.z);var flat_b=Vector2(b.x,b.z)
		entries.append({"id":i,"source":source,"a":flat_a,"delta":flat_b-flat_a,"minimum":flat_a.min(flat_b),"maximum":flat_a.max(flat_b),"center":(flat_a+flat_b)*0.5})
		ids.append(i)
	if not ids.is_empty():_build(ids)
func _build(ids:Array[int])->int:
	var minimum=Vector2(INF,INF);var maximum=Vector2(-INF,-INF)
	for id in ids:minimum=minimum.min(entries[id].minimum);maximum=maximum.max(entries[id].maximum)
	var index=nodes.size();nodes.append({})
	if ids.size()<=LEAF_SIZE:
		nodes[index]={"minimum":minimum,"maximum":maximum,"ids":ids};return index
	var x_axis=(maximum.x-minimum.x)>=(maximum.y-minimum.y)
	ids.sort_custom(func(a:int,b:int)->bool:
		var av:float=entries[a].center.x if x_axis else entries[a].center.y
		var bv:float=entries[b].center.x if x_axis else entries[b].center.y
		return av<bv if av!=bv else a<b)
	var middle=ids.size()/2
	var left:Array[int]=[];var right:Array[int]=[]
	for i in range(ids.size()):(left if i<middle else right).append(ids[i])
	var a=_build(left);var b=_build(right)
	nodes[index]={"minimum":minimum,"maximum":maximum,"left":a,"right":b}
	return index
static func _bound_distance_squared(point:Vector2,node:Dictionary)->float:
	var nearest=point.clamp(node.minimum,node.maximum)
	return point.distance_squared_to(nearest)
func nearest(point:Vector2)->Dictionary:
	queries+=1
	var result={"distance":1000.0,"height":0.04,"width":0.24}
	if nodes.is_empty():return result
	var best_id=2147483647;var best_squared=1000000.0
	var stack:Array[int]=[0]
	while not stack.is_empty():
		var node:Dictionary=nodes[stack.pop_back()]
		visited_nodes+=1
		# The small conservative epsilon only prevents float-roundoff pruning;
		# candidate distance and tie comparison remain exactly the source formula.
		if _bound_distance_squared(point,node)>best_squared+0.000002+best_squared*0.000002:continue
		if node.has("ids"):
			for id in node.ids:
				candidate_checks+=1
				var entry:Dictionary=entries[id];var source:Dictionary=entry.source
				var delta:Vector2=entry.delta
				var offset:Vector2=point-entry.a
				var t=clampf(offset.dot(delta)/maxf(delta.length_squared(),0.0001),0.0,1.0)
				var distance=offset.distance_to(delta*t)
				if distance<float(result.distance) or (distance==float(result.distance) and id<best_id):
					var a:Vector3=source.a;var b:Vector3=source.b
					result={"distance":distance,"height":lerpf(a.y,b.y,t),"width":lerpf(float(source.get("from_width",source.get("width",0.24))),float(source.get("to_width",source.get("width",0.24))),t),"mouth":source.get("mouth",false),"t":t}
					best_id=id;best_squared=distance*distance
		else:
			var a:int=node.left;var b:int=node.right
			var da=_bound_distance_squared(point,nodes[a]);var db=_bound_distance_squared(point,nodes[b])
			# Last-in first-out: visit the nearest bound first, then prune the far.
			stack.append(b if da<=db else a);stack.append(a if da<=db else b)
	return result
func metrics()->Dictionary:
	return {"segments":entries.size(),"nodes":nodes.size(),"queries":queries,"candidate_checks":candidate_checks,"visited_nodes":visited_nodes,"mean_candidates":float(candidate_checks)/maxi(1,queries)}
