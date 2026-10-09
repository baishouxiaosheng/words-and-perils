extends "res://core/ai_gm_rebuilt/engine.gd"
## Same transaction implementation. Only the opt-in phase/projection admission differs.
const ActorPolicy=preload("res://view/actor_action_profile_v2/policy.gd")
const ActorProjection=preload("res://view/actor_status_profile_v1/projection.gd")
const OrdinaryHooks=preload("res://view/actor_status_profile_v1/hooks.gd")
const Domain=preload("res://view/actor_status_profile_v1/domain.gd")
const PublicStatus=preload("res://view/actor_status_profile_v1/public_status.gd")
const MAX_REQUEST=65536
const PUBLIC_RECORD_SCHEMA="actor_status_public_receipt/v1"
var _public_records:Dictionary={}

func frozen_public_record(action_id:String)->Dictionary:
	if not _pending.has(action_id) or _pending[action_id].status!="staged":return C.fail("ACTOR_PUBLIC_STAGE","Public evidence requires the exact staged action.")
	var action:Dictionary=_pending[action_id]
	var record:Dictionary={"schema_version":PUBLIC_RECORD_SCHEMA,"action_id":action_id,"actor_id":action.actor_id,"after_version":action.staged.state_version,"receipt_hash":"0".repeat(64),"attention_focus":_context(action).attention_focus,"public_effects":authoritative_result(action_id).public_effects}
	if not C.safe(record) or not valid_transport_strings(record) or C.bytes(record).to_utf8_buffer().size()>MAX_REQUEST:return C.fail("ACTOR_PUBLIC_BUDGET","Frozen public evidence must be finite, supported text and within the receipt record budget including its full hash.")
	return {"ok":true,"record":C.normalized(record)}

func _record_for_receipt(action_id:String)->Dictionary:
	if not _receipts.has(action_id) or not _public_records.has(action_id):return {}
	var record:Dictionary=_public_records[action_id];var receipt:Dictionary=_receipts[action_id]
	if record.get("schema_version")!=PUBLIC_RECORD_SCHEMA or record.get("action_id")!=action_id or record.get("actor_id")!=receipt.actor_id or record.get("after_version")!=receipt.after_version or record.get("receipt_hash")!=receipt.receipt_hash:return {}
	return record.duplicate(true)
func begin_intent(goal:String,reference:Dictionary={},actor_id:String="actor_player")->Dictionary:
	if not valid_transport_strings(goal) or goal.to_utf8_buffer().size()>8192:return C.fail("INTENT_BUDGET","Intention exceeds this profile's 8 KiB bound.")
	if not ActorProjection.visible_focus(_state,actor_id,reference):return C.fail("ACTOR_VISIBILITY","Attention cannot disclose an unseen actor, item, or tile.")
	return super.begin_intent(goal,reference,actor_id)
func _context(action:Dictionary)->Dictionary:
	var public=ActorProjection.facts(action.snapshot,action.actor_id)
	return {"facts":public,"attention_focus":ModelView.focus_view(action.focus,public),"goal":action.goal,"actor_id":action.actor_id,"text_priority":"explicit_acting_actor_text"}
func model_request(action_id:String)->Dictionary:
	var result:Dictionary=super.model_request(action_id)
	if _pending.has(action_id) and not result.is_empty():
		var action:Dictionary=_pending[action_id]
		result["status_context"]=PublicStatus.compact(action.snapshot,action.actor_id)
	return result
func attention(reference:Dictionary)->Dictionary:
	var actor_id=ActorPolicy.authorized(_state)
	if not ActorProjection.visible_focus(_state,actor_id,reference):return C.fail("ACTOR_VISIBILITY","Unseen focus is not public context.")
	var resolved:Dictionary=_focus.resolve(reference,_state)
	if not resolved.ok:return resolved
	return {"ok":true,"readonly":true,"focus":ModelView.focus_view(resolved.focus,ActorProjection.facts(_state,actor_id))}
func capability_catalog(actor_id:String="actor_player",selected_focus:Dictionary={})->Dictionary:
	var admission:Dictionary=ActorPolicy.validate_assessment(_state,{"bindings":{"actor_id":actor_id}})
	if not _pending.is_empty():admission=C.fail("ACTION_IN_PROGRESS","Finish or cancel the current intention first.")
	if not ActorProjection.visible_focus(_state,actor_id,selected_focus):admission=C.fail("ACTOR_VISIBILITY","Unseen selected target.")
	return CapabilityCatalog.build(ActorProjection.facts(_state,actor_id),_resolver_ids(),_action_schemas(),actor_id,admission,selected_focus)
func narration_request(action_id:String)->Dictionary:
	var result:Dictionary=super.narration_request(action_id)
	if result.is_empty():return result
	if _pending.has(action_id):
		var action:Dictionary=_pending[action_id]
		result.context.facts_after=ActorProjection.facts(action.staged,action.actor_id)
	elif _receipts.has(action_id):
		var recorded:Dictionary=_record_for_receipt(action_id)
		result.context.attention_focus=recorded.attention_focus if not recorded.is_empty() else PublicStatus.historical_focus(_receipts[action_id].attention_focus)
	result.context_hash=C.digest(result.context)
	return result

func authoritative_result(action_id:String)->Dictionary:
	var result:Dictionary=super.authoritative_result(action_id)
	if result.is_empty():return result
	if _receipts.has(action_id):
		var recorded:Dictionary=_record_for_receipt(action_id)
		if not recorded.is_empty():
			result.public_effects=recorded.public_effects
			return result
	var filtered:Array=[]
	for patch in result.public_effects:
		if patch.get("type")=="status_v2_event":
			var visible=false
			if _pending.has(action_id) and _pending[action_id].status=="staged":
				var action:Dictionary=_pending[action_id]
				visible=PublicStatus.visible_event(action.snapshot,action.staged,action.actor_id,patch)
			elif _receipts.has(action_id):visible=PublicStatus.recorded_event(_receipts[action_id],patch)
			if not visible:continue
		elif patch.get("type") in ["actor_status_set","actor_status_remove"] and not PublicStatus.public_legacy_patch(patch):continue
		filtered.append(patch)
	result.public_effects=filtered
	return result

func _validate_assessment(action: Dictionary, reply: Variant) -> Dictionary:
	var fields := ["schema_version", "action_id", "state_version", "context_hash", "narration", "interpretation", "resolver_id", "bindings", "components", "fact_refs", "provenance"]
	if not C.exact_fields(reply, fields) or not C.safe(reply): return C.fail("INVALID_ASSESSMENT", "Assessment requires exact typed fields and finite JSON; code/patch extensions are not accepted.")
	if not reply.schema_version is String or reply.schema_version != ASSESSMENT_SCHEMA or not reply.action_id is String or reply.action_id != action.action_id or not C.integer(reply.state_version) or reply.state_version != action.state_version or reply.state_version != _state.state_version: return C.fail("STALE_ASSESSMENT", "Assessment schema, action or version differs from frozen state.")
	if not reply.context_hash is String or reply.context_hash != action.context_hash or not World.text(reply.narration) or not World.text(reply.interpretation) or not reply.resolver_id is String or not _resolvers.has(reply.resolver_id): return C.fail("INVALID_ASSESSMENT", "Assessment context, narration or registered resolver is invalid.")
	if not reply.bindings is Dictionary or not reply.components is Array or reply.components.is_empty() or reply.components.size() > 4 or not reply.fact_refs is Array or reply.fact_refs.is_empty(): return C.fail("INVALID_ASSESSMENT", "Assessment requires bindings, one to four components and explicit fact references.")
	if reply.bindings.has("actor_id") and (not reply.bindings.actor_id is String or reply.bindings.actor_id != action.actor_id): return C.fail("INVALID_BINDING", "Assessment cannot replace the acting actor from the frozen intent.")
	var phase_check: Dictionary = ActorPolicy.validate_assessment(action.snapshot, reply)
	if not phase_check.ok: return phase_check
	if not C.exact_fields(reply.provenance, ["provider", "live", "kind"]) or not World.text(reply.provenance.provider) or not reply.provenance.live is bool or not reply.provenance.kind is String or not reply.provenance.kind in ["fixture", "model_reply"]: return C.fail("INVALID_ASSESSMENT", "Provenance is typed metadata, not proof of a live call.")
	if reply.provenance.kind == "fixture" and not rule_id().begins_with("ai_gm_test_"):
		var authorized_fixture: Variant = false
		if _calculator.has_method("allows_fixture_assessment"):
			authorized_fixture = _calculator.allows_fixture_assessment(action.snapshot.duplicate(true), reply.duplicate(true), action.goal, action.focus.duplicate(true))
		if not authorized_fixture is bool or not authorized_fixture: return C.fail("TEST_ONLY", "Production fixtures require the trusted calculator's exact authored-example validation.")
	var refs: Dictionary = {}; var facts := ActorProjection.facts(action.snapshot, action.actor_id)
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

func prepare_assessment(reply:Variant)->Dictionary:
	if not C.safe(reply) or not valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size()>MAX_REQUEST:return C.fail("ASSESSMENT_BUDGET","Reply must fit the same bounded typed public contract.")
	return super.prepare_assessment(reply)
func load_data(value:Variant)->Dictionary:
	if not C.safe(value) or not valid_transport_strings(value):return C.fail("ACTOR_SAVE_TEXT","Saved strings must roundtrip through supported JSON text.")
	if value is Dictionary and value.get("pending") is Dictionary and value.get("state") is Dictionary:
		var valid_world:Dictionary=World.validate(value.state)
		if not valid_world.ok:return valid_world
		value=C.normalized(value)
		if _resolvers.is_empty():return C.fail("ACTOR_REGISTRY","No registered profile resolvers.")
		valid_world=_resolvers.values()[0].source.validate_state(value.state)
		if not valid_world.ok:return valid_world
		for action in value.pending.values():
			if not action is Dictionary or not action.get("actor_id") is String or not action.get("goal") is String or action.goal.to_utf8_buffer().size()>8192:return C.fail("ACTOR_PENDING","Invalid pending actor or bounded goal.")
			var check:Dictionary=ActorPolicy.validate_assessment(value.state,{"bindings":{"actor_id":action.actor_id}})
			if not check.ok:return check
			if not action.get("focus") is Dictionary or not ActorProjection.visible_focus(value.state,action.actor_id,_focus.reference_for(action.focus)):return C.fail("ACTOR_VISIBILITY","Pending focus is outside the actor's exact public context.")
	return super.load_data(value)

static func valid_transport_strings(value:Variant)->bool:
	if value is String or value is StringName:
		var text_:String=str(value)
		for i in text_.length():
			if text_.unicode_at(i)<32 and text_.unicode_at(i) not in [9,10,13]:return false
	elif value is Array:
		for child in value:
			if not valid_transport_strings(child):return false
	elif value is Dictionary:
		for key in value:
			if not valid_transport_strings(key) or not valid_transport_strings(value[key]):return false
	return true
func validate_narration_reply(reply:Variant)->Dictionary:
	if not C.safe(reply) or not valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size()>MAX_REQUEST:return C.fail("NARRATION_TEXT","Narration must contain supported bounded text.")
	return super.validate_narration_reply(reply)

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
			if patch is Dictionary and patch.get("type")=="combat_turn_set":return C.fail("ACTOR_PHASE_HOOK","Ordinary branches cannot write phase, including no-op or change-and-restore sequences.")
			var applied: Dictionary = Domain.apply(candidate, patch)
			if not applied.ok: return applied
		var hooks: Dictionary = OrdinaryHooks.freeze(snapshot, candidate, acting_actor_id, _resolvers[plan.resolver_id].source.navigation)
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

func _candidate(action:Dictionary)->Dictionary:
	# Same frozen-patch/hash/counter protocol as core. Only the movement apply seam
	# differs, and it is shared with resolver preview and branch preparation.
	var found:Array=_matching(action.branches,action.outcomes)
	if found.size()!=1:return C.fail("INVALID_OUTCOME","No unique frozen consequence branch exists.")
	var branch:Dictionary=found[0];var candidate:Dictionary=action.snapshot.duplicate(true)
	for patch in branch.patches:
		var applied:Dictionary=Domain.apply(candidate,patch)
		if not applied.ok:return applied
	for patch in branch.hook_patches:
		var applied:Dictionary=Domain.apply(candidate,patch,true)
		if not applied.ok:return applied
	if C.digest(candidate)!=branch.candidate_hash:return C.fail("PLAN_CONFLICT","Selected candidate differs from its pre-roll frozen patches.")
	candidate.state_version+=1;candidate.turn+=1
	var checked:Dictionary=_resolvers[action.assessment.resolver_id].source.validate_state(candidate)
	if not checked.ok:return checked
	if not World.stable(action.snapshot,candidate):return C.fail("INVALID_STAGE","Staged state violates world integrity.")
	return {"ok":true,"state":C.normalized(candidate),"branch":branch}
