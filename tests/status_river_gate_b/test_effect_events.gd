extends "res://tests/status_river_gate_b/harness.gd"
## Synthetic read-only renderer fixtures, NOT engine actions or source-world facts.
## Imports the actual router/EffectNode/font closure, so native compilation still
## belongs to the full-resource admission gate even though this has no Main scene.
const Router = preload("res://view/playable_build/committed_effect_router.gd")

func _initialize() -> void:
	case_name = "effect_events"
	if not storage_safe():
		finish()
		return
	var before: Dictionary = {"world_id":"offline_renderer_contract_fixture", "state_version":0, "actors":{"actor_player":{"name":"测试旅人", "statuses":{}}, "actor_target":{"name":"测试目标", "statuses":{}}}}
	var after: Dictionary = before.duplicate(true)
	after.state_version = 1
	var recorded: Dictionary = {}
	for style in ["melee","ranged","magic"]:
		var receipt := synthetic_receipt(style)
		var events: Array = Router.events_for(receipt,before,after)
		var hit: Dictionary = first_event(events,style)
		var poison: Dictionary = first_event(events,"poison")
		var impact_delay: float = {"melee":0.18,"ranged":0.12,"magic":0.52}[style]
		check(not hit.is_empty() and not poison.is_empty(), "synthetic " + style + " hit and typed poison application both route")
		check(poison.get("after_move_actor") == "actor_player" and poison.get("source_id") == "actor_player" and is_equal_approx(float(poison.get("delay",-1)),impact_delay+0.12), "hook poison starts after actual hit timing and waits for source movement: " + style)
		check(hit.get("delay") == 0.0 and poison.get("delay",0.0) > impact_delay, "poison does not visually precede the " + style + " impact")
		recorded[style] = events
	# Exact duplicate suppression runs on the real consumer. Empty token map
	# avoids rendering invented actors; this is presentation-only input data.
	var receipt := synthetic_receipt("magic")
	var router: Node3D = Router.new()
	root.add_child(router)
	router.reset_to(before)
	var accepted: Dictionary = router.consume(receipt,before,after,{})
	check(accepted.get("ok",false) and router.accepted_receipts == 1, "synthetic renderer envelope accepted once")
	var pending_hash := C.digest(router.pending)
	var count: int = router.emitted_effects
	var repeated: Dictionary = router.consume(receipt,before,after,{})
	check(not repeated.get("ok",false) and router.accepted_receipts == 1 and router.ignored_receipts == 1 and C.digest(router.pending) == pending_hash and router.emitted_effects == count, "repeated renderer receipt cannot enqueue or emit again")
	var changed: Dictionary = receipt.duplicate(true)
	changed.action_id = "changed_without_resigning"
	router.reset_to(before)
	check(not router.consume(changed,before,after,{}).get("ok",false), "otherwise-fresh tampered receipt cannot bypass consumer hash gate")
	router.reset_to(after)
	check(router.pending.is_empty() and router.last_events.is_empty() and not router.consume(receipt,before,after,{}).get("ok",false), "load/reset invalidates delayed effects and treats saved receipts as baseline")
	router.queue_free()
	var poisoned: Dictionary = before.duplicate(true)
	poisoned.status_gameplay={"schema_version":"status_gameplay_world/v1"}
	poisoned.items={"offline_renderer_weapon":{"weapon_profile":{"on_full_hit":"poison"},"status_on_hit":{"definition_id":"poison","parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0},"duration_owner_actions":3}}}
	poisoned.status_foundation = {"instances":{"offline_poison":{"owner_kind":"actor","owner_id":"actor_target","definition_id":"poison","source_id":"offline_renderer_weapon"}}}
	var periodic: Dictionary = {"patches":[],"hook_patches":[{"type":"actor_pool_delta","actor_id":"actor_target","pool":"health","delta":-2}, status_event("removed")]}
	var periodic_events: Array = Router.events_for(periodic,poisoned,after)
	var damage := first_event(periodic_events,"damage")
	var removed := first_event(periodic_events,"status_end")
	check(damage.get("cause") == "poison" and is_equal_approx(float(damage.get("delay",-1)),0.24), "periodic poison damage retains hook timing without inventing attack delay")
	check(is_equal_approx(float(removed.get("delay",-1)),0.66), "typed poison removal retains status-end timing")
	check(first_event(periodic_events,"poison").is_empty(), "periodic decrement/removal does not replay application")
	var private_before:Dictionary=poisoned.duplicate(true);private_before.status_foundation.instances.offline_poison.source_id="private_unobserved"
	var private_events:Array=Router.events_for({"patches":[],"hook_patches":[{"type":"actor_pool_delta","actor_id":"actor_target","pool":"health","delta":-2}]},private_before,after)
	check(first_event(private_events,"damage").get("cause")=="unknown" and not first_event(private_events,"damage").get("text","").contains("中毒"),"private NPC source does not become an FX diagnosis")
	report["synthetic_events"] = recorded
	report["scope"] = "Static events_for contract plus actual consumer idempotence on labelled synthetic renderer envelopes; no combat gameplay, no screenshots, no pixel/font appearance validation"
	completed = true
	finish()

func first_event(events: Array, kind: String) -> Dictionary:
	for event in events:
		if event.get("kind") == kind:
			return event
	return {}

func status_event(change: String) -> Dictionary:
	return {"type":"status_v2_event", "owner_kind":"actor", "owner_id":"actor_target", "definition_id":"poison", "change":change, "remaining":3 if change == "applied" else 0, "clock":"owner_action", "parameters":{"intensity":1,"flat_damage":1,"max_health_bps":0}, "name":"中毒"}

func synthetic_receipt(style: String) -> Dictionary:
	var receipt := {"action_id":"offline_renderer_fixture:"+style, "stage_hash":"offline_non_authoritative_stage", "before_version":0, "after_version":1, "patches":[{"type":"actor_move","actor_id":"actor_player","hex":[1,0]}, {"type":"combat_event","actor_id":"actor_player","target_actor_id":"actor_target","weapon_item_id":"offline_renderer_weapon", "presentation_kind":style,"outcome":"hit"}], "hook_patches":[status_event("applied")]}
	receipt["receipt_hash"] = C.digest(receipt)
	return receipt
