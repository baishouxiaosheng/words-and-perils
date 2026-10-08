extends RefCounted
const StatusFoundation = preload("res://core/status_foundation/engine_bridge.gd")
## Isolated experimental transaction core; no API client and no production rule.
const NPCState = preload("res://core/source_npc/state.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const CreativeControl = preload("res://core/ai_gm_rebuilt/creative_control.gd")
const Focus = preload("res://core/focus_contract.gd")
const CapabilityCatalog = preload("res://core/capability_catalog/catalog.gd")
const CampaignMemory = preload("res://core/campaign_memory/journal.gd")
const SCHEMA := "ai_gm_rebuilt/v1"
const RETRY_HISTORY := "material_attempt_history/v1"
const MAX_RETRY_HISTORY := 256
const ASSESSMENT_SCHEMA := "ai_gm_assessment/v1"
var _state: Dictionary = {}
var _campaign_memory: Dictionary = {}
var _pending: Dictionary = {}
var _receipts: Dictionary = {}
var _attempt_ledger: Dictionary = {}
var _policy: Dictionary = {}
var _next_action := 1
var _calculator: RefCounted
var _configured_rule_id := "NOT_CONFIGURED"
var _resolvers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rng_mode := "runtime_random"
var _focus := Focus.new()
var _initial_error: Dictionary = {}

func _init(initial: Dictionary, calculator: RefCounted = null, resolvers: Dictionary = {}, projection: Dictionary = {}, test_seed: Variant = null) -> void:
	var checked: Dictionary = World.validate(initial)
	if not checked.ok: _initial_error = checked; return
	_state = C.normalized(initial)
	_campaign_memory = CampaignMemory.empty(_state.world_id, int(_state.state_version))
	_policy = projection.duplicate(true) if not projection.is_empty() else {"npc_secret_allowlist": [], "public_flag_ids": []}
	checked = ModelView.validate_policy(_state, _policy)
	if not checked.ok: _initial_error = checked; return
	_calculator = calculator
	_resolvers = resolvers.duplicate()
	for id in _resolvers:
		var resolver: Variant = _resolvers[id]
		if not id is String or not resolver is RefCounted or not resolver.has_method("resolver_id") or not resolver.has_method("freeze") or not resolver.has_method("attempt_key") or not resolver.has_method("attempt_fingerprint"):
			_initial_error = C.fail("INVALID_REGISTRY", "Resolvers must be trusted pre-registered objects with stable IDs."); return
		var provided_id: Variant = resolver.resolver_id()
		if not provided_id is String or provided_id != id:
			_initial_error = C.fail("INVALID_REGISTRY", "Resolver returned an invalid stable ID."); return
	if _calculator != null and (not _calculator.has_method("rule_id") or not _calculator.has_method("calculate")):
		_initial_error = C.fail("INVALID_CALCULATOR", "Calculator must be a trusted registered plugin."); return
	if _calculator != null:
		var provided_rule_id: Variant = _calculator.rule_id()
		if not provided_rule_id is String or not World.text(provided_rule_id):
			_initial_error = C.fail("INVALID_CALCULATOR", "Calculator returned an invalid stable ID."); return
		_configured_rule_id = provided_rule_id
	_rng.randomize()
	if test_seed != null:
		if _calculator == null or not _configured_rule_id.begins_with("ai_gm_test_") or not C.integer(test_seed):
			_initial_error = C.fail("TEST_ONLY", "A deterministic seed requires an explicitly injected test-only rule."); return
		_rng.seed = int(test_seed); _rng_mode = "test_seed"

func state_copy() -> Dictionary: return _state.duplicate(true)
func committed_receipt_hash(action_id: String) -> String: return String(_receipts.get(action_id, {}).get("receipt_hash", ""))
func action_copy(action_id: String) -> Dictionary: return _pending.get(action_id, {}).duplicate(true)
func rule_id() -> String: return _configured_rule_id
func supports_resolver(resolver_id: String) -> bool: return _resolvers.has(resolver_id)
func ready() -> Dictionary: return {"ok": true} if _initial_error.is_empty() else _initial_error.duplicate(true)

func capability_catalog(actor_id: String = "actor_player", selected_focus: Dictionary = {}) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var admission := {"ok": true}
	if not _state.actors.has(actor_id): admission = C.fail("UNKNOWN_ACTOR", "Unknown stable actor ID.")
	elif _state.actors[actor_id].health.current <= 0: admission = C.fail("ACTOR_DOWNED", "A downed actor cannot begin an intention.")
	elif not StatusFoundation.permits_intent(_state, actor_id): admission = C.fail("STATUS_ACTION_BLOCKED", "A program-validated capability blocks deliberate action.")
	elif not BasicEffects.authorized_actor(_state).is_empty() and BasicEffects.authorized_actor(_state) != actor_id: admission = C.fail("TURN_ACTOR", "The current encounter phase belongs to another actor.")
	elif not _pending.is_empty(): admission = C.fail("ACTION_IN_PROGRESS", "Finish or cancel the existing intention first.")
	elif _calculator == null: admission = C.fail("NOT_CONFIGURED", "No trusted rule calculator is configured.")
	return CapabilityCatalog.build(ModelView.facts(_state, _policy), _resolver_ids(), _action_schemas(), actor_id, admission, selected_focus)

func query_capability(assessment: Variant) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	# Same trusted validation and retry rules as preparation, isolated from live state.
	# No roll, stage, or commit is invoked. Schemas are not a second rules engine.
	var probe = get_script().new(_state, _calculator, _resolvers, _policy)
	if not probe.ready().ok: return probe.ready()
	probe._pending = _pending.duplicate(true); probe._receipts = _receipts.duplicate(true)
	probe._attempt_ledger = _attempt_ledger.duplicate(true)
	probe._rng.seed = _rng.seed; probe._rng.state = _rng.state; probe._rng_mode = _rng_mode
	var checked: Dictionary = probe.prepare_assessment(assessment)
	return {"ok": true, "readonly": true, "available": bool(checked.get("ok", false)), "availability_scope": "validated_supplied_assessment", "resolver_id": assessment.get("resolver_id", "") if assessment is Dictionary else "", "reason_code": "AVAILABLE" if checked.get("ok", false) else checked.get("code", "UNAVAILABLE"), "reasons": checked.get("errors", []), "roll_or_execution_performed": false}

func memory_context(observer_id: String = "actor_player", scene_id: String = "", task_id: String = "", limit: int = 8, budget_bytes: int = 6000) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	return CampaignMemory.recall(_campaign_memory, observer_id, scene_id, task_id, limit, budget_bytes)

static func _public_receipt_witnesses(receipt: Dictionary) -> Array:
	var witnesses: Array = []
	for effect in receipt.patches:
		# An actual targeted combat result is a trusted visible interaction. Generic
		# nearby NPCs, model dialogue, private flags and narrative claims grant none.
		if effect.get("type") == "combat_event" and effect.get("actor_id") == receipt.actor_id and effect.get("target_actor_id") is String and not effect.target_actor_id in witnesses: witnesses.append(effect.target_actor_id)
	return witnesses

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
		projected = ModelView.facts(_state, _policy, resolved.focus)
	return {"ok": true, "focus": ModelView.focus_view(resolved.focus, projected), "readonly": true}

func begin_intent(goal: String, attention_reference: Dictionary = {}, actor_id: String = "actor_player") -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	if goal.strip_edges().is_empty(): return C.fail("NEEDS_INTENT", "Attention is context only; write an explicit intended action.")
	if not _state.actors.has(actor_id): return C.fail("UNKNOWN_ACTOR", "Unknown stable actor ID.")
	if not StatusFoundation.permits_intent(_state, actor_id): return C.fail("STATUS_ACTION_BLOCKED", "A program-validated capability blocks deliberate action.")
	var phase_actor: String = BasicEffects.authorized_actor(_state)
	if not phase_actor.is_empty() and phase_actor != actor_id: return C.fail("TURN_ACTOR", "The authoritative encounter phase belongs to another actor.")
	if _state.actors[actor_id].health.current <= 0: return C.fail("ACTOR_DOWNED", "A downed actor cannot begin a new intention; recovery gameplay is not installed.")
	if not _pending.is_empty(): return C.fail("ACTION_IN_PROGRESS", "Finish the existing action before starting another.")
	var resolved: Dictionary = _focus.resolve(attention_reference, _state)
	if not resolved.ok: return resolved
	if not Focus.validate_scene_scope(resolved.focus, _state, actor_id): return C.fail("FOCUS_SCENE", "Attention target is not in the acting actor's active scene.")
	var id := "%s:action_%d" % [_state.world_id, _next_action]
	var action := {"action_id": id, "actor_id": actor_id, "goal": goal, "snapshot": _state.duplicate(true), "focus": resolved.focus.duplicate(true), "state_version": _state.state_version,
		"status": "awaiting_assessment", "context_hash": "", "assessment": {}, "checks": [], "branches": [], "plan_hash": "", "attempt_key": "", "attempt_fingerprint": "",
		"rng_before": {"seed": str(_rng.seed), "state": str(_rng.state)}, "rolls": [], "outcomes": {}, "roll_hash": "", "staged": {}, "stage_hash": ""}
	action.context_hash = C.digest(_context(action))
	_pending[id] = action; _next_action += 1
	return {"ok": true, "request": model_request(id)}

func _context(action: Dictionary) -> Dictionary:
	var projected := ModelView.facts(action.snapshot, _policy, action.focus)
	return {"facts": projected, "attention_focus": ModelView.focus_view(action.focus, projected), "goal": action.goal, "actor_id": action.actor_id, "text_priority": "explicit_player_text"}

func model_request(action_id: String) -> Dictionary:
	if not _pending.has(action_id): return {}
	var action: Dictionary = _pending[action_id]
	var result := {"schema_version": SCHEMA, "action_id": action_id, "state_version": action.state_version, "phase": "assessment", "context_hash": action.context_hash,
		"context": _context(action), "contract": {"assessment_schema": ASSESSMENT_SCHEMA, "assessment_required_for_every_intent": true, "attention_is_action": false, "narration_is_facts": false,
		"calculator": rule_id(), "rule_schema": _rule_schema(), "resolver_ids": _resolver_ids(), "action_schemas": _action_schemas(), "model_reply_is_data_only": true}}
	if _resolvers.has("coast_creative_obstruction_v1") and action.snapshot.has("physical_catalog"):
		result.contract["control_reply"] = CreativeControl.contract()
		result.contract["assessment_reply"] = CreativeControl.assessment_contract()
	# Outside the historical frozen context: existing pending hashes remain exact.
	result["memory_context"] = memory_context(action.actor_id, "", "", 6, 4096)
	if action.snapshot.has("status_foundation"):
		result["status_context"] = StatusFoundation.compact_context(action.snapshot, action.actor_id)
	return C.normalized(result)

func _rule_schema() -> Dictionary:
	if _calculator == null or not _calculator.has_method("rule_schema"): return {}
	var schema: Variant = _calculator.rule_schema()
	return C.normalized(schema) if schema is Dictionary and C.safe(schema) and schema.get("schema_version") == rule_id() else {}

func _action_schemas() -> Dictionary:
	# Trusted versioned resolvers may publish bounded declarative contracts only.
	# Kept outside frozen facts so old pending context hashes remain reproducible.
	var result: Dictionary = {}
	for id in _resolver_ids():
		if _resolvers[id].has_method("action_schema"):
			var schema: Variant = _resolvers[id].action_schema()
			if schema is Dictionary and C.safe(schema) and schema.get("resolver_id") == id:
				result[id] = C.normalized(schema)
	return result

func _resolver_ids() -> Array:
	var ids: Array = _resolvers.keys(); ids.sort(); return ids

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
	var refs: Dictionary = {}; var facts := ModelView.facts(action.snapshot, _policy, action.focus)
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

func prepare_assessment(reply: Variant) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	if not reply is Dictionary or not _pending.has(reply.get("action_id")): return C.fail("UNKNOWN_ACTION", "Unknown assessed action.")
	var action: Dictionary = _pending[reply.action_id]
	if action.status != "awaiting_assessment": return C.fail("FROZEN_PLAN", "Assessment has already been frozen for this action.")
	if _calculator == null: return C.fail("NOT_CONFIGURED", "No production calculator is configured; no ruling or roll has been made.")
	if reply.get("schema_version") is String and reply.schema_version == CreativeControl.SCHEMA: return CreativeControl.validate(model_request(action.action_id),reply)
	var checked: Dictionary = _validate_assessment(action, reply)
	if not checked.ok: return checked
	var calculated: Variant = _calculator.calculate(action.snapshot.duplicate(true), C.normalized(reply))
	if not calculated is Dictionary or not calculated.get("ok") is bool: return C.fail("INVALID_CALCULATION", "Calculator must return a typed result object.")
	if not calculated.ok: return calculated
	checked = _validate_checks(reply, calculated)
	if not checked.ok: return checked
	var resolver: RefCounted = _resolvers[reply.resolver_id]
	var frozen: Variant = resolver.freeze(action.snapshot.duplicate(true), C.normalized(reply))
	if not frozen is Dictionary or not frozen.get("ok") is bool: return C.fail("INVALID_PLAN", "Resolver must return a typed result object.")
	if not frozen.ok: return frozen
	if not frozen.get("resolver_id") is String or frozen.resolver_id != reply.resolver_id: return C.fail("INVALID_PLAN", "Resolver cannot substitute a different registered consequence contract.")
	checked = _freeze_branches(action.snapshot, calculated.checks, frozen, action.actor_id)
	if not checked.ok: return checked
	var attempt_key: Variant = resolver.attempt_key(action.snapshot.duplicate(true), C.normalized(reply))
	var fingerprint: Variant = resolver.attempt_fingerprint(action.snapshot.duplicate(true), C.normalized(reply))
	if not World.text(attempt_key) or not C.safe(fingerprint): return C.fail("INVALID_ATTEMPT", "Trusted resolver must provide a stable semantic key and real-fact fingerprint.")
	var ledger_key: String = C.digest([action.actor_id, reply.resolver_id, attempt_key])
	# Opt-in versioned contracts may recognize unresolved legacy attempts without
	# relabeling old opaque hashes. Old resolver/pending contracts never call this.
	if resolver.has_method("legacy_failure_keys"):
		var old_keys: Variant = resolver.legacy_failure_keys(action.snapshot.duplicate(true), C.normalized(reply))
		if not old_keys is Array or not C.safe(old_keys): return C.fail("INVALID_ATTEMPT", "Trusted resolver returned invalid legacy attempt identities.")
		for old_key in old_keys:
			if not World.text(old_key): return C.fail("INVALID_ATTEMPT", "Legacy attempt identity must be a stable key.")
			if not _attempt_ledger.has(old_key): continue
			var old_receipt: Dictionary = _receipts.get(_attempt_ledger[old_key].action_id, {})
			if false in old_receipt.get("outcomes", {}).values():
				return C.fail("RETRY_HISTORY_INCOMPATIBLE", "这个目标与做法曾在旧规则下失败，旧记录不足以安全重判这一次尝试。其他行动不受影响；可保留存档在对应旧版本继续，或另开新游戏。")
	var fingerprint_hash := C.digest(fingerprint)
	var history_mode: bool = resolver.has_method("retry_history_version") and resolver.retry_history_version() == RETRY_HISTORY
	var prior: Dictionary = _attempt_ledger.get(ledger_key,{})
	if history_mode:
		if not prior.is_empty() and (prior.get("schema_version") != RETRY_HISTORY or prior.get("resolver_id") != reply.resolver_id): return C.fail("RETRY_HISTORY_INCOMPATIBLE", "This creative attempt has an incompatible retained history.")
		if fingerprint_hash in prior.get("fingerprints",[]): return C.fail("REPEAT_ATTEMPT", "This physical arrangement was already attempted in the unresolved episode, including the attempt's own resulting arrangement.")
		# Reserve both original and post-hook baselines before any dice. Fail closed;
		# never evict old arrangements to buy a repeat after A -> B -> A.
		if reply.bindings.get("operation") == "place_obstruction" and _retry_history_count(_attempt_ledger) + 2 > MAX_RETRY_HISTORY: return C.fail("RETRY_HISTORY_CAPACITY", "The bounded unresolved creative-attempt history is full; no roll or cost.")
	elif not prior.is_empty() and prior.get("fingerprint", "") == fingerprint_hash: return C.fail("REPEAT_ATTEMPT", "Equivalent wording cannot reroll unchanged relevant conditions.")
	var candidate: Dictionary = action.duplicate(true)
	candidate.assessment = C.normalized(reply)
	candidate.checks = checked.checks
	candidate.branches = checked.branches
	candidate.attempt_key = ledger_key; candidate.attempt_fingerprint = fingerprint_hash
	candidate.plan_hash = C.digest({"rule_id": rule_id(), "assessment": candidate.assessment, "checks": candidate.checks, "branches": candidate.branches, "attempt_key": ledger_key, "attempt_fingerprint": fingerprint_hash})
	candidate.status = "ready_roll"
	_pending[action.action_id] = candidate
	return {"ok": true, "status": candidate.status, "plan_hash": candidate.plan_hash, "checks": candidate.checks.duplicate(true), "test_only_rule": rule_id().begins_with("ai_gm_test_")}

func _validate_checks(reply: Dictionary, result: Dictionary) -> Dictionary:
	if not C.exact_fields(result, ["ok", "rule_id", "checks"]) or not C.safe(result) or not result.rule_id is String or result.rule_id != rule_id() or not result.checks is Array or result.checks.size() != reply.components.size(): return C.fail("INVALID_CALCULATION", "Calculator output schema or component count differs.")
	var expected: Dictionary = {}
	for component in reply.components: expected[component.id] = true
	for check in result.checks:
		if not C.exact_fields(check, ["id", "method", "roll_min", "roll_max", "success_at_most", "explanation", "derived_facts"]) or not expected.has(check.id) or not check.method is String or not check.method in ["random", "direct_success", "direct_failure"] or not check.explanation is String or not check.derived_facts is Dictionary: return C.fail("INVALID_CALCULATION", "Unknown or malformed calculated check.")
		expected.erase(check.id)
		for field in ["roll_min", "roll_max", "success_at_most"]:
			if not C.integer(check[field]): return C.fail("INVALID_CALCULATION", "Roll domains and thresholds must be exact integers.")
		if check.method == "random" and (check.roll_min < 0 or check.roll_max < check.roll_min or check.roll_max > 1000000000 or check.success_at_most < check.roll_min - 1 or check.success_at_most > check.roll_max): return C.fail("INVALID_CALCULATION", "Random check has invalid domain or threshold.")
		if check.method != "random" and (check.roll_min != 0 or check.roll_max != 0 or check.success_at_most != 0): return C.fail("INVALID_CALCULATION", "Direct outcomes must not manufacture a die.")
	return {"ok": true}

func _freeze_branches(snapshot: Dictionary, checks_input: Array, plan: Dictionary, acting_actor_id: String = "") -> Dictionary:
	if not C.exact_fields(plan, ["ok", "resolver_id", "branches"]) or not C.safe(plan) or not _resolvers.has(plan.resolver_id) or not plan.branches is Array or plan.branches.is_empty() or plan.branches.size() > 16: return C.fail("INVALID_PLAN", "Registered resolver must return bounded typed candidate branches.")
	var checks: Array = C.normalized(checks_input)
	checks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	var ids: Dictionary = {}; var branch_ids: Dictionary = {}; var branches: Array = []
	for check in checks: ids[check.id] = true
	for branch in plan.branches:
		if not C.exact_fields(branch, ["id", "requires", "patches"]) or not World.text(branch.id) or branch_ids.has(branch.id) or not branch.requires is Dictionary or not branch.patches is Array: return C.fail("INVALID_PLAN", "Candidate branch schema or stable ID is invalid.")
		for id in branch.requires:
			if not ids.has(id) or not branch.requires[id] is bool: return C.fail("INVALID_PLAN", "Branch predicates may only test known component booleans.")
		var candidate: Dictionary = snapshot.duplicate(true)
		for patch in branch.patches:
			var applied: Dictionary = World.apply(candidate, patch)
			if not applied.ok: return applied
		var hooks: Dictionary = Hooks.freeze(snapshot, candidate, acting_actor_id)
		if not hooks.ok: return hooks
		var valid: Dictionary = World.validate(candidate)
		if not valid.ok or not World.stable(snapshot, candidate): return C.fail("INVALID_PLAN", "A candidate branch violates full world/stable-ID integrity.")
		branches.append({"id": branch.id, "requires": C.normalized(branch.requires), "patches": C.normalized(branch.patches), "hook_patches": C.normalized(hooks.patches), "candidate_hash": C.digest(candidate)})
		branch_ids[branch.id] = true
	branches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for mask in range(1 << checks.size()):
		var outcomes: Dictionary = {}
		for i in range(checks.size()): outcomes[checks[i].id] = bool(mask & (1 << i))
		if _matching(branches, outcomes).size() != 1: return C.fail("INVALID_PLAN", "Candidate branches must cover each compound outcome exactly once.")
	return {"ok": true, "checks": checks, "branches": branches}

static func _matching(branches: Array, outcomes: Dictionary) -> Array:
	var found: Array = []
	for branch in branches:
		var matches := true
		for id in branch.requires:
			if not outcomes.has(id) or outcomes[id] != branch.requires[id]: matches = false; break
		if matches: found.append(branch)
	return found

func roll_once(action_id: String) -> Dictionary:
	if not _pending.has(action_id): return C.fail("UNKNOWN_ACTION", "Unknown pending action.")
	var action: Dictionary = _pending[action_id]
	if action.state_version != _state.state_version: return C.fail("STALE_ACTION", "Action was prepared against an older state version.")
	if action.status in ["rolled", "staged"]: return {"ok": true, "already_rolled": true, "rolls": action.rolls.duplicate(true), "outcomes": action.outcomes.duplicate(true)}
	if action.status != "ready_roll": return C.fail("ASSESSMENT_REQUIRED", "Every intent requires a validated assessment and frozen consequence plan before a roll.")
	if str(_rng.seed) != action.rng_before.seed or str(_rng.state) != action.rng_before.state: return C.fail("RNG_CONFLICT", "RNG changed outside the frozen action lineage.")
	var rolls: Array = []; var outcomes: Dictionary = {}
	for check in action.checks:
		if check.method == "random":
			var value: int = _rng.randi_range(check.roll_min, check.roll_max)
			rolls.append({"component_id": check.id, "value": value, "source": "program_rng", "test_seeded": _rng_mode == "test_seed"})
			outcomes[check.id] = value <= check.success_at_most
		else: outcomes[check.id] = check.method == "direct_success"
	action.rolls = rolls; action.outcomes = outcomes
	action.roll_hash = C.digest({"action_id": action_id, "plan_hash": action.plan_hash, "rolls": rolls, "outcomes": outcomes})
	action.status = "rolled"
	return {"ok": true, "already_rolled": false, "rolls": rolls.duplicate(true), "outcomes": outcomes.duplicate(true)}

func _candidate(action: Dictionary) -> Dictionary:
	var found: Array = _matching(action.branches, action.outcomes)
	if found.size() != 1: return C.fail("INVALID_OUTCOME", "No unique frozen consequence branch exists.")
	var branch: Dictionary = found[0]; var candidate: Dictionary = action.snapshot.duplicate(true)
	for patch in branch.patches:
		var applied: Dictionary = World.apply(candidate, patch)
		if not applied.ok: return applied
	for patch in branch.hook_patches:
		var applied: Dictionary = World.apply(candidate, patch, true)
		if not applied.ok: return applied
	if C.digest(candidate) != branch.candidate_hash: return C.fail("PLAN_CONFLICT", "Selected candidate differs from its pre-roll frozen patches.")
	candidate.state_version += 1; candidate.turn += 1
	var checked: Dictionary = World.validate(candidate)
	if not checked.ok or not World.stable(action.snapshot, candidate): return C.fail("INVALID_STAGE", "Staged state violates world integrity.")
	return {"ok": true, "state": C.normalized(candidate), "branch": branch}

func stage(action_id: String) -> Dictionary:
	if not _pending.has(action_id): return C.fail("UNKNOWN_ACTION", "Unknown pending action.")
	var action: Dictionary = _pending[action_id]
	if action.status == "staged": return {"ok": true, "already_staged": true, "stage_hash": action.stage_hash}
	if action.status != "rolled" or action.state_version != _state.state_version or C.digest(action.snapshot) != C.digest(_state): return C.fail("INVALID_STAGE", "Stage requires the current frozen action's one-time outcome.")
	var candidate: Dictionary = _candidate(action)
	if not candidate.ok: return candidate
	action.staged = candidate.state
	action.stage_hash = C.digest({"action_id": action_id, "plan_hash": action.plan_hash, "roll_hash": action.roll_hash, "state": action.staged})
	action.status = "staged"
	return {"ok": true, "already_staged": false, "stage_hash": action.stage_hash, "branch_id": candidate.branch.id}

func commit(action_id: String, stage_hash: String) -> Dictionary:
	if _receipts.has(action_id):
		var previous: Dictionary = _receipts[action_id]
		if previous.stage_hash != stage_hash: return C.fail("COMMIT_CONFLICT", "This action was committed with a different frozen token.")
		return {"ok": true, "already_committed": true, "receipt": previous.duplicate(true)}
	if not _pending.has(action_id): return C.fail("UNKNOWN_ACTION", "Unknown pending action.")
	var action: Dictionary = _pending[action_id]
	if action.status != "staged" or action.stage_hash != stage_hash or action.state_version != _state.state_version or C.digest(action.snapshot) != C.digest(_state): return C.fail("COMMIT_CONFLICT", "Commit token or current state differs from the staged transaction.")
	var expected: Dictionary = _candidate(action)
	if not expected.ok: return expected
	var expected_hash := C.digest({"action_id": action_id, "plan_hash": action.plan_hash, "roll_hash": action.roll_hash, "state": expected.state})
	if expected_hash != stage_hash or C.digest(expected.state) != C.digest(action.staged): return C.fail("COMMIT_CONFLICT", "Staged state was changed after validation.")
	var receipt := {"schema_version": SCHEMA, "action_id": action_id, "stage_hash": stage_hash, "before_version": _state.state_version, "after_version": expected.state.state_version,
		"turn": expected.state.turn, "actor_id": action.actor_id, "goal": action.goal, "attention_focus": action.focus.duplicate(true), "rolls": action.rolls.duplicate(true), "plan_hash": action.plan_hash, "roll_hash": action.roll_hash, "branch_id": expected.branch.id, "outcomes": action.outcomes.duplicate(true),
		"patches": expected.branch.patches.duplicate(true), "hook_patches": expected.branch.hook_patches.duplicate(true), "narration": action.assessment.narration, "provenance": action.assessment.provenance.duplicate(true)}
	receipt["receipt_hash"] = C.digest(receipt)
	# Publication is synchronous and performed only after every validation succeeds.
	var next_receipts: Dictionary = _receipts.duplicate(true); next_receipts[action_id] = receipt
	var next_ledger: Dictionary = _attempt_ledger.duplicate(true)
	var retained_fingerprint: String = action.attempt_fingerprint
	var retain_attempt := true
	var resolver: RefCounted = _resolvers[action.assessment.resolver_id]
	if resolver.has_method("retry_commit_policy"):
		# Pure, trusted, opt-in policy over the validated selected post-hook candidate.
		# Do this before publishing any state, ledger or receipt. Model fields cannot
		# request a reset; historical resolvers retain their exact old behavior.
		var retry: Variant = resolver.retry_commit_policy(expected.state.duplicate(true), action.assessment.duplicate(true), action.outcomes.duplicate(true))
		if not retry is Dictionary or not C.safe(retry) or not retry.get("retain") is bool: return C.fail("INVALID_ATTEMPT", "Trusted post-result retry policy is malformed.")
		if retry.retain:
			if not C.exact_fields(retry, ["retain", "fingerprint"]): return C.fail("INVALID_ATTEMPT", "Retained post-result retry policy requires one material fingerprint.")
			retained_fingerprint = C.digest(retry.fingerprint)
		elif not C.exact_fields(retry, ["retain"]): return C.fail("INVALID_ATTEMPT", "Completed retry policy cannot carry an untrusted reset payload.")
		retain_attempt = retry.retain
	if retain_attempt:
		if resolver.has_method("retry_history_version") and resolver.retry_history_version() == RETRY_HISTORY:
			var fingerprints: Array = next_ledger.get(action.attempt_key,{}).get("fingerprints",[]).duplicate()
			for fingerprint in [action.attempt_fingerprint,retained_fingerprint]:
				if not fingerprint in fingerprints: fingerprints.append(fingerprint)
			fingerprints.sort()
			next_ledger[action.attempt_key] = {"schema_version":RETRY_HISTORY,"resolver_id":action.assessment.resolver_id,"fingerprints":fingerprints,"turn":expected.state.turn,"action_id":action_id}
			if _retry_history_count(next_ledger)>MAX_RETRY_HISTORY: return C.fail("RETRY_HISTORY_CAPACITY", "Retained creative arrangements exceed the pre-roll declared capacity.")
		else:
			next_ledger[action.attempt_key] = {"fingerprint": retained_fingerprint, "turn": expected.state.turn, "action_id": action_id}
	else:
		next_ledger.erase(action.attempt_key)
	var remembered := CampaignMemory.record(_campaign_memory, receipt, _state, _policy, action.assessment.resolver_id, _public_receipt_witnesses(receipt))
	if not remembered.ok: return remembered
	_state = expected.state; _receipts = next_receipts; _attempt_ledger = next_ledger; _campaign_memory = remembered.memory; _pending = {}
	return {"ok": true, "already_committed": false, "receipt": receipt.duplicate(true)}

func save_data() -> Dictionary:
	return C.normalized({"schema_version": SCHEMA, "state": _state, "policy": _policy, "rng": {"seed": str(_rng.seed), "state": str(_rng.state), "mode": _rng_mode},
		"campaign_memory": _campaign_memory, "next_action": _next_action, "pending": _pending, "receipts": _receipts, "attempt_ledger": _attempt_ledger, "rule_id": rule_id(), "resolver_ids": _resolver_ids()})

func save_file(path: String) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var encoded: String = C.bytes(save_data())
	var expected: PackedByteArray = encoded.to_utf8_buffer()
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return C.fail("SAVE_FAILED", "Cannot write temporary save.")
	var stored: bool = file.store_string(encoded)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not stored or write_error != OK: return C.fail("SAVE_FAILED", "Temporary save write failed.")
	# A buffered flush/close failure may not be reflected in get_error().
	# Verify the closed staging bytes before allowing destination replacement.
	var reader := FileAccess.open(temporary, FileAccess.READ)
	if reader == null: return C.fail("SAVE_FAILED", "Cannot verify temporary save.")
	var verified: bool = reader.get_length() == expected.size() and reader.get_error() == OK
	var offset: int = 0
	while verified and offset < expected.size():
		var amount: int = mini(65536, expected.size() - offset)
		var actual: PackedByteArray = reader.get_buffer(amount)
		var read_error: Error = reader.get_error()
		verified = read_error == OK and actual.size() == amount and actual == expected.slice(offset, offset + amount)
		offset += amount
	if verified: verified = reader.get_length() == expected.size() and reader.get_error() == OK
	reader.close()
	if not verified: return C.fail("SAVE_FAILED", "Temporary save verification failed.")
	var renamed: Error = DirAccess.rename_absolute(temporary, path)
	if renamed != OK: return C.fail("SAVE_FAILED", "Atomic save rename failed.")
	return {"ok": true}

func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return C.fail("LOAD_FAILED", "Cannot read save file.")
	var parser := JSON.new(); var parsed: Error = parser.parse(file.get_as_text()); file.close()
	if parsed != OK: return C.fail("LOAD_FAILED", "Save JSON is invalid.")
	return load_data(parser.data)

func load_data(value: Variant) -> Dictionary:
	var fields := ["schema_version", "state", "policy", "rng", "next_action", "pending", "receipts", "attempt_ledger", "rule_id", "resolver_ids"]
	if value is Dictionary and value.has("campaign_memory"): fields.append("campaign_memory")
	if not C.exact_fields(value, fields) or not C.safe(value) or not value.schema_version is String or value.schema_version != SCHEMA or not value.rule_id is String or value.rule_id != rule_id() or C.bytes(value.resolver_ids) != C.bytes(_resolver_ids()): return C.fail("INVALID_SAVE", "Save schema or trusted plugin identities differ.")
	var checked: Dictionary = World.validate(value.state)
	if not checked.ok: return checked
	if C.bytes(value.policy) != C.bytes(_policy): return C.fail("PROJECTION_CONFLICT", "A save cannot expand or replace trusted runtime disclosure policy.")
	checked = ModelView.validate_policy(value.state, value.policy)
	if not checked.ok: return checked
	if not C.exact_fields(value.rng, ["seed", "state", "mode"]) or not C.int64_string(value.rng.seed) or not C.int64_string(value.rng.state) or not value.rng.mode in ["runtime_random", "test_seed"] or (value.rng.mode == "test_seed" and not rule_id().begins_with("ai_gm_test_")): return C.fail("INVALID_SAVE", "RNG seed/state must be exact signed decimal strings with an honest mode.")
	if not C.integer(value.next_action) or value.next_action < 1 or not value.pending is Dictionary or value.pending.size() > 1 or not value.receipts is Dictionary or not value.attempt_ledger is Dictionary: return C.fail("INVALID_SAVE", "Malformed save transaction collections.")
	for action_id in value.receipts:
		if not _valid_action_sequence(action_id, value.state.world_id, int(value.next_action)): return C.fail("INVALID_SAVE", "Receipt action ID collides with the saved action counter or world.")
		var receipt: Variant = value.receipts[action_id]
		var receipt_fields := ["schema_version", "action_id", "stage_hash", "before_version", "after_version", "turn", "actor_id", "goal", "attention_focus", "rolls", "plan_hash", "roll_hash", "branch_id", "outcomes", "patches", "hook_patches", "narration", "provenance", "receipt_hash"]
		if not C.exact_fields(receipt, receipt_fields) or not receipt.schema_version is String or receipt.schema_version != SCHEMA or not receipt.action_id is String or receipt.action_id != action_id or not C.integer(receipt.before_version) or receipt.before_version < 0 or not C.integer(receipt.after_version) or receipt.after_version != receipt.before_version + 1 or receipt.after_version > value.state.state_version or not C.integer(receipt.turn) or receipt.turn < 1 or receipt.turn > value.state.turn or not World.text(receipt.narration) or not World.text(receipt.goal) or not value.state.actors.has(receipt.actor_id) or not receipt.attention_focus is Dictionary or not receipt.rolls is Array or not receipt.outcomes is Dictionary or not receipt.patches is Array or not receipt.hook_patches is Array or not World.text(receipt.stage_hash): return C.fail("INVALID_SAVE", "Malformed idempotent receipt.")
		for outcome in receipt.outcomes.values():
			if not outcome is bool: return C.fail("INVALID_SAVE", "Receipt outcomes must be fixed booleans.")
		var payload: Dictionary = receipt.duplicate(true); payload.erase("receipt_hash")
		if not receipt.receipt_hash is String or C.digest(payload) != receipt.receipt_hash: return C.fail("INVALID_SAVE", "Receipt hash changed.")
		if not _focus.validate_historical(receipt.attention_focus, value.state).is_empty(): return C.fail("INVALID_SAVE", "Malformed historical attention in receipt.")
	for key in value.attempt_ledger:
		var entry: Variant = value.attempt_ledger[key]
		if not entry is Dictionary: return C.fail("INVALID_SAVE", "Malformed semantic attempt ledger.")
		if entry.get("schema_version") is String and entry.schema_version == RETRY_HISTORY:
			if not C.exact_fields(entry,["schema_version","resolver_id","fingerprints","turn","action_id"]) or not _resolvers.has(entry.resolver_id) or not _resolvers[entry.resolver_id].has_method("retry_history_version") or _resolvers[entry.resolver_id].retry_history_version()!=RETRY_HISTORY or not entry.fingerprints is Array or entry.fingerprints.is_empty() or entry.fingerprints.size()>MAX_RETRY_HISTORY: return C.fail("INVALID_SAVE", "Malformed versioned material-attempt history.")
			var seen: Dictionary = {}
			for hash_ in entry.fingerprints:
				if not hash_ is String or hash_.length()!=64 or not hash_.is_valid_hex_number(false) or seen.has(hash_): return C.fail("INVALID_SAVE", "Material history needs unique exact arrangement hashes.")
				seen[hash_] = true
		elif not C.exact_fields(entry, ["fingerprint", "turn", "action_id"]) or not World.text(entry.fingerprint): return C.fail("INVALID_SAVE", "Malformed semantic attempt ledger.")
		if not C.integer(entry.turn) or entry.turn > value.state.turn or not value.receipts.has(entry.action_id) or value.receipts[entry.action_id].turn != entry.turn: return C.fail("INVALID_SAVE", "Attempt history must bind an actual committed receipt.")
	if _retry_history_count(value.attempt_ledger)>MAX_RETRY_HISTORY: return C.fail("INVALID_SAVE", "Retained material history exceeds the declared global bound.")
	var loaded_memory: Dictionary = CampaignMemory.empty(value.state.world_id, int(value.state.state_version))
	if value.has("campaign_memory"):
		checked = CampaignMemory.validate(value.campaign_memory, value.state, value.receipts, value.policy)
		if not checked.ok: return checked
		loaded_memory = C.normalized(value.campaign_memory)
	# Re-derive frozen plan, real RNG output and staged state using trusted plugins.
	var verifier = get_script().new(value.state, _calculator, _resolvers, value.policy)
	if not verifier.ready().ok: return verifier.ready()
	verifier._receipts = C.normalized(value.receipts); verifier._attempt_ledger = C.normalized(value.attempt_ledger)
	verifier._rng_mode = value.rng.mode
	for action_id in value.pending:
		if value.receipts.has(action_id) or not _valid_action_sequence(action_id, value.state.world_id, int(value.next_action)): return C.fail("INVALID_SAVE", "Pending action ID collides with a receipt, action counter or world.")
		var action: Variant = C.normalized(value.pending[action_id])
		var action_fields := ["action_id", "actor_id", "goal", "snapshot", "focus", "state_version", "status", "context_hash", "assessment", "checks", "branches", "plan_hash", "attempt_key", "attempt_fingerprint", "rng_before", "rolls", "outcomes", "roll_hash", "staged", "stage_hash"]
		if not C.exact_fields(action, action_fields) or not action.action_id is String or action.action_id != action_id or not value.state.actors.has(action.actor_id) or not World.text(action.goal) or not C.integer(action.state_version) or action.state_version != value.state.state_version or C.bytes(action.snapshot) != C.bytes(value.state) or not action.context_hash is String or not action.status is String or not action.status in ["awaiting_assessment", "ready_roll", "rolled", "staged"] or not C.exact_fields(action.rng_before, ["seed", "state"]) or not C.int64_string(action.rng_before.seed) or not C.int64_string(action.rng_before.state): return C.fail("INVALID_SAVE", "Malformed frozen pending action.")
		if not verifier._focus.validate_frozen(action.focus, action.snapshot).is_empty() or C.digest(verifier._context(action)) != action.context_hash: return C.fail("INVALID_SAVE", "Pending frozen context or attention changed.")
		verifier._rng.seed = int(action.rng_before.seed); verifier._rng.state = int(action.rng_before.state)
		var base: Dictionary = action.duplicate(true)
		base.status = "awaiting_assessment"; base.assessment = {}; base.checks = []; base.branches = []; base.plan_hash = ""; base.attempt_key = ""; base.attempt_fingerprint = ""; base.rolls = []; base.outcomes = {}; base.roll_hash = ""; base.staged = {}; base.stage_hash = ""
		verifier._pending[action_id] = base
		if action.status != "awaiting_assessment":
			checked = verifier.prepare_assessment(action.assessment)
			if not checked.ok: return checked
		if action.status in ["rolled", "staged"]:
			checked = verifier.roll_once(action_id)
			if not checked.ok: return checked
		if action.status == "staged":
			checked = verifier.stage(action_id)
			if not checked.ok: return checked
		if C.bytes(verifier._pending[action_id]) != C.bytes(action) or str(verifier._rng.seed) != value.rng.seed or str(verifier._rng.state) != value.rng.state: return C.fail("INVALID_SAVE", "Saved plan, one-time RNG or stage cannot be reproduced exactly.")
	_state = C.normalized(value.state); _policy = C.normalized(value.policy); _pending = C.normalized(value.pending)
	_campaign_memory = loaded_memory
	_receipts = C.normalized(value.receipts); _attempt_ledger = C.normalized(value.attempt_ledger); _next_action = int(value.next_action)
	_rng.seed = int(value.rng.seed); _rng.state = int(value.rng.state); _rng_mode = value.rng.mode
	_initial_error = {}
	return {"ok": true}

static func _retry_history_count(ledger: Dictionary) -> int:
	var count := 0
	for entry in ledger.values():
		if entry is Dictionary and entry.get("schema_version") is String and entry.schema_version == RETRY_HISTORY: count += entry.get("fingerprints",[]).size()
	return count

static func _valid_action_sequence(action_id: String, world_id: String, next_action: int) -> bool:
	var prefix := world_id + ":action_"
	if not action_id.begins_with(prefix): return false
	var suffix := action_id.substr(prefix.length())
	return not suffix.is_empty() and suffix == str(int(suffix)) and int(suffix) > 0 and int(suffix) < next_action

func authoritative_result(action_id: String) -> Dictionary:
	var source: Dictionary = {}; var patches: Array = []; var hooks: Array = []
	if _pending.has(action_id) and _pending[action_id].status == "staged":
		var action: Dictionary = _pending[action_id]
		var branch: Dictionary = _matching(action.branches, action.outcomes)[0]
		source = {"state_version": action.staged.state_version, "turn": action.staged.turn, "outcomes": action.outcomes, "rolls": action.rolls}
		patches = branch.patches; hooks = branch.hook_patches
	elif _receipts.has(action_id):
		var receipt: Dictionary = _receipts[action_id]
		source = {"state_version": receipt.after_version, "turn": receipt.turn, "outcomes": receipt.outcomes, "rolls": receipt.rolls}
		patches = receipt.patches; hooks = receipt.hook_patches
	else: return {}
	var effects: Array = []
	for patch in patches + hooks:
		if patch.type == "npc_conversation_record":
			effects.append(NPCState.public_effect(patch)); continue
		# All supported actor/item/cell/status effects concern projected fields.
		# Private flags are the one supported non-public patch destination.
		if not patch.type in ["status_v2_event", "actor_pool_delta", "item_quantity_delta", "actor_move", "cell_blocking_set", "actor_status_set", "actor_status_remove", "flag_set", "environment_fell", "item_relocate", "item_equip", "combat_event", "combat_turn_set", "actor_scene_transition", "creative_source_place", "creative_relation_set"]: continue
		if patch.type == "flag_set" and not patch.flag_id in _policy.public_flag_ids: continue
		effects.append(C.normalized(patch))
	return C.normalized({"schema_version": "ai_gm_result/v1", "action_id": action_id, "state_version": source.state_version, "turn": source.turn,
		"outcomes": source.outcomes, "rolls": source.rolls, "public_effects": effects, "numbers_authoritative": true})

func narration_request(action_id: String) -> Dictionary:
	var summary: Dictionary = authoritative_result(action_id)
	if summary.is_empty(): return {}
	var context: Dictionary = {"authoritative_result": summary}
	if _pending.has(action_id):
		var action: Dictionary = _pending[action_id]
		context.actor_id = action.actor_id; context.goal = action.goal
		context.attention_focus = _context(action).attention_focus
		context.facts_after = ModelView.facts(action.staged, _policy, action.focus)
		context.provisional_until_commit = true
	else:
		var receipt: Dictionary = _receipts[action_id]
		context.actor_id = receipt.actor_id; context.goal = receipt.goal
		context.attention_focus = ModelView.historical_focus(receipt.attention_focus, _policy)
		context.fact_scope = "historical_recorded_public_effects"
		context.provisional_until_commit = false
	return C.normalized({"schema_version": SCHEMA, "reply_schema": "ai_gm_narration/v1", "phase": "narration", "action_id": action_id, "state_version": summary.state_version,
		"context_hash": C.digest(context), "context": context, "contract": {"text_only": true, "cannot_rejudge": true, "cannot_patch_facts": true, "semantic_truth_not_programmatically_certified": true}})

func validate_narration_reply(reply: Variant) -> Dictionary:
	if not C.exact_fields(reply, ["schema_version", "action_id", "state_version", "context_hash", "narration"]) or not C.safe(reply) or not reply.schema_version is String or reply.schema_version != "ai_gm_narration/v1" or not C.integer(reply.state_version) or not reply.context_hash is String or not World.text(reply.action_id) or not World.text(reply.narration): return C.fail("INVALID_NARRATION", "Narration is text plus exact schema/action/version/context bindings only.")
	var request: Dictionary = narration_request(reply.action_id)
	if request.is_empty() or reply.state_version != request.state_version or reply.context_hash != request.context_hash: return C.fail("STALE_NARRATION", "Narration is not bound to this recorded authoritative result.")
	# This returns display text. It deliberately never alters facts, plans, tokens,
	# RNG, receipts or attempt policy, and is not a prerequisite for commit.
	return {"ok": true, "narration": reply.narration, "authoritative_result": request.context.authoritative_result, "semantic_verified": false}

func cancel_intent(action_id: String) -> Dictionary:
	if not _pending.has(action_id): return C.fail("UNKNOWN_ACTION", "Only an existing unresolved intent can be cancelled.")
	var action: Dictionary = _pending[action_id]
	if not action.status in ["awaiting_assessment", "ready_roll"]: return C.fail("OUTCOME_FROZEN", "An already resolved/rolled or staged action cannot be cancelled to retry.")
	if action.state_version != _state.state_version or C.digest(action.snapshot) != C.digest(_state) or str(_rng.seed) != action.rng_before.seed or str(_rng.state) != action.rng_before.state: return C.fail("CANCEL_CONFLICT", "Cancellation requires the unchanged pre-roll snapshot and RNG lineage.")
	# Intent metadata only: no RNG draw, factual mutation, turn advance, receipt
	# deletion, semantic-attempt reset or action-ID reuse.
	_pending.erase(action_id)
	return {"ok": true, "cancelled": true, "action_id": action_id}
