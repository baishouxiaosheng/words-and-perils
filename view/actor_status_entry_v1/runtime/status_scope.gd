extends "res://view/actor_action_entry/runtime/actor_scope.gd"
## Exact status admission, reusing the original single-owner ticket/budget logic.
const StatusSource = preload("res://view/actor_status_profile_v1/source.gd")
const StatusRule = preload("res://view/actor_status_profile_v1/rule.gd")
const StatusCore = preload("res://view/actor_status_profile_v1/adapter.gd")
const PROPOSAL = "actor_status_intent_proposal/v1"

static func recognizes_status(state: Dictionary) -> bool:
	var marker: Variant = state.get("actor_action_identity")
	return (marker is Dictionary and marker.get("schema_version") == StatusSource.PROFILE) or str(state.get("world_id", "")).begins_with(StatusSource.PREFIX) or state.has("actor_status_domain")

func _admitted() -> bool:
	if not permitted.call() or adapter == null or adapter.engine != engine:
		last_error = C.fail("STALE_CONTEXT", "The admitted adventure changed; no request or reply is used."); return false
	var core: Variant = adapter.get("core")
	if core == null or core.engine != engine or core.source == null or adapter.profile_id() != StatusSource.PROFILE or adapter.default_save_path().get_file() != "actor_status_v1.json":
		last_error = C.fail("ACTOR_RUNTIME_PROFILE", "Status traffic requires its admitted facade and independent save namespace."); return false
	var state: Dictionary = engine.state_copy()
	if not state.get("actor_action_identity") is Dictionary or state.actor_action_identity.get("schema_version") != StatusSource.PROFILE or state.get("world_id") != StatusSource.PREFIX + C.digest(core.source.identity) or C.bytes(state.actor_action_identity) != C.bytes(core.source.identity) or engine.rule_id() != StatusRule.PROFILE_RULE:
		last_error = C.fail("ACTOR_RUNTIME_PROFILE", "Invalid status marker, rule or source identity; fallback is forbidden."); return false
	if core.get_script() != StatusCore or core.source.get_script() != StatusSource:
		last_error = C.fail("ACTOR_RUNTIME_PROFILE", "Status authority or registered profile resources changed."); return false
	var checked: Dictionary = core.source.validate_state(state)
	if not checked.get("ok", false): last_error = checked; return false
	return true

func intention_request(id: String) -> Dictionary:
	if not _admitted() or id != decision_id or id.is_empty(): return {}
	var grant: Dictionary = adapter.core.decision.grant
	if grant.is_empty() or grant.get("proposal_id") != id: return {}
	if int(grant.expires_ms) >= 0 and int(clock.call()) >= int(grant.expires_ms):
		last_error = C.fail("DECISION_EXPIRED", "The proposal expired without changing the actor slot or state."); return {}
	var slot: Dictionary = adapter.core.scheduler.next_slot()
	if not slot.get("ok", false) or not slot.needs_intent or slot.actor_id != grant.actor_id or engine.state_copy().state_version != grant.state_version: return {}
	if grant.get("schema_version") != PROPOSAL or grant.context.facts.get("actor_action_identity", {}).get("schema_version") != StatusSource.PROFILE or grant.context.facts.get("context_scope", {}).get("observer_id") != grant.actor_id:
		last_error = C.fail("ACTOR_PUBLIC_REQUEST", "Status proposal facts must belong to this exact profile and actual actor."); return {}
	return _bounded(grant.duplicate(true), id + ":intention")
