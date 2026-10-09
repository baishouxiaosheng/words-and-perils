extends "res://view/playable_build/committed_effect_router.gd"
const PublicEvents = preload("res://view/actor_status_entry_v1/public_events.gd")

func consume_public(receipt: Dictionary, before: Dictionary, after: Dictionary, actor_nodes: Dictionary, record: Dictionary) -> Dictionary:
	if not _fresh(receipt,before,after):
		ignored_receipts += 1
		return {"ok":false,"presented":false,"reason":"not_a_fresh_committed_receipt"}
	var public: Dictionary = PublicEvents.extract(receipt, before, after, record)
	if not public.get("ok", false):
		ignored_receipts += 1
		return public
	consumed_version = int(receipt.after_version)
	accepted_receipts += 1; tokens = actor_nodes.duplicate()
	last_events = public.events
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


func consume(_receipt: Dictionary, _before: Dictionary, _after: Dictionary, _actor_nodes: Dictionary) -> Dictionary:
	return {"ok": false, "presented": false, "reason": "status_public_record_required"}
