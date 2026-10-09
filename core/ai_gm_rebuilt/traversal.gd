extends RefCounted
const StatusContent=preload("res://core/status_gameplay/content.gd")
const StatusMovement=preload("res://core/status_gameplay/movement.gd")
## One predicate and one BFS serve both legal paths and the reachable overlay.
const Settlement = preload("res://view/playable_build/settlement_content.gd")
const Creative = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const DIRECTIONS := [[-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0]]

static func key(hex: Array) -> String: return "%d,%d" % [hex[0], hex[1]]
static func flight(actor: Dictionary, world:Dictionary={}, cell:Dictionary={}) -> bool:
	if StatusContent.active(world): return StatusMovement.flight_at(world,actor,cell if not cell.is_empty() else Cells.cell(world,actor.scene_id,actor.hex))
	for status in actor.get("statuses", {}).values():
		if status.get("kind") == "flight" and status.get("remaining_turns", 0) > 0: return true
	return false

static func can_enter(state: Dictionary, actor: Dictionary, hex: Array) -> bool:
	var cell: Dictionary = Cells.cell(state, actor.scene_id, hex)
	if cell.is_empty(): return false
	if StatusContent.active(state):return StatusMovement.can_enter(state,actor,cell)
	if cell.scene_id != actor.scene_id or cell.all_blocked: return false
	return not cell.air_blocked if flight(actor) else not cell.ground_blocked

static func edge_allowed(state: Dictionary, actor: Dictionary, from: Array, to: Array) -> bool:
	if StatusContent.active(state) and StatusMovement.has_flight(state,actor):
		if not flight(actor,state,Cells.cell(state,actor.scene_id,from)) or not flight(actor,state,Cells.cell(state,actor.scene_id,to)):return false
		# The two existing edge systems explicitly represent ground/perimeter
		# barriers and already allow legacy flight. Keep the same authored scope.
		if state.has("settlement_state") and not Settlement.active(state):return false
		return true
	return Settlement.edge_allowed(state,actor,from,to) and Creative.edge_allowed(state,actor,from,to)

static func reachable(state: Dictionary, actor_id: String, max_steps: int) -> Dictionary:
	var nodes:Dictionary=_reachable_nodes(state,actor_id,max_steps)
	if not StatusContent.active(state) or not state.actors.has(actor_id):return nodes
	var result:Dictionary={}
	for key_ in nodes:
		if StatusMovement.can_finish_route(state,actor_id,nodes[key_].hex,int(nodes[key_].distance)).ok:result[key_]=nodes[key_]
	return result

static func _reachable_nodes(state: Dictionary, actor_id: String, max_steps: int) -> Dictionary:
	if max_steps < 0 or not state.actors.has(actor_id): return {}
	var actor: Dictionary = state.actors[actor_id]
	var result: Dictionary = {key(actor.hex): {"hex": actor.hex.duplicate(), "distance": 0, "parent": ""}}
	var queue: Array = [actor.hex.duplicate()]
	var cursor := 0
	while cursor < queue.size():
		var current: Array = queue[cursor]; cursor += 1
		var distance: int = result[key(current)].distance
		if distance >= max_steps: continue
		for offset in DIRECTIONS:
			var next: Array = [current[0] + offset[0], current[1] + offset[1]]
			var next_key: String = key(next)
			if result.has(next_key) or not can_enter(state, actor, next) or not edge_allowed(state,actor,current,next): continue
			result[next_key] = {"hex": next, "distance": distance + 1, "parent": key(current)}
			queue.append(next)
	return result

static func path(state: Dictionary, actor_id: String, target: Array, max_steps: int, require_safe_finish:bool=true) -> Array:
	var visited := _reachable_nodes(state, actor_id, max_steps)
	if require_safe_finish and StatusContent.active(state) and state.actors.has(actor_id) and not StatusMovement.can_finish_action(state,state.actors[actor_id],target):return []
	var cursor := key(target)
	if not visited.has(cursor): return []
	var result: Array = []
	while not cursor.is_empty():
		result.push_front(visited[cursor].hex.duplicate())
		cursor = visited[cursor].parent
	return result
