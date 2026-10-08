extends "res://core/ai_gm_rebuilt/engine.gd"
## Public projection seams and save-destination protection differ.
## Transactions, RNG, stage, commit, loading and the existing temp-write/rename implementation remain inherited.
const CoastProjection = preload("res://view/generated_natural_coast_basic/projection.gd")
const MAX_DIRECT_SAVE_BYTES := 24 * 1024 * 1024
var _save_world_id := ""
var _save_authority_identity: Dictionary = {}

func _init(initial: Dictionary, calculator: RefCounted = null, resolvers: Dictionary = {}, projection: Dictionary = {}, test_seed: Variant = null) -> void:
	# Keep the exact inherited constructor signature and initialization once.
	super(initial,calculator,resolvers,projection,test_seed)
	if _initial_error.is_empty() and _state.get("generated_world") is Dictionary:
		_save_world_id = String(_state.get("world_id",""))
		_save_authority_identity = _state.get("generated_world",{}).duplicate(true)

func _matches_configured_world(value: Variant) -> bool:
	return value is Dictionary and not _save_world_id.is_empty() and not _save_authority_identity.is_empty() and value.get("world_id") == _save_world_id and value.get("generated_world") is Dictionary and C.bytes(value.generated_world) == C.bytes(_save_authority_identity)

func matches_save_identity(value: Variant) -> bool:
	# Terrain content alone is insufficient: public/native authority code hashes
	# produce different runtime/world identities. Do not reinterpret either one.
	var fields := ["schema_version","state","policy","rng","next_action","pending","receipts","attempt_ledger","rule_id","resolver_ids"]
	if value is Dictionary and value.has("campaign_memory"): fields.append("campaign_memory")
	if not C.exact_fields(value,fields) or not C.safe(value): return false
	if value.schema_version != SCHEMA or value.rule_id != rule_id() or not value.resolver_ids is Array or C.bytes(value.resolver_ids) != C.bytes(_resolver_ids()): return false
	if not value.policy is Dictionary or C.bytes(value.policy) != C.bytes(_policy) or not value.state is Dictionary or not value.state.get("generated_world") is Dictionary: return false
	return _matches_configured_world(value.state)

func save_file(path: String) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	if not _matches_configured_world(_state): return C.fail("V3_SAVE_NAMESPACE","当前世界与此运行版本的原始身份不同，未写入。")
	if path.is_empty(): return C.fail("V3_SAVE_NAMESPACE","请使用此版本的独立文件，旧旅程不会被覆盖。")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: return C.fail("V3_SAVE_NAMESPACE","无法验证已有文件，未覆盖。")
		if file.get_length() > MAX_DIRECT_SAVE_BYTES:
			file.close()
			return C.fail("V3_SAVE_NAMESPACE","无法验证已有文件，未覆盖。")
		var encoded := file.get_as_text(); var read_error: Error = file.get_error(); file.close()
		var parser := JSON.new(); var parsed: Error = parser.parse(encoded)
		# The raw API cannot replace an adapter envelope, even for this identity.
		if read_error not in [OK,ERR_FILE_EOF] or parsed != OK or not matches_save_identity(parser.data): return C.fail("V3_SAVE_NAMESPACE","已有文件不属于此精确运行版本，未覆盖。")
	return super.save_file(path)

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

