extends Node3D
signal event_started(event:Dictionary)
## Presentation consumes a fresh committed receipt, never prose or a UI refresh.
## Version/hash gates are additional replay protection, not a second adjudicator.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SourceProfiles=preload("res://core/status_gameplay/source_profiles.gd")
const EffectNode = preload("res://view/playable_build/committed_effect_node.gd")
const MAX_ACTIVE := 16
const MAX_PENDING := 64
var world_id := ""
var consumed_version := -1
var slots: Array[Node3D] = []
var pending: Array[Dictionary] = []
var tokens: Dictionary = {}
var motion_presenter: Node3D
var feedback_camera: Camera3D
var safe_rect_provider: Callable
var framing_gate: Callable
var _feedback_obstacles:Array[Rect2]=[]
var last_events: Array = []
var accepted_receipts := 0
var ignored_receipts := 0
var emitted_effects := 0
var dropped_effects := 0

func reset_to(state: Dictionary) -> void:
	# Used on initial display/load/new game. Existing receipts are a baseline,
	# not new happenings. All active and delayed effects are invalidated.
	world_id = str(state.get("world_id", ""))
	consumed_version = int(state.get("state_version", -1))
	pending.clear(); last_events.clear(); tokens = {}
	for slot in slots: slot.stop()
	set_process(false)

func consume(receipt: Dictionary, before: Dictionary, after: Dictionary, actor_nodes: Dictionary) -> Dictionary:
	if not _fresh(receipt,before,after):
		ignored_receipts += 1
		return {"ok":false,"presented":false,"reason":"not_a_fresh_committed_receipt"}
	consumed_version = int(receipt.after_version)
	accepted_receipts += 1; tokens = actor_nodes.duplicate()
	last_events = events_for(receipt,before,after)
	for event in last_events:
		if pending.size() >= MAX_PENDING:
			dropped_effects += 1; continue
		var row := {"wait":float(event.get("delay",0.0)),"event":event.duplicate(true)}
		var generations: Dictionary = {}
		# A fast subsequent NPC commit may target an actor whose previous
		# committed route is still playing. Wait for both ends, not just a
		# movement patch in this receipt; facts were already committed once.
		for actor_id in [event.get("source_id", ""),event.get("target_id", ""),event.get("after_move_actor", "")]:
			if is_instance_valid(motion_presenter) and motion_presenter.actors.has(actor_id):
				generations[actor_id] = int(motion_presenter.actors[actor_id].generation)
		row["movement_generations"] = generations
		pending.append(row)
	set_process(not pending.is_empty() or active_count() > 0)
	_process(0.0)
	return {"ok":true,"presented":not last_events.is_empty(),"event_count":last_events.size()}

func _fresh(receipt: Dictionary, before: Dictionary, after: Dictionary) -> bool:
	if receipt.is_empty() or world_id.is_empty() or before.get("world_id", "") != world_id or after.get("world_id", "") != world_id: return false
	if not receipt.get("action_id") is String or not receipt.get("receipt_hash") is String or not receipt.get("stage_hash") is String: return false
	if not receipt.get("patches") is Array or not receipt.get("hook_patches") is Array: return false
	var version := int(receipt.get("after_version", -1))
	if version <= consumed_version or version != int(after.get("state_version", -2)): return false
	if int(receipt.get("before_version", -2)) != int(before.get("state_version", -3)) or version != int(before.get("state_version", -3)) + 1: return false
	var payload := receipt.duplicate(true); payload.erase("receipt_hash")
	return C.digest(payload) == receipt.receipt_hash

static func events_for(receipt: Dictionary, before: Dictionary, _after: Dictionary) -> Array:
	var events: Array = []
	var impacts: Dictionary = {}
	var moved: Dictionary = {}
	var hook_gate := ""
	for attack in receipt.get("patches", []):
		if not attack is Dictionary: continue
		if attack.get("type", "") == "actor_move": moved[str(attack.get("actor_id", ""))] = true
		if attack.get("type", "") != "combat_event": continue
		if not C.exact_fields(attack,["type","actor_id","target_actor_id","weapon_item_id","presentation_kind","outcome"]): continue
		if not attack.get("presentation_kind", "") in ["melee","ranged","magic"] or not attack.get("outcome", "") in ["miss","graze","hit"]: continue
		if not attack.actor_id is String or not attack.target_actor_id is String or not attack.weapon_item_id is String: continue
		if not before.get("actors", {}).has(attack.actor_id) or not before.get("actors", {}).has(attack.target_actor_id): continue
		var style := str(attack.presentation_kind)
		var wait: float = {"melee":0.18,"ranged":0.12,"magic":0.52}[style]
		var miss: bool = attack.outcome == "miss"
		var gate := str(attack.actor_id) if moved.has(attack.actor_id) else ""
		if not gate.is_empty(): hook_gate = gate
		events.append({"kind":style,"source_id":attack.actor_id,"target_id":attack.target_actor_id,"miss":miss,"outcome":attack.outcome,"delay":0.0,"after_move_actor":gate})
		impacts[attack.target_actor_id] = {"delay":wait,"outcome":attack.outcome,"after_move_actor":gate,"source_id":attack.actor_id}
		if miss: events.append({"kind":"miss","source_id":attack.actor_id,"target_id":attack.target_actor_id,"text":"未命中","delay":wait,"after_move_actor":gate})
	for patch in receipt.get("patches", []):
		_append_patch(events,patch,before,impacts,false)
	for patch in receipt.get("hook_patches", []):
		# New lifecycle application shares the committed hit's visual impact gate.
		# Periodic tick/removal keep their existing hook timing.
		var source_impacts:Dictionary=impacts if patch.get("type")=="status_v2_event" and patch.get("change")=="applied" else {}
		_append_patch(events,patch,before,source_impacts,true,hook_gate)
	for event in events:
		var actor:Dictionary=before.get("actors",{}).get(event.get("target_id",""),{})
		event["target_name"]=str(actor.get("name",event.get("target_id","")))
		event["source_name"]=str(before.get("actors",{}).get(event.get("source_id",""),{}).get("name",event.get("source_id","")))
	return events

static func _append_patch(events: Array, patch: Dictionary, before: Dictionary, impacts: Dictionary, hook: bool, hook_gate := "") -> void:
	var type := str(patch.get("type", ""))
	var actor_id := str(patch.get("owner_id", "")) if type=="status_v2_event" and patch.get("owner_kind", "")=="actor" else str(patch.get("actor_id", ""))
	if not before.get("actors", {}).has(actor_id): return
	var actor: Dictionary = before.actors[actor_id]
	var impact: Dictionary = impacts.get(actor_id,{})
	var delay := float(impact.get("delay",0.0))
	var gate := str(impact.get("after_move_actor", hook_gate))
	var source_id := str(impact.get("source_id", ""))
	if type == "actor_pool_delta" and patch.get("pool", "") == "health" and int(patch.delta) != 0:
		var loss: bool = int(patch.delta) < 0
		var poison := false
		if hook and loss:
			for status in actor.get("statuses", {}).values():
				if status.kind == "poison": poison = true
			for status in before.get("status_foundation",{}).get("instances",{}).values():
				if status.owner_kind=="actor" and status.owner_id==actor_id and status.definition_id=="poison" and SourceProfiles.public_instance(before,status):poison=true
		var text := ("中毒 " if poison else ("擦伤 " if impact.get("outcome", "") == "graze" else "")) + ("−%d" % -int(patch.delta) if loss else "+%d" % int(patch.delta))
		events.append({"kind":"damage" if loss else "heal","target_id":actor_id,"amount":absi(int(patch.delta)),"cause":"poison" if poison else ("unknown" if hook else "impact"),"text":text,"delay":maxf(delay,0.24) if hook else delay,"after_move_actor":gate,"source_id":source_id})
	elif type=="status_v2_event":
		var kind:String=str(patch.get("definition_id",""))
		if not kind in ["poison","flight"]:return
		if patch.change=="applied":events.append({"kind":kind,"target_id":actor_id,"text":"中毒" if kind=="poison" else "飞行","delay":delay+0.12,"after_move_actor":gate,"source_id":source_id})
		elif patch.change=="removed":events.append({"kind":"status_end","target_id":actor_id,"text":"中毒结束" if kind=="poison" else "飞行结束","delay":0.66,"after_move_actor":gate,"source_id":source_id})
	elif type == "actor_status_set":
		var kind := str(patch.status.get("kind", ""))
		if not kind in ["poison","flight"]: return
		# A decrement is represented by tick damage; it is not a new application.
		if actor.get("statuses", {}).has(patch.status_id): return
		events.append({"kind":kind,"target_id":actor_id,"text":"中毒" if kind == "poison" else "飞行","delay":delay+0.12,"after_move_actor":gate,"source_id":source_id})
	elif type == "actor_status_remove" and actor.get("statuses", {}).has(patch.status_id):
		var kind := str(actor.statuses[patch.status_id].kind)
		if kind in ["poison","flight"]:
			events.append({"kind":"status_end","target_id":actor_id,"text":"中毒结束" if kind == "poison" else "飞行结束","delay":0.66,"after_move_actor":gate,"source_id":source_id})

func _process(delta: float) -> void:
	_feedback_obstacles=_nameplate_rects()
	for slot in slots:
		if slot.active:
			slot.tick(delta)
			if slot.active:_screen_safe(slot)
	var ready: Array[Dictionary] = []
	var stale: Array[Dictionary] = []
	for row in pending:
		var waiting := false
		var invalid := false
		for actor_id in row.get("movement_generations", {}):
			if not is_instance_valid(motion_presenter) or not motion_presenter.actors.has(actor_id) or int(motion_presenter.actors[actor_id].generation) != int(row.movement_generations[actor_id]):
				invalid = true; break
			if motion_presenter.actors[actor_id].moving: waiting = true
		if invalid: stale.append(row); continue
		if waiting or (framing_gate.is_valid() and not framing_gate.call()): continue
		row.wait -= delta
		if row.wait <= 0.0: ready.append(row)
	for row in stale:
		pending.erase(row); dropped_effects += 1
	for row in ready:
		pending.erase(row); _emit(row.event)
	if pending.is_empty() and active_count() == 0: set_process(false)

func _emit(event: Dictionary) -> void:
	var target_id := str(event.get("target_id", ""))
	if not tokens.has(target_id) or not is_instance_valid(tokens[target_id]): return
	if event.get("kind", "") in ["melee","ranged","magic"]:
		var source_id := str(event.get("source_id", ""))
		if not tokens.has(source_id) or not is_instance_valid(tokens[source_id]): return
	var target: Node3D = tokens[target_id]
	var to := target.position+Vector3(0,0.58,0)
	var from := to
	if tokens.has(event.get("source_id", "")) and is_instance_valid(tokens[event.source_id]):
		from = tokens[event.source_id].position+Vector3(0,0.64,0)
	var free: Node3D
	for slot in slots:
		if not slot.active: free = slot; break
	if free == null:
		if slots.size() >= MAX_ACTIVE:
			dropped_effects += 1; return
		free = EffectNode.new(); free.name = "PooledCommittedEffect_%02d" % slots.size()
		add_child(free); slots.append(free)
	free.start(event,from,to,target)
	_screen_safe(free)
	emitted_effects += 1
	event_started.emit(event.duplicate(true))

func _screen_safe(slot:Node3D)->void:
	if is_instance_valid(feedback_camera) and safe_rect_provider.is_valid():
		slot.keep_label_screen_safe(feedback_camera,safe_rect_provider.call(),_feedback_obstacles)
		if slot.label.visible and slot.label_screen_rect.has_area():_feedback_obstacles.append(slot.label_screen_rect.grow(3.0))

func _nameplate_rects()->Array[Rect2]:
	var rectangles:Array[Rect2]=[]
	if not is_instance_valid(feedback_camera):return rectangles
	var pixels:=feedback_camera.get_viewport().get_visible_rect().size.y/maxf(0.01,feedback_camera.size)
	for token in tokens.values():
		if not is_instance_valid(token):continue
		var plate:Label3D=token.get_node_or_null("Nameplate") as Label3D
		if plate==null or plate.font==null or not plate.is_visible_in_tree() or feedback_camera.is_position_behind(plate.global_position):continue
		var world_scale:=plate.global_transform.basis.get_scale()
		var measure:=plate.font.get_string_size(plate.text,HORIZONTAL_ALIGNMENT_LEFT,-1,plate.font_size)
		var extent:=Vector2(measure.x*world_scale.x,plate.font.get_height(plate.font_size)*world_scale.y)*plate.pixel_size*pixels
		var center:=feedback_camera.unproject_position(plate.global_position)
		rectangles.append(Rect2(center-extent*0.5,extent).grow(4.0))
	return rectangles

func active_count() -> int:
	var count := 0
	for slot in slots:
		if slot.active: count += 1
	return count

func report() -> Dictionary:
	return {"accepted_receipts":accepted_receipts,"ignored_receipts":ignored_receipts,"active_effects":active_count(),"pending_effects":pending.size(),"pooled_nodes":slots.size(),"pool_cap":MAX_ACTIVE,"emitted_effects":emitted_effects,"dropped_effects":dropped_effects,"postprocessing":false,"realtime_lights":false,"gameplay_writes":false}
