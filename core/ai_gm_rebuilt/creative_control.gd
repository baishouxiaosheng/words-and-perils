extends RefCounted
## Strict, non-mutating interpretation feedback negotiated only by new contracts.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "ai_gm_control/v1"
const CODES := ["NEEDS_PUBLIC_CONTEXT","NEEDS_CLARIFICATION","INFEASIBLE","NO_SUPPORTED_MECHANISM"]
static func assessment_contract() -> Dictionary:
	return {"schema_version":"ai_gm_assessment/v1","exact_fields":["schema_version","action_id","state_version","context_hash","narration","interpretation","resolver_id","bindings","components","fact_refs","provenance"],"component_fields":["id","parameters","disposition","fact_ref_ids"],"fact_ref_fields":["id","path","expected"],"provenance_fields":["provider","live","kind"],"dispositions":["possible","certain","impossible"],"text":"Copy envelope identity/hash exactly. Nonempty narration previews only; interpretation preserves every clause. Reference paths point into context.facts and expected copies the complete exact public value. Numeric parameters and bindings follow the selected action schema. No code, patches or outcomes."}
static func contract() -> Dictionary:
	return {"schema_version":SCHEMA,"exact_fields":["schema_version","action_id","state_version","context_hash","code","message","candidates","context_paths","provenance"],"codes":CODES,"candidate_shape":{"kind":"item or passage_edge or actor","id":"existing public stable ID"},"max_candidates":8,"max_context_paths":8,"message_limit":1000,"context_policy":"Request only known-public whole object, passage, actor or cell facts from this frozen snapshot. No secrets, RNG, receipts or arbitrary paths. The user can request reassessment after bounded public expansion; no automatic network retry, dice, turn or cost."}
static func allowed_path(path: String) -> bool:
	if path in ["/physical_catalog","/creative_placements","/creative_relations"]: return true
	var tokens:=path.split("/")
	if tokens.size()==3 and tokens[0].is_empty() and tokens[1] in ["items","actors","passage_targets","settlements","hexes"] and not tokens[2].is_empty(): return true
	return tokens.size()==4 and tokens[0].is_empty() and tokens[1]=="scene_hexes" and not tokens[2].is_empty() and not tokens[3].is_empty()
static func validate(request: Dictionary, reply: Variant) -> Dictionary:
	if not request.get("contract",{}).has("control_reply") or not C.exact_fields(reply,["schema_version","action_id","state_version","context_hash","code","message","candidates","context_paths","provenance"]) or not C.safe(reply) or not reply.schema_version is String or reply.schema_version!=SCHEMA or not reply.action_id is String or reply.action_id!=request.action_id or not C.integer(reply.state_version) or reply.state_version!=request.state_version or not reply.context_hash is String or reply.context_hash!=request.context_hash: return C.fail("INVALID_CONTROL","Interpretation feedback must exactly bind the current negotiated frozen request.")
	if not reply.code in CODES or not reply.message is String or reply.message.strip_edges().is_empty() or reply.message.length()>1000 or not reply.candidates is Array or reply.candidates.size()>8 or not reply.context_paths is Array or reply.context_paths.size()>8 or not C.exact_fields(reply.provenance,["provider","live","kind"]) or not reply.provenance.provider is String or reply.provenance.provider.is_empty() or not reply.provenance.live is bool or not reply.provenance.kind is String or reply.provenance.kind!="model_reply": return C.fail("INVALID_CONTROL","Malformed or unbounded non-mutating interpretation feedback.")
	var facts: Dictionary=request.context.facts;var seen: Dictionary={};var public_context: Dictionary={}
	for candidate in reply.candidates:
		if not C.exact_fields(candidate,["kind","id"]) or not candidate.kind in ["item","passage_edge","actor"] or not candidate.id is String: return C.fail("INVALID_CONTROL","Clarification candidates must be existing public stable objects.")
		var collection: String={"item":"items","passage_edge":"passage_targets","actor":"actors"}[candidate.kind]
		if not facts.get(collection,{}).has(candidate.id) or seen.has(candidate.kind+":"+candidate.id): return C.fail("INVALID_CONTROL","Unknown or duplicate clarification candidate.")
		seen[candidate.kind+":"+candidate.id]=true
	seen.clear()
	if (reply.code=="NEEDS_PUBLIC_CONTEXT") != (not reply.context_paths.is_empty()): return C.fail("INVALID_CONTROL","Only context-needed feedback may carry one to eight public paths.")
	for path in reply.context_paths:
		if not path is String or path.length()>240 or not allowed_path(path) or seen.has(path): return C.fail("INVALID_CONTROL","Context request contains an unapproved path or duplicate.")
		var found:=C.pointer(facts,path)
		if not found.ok: return C.fail("PUBLIC_CONTEXT_UNAVAILABLE","That fact does not exist in the frozen public snapshot; no hidden data or physical property was invented.")
		public_context[path]=found.value;seen[path]=true
	if C.bytes(public_context).to_utf8_buffer().size()>16384: return C.fail("CONTEXT_BUDGET","Public expansion exceeds the 16KiB per-pass budget; no request, cost or turn.")
	var result:=C.fail(reply.code,reply.message)
	result["control_reply"]=C.normalized(reply);result["public_context"]=C.normalized(public_context)
	return result
