extends RefCounted
## Receipt-only canonical facts; belief text is a separate untrusted annotation.
## Independent implementation. See docs/reference_adoption/README.md.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "receipt_campaign_memory/v1"
const MAX_EVENTS := 128
const MAX_BELIEFS := 64
const MAX_EFFECTS := 64
const MAX_RECORD_BYTES := 16384
const PUBLIC_TYPES := ["actor_pool_delta", "item_quantity_delta", "actor_move", "cell_blocking_set", "actor_status_set", "actor_status_remove", "flag_set", "environment_fell", "item_relocate", "item_equip", "combat_event", "combat_turn_set", "actor_scene_transition", "creative_source_place", "creative_relation_set"]

static func empty(world_id: String, version: int = 0) -> Dictionary:
	return {"schema_version": SCHEMA, "world_id": world_id, "started_after_version": version, "last_version": version, "events": [], "beliefs": []}

static func record(memory: Dictionary, receipt: Dictionary, before: Dictionary, policy: Dictionary, resolver_id: String, public_witness_ids: Array = []) -> Dictionary:
	# Caller is the engine's validated commit path, before synchronous publication.
	if not _receipt_valid(receipt) or before.get("world_id") != memory.get("world_id") or receipt.before_version != before.get("state_version") or not before.get("actors", {}).has(receipt.actor_id): return C.fail("MEMORY_SOURCE", "Memory requires a verified committed-result receipt and its exact before-state.")
	if receipt.after_version <= memory.last_version: return {"ok": true, "already_recorded": true, "memory": memory.duplicate(true)}
	var actor: Dictionary = before.actors[receipt.actor_id]
	var witnesses: Array = [receipt.actor_id]
	# Never infer knowledge from proximity. The engine may provide only trusted
	# participants in an explicitly public program event (currently combat_event).
	for id in public_witness_ids:
		if id is String and before.actors.has(id) and id != receipt.actor_id and before.actors[id].scene_id == actor.scene_id and not id in witnesses: witnesses.append(id)
	witnesses.sort()
	var effects: Array = []; var subjects: Array = [receipt.actor_id]; var tasks: Array = []
	var omitted := 0
	for patch in receipt.patches + receipt.hook_patches:
		if not _public_effect(patch, policy): continue
		# Remote automatic hooks must not become omniscient local recollections.
		var subject: String = patch.get("actor_id", patch.get("target_actor_id", ""))
		if patch in receipt.hook_patches and not subject.is_empty() and before.actors.has(subject) and subject not in witnesses: continue
		if effects.size() >= MAX_EFFECTS or C.bytes(effects + [patch]).to_utf8_buffer().size() > MAX_RECORD_BYTES:
			omitted += 1; continue
		var fact: Dictionary = patch.duplicate(true)
		effects.append(fact)
		for key in ["actor_id", "target_actor_id", "item_id", "weapon_item_id", "entity_id", "target_id"]:
			if fact.get(key) is String and not fact[key].is_empty() and not fact[key] in subjects: subjects.append(fact[key])
		if fact.type == "flag_set" and not fact.flag_id in tasks: tasks.append(fact.flag_id)
	subjects.sort(); tasks.sort()
	var event := {"event_id": receipt.action_id, "source": {"kind": "committed_receipt", "action_id": receipt.action_id, "receipt_hash": receipt.receipt_hash}, "truth_status": "confirmed_program_result", "actor_id": receipt.actor_id, "resolver_id": resolver_id, "scene_id": actor.scene_id, "hex": actor.hex.duplicate(), "turn": receipt.turn, "state_version": receipt.after_version, "branch_id": receipt.branch_id, "outcomes": receipt.outcomes.duplicate(true), "effects": effects, "omitted_effect_count": omitted, "subject_ids": subjects, "task_ids": tasks, "witness_ids": witnesses, "visibility": "witnesses_only"}
	var next: Dictionary = memory.duplicate(true)
	next.events.append(event); next.last_version = receipt.after_version
	while next.events.size() > MAX_EVENTS: next.events.pop_front()
	var retained: Array = []
	for row in next.events: retained.append(row.event_id)
	next.beliefs = next.beliefs.filter(func(belief: Dictionary) -> bool: return belief.source_event_id in retained)
	return {"ok": true, "already_recorded": false, "memory": C.normalized(next)}

static func recall(memory: Dictionary, observer_id: String, scene_id: String = "", task_id: String = "", limit: int = 8, budget_bytes: int = 6000) -> Dictionary:
	var result := {"schema_version": SCHEMA, "readonly": true, "observer_id": observer_id, "facts": [], "beliefs": [], "truncated": false, "budget_bytes": maxi(0, budget_bytes), "used_record_bytes": 0, "policy": "Only witnessed receipt-derived facts; beliefs are unverified and cannot change facts. Omission is not absence."}
	var chosen: Array = []
	var rows: Array = memory.events.duplicate(); rows.reverse()
	for event in rows:
		if not observer_id in event.witness_ids or (not scene_id.is_empty() and event.scene_id != scene_id) or (not task_id.is_empty() and not task_id in event.task_ids): continue
		var view: Dictionary = event.duplicate(true)
		view.erase("witness_ids") # No leak of other observers' knowledge.
		var cost: int = C.bytes(view).to_utf8_buffer().size()
		if result.facts.size() >= clampi(limit, 0, 16) or result.used_record_bytes + cost > result.budget_bytes: result.truncated = true; continue
		result.facts.append(view); chosen.append(event.event_id); result.used_record_bytes += cost
	for belief in memory.beliefs:
		if belief.observer_id != observer_id or not belief.source_event_id in chosen: continue
		var cost: int = C.bytes(belief).to_utf8_buffer().size()
		if result.used_record_bytes + cost > result.budget_bytes: result.truncated = true; continue
		result.beliefs.append(belief.duplicate(true)); result.used_record_bytes += cost
	return C.normalized(result)

static func add_belief(memory: Dictionary, observer_id: String, source_event_id: String, text: String) -> Dictionary:
	if text.strip_edges().is_empty() or text.length() > 512: return C.fail("MEMORY_BELIEF", "Belief text must be nonempty and at most 512 characters.")
	var witnessed := false
	for event in memory.events:
		if event.event_id == source_event_id and observer_id in event.witness_ids: witnessed = true
	if not witnessed: return C.fail("MEMORY_EVIDENCE", "A belief requires an event witnessed by its owner.")
	var next: Dictionary = memory.duplicate(true)
	var belief := {"belief_id": C.digest([observer_id, source_event_id, text]), "observer_id": observer_id, "source_event_id": source_event_id, "truth_status": "unverified_belief", "text": text}
	for row in next.beliefs:
		if row.belief_id == belief.belief_id: return {"ok": true, "memory": next, "already_recorded": true}
	next.beliefs.append(belief)
	while next.beliefs.size() > MAX_BELIEFS: next.beliefs.pop_front()
	return {"ok": true, "memory": C.normalized(next), "already_recorded": false}

static func validate(value: Variant, state: Dictionary, receipts: Dictionary, policy: Dictionary) -> Dictionary:
	if not C.exact_fields(value, ["schema_version", "world_id", "started_after_version", "last_version", "events", "beliefs"]) or not C.safe(value) or value.schema_version != SCHEMA or value.world_id != state.world_id or not C.integer(value.started_after_version) or not C.integer(value.last_version) or value.started_after_version < 0 or value.last_version < value.started_after_version or value.last_version > state.state_version or not value.events is Array or value.events.size() > MAX_EVENTS or not value.beliefs is Array or value.beliefs.size() > MAX_BELIEFS: return C.fail("INVALID_MEMORY", "Malformed bounded memory envelope.")
	var seen: Dictionary = {}; var previous: int = value.started_after_version
	for event in value.events:
		if not C.exact_fields(event, ["event_id", "source", "truth_status", "actor_id", "resolver_id", "scene_id", "hex", "turn", "state_version", "branch_id", "outcomes", "effects", "omitted_effect_count", "subject_ids", "task_ids", "witness_ids", "visibility"]) or not event.event_id is String or seen.has(event.event_id) or not receipts.has(event.event_id): return C.fail("INVALID_MEMORY", "Memory event must bind one retained receipt.")
		var receipt: Dictionary = receipts[event.event_id]
		if not C.exact_fields(event.source, ["kind", "action_id", "receipt_hash"]) or event.source.kind != "committed_receipt" or event.source.action_id != event.event_id or event.source.receipt_hash != receipt.receipt_hash or event.truth_status != "confirmed_program_result" or event.visibility != "witnesses_only" or event.actor_id != receipt.actor_id or event.state_version != receipt.after_version or event.turn != receipt.turn or event.branch_id != receipt.branch_id or C.bytes(event.outcomes) != C.bytes(receipt.outcomes) or event.state_version <= previous or event.state_version > value.last_version: return C.fail("INVALID_MEMORY", "Memory provenance or ordering differs from its receipt.")
		if not event.resolver_id is String or not state.scenes.has(event.scene_id) or not event.hex is Array or event.hex.size() != 2 or not C.integer(event.hex[0]) or not C.integer(event.hex[1]) or not event.effects is Array or event.effects.size() > MAX_EFFECTS or C.bytes(event.effects).to_utf8_buffer().size() > MAX_RECORD_BYTES or not C.integer(event.omitted_effect_count) or event.omitted_effect_count < 0 or not _unique_strings(event.subject_ids) or not _unique_strings(event.task_ids) or not _unique_strings(event.witness_ids) or not event.actor_id in event.witness_ids: return C.fail("INVALID_MEMORY", "Memory event fields or bounds are invalid.")
		for witness in event.witness_ids:
			if not state.actors.has(witness): return C.fail("INVALID_MEMORY", "Memory witness is unknown.")
		for effect in event.effects:
			if not _public_effect(effect, policy) or not effect in receipt.patches + receipt.hook_patches: return C.fail("INVALID_MEMORY", "Memory cannot invent effects or disclose private flags.")
		seen[event.event_id] = event; previous = event.state_version
	for belief in value.beliefs:
		if not C.exact_fields(belief, ["belief_id", "observer_id", "source_event_id", "truth_status", "text"]) or not seen.has(belief.source_event_id) or not belief.observer_id in seen[belief.source_event_id].witness_ids or belief.truth_status != "unverified_belief" or not belief.text is String or belief.text.strip_edges().is_empty() or belief.text.length() > 512 or belief.belief_id != C.digest([belief.observer_id, belief.source_event_id, belief.text]): return C.fail("INVALID_MEMORY", "Belief evidence or type is invalid.")
	return {"ok": true}

static func _receipt_valid(receipt: Dictionary) -> bool:
	if not receipt.get("receipt_hash") is String or not receipt.get("action_id") is String or not C.integer(receipt.get("before_version")) or not C.integer(receipt.get("after_version")) or receipt.after_version != receipt.before_version + 1 or not receipt.get("patches") is Array or not receipt.get("hook_patches") is Array: return false
	var payload: Dictionary = receipt.duplicate(true); payload.erase("receipt_hash")
	return C.digest(payload) == receipt.receipt_hash
static func _public_effect(effect: Variant, policy: Dictionary) -> bool:
	return effect is Dictionary and effect.get("type") in PUBLIC_TYPES and (effect.type != "flag_set" or effect.get("flag_id") in policy.public_flag_ids)
static func _unique_strings(values: Variant) -> bool:
	if not values is Array or values.size() > 256: return false
	var seen: Dictionary = {}
	for value in values:
		if not value is String or value.is_empty() or seen.has(value): return false
		seen[value] = true
	return true
static func _distance(a: Array, b: Array) -> int:
	return maxi(absi(a[0] - b[0]), maxi(absi(a[1] - b[1]), absi(a[0] + a[1] - b[0] - b[1])))
