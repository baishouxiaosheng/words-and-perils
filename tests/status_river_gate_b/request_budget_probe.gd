extends RefCounted
## Pure serialization only. Encoded bytes are budgeted; expanded facts preserve
## exact original scope semantics. No Client/HTTP, cap change or payload trimming.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ScopedEngine = preload("res://view/runtime_ai/scoped_engine.gd")
const PublicDictionary = preload("res://core/status_gameplay/public_dictionary.gd")
const Codec = preload("res://core/ai_gm_http/openai_chat_codec.gd")
const CoastContract = preload("res://core/ai_gm_http/coast_contract.gd")
const RuntimeController = preload("res://view/runtime_ai/controller.gd")
const Foundation = preload("res://core/status_foundation/engine_bridge.gd")
const CAP_BYTES = 65536
const WRAPPER_CAP_BYTES = 4194304
const WRAPPER_OBSERVATION_BYTES = 65536
const PROVENANCE = {"provider":"offline_budget_fixture", "live":false, "kind":"model_reply"}

class DiagnosticScope:
	extends "res://view/runtime_ai/scoped_engine.gd"
	var raw_candidate: Dictionary = {}
	var candidate: Dictionary = {}
	var capture_error: Dictionary = {}
	func _budget(full: Dictionary, scoped: Dictionary, key: String) -> Dictionary:
		raw_candidate = scoped.duplicate(true)
		candidate = scoped.duplicate(true)
		if PublicDictionary.enabled(full):
			var packed: Dictionary = PublicDictionary.pack(scoped)
			if packed.ok: candidate = packed.request
			else: capture_error = packed
		# Pass original raw argument to production; do not double-pack or change
		# expanded-size metrics. Captured packing is diagnostic reproduction only.
		return super._budget(full,scoped,key)

static func inspect(engine: RefCounted, reply: Dictionary) -> Dictionary:
	var problems: Array = []
	var action_id: String = reply.get("action_id", "")
	var before := C.digest(engine.save_data())
	var full: Dictionary = engine.model_request(action_id)
	var result: Dictionary = {"ok":false,"action_id":action_id,"resolver_id":reply.get("resolver_id", ""),"public_cap_bytes":CAP_BYTES,"wrapper_cap_bytes":WRAPPER_CAP_BYTES,"wrapper_observation_bytes":WRAPPER_OBSERVATION_BYTES,"scope_constructor_budget":CAP_BYTES,"transport_admitted":false,"http_nodes_created":0,"network_sends":0,"model_calls":0,"cap_changed":false,"payload_trimmed_to_fit":false,"full_public_bytes":0,"scoped_public_bytes":0,"wrapper_bytes":null,"wrapper_sha256":null,"offline_provenance":PROVENANCE.duplicate(true),"problems":problems}
	if full.is_empty(): problems.append("NO_FROZEN_SOURCE_REQUEST"); return result
	result.full_public_bytes = C.bytes(full).to_utf8_buffer().size()
	result["full_public_sha256"] = C.digest(full)
	result["focus_sha256"] = C.digest(full.context.attention_focus)
	var entries: Dictionary = Foundation.runtime().entries
	if entries.size() != 168: problems.append("EXPECTED_168_LOCAL_CATALOG_DEFINITIONS")
	result["local_catalog_count"] = entries.size()
	if _contains_internal_status(full,entries): problems.append("INTERNAL_STATUS_CATALOG_OR_STORE_IN_PUBLIC_REQUEST")
	var compact: Dictionary = full.get("status_context",{})
	if compact.is_empty() or compact.get("schema_version") != "active_status_context/v1" or compact.get("truncated",true) or compact.get("omitted",-1) != 0:
		problems.append("SOURCE_FIXTURE_STATUS_CONTEXT_MISSING_OR_TRUNCATED")
	result["active_status_count"] = compact.get("active",[]).size()
	result["status_context_bytes"] = C.bytes(compact).to_utf8_buffer().size()
	var scope: RefCounted = ScopedEngine.new(engine,func(): return true,CAP_BYTES)
	var scoped: Dictionary = scope.model_request(action_id)
	var diagnostic: RefCounted = DiagnosticScope.new(engine,func(): return true,CAP_BYTES)
	var mirrored: Dictionary = diagnostic.model_request(action_id)
	if not diagnostic.capture_error.is_empty() or C.bytes(mirrored) != C.bytes(scoped) or C.bytes(scope.last_metrics) != C.bytes(diagnostic.last_metrics) or C.bytes(scope.last_error) != C.bytes(diagnostic.last_error):
		problems.append("CAPTURE_DIFFERS_FROM_PRODUCTION_PACK_OR_ADMISSION")
	var encoded: Dictionary = diagnostic.candidate
	var raw: Dictionary = diagnostic.raw_candidate
	var restored: Dictionary = PublicDictionary.expand(encoded)
	if not restored.ok or C.bytes(restored.get("request")) != C.bytes(raw):
		problems.append("ENCODED_REQUEST_DOES_NOT_EXPAND_EXACTLY_TO_ORIGINAL_SCOPE")
		result["dictionary_error"] = restored
		return result
	var semantic: Dictionary = restored.request
	var uses_dictionary: bool = encoded.has(PublicDictionary.FIELD)
	if PublicDictionary.enabled(full) and not uses_dictionary:
		problems.append("STATUS_FIXTURE_EXPECTED_ACTUAL_PUBLIC_DICTIONARY_ENCODING")
	if uses_dictionary and (_reference_count(encoded) == 0 or PublicDictionary._has_ref(semantic)):
		problems.append("DICTIONARY_MUST_HAVE_REFERENCES_AND_FULLY_EXPAND")
	if _contains_internal_status(encoded,entries) or _contains_internal_status(semantic,entries):
		problems.append("INTERNAL_STATUS_CATALOG_OR_STORE_IN_ENCODED_OR_EXPANDED_SCOPE")
	result["scope_metrics"] = scope.last_metrics.duplicate(true)
	result.scoped_public_bytes = C.bytes(encoded).to_utf8_buffer().size()
	result["public_headroom_bytes"] = CAP_BYTES-int(result.scoped_public_bytes)
	result["scoped_public_sha256"] = C.digest(encoded)
	result["expanded_scoped_public_bytes"] = C.bytes(semantic).to_utf8_buffer().size()
	result["expanded_scoped_sha256"] = C.digest(semantic)
	result["dictionary"] = dictionary_stats(encoded,semantic)
	if int(result.expanded_scoped_public_bytes) < int(result.scoped_public_bytes): problems.append("ENCODING_EXPANDS_ORIGINAL_SCOPED_PAYLOAD")
	# These must remain literal in encoded data, not merely reconstructable.
	for field in ["attention_focus","goal","actor_id","text_priority"]:
		if C.bytes(encoded.context.get(field)) != C.bytes(raw.context.get(field)) or C.bytes(semantic.context.get(field)) != C.bytes(full.context.get(field)):
			problems.append("LITERAL_CONTEXT_CHANGED:" + field)
	for field in ["schema_version","phase","action_id","state_version","context_hash","transport_scope"]:
		if C.bytes(encoded.get(field)) != C.bytes(raw.get(field)): problems.append("LITERAL_HEADER_HISTORY_OR_STATUS_CHANGED:" + field)
	for collection in ["actors","items"]:
		if C.bytes(semantic.context.facts.get(collection)) != C.bytes(full.context.facts.get(collection)): problems.append("EXPANDED_WHOLE_FACT_COLLECTION_CHANGED:" + collection)
	for field in ["contract","status_context","memory_context","context_hash","action_id","state_version"]:
		if C.bytes(semantic.get(field)) != C.bytes(full.get(field)): problems.append("EXPANDED_REQUEST_CHANGED:" + field)
	var visible: Dictionary = semantic.context.facts.duplicate(true)
	visible.attention_focus = semantic.context.attention_focus
	var refs_exact := true
	for reference in reply.get("fact_refs",[]):
		var found: Dictionary = C.pointer(visible,reference.path)
		if not found.ok or C.bytes(found.get("value")) != C.bytes(reference.expected):
			refs_exact = false; problems.append("EXPANDED_SOURCE_FACT_REFERENCE_NOT_EXACT:" + str(reference.path))
	result["full_source_refs_exact"] = refs_exact
	result["facts_and_focus_exact"] = refs_exact and problems.is_empty()
	result["fact_reference_paths"] = reply.get("fact_refs",[]).map(func(reference): return reference.path)
	# Pure expected-value A/B also exercises references nested within actor/item
	# facts. Actual Scope.prepare is additionally exercised by the matrix script.
	var reply_encoding: Dictionary = encoded_reply(reply,encoded)
	result["encoded_expected_reference_count"] = reply_encoding.reference_count
	if not reply_encoding.ok: problems.append("ENCODED_EXPECTED_DOES_NOT_EXPAND_TO_ORIGINAL_FACT")
	if scoped.is_empty():
		result["transport_outcome"] = "source_scope_rejected_before_codec_envelope"
		result["source_error"] = scope.last_error.duplicate(true)
		result["wrapper_unavailable_reason"] = "No admitted request; diagnostic encoded candidate exists but was never a send candidate"
		if scope.last_error.get("code") != "CONTEXT_BUDGET" or scope.last_error.get("budget_bytes") != CAP_BYTES or scope.last_error.get("used_bytes") != result.scoped_public_bytes or scope._sent_requests.has(action_id):
			problems.append("EMPTY_SCOPE_NOT_EXPLICIT_UNSENT_CONTEXT_BUDGET")
	else:
		result.transport_admitted = true
		if C.bytes(scoped) != C.bytes(encoded) or result.scoped_public_bytes > CAP_BYTES: problems.append("ADMITTED_ENCODED_REQUEST_DIFFERS_OR_EXCEEDS_65536")
		var legacy: bool = full.contract.get("calculator") == "ai_gm_test_coast_actions/v1"
		var trusted: String = CoastContract.instructions() if legacy else RuntimeController.CONTRACT
		var config: Dictionary = {"model":"offline-budget-fixture"}
		result["applicable_contract"] = "CoastContract.instructions" if legacy else "RuntimeController.CONTRACT"
		result["coast_contract_applicable"] = legacy
		var envelope: Dictionary = Codec.encode(scoped,config,PROVENANCE,trusted)
		result.wrapper_bytes = C.bytes(envelope).to_utf8_buffer().size()
		result.wrapper_sha256 = C.digest(envelope)
		result["codec_request_roundtrip_exact"] = envelope.messages[1].content == C.bytes(scoped) and C.bytes(JSON.parse_string(envelope.messages[1].content)) == C.bytes(scoped)
		if not result.codec_request_roundtrip_exact: problems.append("CODEC_CHANGED_ENCODED_REQUEST")
		if uses_dictionary and not envelope.messages[0].content.contains("public_dictionary/v2"): problems.append("CODEC_MISSING_PUBLIC_DICTIONARY_EXPLANATION")
		result["legacy_coast_contract_diagnostic_wrapper_bytes"] = C.bytes(Codec.encode(scoped,config,PROVENANCE,CoastContract.instructions())).to_utf8_buffer().size()
		result["expanded_scoped_wrapper_bytes"] = C.bytes(Codec.encode(semantic,config,PROVENANCE,trusted)).to_utf8_buffer().size()
		result["wrapper_exceeds_65536_observation"] = result.wrapper_bytes > WRAPPER_OBSERVATION_BYTES
		result["wrapper_headroom_bytes"] = WRAPPER_CAP_BYTES-int(result.wrapper_bytes)
		result["wrapper_65536_observation_margin_bytes"] = WRAPPER_OBSERVATION_BYTES-int(result.wrapper_bytes)
		if result.wrapper_bytes > WRAPPER_CAP_BYTES: problems.append("COMPLETE_WRAPPER_EXCEEDS_EXISTING_4MIB_CAP")
		result["transport_outcome"] = "encoded_public65536_wrapper4MiB_serialized_only"
		var detached: Dictionary = semantic.duplicate(true)
		var packet_count: int = _remove_display_packets_for_diagnostic_only(detached)
		var baseline: Dictionary = diagnostic_bytes(detached,uses_dictionary,config,trusted,PROVENANCE)
		if not baseline.ok: problems.append("DETACHED_DISPLAY_REPACK_DIAGNOSTIC_FAILED")
		else:
			result["display_packet_diagnostic"] = {"not_a_send_candidate":true,"expanded_detached_copy_then_repacked":true,"packet_count":packet_count,"scoped_public_without_display_packets_bytes":baseline.public,"scoped_public_display_increment_bytes":int(result.scoped_public_bytes)-int(baseline.public),"wrapper_without_display_packets_bytes":baseline.wrapper,"wrapper_display_increment_bytes":int(result.wrapper_bytes)-int(baseline.wrapper),"unencoded_public_display_increment_bytes":int(result.expanded_scoped_public_bytes)-int(baseline.unencoded_public)}
		if C.digest(scoped) != result.scoped_public_sha256: problems.append("DETACHED_DIAGNOSTIC_CHANGED_ADMITTED_REQUEST")
	result["engine_unchanged"] = C.digest(engine.save_data()) == before
	if not result.engine_unchanged: problems.append("SERIALIZATION_CHANGED_ENGINE")
	result.ok = problems.is_empty()
	return result

static func dictionary_stats(encoded: Dictionary, expanded: Dictionary) -> Dictionary:
	var encoded_size: int = C.bytes(encoded).to_utf8_buffer().size()
	var expanded_size: int = C.bytes(expanded).to_utf8_buffer().size()
	var table: Dictionary = encoded.get(PublicDictionary.FIELD,{}).get("values",{})
	return {"present":encoded.has(PublicDictionary.FIELD),"values":table.size(),"references":_reference_count(encoded),"flat_values_reference_free":not PublicDictionary._has_ref(table),"encoded_public_bytes":encoded_size,"expanded_public_bytes":expanded_size,"saved_public_bytes":expanded_size-encoded_size,"unencoded_public_headroom_bytes":CAP_BYTES-expanded_size,"encoded_public_headroom_bytes":CAP_BYTES-encoded_size,"unencoded_would_be_admitted":expanded_size<=CAP_BYTES,"roundtrip_expanded_sha256":C.digest(expanded)}

static func diagnostic_bytes(semantic: Dictionary, use_dictionary: bool, config: Dictionary, trusted: String, provenance: Dictionary) -> Dictionary:
	var encoded: Dictionary = semantic.duplicate(true)
	if use_dictionary:
		var packed: Dictionary = PublicDictionary.pack(semantic)
		if not packed.ok: return packed
		encoded = packed.request
	var expanded: Dictionary = PublicDictionary.expand(encoded)
	if not expanded.ok or C.bytes(expanded.request) != C.bytes(semantic): return C.fail("GATE_DIAGNOSTIC_EQUIVALENCE","Detached repack must be lossless")
	return {"ok":true,"public":C.bytes(encoded).to_utf8_buffer().size(),"wrapper":C.bytes(Codec.encode(encoded,config,provenance,trusted)).to_utf8_buffer().size(),"unencoded_public":C.bytes(semantic).to_utf8_buffer().size(),"unencoded_wrapper":C.bytes(Codec.encode(semantic,config,provenance,trusted)).to_utf8_buffer().size(),"diagnostic_only_not_send_candidate":true}

static func encoded_reply(reply: Dictionary, encoded: Dictionary) -> Dictionary:
	var table: Dictionary = encoded.get(PublicDictionary.FIELD,{}).get("values",{})
	var transformed: Dictionary = reply.duplicate(true)
	var count := 0
	for ref in transformed.get("fact_refs",[]):
		var original: Variant = ref.expected
		ref.expected = _intern_expected(original,table)
		count += _reference_count(ref.expected)
		var restored: Dictionary = PublicDictionary.expand_value(ref.expected,table)
		if not restored.ok or C.bytes(restored.value) != C.bytes(original): return {"ok":false,"reference_count":count,"reply":transformed}
	return {"ok":true,"reference_count":count,"reply":transformed}

static func _intern_expected(value: Variant, table: Dictionary) -> Variant:
	var bytes: String = C.bytes(value)
	for id in table:
		if C.bytes(table[id]) == bytes: return {"$p":int(id)}
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value: out[key] = _intern_expected(value[key],table)
		return out
	if value is Array:
		var out: Array = []
		for child in value: out.append(_intern_expected(child,table))
		return out
	return value

static func _reference_count(value: Variant) -> int:
	if value is Dictionary:
		if value.size() == 1 and value.has("$p"): return 1
		var total := 0
		for child in value.values(): total += _reference_count(child)
		return total
	if value is Array:
		var total := 0
		for child in value: total += _reference_count(child)
		return total
	return 0

static func _contains_internal_status(value: Variant, entries: Dictionary) -> bool:
	if value is Dictionary:
		if value.has("status_foundation") or value.get("schema_version") in ["status_catalog/v1","status_state/v1"]: return true
		if value.size() == entries.size() and entries.keys().all(func(id): return value.has(id)): return true
		for child in value.values():
			if _contains_internal_status(child,entries): return true
	elif value is Array:
		if value.size() == entries.size() and value.all(func(row): return row is Dictionary and entries.has(row.get("id"))): return true
		for child in value:
			if _contains_internal_status(child,entries): return true
	return false

static func _remove_display_packets_for_diagnostic_only(value: Variant) -> int:
	var removed := 0
	if value is Dictionary:
		if value.has("status_details"):
			value.erase("status_details")
			removed += 1
		for child in value.values(): removed += _remove_display_packets_for_diagnostic_only(child)
	elif value is Array:
		for child in value: removed += _remove_display_packets_for_diagnostic_only(child)
	return removed
