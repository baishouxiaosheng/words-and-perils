extends RefCounted
## Isolated experimental transaction core; no API client and no production rule.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const Focus = preload("res://core/focus_contract.gd")
const SCHEMA := "ai_gm_rebuilt/v1"
const ASSESSMENT_SCHEMA := "ai_gm_assessment/v1"
var _state: Dictionary = {}
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

func attention(reference: Dictionary) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var resolved: Dictionary = _focus.resolve(reference, _state)
	if not resolved.ok: return resolved
	if not Focus.validate_scene_scope(resolved.focus, _state): return C.fail("FOCUS_SCENE", "Attention target is not in the acting actor's active scene.")
	return {"ok": true, "focus": ModelView.focus_view(resolved.focus, ModelView.facts(_state, _policy)), "readonly": true}

func begin_intent(goal: String, attention_reference: Dictionary = {}, actor_id: String = "actor_player") -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	if goal.strip_edges().is_empty(): return C.fail("NEEDS_INTENT", "Attention is context only; write an explicit intended action.")
	if not _state.actors.has(actor_id): return C.fail("UNKNOWN_ACTOR", "Unknown stable actor ID.")
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
	var projected := ModelView.facts(action.snapshot, _policy)
	return {"facts": projected, "attention_focus": ModelView.focus_view(action.focus, projected), "goal": action.goal, "actor_id": action.actor_id, "text_priority": "explicit_player_text"}

func model_request(action_id: String) -> Dictionary:
	if not _pending.has(action_id): return {}
	var action: Dictionary = _pending[action_id]
	var result := {"schema_version": SCHEMA, "action_id": action_id, "state_version": action.state_version, "phase": "assessment", "context_hash": action.context_hash,
		"context": _context(action), "contract": {"assessment_schema": ASSESSMENT_SCHEMA, "assessment_required_for_every_intent": true, "attention_is_action": false, "narration_is_facts": false,
		"calculator": rule_id(), "rule_schema": _rule_schema(), "resolver_ids": _resolver_ids(), "action_schemas": _action_schemas(), "model_reply_is_data_only": true}}
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
	var refs: Dictionary = {}; var facts := ModelView.facts(action.snapshot, _policy)
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
	checked = _freeze_branches(action.snapshot, calculated.checks, frozen)
	if not checked.ok: return checked
	var attempt_key: Variant = resolver.attempt_key(action.snapshot.duplicate(true), C.normalized(reply))
	var fingerprint: Variant = resolver.attempt_fingerprint(action.snapshot.duplicate(true), C.normalized(reply))
	if not World.text(attempt_key) or not C.safe(fingerprint): return C.fail("INVALID_ATTEMPT", "Trusted resolver must provide a stable semantic key and real-fact fingerprint.")
	var ledger_key: String = C.digest([action.actor_id, reply.resolver_id, attempt_key])
	var fingerprint_hash := C.digest(fingerprint)
	if _attempt_ledger.has(ledger_key) and _attempt_ledger[ledger_key].fingerprint == fingerprint_hash: return C.fail("REPEAT_ATTEMPT", "Equivalent wording cannot reroll unchanged relevant conditions.")
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

func _freeze_branches(snapshot: Dictionary, checks_input: Array, plan: Dictionary) -> Dictionary:
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
		var hooks: Dictionary = Hooks.freeze(snapshot, candidate)
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
	next_ledger[action.attempt_key] = {"fingerprint": action.attempt_fingerprint, "turn": expected.state.turn, "action_id": action_id}
	_state = expected.state; _receipts = next_receipts; _attempt_ledger = next_ledger; _pending = {}
	return {"ok": true, "already_committed": false, "receipt": receipt.duplicate(true)}

func save_data() -> Dictionary:
	return C.normalized({"schema_version": SCHEMA, "state": _state, "policy": _policy, "rng": {"seed": str(_rng.seed), "state": str(_rng.state), "mode": _rng_mode},
		"next_action": _next_action, "pending": _pending, "receipts": _receipts, "attempt_ledger": _attempt_ledger, "rule_id": rule_id(), "resolver_ids": _resolver_ids()})

func save_file(path: String) -> Dictionary:
	if not _initial_error.is_empty(): return ready()
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return C.fail("SAVE_FAILED", "Cannot write temporary save.")
	file.store_string(C.bytes(save_data())); file.flush(); file.close()
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
		if not C.exact_fields(entry, ["fingerprint", "turn", "action_id"]) or not World.text(entry.fingerprint) or not C.integer(entry.turn) or entry.turn > value.state.turn or not value.receipts.has(entry.action_id) or value.receipts[entry.action_id].turn != entry.turn: return C.fail("INVALID_SAVE", "Malformed semantic attempt ledger.")
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
	_receipts = C.normalized(value.receipts); _attempt_ledger = C.normalized(value.attempt_ledger); _next_action = int(value.next_action)
	_rng.seed = int(value.rng.seed); _rng.state = int(value.rng.state); _rng_mode = value.rng.mode
	_initial_error = {}
	return {"ok": true}

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
		# All supported actor/item/cell/status effects concern projected fields.
		# Private flags are the one supported non-public patch destination.
		if not patch.type in ["actor_pool_delta", "item_quantity_delta", "actor_move", "cell_blocking_set", "actor_status_set", "actor_status_remove", "flag_set", "environment_fell", "item_relocate", "item_equip", "combat_event", "combat_turn_set", "actor_scene_transition"]: continue
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
		context.facts_after = ModelView.facts(action.staged, _policy)
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
