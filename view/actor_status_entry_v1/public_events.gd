extends RefCounted
## Pure display derivation from a verified receipt and its saved public record.
## No authority writes, re-hashing a filtered receipt, prose or history backfill.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicStatus = preload("res://view/actor_status_profile_v1/public_status.gd")
const PublicProjection = preload("res://view/actor_status_profile_v1/projection.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const RECORD_SCHEMA = "actor_status_public_receipt/v1"

static func extract(receipt: Dictionary, before: Dictionary, after: Dictionary, record: Dictionary, observer: String = "actor_player") -> Dictionary:
	if not C.safe(receipt) or not C.safe(record) or not C.exact_fields(record, ["schema_version", "action_id", "actor_id", "after_version", "receipt_hash", "attention_focus", "public_effects"]): return C.fail("STATUS_PUBLIC_RECORD", "Missing exact saved public receipt evidence.")
	if record.schema_version != RECORD_SCHEMA or not record.public_effects is Array or record.action_id != receipt.get("action_id") or record.actor_id != receipt.get("actor_id") or record.after_version != receipt.get("after_version") or record.receipt_hash != receipt.get("receipt_hash"): return C.fail("STATUS_PUBLIC_RECORD", "Public evidence does not bind this original receipt.")
	var payload: Dictionary = receipt.duplicate(true); payload.erase("receipt_hash")
	if C.digest(payload) != receipt.get("receipt_hash"): return C.fail("STATUS_PUBLIC_RECORD", "The original receipt hash is invalid.")
	if not receipt.get("patches") is Array or not receipt.get("hook_patches") is Array: return C.fail("STATUS_PUBLIC_RECORD", "Receipt patches are incomplete.")
	if before.get("world_id") != after.get("world_id") or not str(receipt.get("action_id", "")).begins_with(str(before.get("world_id", "")) + ":action_") or receipt.get("before_version") != before.get("state_version") or receipt.get("after_version") != after.get("state_version") or int(receipt.get("after_version", -1)) != int(receipt.get("before_version", -1)) + 1: return C.fail("STATUS_PUBLIC_RECORD", "Display requires the original immediate before/after snapshots, never current history backfill.")
	# A claimed public effect must occur in the original immutable transaction.
	var available: Array = receipt.patches.duplicate(true); available.append_array(receipt.hook_patches)
	for effect in record.public_effects:
		var found := -1
		for i in range(available.size()):
			if C.bytes(available[i]) == C.bytes(effect): found = i; break
		if found < 0: return C.fail("STATUS_PUBLIC_RECORD", "Public effect is not an original receipt patch.")
		available.remove_at(found)
	return {"ok": true, "events": _events(receipt, before, after, record, observer)}

static func _contains(values: Array, patch: Dictionary) -> bool:
	for value in values:
		if C.bytes(value) == C.bytes(patch): return true
	return false
static func _visible(before: Dictionary, after: Dictionary, observer: String, id: String) -> bool:
	for state in [before, after]:
		if not state.get("actors", {}).has(observer) or not state.actors.has(id): continue
		var a: Dictionary = state.actors[observer]; var b: Dictionary = state.actors[id]
		if a.scene_id == b.scene_id and Basic._distance(a.hex, b.hex) <= PublicProjection.RADIUS: return true
	return false
static func _public_patch(patch: Dictionary, record: Dictionary, before: Dictionary, after: Dictionary, observer: String) -> bool:
	if not _contains(record.public_effects, patch): return false
	var id: String = str(patch.get("owner_id", "")) if patch.get("type") == "status_v2_event" else str(patch.get("actor_id", ""))
	if not _visible(before, after, observer, id): return false
	if patch.get("type") == "status_v2_event": return PublicStatus.visible_event(before, after, observer, patch)
	if patch.get("type") in ["actor_status_set", "actor_status_remove"]: return PublicStatus.public_legacy_patch(patch)
	return true
static func _applied_in_receipt(receipt: Dictionary, event: Dictionary) -> bool:
	for patch in receipt.patches:
		if PublicStatus.observable_application(patch) and PublicStatus.matches_event(patch,event): return true
	return false
static func _public_poison_tick(receipt: Dictionary, record: Dictionary, before: Dictionary, actor_id: String) -> bool:
	for event in record.public_effects:
		if event.get("type") in ["actor_status_set", "actor_status_remove"] and event.get("actor_id") == actor_id and PublicStatus.public_legacy_patch(event) and before.actors[actor_id].get("statuses", {}).has("weapon_poison"): return true
		if event.get("type") != "status_v2_event" or event.get("definition_id") != "poison" or event.get("owner_id") != actor_id or event.get("change") not in ["updated", "removed"] or receipt.get("actor_id") != actor_id: continue
		for instance in before.get("status_foundation", {}).get("instances", {}).values():
			if PublicStatus.observable(before,instance) and PublicStatus.matches_event(instance,event): return true
	# A same-generation owner refresh may leave identical instance bytes after
	# its owner tick. The original successful apply still proves the refresh;
	# a private retained source must never qualify through this path.
	if receipt.get("actor_id") == actor_id:
		for instance in before.get("status_foundation", {}).get("instances", {}).values():
			if instance.get("owner_id") == actor_id and instance.get("definition_id") == "poison" and PublicStatus.observable(before,instance) and _applied_in_receipt(receipt,instance): return true
	return false
static func _append_refreshes(events: Array, receipt: Dictionary, before: Dictionary, after: Dictionary, observer: String, gate: String) -> void:
	var emitted: Dictionary = {}
	for patch in receipt.patches:
		if not PublicStatus.observable_application(patch) or not _visible(before,after,observer,patch.owner_id): continue
		var old_public := false; var new_public := false
		for instance in before.get("status_foundation", {}).get("instances", {}).values():
			if PublicStatus.observable(before,instance) and PublicStatus.matches_event(instance,patch): old_public = true
		for instance in after.get("status_foundation", {}).get("instances", {}).values():
			if PublicStatus.observable(after,instance) and PublicStatus.matches_event(instance,patch): new_public = true
		var key: String = str(patch.owner_id) + ":" + str(patch.definition_id)
		if not old_public or not new_public or emitted.has(key): continue
		emitted[key] = true
		events.append({"kind":patch.definition_id,"target_id":patch.owner_id,"text":"中毒刷新" if patch.definition_id=="poison" else "飞行刷新","delay":0.12,"after_move_actor":gate,"source_id":""})

static func _events(receipt: Dictionary, before: Dictionary, after: Dictionary, record: Dictionary, observer: String) -> Array:
	var events: Array = []
	var impacts: Dictionary = {}
	var moved: Dictionary = {}
	var hook_gate := ""
	for attack in receipt.get("patches", []):
		if not attack is Dictionary or not _contains(record.public_effects, attack): continue
		if attack.get("type", "") == "actor_move": moved[str(attack.get("actor_id", ""))] = true
		if attack.get("type", "") != "combat_event": continue
		if not C.exact_fields(attack,["type","actor_id","target_actor_id","weapon_item_id","presentation_kind","outcome"]): continue
		if not attack.get("presentation_kind", "") in ["melee","ranged","magic"] or not attack.get("outcome", "") in ["miss","graze","hit"]: continue
		if not attack.actor_id is String or not attack.target_actor_id is String or not attack.weapon_item_id is String: continue
		if not before.get("actors", {}).has(attack.actor_id) or not before.get("actors", {}).has(attack.target_actor_id): continue
		if not _visible(before, after, observer, attack.actor_id) or not _visible(before, after, observer, attack.target_actor_id): continue
		var style := str(attack.presentation_kind)
		var wait: float = {"melee":0.18,"ranged":0.12,"magic":0.52}[style]
		var miss: bool = attack.outcome == "miss"
		var gate := str(attack.actor_id) if moved.has(attack.actor_id) else ""
		if not gate.is_empty(): hook_gate = gate
		events.append({"kind":style,"source_id":attack.actor_id,"target_id":attack.target_actor_id,"miss":miss,"outcome":attack.outcome,"delay":0.0,"after_move_actor":gate})
		impacts[attack.target_actor_id] = {"delay":wait,"outcome":attack.outcome,"after_move_actor":gate,"source_id":attack.actor_id}
		if miss: events.append({"kind":"miss","source_id":attack.actor_id,"target_id":attack.target_actor_id,"text":"未命中","delay":wait,"after_move_actor":gate})
	for patch in receipt.get("patches", []):
		if _public_patch(patch, record, before, after, observer): _append_patch(events,patch,before,impacts,false,"",receipt,record)
	for patch in receipt.get("hook_patches", []):
		# New lifecycle application shares the committed hit's visual impact gate.
		# Periodic tick/removal keep their existing hook timing.
		var source_impacts:Dictionary=impacts if patch.get("type")=="status_v2_event" and patch.get("change")=="applied" else {}
		if _public_patch(patch, record, before, after, observer): _append_patch(events,patch,before,source_impacts,true,hook_gate,receipt,record)
	_append_refreshes(events,receipt,before,after,observer,hook_gate)
	for event in events:
		var actor:Dictionary=before.get("actors",{}).get(event.get("target_id",""),{})
		event["target_name"]=str(actor.get("name",event.get("target_id","")))
		event["source_name"]=str(before.get("actors",{}).get(event.get("source_id",""),{}).get("name",event.get("source_id","")))
	return events

static func _append_patch(events: Array, patch: Dictionary, before: Dictionary, impacts: Dictionary, hook: bool, hook_gate: String, receipt: Dictionary, record: Dictionary) -> void:
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
			poison = _public_poison_tick(receipt, record, before, actor_id)
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

