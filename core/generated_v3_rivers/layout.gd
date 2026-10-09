extends RefCounted
## Immutable, bounded interpretation of the source drainage graph. Never prunes.
const VERSION = "river_layout/v1"
const PROFILE = "structured_rivers_v1"
const DIRECTIONS = [[1,0],[0,1],[-1,1],[-1,0],[0,-1],[1,-1]]

static func _error(code: String, message: String) -> Dictionary:
	return {"ok":false,"error_code":code,"message":message}

static func edge_index(c: Dictionary, other: Dictionary) -> int:
	# Polygon edges start at the 30-degree corner, whereas axial direction 0 is east.
	for d in range(6):
		if int(other.q)-int(c.q)==DIRECTIONS[d][0] and int(other.r)-int(c.r)==DIRECTIONS[d][1]: return (d+5)%6
	return -1

static func pair_key(a: String, b: String) -> String:
	return a+"|"+b if a<b else b+"|"+a

static func build(source: Dictionary) -> Dictionary:
	if not source.get("cells") is Dictionary or not source.get("river_edges",[]) is Array:
		return _error("RIVER_LAYOUT_SOURCE","Expected cells and river_edges.")
	var cells: Dictionary=source.cells
	var nodes: Dictionary={}; var ports: Dictionary={}
	var keys=cells.keys();keys.sort()
	for key in keys:
		var c: Dictionary=cells[key]
		if c.get("river",false):
			if c.get("ocean",true):return _error("RIVER_OCEAN_NODE","River-marked node is ocean: "+key)
			nodes[key]={"cell":key,"incoming":[],"outgoing":"","arms":[],"role":"","water_y":0.0}
	if nodes.size()>128:return _error("RIVER_NODE_LIMIT","At most 128 river cells are supported.")
	for raw in source.get("river_edges",[]):
		if not raw is Dictionary:return _error("RIVER_EDGE_TYPE","River edges must be dictionaries.")
		var a=raw.get("from","");var b=raw.get("to","")
		if not a is String or not b is String or not nodes.has(a) or not cells.has(b):
			return _error("RIVER_EDGE_DOMAIN","River edge endpoint is missing or not river-marked.")
		if not nodes[a].outgoing.is_empty():return _error("RIVER_SPLIT","Multiple outgoing source edges at "+a)
		var ca: Dictionary=cells[a];var cb: Dictionary=cells[b]
		for value in [raw.get("flow"),ca.get("flow",raw.get("flow")),cb.get("flow",raw.get("flow"))]:
			if not (typeof(value) in [TYPE_INT,TYPE_FLOAT]) or not is_finite(float(value)):
				return _error("RIVER_FLOW_TYPE","Accumulated flow must be finite numeric metadata at "+a)
		var side=edge_index(ca,cb)
		if side<0:return _error("RIVER_ADJACENCY","Non-adjacent edge "+a+" -> "+b)
		if float(ca.elevation)<=float(cb.elevation):return _error("RIVER_UPHILL","Source river edge is not strictly downhill: "+a+" -> "+b)
		if not cb.ocean and not nodes.has(b):return _error("RIVER_CONTINUATION","Inland destination is not river-marked: "+b)
		if ca.get("flow_to",b)!=b:return _error("RIVER_SOURCE_FLOW","Edge disagrees with source flow_to at "+a)
		for field in ["surface_from","surface_to"]:
			if raw.has(field):
				var expected=float(ca.elevation) if field=="surface_from" else float(cb.elevation)
				if not (typeof(raw[field]) in [TYPE_FLOAT,TYPE_INT]) or float(raw[field])!=expected:
					return _error("RIVER_SOURCE_HEIGHT","Edge height provenance disagrees at "+a)
		if float(raw.get("flow",0.0))<=0.0 or float(raw.get("flow",0.0))!=float(ca.get("flow",raw.get("flow",0.0))):
			return _error("RIVER_FLOW","Invalid edge accumulated flow at "+a)
		if not cb.ocean and float(cb.get("flow",0.0))<float(ca.get("flow",0.0)):
			return _error("RIVER_FLOW_CONTINUATION","Accumulated flow decreases at "+b)
		var id=pair_key(a,b)
		if ports.has(id):return _error("RIVER_DUPLICATE_EDGE","Duplicate river edge "+id)
		var ordered=[a,b];ordered.sort()
		ports[id]={"id":id,"kind":"mouth" if cb.ocean else "connection","from":a,"to":b,"canonical_cells":ordered,"source_edge_id":a+">"+b,"flow":float(raw.flow),"sections":[]}
		nodes[a].outgoing=b
		nodes[a].arms.append({"side":side,"port_id":id,"direction":"out","neighbor":b})
		if not cb.ocean:
			nodes[b].incoming.append(a)
			nodes[b].arms.append({"side":(side+3)%6,"port_id":id,"direction":"in","neighbor":a})
	for key in nodes:
		var node: Dictionary=nodes[key];var c: Dictionary=cells[key]
		node.incoming.sort()
		if node.incoming.size()>2:return _error("RIVER_JUNCTION_DEGREE","Only two-in/one-out junctions are supported: "+key)
		if node.outgoing.is_empty():
			if not str(c.get("flow_to","")).is_empty():return _error("RIVER_MISSING_EDGE","Missing downstream continuation at "+key)
			var missing: Array=[]
			for d in range(6):
				var nk="%d,%d"%[int(c.q)+DIRECTIONS[d][0],int(c.r)+DIRECTIONS[d][1]]
				if not cells.has(nk):missing.append(d)
			if missing.is_empty():return _error("RIVER_INLAND_TERMINAL","River terminates inside the crop at "+key)
			var target=Vector2(sqrt(3.0)*(float(c.q)+float(c.r)/2.0),1.5*float(c.r))
			if not node.incoming.is_empty():
				target=Vector2.ZERO
				for parent in node.incoming:
					var p: Dictionary=cells[parent]
					target+=Vector2(sqrt(3.0)*(float(c.q-p.q)+float(c.r-p.r)/2.0),1.5*float(c.r-p.r))
			var chosen=int(missing[0]);var best=-INF
			for d in missing:
				var direction=Vector2(cos(float(d)*PI/3.0),sin(float(d)*PI/3.0))
				var score=direction.dot(target)
				if score>best+0.00000001:best=score;chosen=d
			var side=(chosen+5)%6;var id=key+"|crop:%d"%side
			ports[id]={"id":id,"kind":"crop","from":key,"to":"","canonical_cells":[key],"source_edge_id":"crop:"+key,"flow":float(c.get("flow",0.0)),"crop_side":side,"sections":[],"selection":"most aligned missing axial direction; lowest direction wins ties"}
			node.arms.append({"side":side,"port_id":id,"direction":"out","neighbor":""})
			node.role="crop_outlet"
		elif cells[node.outgoing].ocean:node.role="sea_mouth"
		elif node.incoming.size()==2:node.role="junction"
		elif node.incoming.is_empty():node.role="source"
		else:node.role="chain"
		node.arms.sort_custom(func(a,b):return a.side<b.side)
		var used: Dictionary={}
		for arm in node.arms:
			if used.has(arm.side):return _error("RIVER_PORT_COLLISION","Two arms claim the same side of "+key)
			used[arm.side]=true
	# Deterministic Kahn order, also retained as the surface-solver order.
	var indegree: Dictionary={};var queue: Array=[];var order: Array=[]
	for key in nodes:
		indegree[key]=nodes[key].incoming.size()
		if indegree[key]==0:queue.append(key)
	queue.sort()
	while not queue.is_empty():
		var key=queue.pop_front();order.append(key)
		var downstream: String=nodes[key].outgoing
		if nodes.has(downstream):
			indegree[downstream]-=1
			if indegree[downstream]==0:queue.append(downstream);queue.sort()
	if order.size()!=nodes.size():return _error("RIVER_CYCLE","Drainage graph contains a directed cycle.")
	var layout={"version":VERSION,"profile_id":PROFILE,"source_hash":source.get("content_hash",""),"nodes":nodes,"ports":ports,"topological_order":order,"junctions":[]}
	for key in nodes:
		if nodes[key].incoming.size()==2:layout.junctions.append(key)
	layout.junctions.sort()
	layout["graph_payload"]=layout.duplicate(true)
	layout["layout_canonical_json"]=JSON.stringify(layout.graph_payload,"",true,true)
	layout["layout_hash"]=layout.layout_canonical_json.sha256_text()
	layout["layout_hash_encoding"]="SHA256 UTF-8 of layout_canonical_json; JSON parsed value equals immutable graph_payload; sorted keys/full_precision=true"
	return {"ok":true,"layout":layout}
