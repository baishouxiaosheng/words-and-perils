extends RefCounted
## Versioned integer costs. Never reads mesh/display heights or accepts model costs.
## Dijkstra uses the same accumulated edge cost for choosing and charging a route.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const ID := "terrain_traversal/v1"
const COSTS := {"smooth":1,"floor":1,"plain":1,"grass":1,"road":1,"bridge":1,"arid":2,"forest":2,"hill":3,"hills":3,"jungle":3,"swamp":3,"mountain":4}
const PROFILE_FIELDS := ["policy_id", "terrain_discounts", "max_action_cost"]

static func validate_profile(profile: Variant) -> bool:
	if not C.exact_fields(profile, PROFILE_FIELDS) or profile.policy_id != ID or not profile.terrain_discounts is Dictionary or not C.integer(profile.max_action_cost) or profile.max_action_cost < 1 or profile.max_action_cost > 32: return false
	for terrain in profile.terrain_discounts:
		if not COSTS.has(terrain) or not C.integer(profile.terrain_discounts[terrain]) or profile.terrain_discounts[terrain] < 0 or profile.terrain_discounts[terrain] > 2: return false
	return true

static func profile_for(actor: Dictionary) -> Dictionary:
	return actor.get("traversal_profile", {"policy_id":ID,"terrain_discounts":{},"max_action_cost":32}).duplicate(true)

static func budget_for(actor: Dictionary, requested: int) -> int:
	var profile := profile_for(actor)
	if not validate_profile(profile): return 0
	return maxi(0, mini(mini(requested, int(actor.stamina.current)), int(profile.max_action_cost)))

static func edge_cost(actor: Dictionary, cell: Dictionary, state:Dictionary={}) -> Dictionary:
	var profile := profile_for(actor)
	if not validate_profile(profile): return C.fail("TRAVERSAL_PROFILE", "行动者的移动能力配置无效。")
	var base: int = COSTS.get(cell.terrain, 2)
	var discount: int = profile.terrain_discounts.get(cell.terrain, 0)
	# Flight changes ground effort, not dry support, water, all-wall or air-wall rules.
	var flight_discount: int = base - 1 if Traversal.flight(actor,state,cell) else 0
	return {"ok":true,"terrain":cell.terrain,"base_cost":base,"capability_discount":discount,"flight_discount":flight_discount,"cost":maxi(1,base-maxi(discount,flight_discount))}

static func scene_cells(state: Dictionary, scene_id: String) -> Dictionary:
	return Cells.cells(state,scene_id)

static func plan(state: Dictionary, actor_id: String, target: Variant, requested_budget: int, edge_check: Callable) -> Dictionary:
	if not state.actors.has(actor_id): return C.fail("MOVE_ACTOR", "找不到行动者。")
	if not target is Array or target.size()!=2 or not C.integer(target[0]) or not C.integer(target[1]): return C.fail("MOVE_TARGET", "目标必须是两个整数构成的当前场景格坐标。")
	var actor: Dictionary = state.actors[actor_id]
	if not validate_profile(profile_for(actor)): return C.fail("TRAVERSAL_PROFILE", "行动者的移动能力配置无效。")
	var cells := scene_cells(state, actor.scene_id)
	var target_key := Traversal.key(target)
	if target == actor.hex or not cells.has(target_key): return C.fail("MOVE_TARGET", "目标必须是当前场景内不同的落脚点。")
	if not Traversal.can_enter(state, actor, target): return C.fail("MOVE_BLOCKED", "目标被当前移动能力不能通过的障碍阻挡。")
	if not preload("res://core/status_gameplay/movement.gd").can_finish_action(state,actor,target):return C.fail("STATUS_LANDING", "飞行即将到期；当前原型尚未接入坠落、抓攀和救援结算，请改选已登记落脚点。")
	var budget := budget_for(actor, requested_budget)
	if budget < 1: return C.fail("STAMINA_REQUIRED", "没有可用移动体力。")
	var start := Traversal.key(actor.hex)
	var visited: Dictionary = {start:{"hex":actor.hex.duplicate(),"cost":0,"distance":0,"parent":"","edge":{}}}
	var open: Array = [start]
	var closed: Dictionary = {}
	while not open.is_empty():
		var index := 0
		for i in range(1,open.size()):
			if visited[open[i]].cost < visited[open[index]].cost or (visited[open[i]].cost == visited[open[index]].cost and String(open[i]) < String(open[index])): index = i
		var current_key: String = open[index]; open.remove_at(index)
		if closed.has(current_key): continue
		closed[current_key] = true
		if current_key == target_key: break
		var current: Dictionary = visited[current_key]
		for offset in Traversal.DIRECTIONS:
			var next: Array = [int(current.hex[0])+offset[0],int(current.hex[1])+offset[1]]
			var next_key := Traversal.key(next)
			if closed.has(next_key) or not cells.has(next_key) or not Traversal.can_enter(state,actor,next) or not Traversal.edge_allowed(state,actor,current.hex,next): continue
			var edge: Dictionary = edge_cost(actor,cells[next_key],state)
			var cost: int = current.cost + edge.cost
			if cost > budget or (visited.has(next_key) and int(visited[next_key].cost) <= cost): continue
			var physical: Dictionary = edge_check.call(current.hex,next)
			if not physical.get("ok",false):
				if physical.get("code","") in ["NAV_NOT_READY","WATER_QUERY_FAILED","NAV_GEOMETRY_MISMATCH","BUNDLE_MISMATCH","SCENE_ADAPTER"]: return physical
				continue
			visited[next_key] = {"hex":next,"cost":cost,"distance":int(current.distance)+1,"parent":current_key,"edge":edge}
			open.append(next_key)
	if not closed.has(target_key): return C.fail("MOVE_UNREACHABLE_WITHIN_BUDGET", "当前%d点移动预算内没有合法路线；未部分移动或扣费。" % budget)
	var route: Array = []; var costs: Array = []; var cursor := target_key
	while not cursor.is_empty():
		route.push_front(visited[cursor].hex.duplicate())
		if not visited[cursor].edge.is_empty(): costs.push_front(visited[cursor].edge.duplicate(true))
		cursor = visited[cursor].parent
	var status_finish:Dictionary=preload("res://core/status_gameplay/movement.gd").can_finish_route(state,actor_id,target,int(visited[target_key].cost))
	if not status_finish.ok:return status_finish
	return {"ok":true,"route":route,"cost":int(visited[target_key].cost),"distance":route.size()-1,"edge_costs":costs,"budget":budget,"turn_cost":1,"policy_id":ID,"scene_id":actor.scene_id,"state_version":state.state_version,"visited_count":closed.size(),"source_digest":C.digest({"actor":actor,"cells":cells,"world":state.get("generated_world",{}),"state_version":state.state_version})}

## Existing costs/edge checks, stopping at the first affordable safe landing.
## Used only to reject a new flight action that would strand an actor mid-air.
static func safe_landing(state:Dictionary,actor_id:String,requested_budget:int,edge_check:Callable,landing_check:Callable) -> Dictionary:
	if not state.actors.has(actor_id):return C.fail("MOVE_ACTOR","Unknown actor")
	var actor:Dictionary=state.actors[actor_id]
	var budget:int=budget_for(actor,requested_budget)
	if landing_check.call(actor.hex):return {"ok":true,"cost":0,"hex":actor.hex.duplicate()}
	if budget<1:return C.fail("STATUS_FLIGHT_EXIT_REQUIRED","此原型尚未接入耗尽体力后的坠落、抓攀和救援，不能提交这个无撤离体力的空中终态。")
	var cells:=scene_cells(state,actor.scene_id)
	var start:String=Traversal.key(actor.hex)
	var open:Array=[start];var costs:Dictionary={start:0};var closed:Dictionary={}
	while not open.is_empty():
		var best:=0
		for i in range(1,open.size()):
			if costs[open[i]]<costs[open[best]] or (costs[open[i]]==costs[open[best]] and String(open[i])<String(open[best])):best=i
		var key:String=open[best];open.remove_at(best)
		if closed.has(key):continue
		closed[key]=true
		var cell:Dictionary=cells[key];var from:Array=[cell.q,cell.r]
		if landing_check.call(from):return {"ok":true,"cost":costs[key],"hex":from}
		for offset in Traversal.DIRECTIONS:
			var target:Array=[int(from[0])+offset[0],int(from[1])+offset[1]];var target_key:String=Traversal.key(target)
			if closed.has(target_key) or not cells.has(target_key) or not Traversal.can_enter(state,actor,target) or not Traversal.edge_allowed(state,actor,from,target):continue
			var edge:Dictionary=edge_cost(actor,cells[target_key],state)
			var cost:int=int(costs[key])+int(edge.cost)
			if cost>budget or (costs.has(target_key) and int(costs[target_key])<=cost):continue
			var physical:Dictionary=edge_check.call(from,target)
			if not physical.get("ok",false):
				if physical.get("code","") in ["NAV_NOT_READY","WATER_QUERY_FAILED","NAV_GEOMETRY_MISMATCH","BUNDLE_MISMATCH","SCENE_ADAPTER"]:return physical
				continue
			costs[target_key]=cost;open.append(target_key)
	return C.fail("STATUS_FLIGHT_EXIT_REQUIRED","本次行动后没有可负担的落地路线；原型尚未接入明知会坠落时的冒险后果，请改选落脚点或保留撤离体力。")
