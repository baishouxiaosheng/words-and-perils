extends "res://view/runtime_ai/scoped_engine.gd"
## Complete actor-scoped requests from the admitted frozen v2 authority. Never
## invokes the legacy ModelView or grows/shrinks the public neighborhood.
const ActorSource = preload("res://view/actor_action_profile_v2/source.gd")
const ActorEngine = preload("res://view/actor_action_profile_v2/engine.gd")
const ActorRule = preload("res://view/actor_action_profile_v2/rule.gd")
const PROFILE_BUDGET := 65536
var adapter: RefCounted
var ticket: Dictionary = {}
var decision_id := ""
var receipt_id := ""
var receipt_hash := ""
var receipt_request: Dictionary = {}
var configured_budget: Variant
var clock: Callable

func _init(view: RefCounted, guard: Callable, budget_bytes: Variant = PROFILE_BUDGET, now: Callable = Callable()) -> void:
	adapter = view; configured_budget = budget_bytes
	clock = now
	if not clock.is_valid(): clock = func(): return Time.get_ticks_msec()
	var checked := Budget.validate(budget_bytes)
	super(view.engine, guard, mini(int(budget_bytes), PROFILE_BUDGET) if checked.ok else budget_bytes)

static func recognizes(state: Dictionary) -> bool:
	# Presence, not validity, selects this branch before legacy generated markers.
	return state.has("actor_action_identity") or str(state.get("world_id", "")).begins_with("generated_v3_actor_actions_")

func _admitted() -> bool:
	if not permitted.call() or adapter == null or adapter.engine != engine:
		last_error = C.fail("STALE_CONTEXT", "The admitted adventure changed; no request or reply is used."); return false
	var core: Variant = adapter.get("core")
	if core == null or core.engine != engine or core.source == null:
		last_error = C.fail("ACTOR_RUNTIME_PROFILE", "The new profile requires its admitted authority adapter."); return false
	var state: Dictionary = engine.state_copy()
	if not state.get("actor_action_identity") is Dictionary or state.actor_action_identity.get("schema_version") != ActorSource.PROFILE or state.get("world_id") != ActorSource.PREFIX + C.digest(core.source.identity) or C.bytes(state.actor_action_identity) != C.bytes(core.source.identity) or engine.rule_id() != ActorRule.PROFILE_RULE:
		last_error = C.fail("ACTOR_RUNTIME_PROFILE", "Invalid new-profile marker, rule or source identity; legacy fallback is forbidden."); return false
	var checked: Dictionary = core.source.validate_state(state)
	if not checked.ok: last_error = checked; return false
	return true

func _bounded(full: Dictionary, key: String) -> Dictionary:
	if not C.safe(full) or not ActorEngine.valid_transport_strings(full) or full.get("context_hash") != C.digest(full.get("context", {})):
		last_error = C.fail("ACTOR_PUBLIC_REQUEST", "The complete typed actor public context is required."); return {}
	# Actor v2 does not negotiate public_dictionary: this call only measures and
	# enforces the existing budget. Verify that it did not rewrite the request.
	var result: Dictionary = super._budget(full, full, key)
	last_metrics["configured_budget_bytes"] = configured_budget
	last_metrics["profile_budget_bytes"] = PROFILE_BUDGET
	if not result.is_empty() and C.bytes(result) != C.bytes(full):
		last_error = C.fail("ACTOR_PUBLIC_REQUEST", "This profile sends its exact public request without transforms."); return {}
	return result

func begin_intention(ttl_ms: int) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	var slot: Dictionary = adapter.core.scheduler.next_slot()
	if not slot.get("ok", false): return slot
	if not slot.needs_intent or slot.actor_id == "actor_player": return C.fail("INTENTION_PHASE", "Only the authoritative non-player slot may request an automatic proposal.")
	var grant: Dictionary = adapter.core.decision.grant
	var issued: Dictionary = {"ok": true, "request": grant.duplicate(true)} if not grant.is_empty() else adapter.decision_request(int(clock.call()), ttl_ms)
	if not issued.ok: return issued
	decision_id = issued.request.proposal_id
	var request := intention_request(decision_id)
	return {"ok": true, "request": request} if not request.is_empty() else last_error.duplicate(true)

func intention_request(id: String) -> Dictionary:
	if not _admitted() or id != decision_id or id.is_empty(): return {}
	var grant: Dictionary = adapter.core.decision.grant
	if grant.is_empty() or grant.get("proposal_id") != id: return {}
	if int(grant.expires_ms) >= 0 and int(clock.call()) >= int(grant.expires_ms):
		last_error = C.fail("DECISION_EXPIRED", "The proposal expired; the actor slot and numerical state are unchanged."); return {}
	var slot: Dictionary = adapter.core.scheduler.next_slot()
	if not slot.get("ok", false) or not slot.needs_intent or slot.actor_id != grant.actor_id or engine.state_copy().state_version != grant.state_version: return {}
	if grant.get("schema_version") != "actor_intent_proposal/v1" or grant.context.facts.get("context_scope", {}).get("observer_id") != grant.actor_id:
		last_error = C.fail("ACTOR_PUBLIC_REQUEST", "Proposal facts must belong to the actual actor."); return {}
	return _bounded(grant.duplicate(true), id + ":intention")

func accept_intention(reply: Variant) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	if not C.safe(reply) or not ActorEngine.valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size() > PROFILE_BUDGET: return C.fail("DECISION_BUDGET", "Proposal exceeds bounded typed text.")
	return adapter.accept_decision(reply, int(clock.call()))

func begin_assessment(ttl_ms: int) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	var issued: Dictionary = adapter.issue_assessment_ticket(int(clock.call()), ttl_ms)
	if not issued.ok: return issued
	ticket = issued.ticket.duplicate(true)
	var request := model_request(ticket.action_id)
	return {"ok": true, "request": request} if not request.is_empty() else last_error.duplicate(true)

func model_request(id: String) -> Dictionary:
	if not _admitted() or ticket.is_empty() or ticket.get("action_id") != id: return {}
	var request: Dictionary = engine.model_request(id)
	if request.is_empty(): return {}
	if request.get("schema_version") != "ai_gm_rebuilt/v1" or request.get("phase") != "assessment" or request.context.get("actor_id") != ticket.actor_id or request.context.facts.get("context_scope", {}).get("observer_id") != ticket.actor_id or request.context_hash != ticket.context_hash or request.state_version != ticket.state_version:
		last_error = C.fail("ACTOR_PUBLIC_REQUEST", "Assessment must retain the exact actor, snapshot and scheduler ticket."); return {}
	return _bounded(request, id)

func prepare_assessment(reply: Variant) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	# The scheduler consumes its exact action/epoch ticket; Engine remains the
	# only typed assessment validator, and no roll/stage/commit is done here.
	return adapter.accept_assessment(reply, ticket, int(clock.call()))

func bind_receipt(id: String) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	var hash_: String = engine.committed_receipt_hash(id)
	var request: Dictionary = engine.narration_request(id)
	if hash_.is_empty() or request.is_empty() or request.context.get("provisional_until_commit", true): return C.fail("NARRATION_NOT_COMMITTED", "Optional prose requires an actual committed receipt.")
	receipt_id = id; receipt_hash = hash_; receipt_request = request.duplicate(true)
	var bounded := narration_request(id)
	return {"ok": true, "request": bounded} if not bounded.is_empty() else last_error.duplicate(true)

func narration_request(id: String) -> Dictionary:
	if not _admitted() or id != receipt_id or receipt_hash.is_empty() or engine.committed_receipt_hash(id) != receipt_hash: return {}
	var current: Dictionary = engine.narration_request(id)
	if C.bytes(current) != C.bytes(receipt_request): return {}
	return _bounded(receipt_request.duplicate(true), id + ":narration")

func validate_narration_reply(reply: Variant) -> Dictionary:
	if not _admitted(): return last_error.duplicate(true)
	if narration_request(receipt_id).is_empty(): return C.fail("STALE_NARRATION", "The immutable committed receipt or public narration context changed.")
	var checked: Dictionary = engine.validate_narration_reply(reply)
	if checked.get("ok", false) and str(checked.narration).to_utf8_buffer().size() > 8192: return C.fail("NARRATION_TEXT", "Optional prose must fit the existing 8 KiB display sidecar limit.")
	return checked
