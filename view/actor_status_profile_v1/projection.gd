extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const View=preload("res://core/ai_gm_rebuilt/model_view.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Focus=preload("res://core/focus_contract.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const PublicStatus=preload("res://view/actor_status_profile_v1/public_status.gd")
const RADIUS=3
static func facts(state:Dictionary,actor_id:String)->Dictionary:
	if not actor_id in ["actor_player","actor_village_hostile"] or not state.actors.has(actor_id):return {}
	var actor:Dictionary=state.actors[actor_id]
	var result={"schema_version":state.schema_version,"world_id":state.world_id,"state_version":state.state_version,"turn":state.turn,"actors":{},"items":{},"hexes":{},"scenes":{},"story_anchors":state.story_anchors.duplicate(true),"flags":{},"combat_turn":state.combat_turn.duplicate(true),"actor_action_identity":{"schema_version":state.actor_action_identity.schema_version,"profile_hash":state.actor_action_identity.profile_hash},"context_scope":{"observer_id":actor_id,"radius":RADIUS,"selection_expands_visibility":false,"omitted_is_absent":false}}
	for key in state.hexes:
		var cell:Dictionary=state.hexes[key]
		if cell.scene_id==actor.scene_id and Basic._distance(actor.hex,[cell.q,cell.r])<=RADIUS:result.hexes[key]=View.pick(cell,View.CELL_FIELDS)
	for id in state.actors:
		var subject:Dictionary=state.actors[id]
		if subject.scene_id==actor.scene_id and result.hexes.has("%d,%d"%subject.hex):
			result.actors[id]=View.pick(subject,View.ACTOR_FIELDS)
			result.actors[id].erase("statuses")
			result.actors[id]["status_details"]=PublicStatus.details(state,id)
	for id in state.items:
		var item:Dictionary=state.items[id];var owner_id:String=item.get("owner_actor_id","")
		if owner_id==actor_id or (not owner_id.is_empty() and result.actors.has(owner_id)) or (item.get("scene_id")==actor.scene_id and item.has("hex") and result.hexes.has("%d,%d"%item.hex)):result.items[id]=View.pick(item,View.ITEM_FIELDS)
	for key in ["actor_observations_"+actor_id,"actor_last_cell_"+actor_id]:result.flags[key]=state.flags[key]
	var scene:Dictionary=View.pick(state.scenes[actor.scene_id],["id","name","layer_id"]);scene.hex_ids=[]
	for cell in result.hexes.values():scene.hex_ids.append(cell.id)
	result.scenes[actor.scene_id]=scene
	result["learned_facts"]=state.get("npc_state",{}).get("learned_facts",{}).get(actor_id,{}).duplicate(true)
	result["status_context"]=PublicStatus.compact(state,actor_id)
	return C.normalized(result)
static func visible_focus(state:Dictionary,actor_id:String,reference:Dictionary)->bool:
	if not actor_id in ["actor_player","actor_village_hostile"] or not state.get("actors",{}).has(actor_id):return false
	if reference.is_empty():return true
	var f:Dictionary=Focus.new().resolve(reference,state)
	if not f.ok:return false
	if f.focus.is_empty():return true
	var public=facts(state,actor_id);var kind:String=f.focus.get("kind","");var id:String=f.focus.get("id","")
	if kind=="actor":return public.actors.has(id)
	if kind=="item":return public.items.has(id)
	if kind=="tile":
		for cell in public.hexes.values():
			if cell.id==id:return true
	return false
