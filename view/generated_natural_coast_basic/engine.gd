extends "res://core/ai_gm_rebuilt/engine.gd"
## Only public projection seams differ. All transaction, RNG, stage, commit and save code is inherited.
const CoastProjection = preload("res://view/generated_natural_coast_basic/projection.gd")
func capability_catalog(actor_id: String = "actor_player", selected_focus: Dictionary = {}) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var admission := {"ok": true}
	if not _state.actors.has(actor_id): admission = C.fail("UNKNOWN_ACTOR", "Unknown stable actor ID.")
	elif _state.actors[actor_id].health.current <= 0: admission = C.fail("ACTOR_DOWNED", "A downed actor cannot begin an intention.")
	elif not StatusFoundation.permits_intent(_state, actor_id): admission = C.fail("STATUS_ACTION_BLOCKED", "A program-validated capability blocks deliberate action.")
	elif not BasicEffects.authorized_actor(_state).is_empty() and BasicEffects.authorized_actor(_state) != actor_id: admission = C.fail("TURN_ACTOR", "The current encounter phase belongs to another actor.")
	elif not _pending.is_empty(): admission = C.fail("ACTION_IN_PROGRESS", "Finish or cancel the existing intention first.")
	elif _calculator == null: admission = C.fail("NOT_CONFIGURED", "No trusted rule calculator is configured.")
	return CapabilityCatalog.build(CoastProjection.facts(_state), _resolver_ids(), _action_schemas(), actor_id, admission, selected_focus)

func attention(reference: Dictionary) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var resolved: Dictionary = _focus.resolve(reference, _state)
	if not resolved.ok: return resolved
	if not Focus.validate_scene_scope(resolved.focus, _state): return C.fail("FOCUS_SCENE", "Attention target is not in the acting actor's active scene.")
	# These exact typed views already carry their strictly resolved public facts.
	# Building the complete model context here was unused by focus_view().
	# Legacy focus retains its original projection, including policy filtering.
	var projected: Dictionary = {}
	if not resolved.focus.get("catalog_version", "") in ["source-npc-focus/v1", "source-vegetation-focus/v1", "source-static-focus/v1", "source-entity-focus/v1"]:
		projected = CoastProjection.facts(_state, resolved.focus)
	return {"ok": true, "focus": ModelView.focus_view(resolved.focus, projected), "readonly": true}

func _context(action: Dictionary) -> Dictionary:
	var projected := CoastProjection.facts(action.snapshot, action.focus)
	return {"facts": projected, "attention_focus": ModelView.focus_view(action.focus, projected), "goal": action.goal, "actor_id": action.actor_id, "text_priority": "explicit_player_text"}

func _validate_assessment(action: Dictionary, reply: Variant) -> Dictionary:
	var fields := ["schema_version", "action_id", "state_version", "context_hash", "narration", "interpretation", "resolver_id", "bindings", "components", "fact_refs", "provenance"]
	if not C.exact_fields(reply, fields) or not C.safe(reply): return C.fail("INVALID_ASSESSMENT", "Assessment requires exact typed fields and finite JSON; code/patch extensions are not accepted.")
	if not reply.schema_version is String or reply.schema_version != ASSESSMENT_SCHEMA or not reply.action_id is String or reply.action_id != action.action_id or not C.integer(reply.state_version) or reply.state_version != action.state_version or reply.state_version != _state.state_version: return C.fail("STALE_ASSESSMENT", "Assessment schema, action or version differs from frozen state.")
	if not reply.context_hash is String or reply.context_hash != action.context_hash or not World.text(reply.narration) or not World.text(reply.interpretation) or not reply.resolver_id is String or not _resolvers.has(reply.resolver_id): return C.fail("INVALID_ASSESSMENT", "Assessment context, narration or registered resolver is invalid.")
	if not reply.bindings is Dictionary or not reply.components is Array or reply.components.is_empty() or reply.components.size() > 4 or not reply.fact_refs is Array or reply.fact_refs.is_empty(): return C.fail("INVALID_ASSESSMENT", "Assessment requires bindings, one to four components and explicit fact references.")
	if reply.bindings.has("actor_id") and (not reply.bindings.actor_id is String or reply.bindings.actor_id != action.actor_id): return C.fail("INVALID_BINDING", "Assessment cannot replace the acting actor from the frozen intent.")
	var phase_check: Dictionary = BasicEffects.validate_phase_assessment(action.snapshot, reply)
	if not phase_check.ok: return phase_check
	if not C.exact_fields(reply.provenance, ["provider", "live", "kind"]) or not World.text(reply.provenance.provider) or not reply.provenance.live is bool or not reply.provenance.kind is String or not reply.provenance.kind in ["fixture", "model_reply"]: return C.fail("INVALID_ASSESSMENT", "Provenance is typed metadata, not proof of a live call.")
	if reply.provenance.kind == "fixture" and not rule_id().begins_with("ai_gm_test_"):
		var authorized_fixture: Variant = false
		if _calculator.has_method("allows_fixture_assessment"):
			authorized_fixture = _calculator.allows_fixture_assessment(action.snapshot.duplicate(true), reply.duplicate(true), action.goal, action.focus.duplicate(true))
		if not authorized_fixture is bool or not authorized_fixture: return C.fail("TEST_ONLY", "Production fixtures require the trusted calculator's exact authored-example validation.")
	var refs: Dictionary = {}; var facts := CoastProjection.facts(action.snapshot, action.focus)
	# A selected catalog descriptor is public context, not an arbitrary private path.
	facts["attention_focus"] = ModelView.focus_view(action.focus, facts)
	for ref in reply.fact_refs:
		if not C.exact_fields(ref, ["id", "path", "expected"]) or not World.text(ref.id) or not ref.path is String or refs.has(ref.id): return C.fail("INVALID_FACT_REF", "Fact references need unique IDs and exact paths.")
		var found: Dictionary = C.pointer(facts, ref.path)
		if not found.ok or C.bytes(found.value) != C.bytes(ref.expected): return C.fail("INVALID_FACT_REF", "Fact reference is forged, private, unknown or differs from frozen facts.")
		refs[ref.id] = true
	var component_ids: Dictionary = {}
	for component in reply.components:
		if not C.exact_fields(component, ["id", "parameters", "disposition", "fact_ref_ids"]) or not World.text(component.id) or component_ids.has(component.id) or not component.parameters is Dictionary or not component.disposition is String or not component.disposition in ["possible", "certain", "impossible"] or not component.fact_ref_ids is Array or component.fact_ref_ids.is_empty(): return C.fail("INVALID_COMPONENT", "Malformed assessed component or stable ID.")
		for value in component.parameters.values():
			if not value is int and not value is float: return C.fail("INVALID_COMPONENT", "Calculator numeric parameters must be numbers, not executable expressions.")
		for id in component.fact_ref_ids:
			if not id is String or not refs.has(id): return C.fail("INVALID_FACT_REF", "Component references an unknown fact ID.")
		component_ids[component.id] = true
	return {"ok": true}

func narration_request(action_id: String) -> Dictionary:
	var summary: Dictionary = authoritative_result(action_id)
	if summary.is_empty(): return {}
	var context: Dictionary = {"authoritative_result": summary}
	if _pending.has(action_id):
		var action: Dictionary = _pending[action_id]
		context.actor_id = action.actor_id; context.goal = action.goal
		context.attention_focus = _context(action).attention_focus
		context.facts_after = CoastProjection.facts(action.staged, action.focus)
		context.provisional_until_commit = true
	else:
		var receipt: Dictionary = _receipts[action_id]
		context.actor_id = receipt.actor_id; context.goal = receipt.goal
		context.attention_focus = ModelView.historical_focus(receipt.attention_focus, _policy)
		context.fact_scope = "historical_recorded_public_effects"
		context.provisional_until_commit = false
	return C.normalized({"schema_version": SCHEMA, "reply_schema": "ai_gm_narration/v1", "phase": "narration", "action_id": action_id, "state_version": summary.state_version,
		"context_hash": C.digest(context), "context": context, "contract": {"text_only": true, "cannot_rejudge": true, "cannot_patch_facts": true, "semantic_truth_not_programmatically_certified": true}})

