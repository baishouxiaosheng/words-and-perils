extends RefCounted
## Geometry only: any active water surface contact requires assessed crossing.
const CoastWorld=preload("res://view/playable_build/world.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const WaterQueries=preload("res://view/playable_build/physical_water_queries.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Traversal=preload("res://core/ai_gm_rebuilt/traversal.gd")
static var cache:Dictionary={}
static var positions:Dictionary={}
# Navigation cache covers authored walkable-land cells, not every tiny dry island
# anchor retained for source inspection inside a nominal lake/ocean cell.
static var source_walkable:Dictionary={}
static var water:RefCounted
static var accepted_bundle_id:=""
static func reset()->void:
	cache.clear();positions.clear();source_walkable.clear();water=null;accepted_bundle_id=""
static func ready()->bool:
	if not Bundle.ready():reset();return false
	if not cache.is_empty():
		if accepted_bundle_id==Bundle.bundle_id():return true
		reset();return false
	var catalog:=CoastWorld.catalog()
	if catalog.is_empty():return false
	water=WaterQueries.new()
	if not water.load_active():reset();return false
	cache=Bundle.document("navigation");accepted_bundle_id=Bundle.bundle_id()
	for row in catalog.get("cells",[]):
		if row.get("walkable",false):source_walkable["%d,%d"%[row.q,row.r]]=true
		if row.has("support"):
			var p:Array=row.support.position;positions["%d,%d"%[row.q,row.r]]=Vector2(p[0],p[2])
	return true
static func step(from:Array,to:Array)->Dictionary:
	if not ready():return C.fail("NAV_NOT_READY","当前世界水面导航摘要未验证，未执行移动。")
	var a:="%d,%d"%[from[0],from[1]];var b:="%d,%d"%[to[0],to[1]]
	if not positions.has(a) or not positions.has(b):return C.fail("NO_DRY_SUPPORT","当前源地形中没有可验证的干燥落脚点。")
	var dq:int=int(to[0])-int(from[0]);var dr:int=int(to[1])-int(from[1])
	if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))!=1:return C.fail("NOT_ADJACENT","步行样例仅支持相邻落脚点。")
	var contact:Dictionary=water.segment_intersects_water(positions[a],positions[b])
	if not contact.get("ok",false):return C.fail("WATER_QUERY_FAILED","当前水面查询未完成，行动等待评估。")
	if contact.get("intersects",false):
		if "retained_river" in contact.water_kinds:return C.fail("CROSS_RIVER_ASSESSMENT","两处干燥落脚点连线接触实际河水，需要单独跨河评估。")
		return C.fail("CROSS_WATER_ASSESSMENT","两处干燥落脚点连线接触当前湖海水面，需要单独跨水评估；不表示整格无法通行。")
	if not b in cache.allowed_neighbors.get(a,[]):
		# Outside the immutable source-land domain is unsupported, not corrupted.
		# Flight may bypass dynamic ground obstacles on accepted land, but does not
		# acquire permission to use lake/ocean sliver anchors absent from this cache.
		if not source_walkable.has(a) or not source_walkable.has(b):return C.fail("NAV_DOMAIN_UNSUPPORTED","该落脚点不在已验证的陆地导航范围；飞行不会自动开放水域内的零碎干地。")
		return C.fail("NAV_GEOMETRY_MISMATCH","导航摘要与当前水面查询不一致，未执行移动。")
	return {"ok":true}

## Uniform-cost deterministic BFS. Every explored edge obeys both authoritative
## cell blocking and the active bundle's precise physical water-contact query.
## Stable axial neighbor order makes save replay independent of dictionary order.
## Inspired by Red Blob Games' BFS/came_from explanation; no external code copied.
static func plan_route(state:Dictionary,actor_id:String,target:Variant,budget:int)->Dictionary:
	if not target is Array or target.size()!=2 or not C.integer(target[0]) or not C.integer(target[1]):return C.fail("MOVE_TARGET","目标必须是两个整数构成的真实格坐标。")
	if not state.get("actors",{}).has(actor_id):return C.fail("MOVE_ACTOR","找不到行动者。")
	var actor:Dictionary=state.actors[actor_id]
	if actor.scene_id!="scene_coast":return C.fail("ACTION_SCENE","历史海岸路线仅适用于原海岸场景；当前场景需要已注册的加权路线。")
	if target==actor.hex:return C.fail("MOVE_TARGET","目标与当前位置相同，未移动或扣费。")
	var target_key:="%d,%d"%target
	if not state.hexes.has(target_key):return C.fail("MOVE_TARGET","目标不在当前世界。")
	var destination:Dictionary=state.hexes[target_key]
	if not Traversal.can_enter(state,actor,target):return C.fail("MOVE_BLOCKED","目标没有合法的干燥地面通路；跨水或飞行需要另外评估。")
	if budget<1:return C.fail("STAMINA_REQUIRED","没有可用步行体力；可以先评估休息。")
	if not ready():return C.fail("NAV_NOT_READY","当前导航未验证，未移动或扣费。")
	if state.get("generated_world",{}).get("bundle_id","")!=accepted_bundle_id:return C.fail("BUNDLE_MISMATCH","行动快照与当前导航世界版本不一致。")
	if not positions.has(target_key):return C.fail("NO_DRY_SUPPORT","目标没有可验证的干燥落脚点。")
	var limit:=mini(budget,maxi(0,state.hexes.size()-1))
	var start:="%d,%d"%actor.hex
	var visited:Dictionary={start:{"hex":actor.hex.duplicate(),"distance":0,"parent":""}}
	var queue:Array=[start];var cursor:=0
	while cursor<queue.size():
		var current_key:String=queue[cursor];cursor+=1
		var current:Dictionary=visited[current_key]
		if current_key==target_key:break
		if current.distance>=limit:continue
		for offset in [[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0]]:
			var next:Array=[int(current.hex[0])+offset[0],int(current.hex[1])+offset[1]]
			var next_key:="%d,%d"%next
			if visited.has(next_key) or not state.hexes.has(next_key):continue
			var cell:Dictionary=state.hexes[next_key]
			if not Traversal.can_enter(state,actor,next) or not Traversal.edge_allowed(state,actor,current.hex,next):continue
			var edge:=step(current.hex,next)
			if not edge.ok:
				if edge.get("code","") in ["NAV_NOT_READY","WATER_QUERY_FAILED","NAV_GEOMETRY_MISMATCH"]:return edge
				continue
			visited[next_key]={"hex":next,"distance":int(current.distance)+1,"parent":current_key};queue.append(next_key)
	if not visited.has(target_key):return C.fail("MOVE_UNREACHABLE_WITHIN_BUDGET","当前%d点体力内没有到达目标的合法干燥路线；没有部分移动或扣费。"%budget)
	var route:Array=[];var next_key:=target_key
	while not next_key.is_empty():
		route.push_front(visited[next_key].hex.duplicate());next_key=visited[next_key].parent
	return {"ok":true,"route":route,"cost":route.size()-1,"budget":budget,"turn_cost":1,"visited_count":visited.size(),"bundle_id":accepted_bundle_id,"state_version":state.state_version}

## v3 only: minimum terrain/capability effort, with scene-specific physical checks.
static func plan_weighted_route(state: Dictionary, actor_id: String, target: Variant, budget: int) -> Dictionary:
	if not state.get("actors",{}).has(actor_id): return C.fail("MOVE_ACTOR","找不到行动者。")
	var scene_id: String = state.actors[actor_id].scene_id
	var registry = preload("res://view/playable_build/scene_adapters.gd")
	var policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
	var registered: Dictionary = registry.descriptor(state,scene_id)
	if not registered.ok: return registered
	if scene_id=="scene_coast":
		if not ready(): return C.fail("NAV_NOT_READY","当前世界导航未通过验证。")
		var result: Dictionary = policy.plan(state,actor_id,target,budget,func(a,b): return step(a,b))
		if result.ok: result.bundle_id=accepted_bundle_id
		return result
	return policy.plan(state,actor_id,target,budget,func(a,b): return registry.authored_step(state,scene_id,a,b))

static func validate_scene_landing(state: Dictionary, scene_id: String, hex: Array) -> Dictionary:
	var registry = preload("res://view/playable_build/scene_adapters.gd")
	var cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
	var registered: Dictionary = registry.descriptor(state,scene_id)
	if not registered.ok: return registered
	var cell: Dictionary = cells.cell(state,scene_id,hex)
	if cell.is_empty() or cell.ground_blocked or cell.air_blocked or cell.all_blocked: return C.fail("SCENE_LANDING","场景落脚点被阻挡或尚未制作。")
	if scene_id=="scene_coast":
		if not ready(): return C.fail("NAV_NOT_READY","当前海岸水面未验证。")
		var key: String = cells.key(hex)
		if not positions.has(key): return C.fail("NO_DRY_SUPPORT","海岸落脚点没有真实干地支撑。")
		var context: Dictionary = water.water_endpoint_context(positions[key])
		if not context.get("ok",false): return C.fail("WATER_QUERY_FAILED","海岸落脚点水面查询失败。")
		if context.get("is_water",true): return C.fail("SCENE_LANDING","海岸落脚点接触真实水面。")
	elif cell.terrain in ["ocean","main_lake","water","river"]: return C.fail("SCENE_LANDING","室内适配器只允许作者声明的干地落脚点。")
	return {"ok":true}

static func safe_landing_route(state:Dictionary,actor_id:String,landing_check:Callable) -> Dictionary:
	if not state.get("actors",{}).has(actor_id):return C.fail("MOVE_ACTOR","Unknown actor")
	var actor:Dictionary=state.actors[actor_id]
	var registry=preload("res://view/playable_build/scene_adapters.gd")
	var policy=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
	var registered:Dictionary=registry.descriptor(state,actor.scene_id)
	if not registered.ok:return registered
	if actor.scene_id=="scene_coast":
		if not ready():return C.fail("NAV_NOT_READY","无法验证安全落地路线。")
		return policy.safe_landing(state,actor_id,int(actor.stamina.current),func(a,b):return step(a,b),landing_check)
	return policy.safe_landing(state,actor_id,int(actor.stamina.current),func(a,b):return registry.authored_step(state,actor.scene_id,a,b),landing_check)
