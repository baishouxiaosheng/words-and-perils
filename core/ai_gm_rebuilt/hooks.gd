extends RefCounted
const StatusFoundation = preload("res://core/status_foundation/engine_bridge.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")

static func freeze(before: Dictionary, candidate: Dictionary, acting_actor_id: String = "") -> Dictionary:
	var patches: Array = []
	var actor_ids: Array = before.actors.keys(); actor_ids.sort()
	for actor_id in actor_ids:
		var previous: Dictionary = before.actors[actor_id]
		var actor: Dictionary = candidate.actors[actor_id]
		if "status_tick" in previous.hooks:
			var status_ids: Array = previous.statuses.keys(); status_ids.sort()
			for status_id in status_ids:
				if not actor.statuses.has(status_id): continue
				var status: Dictionary = actor.statuses[status_id].duplicate(true)
				if status.kind == "poison" and actor.health.current > 0:
					var damage: int = mini(status.magnitude, actor.health.current)
					var patch := {"type": "actor_pool_delta", "actor_id": actor_id, "pool": "health", "delta": -damage}
					var applied: Dictionary = World.apply(candidate, patch, true)
					if not applied.ok: return applied
					patches.append(patch)
				status.remaining_turns -= 1
				var tick_patch: Dictionary = {"type": "actor_status_remove", "actor_id": actor_id, "status_id": status_id} if status.remaining_turns == 0 else {"type": "actor_status_set", "actor_id": actor_id, "status_id": status_id, "status": status}
				var ticked: Dictionary = World.apply(candidate, tick_patch, true)
				if not ticked.ok: return ticked
				patches.append(tick_patch)
		if "patrol" in previous.hooks and actor.health.current > 0:
			var next_index: int = (actor.patrol.index + 1) % actor.patrol.route.size()
			var target: Array = actor.patrol.route[next_index]
			# Configured patrol moves at most one adjacent step per committed turn.
			var path: Array = Traversal.path(candidate, actor_id, target, 1)
			if path.is_empty(): continue
			var movement := {"type": "actor_move", "actor_id": actor_id, "scene_id": actor.scene_id, "hex": target.duplicate()}
			var moved: Dictionary = World.apply(candidate, movement, true)
			if not moved.ok: return moved
			patches.append(movement)
			var advance := {"type": "patrol_advance", "actor_id": actor_id, "index": next_index}
			var advanced: Dictionary = World.apply(candidate, advance, true)
			if not advanced.ok: return advanced
			patches.append(advance)
	var status_hooks: Dictionary = StatusFoundation.freeze(before, candidate, acting_actor_id)
	if not status_hooks.ok: return status_hooks
	patches.append_array(status_hooks.patches)
	var landing_check:Dictionary=preload("res://core/status_gameplay/movement.gd").validate_after_turn(before,candidate)
	if not landing_check.ok:return landing_check
	var phase_hooks: Dictionary = BasicEffects.finish_turn_hooks(candidate)
	if not phase_hooks.ok: return phase_hooks
	patches.append_array(phase_hooks.patches)
	return {"ok": true, "patches": patches}
