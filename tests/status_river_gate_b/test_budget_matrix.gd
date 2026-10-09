extends "res://tests/status_river_gate_b/harness.gd"
## Supplemental bounded matrix; do not add to an already running frozen batch.
## One actual Coast world, no seed search, no HTTP. Authored turn0 status store
## only; all subsequent gameplay and recent history use ordinary transactions.
const Scoped = preload("res://view/runtime_ai/scoped_engine.gd")
const PublicDictionary = preload("res://core/status_gameplay/public_dictionary.gd")
const Codec = preload("res://core/ai_gm_http/openai_chat_codec.gd")
const RuntimeController = preload("res://view/runtime_ai/controller.gd")
const Equipment = preload("res://view/generated_v3_equipment/adapter.gd")
const EquipmentRuntime = preload("res://view/generated_v3_equipment/runtime_engine.gd")
const PUBLIC_CAP = 65536
const WRAPPER_CAP = 4194304
const NPC_ID = "actor_keeper"
const EQUIPMENT_PATH = "/tmp/equipment_mouse/data/godot/app_userdata/雾岸纪事 · AI 沙盘/generated_v3_village_equipment_v1.json"
const EQUIPMENT_SHA256 = "bf0815e9b3ee265c8df90a0ace21840c02600708c9e9b669ff608e010788e3d3"
const EQUIPMENT_BYTES = 278558
const PROVENANCE = {"provider":"offline_budget_matrix", "live":false, "kind":"model_reply"}
var matrix: Array = []
var committed_history: Array = []

# Capture only the already constructed pre-admission candidate for diagnostics.
# Original65536 admission still executes unchanged. This object never submits
# or replaces its returned request. The independent plain Scoped below is truth.
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
		# Production receives the original raw scope, performs its own identical
		# pack once, records correct expanded size, and enforces the same cap.
		return super._budget(full,scoped,key)

func _initialize() -> void:
	case_name = argument("--case","budget_matrix_status")
	if not storage_safe(): finish(); return
	if case_name == "budget_matrix_status":
		status_matrix()
	elif case_name == "budget_matrix_equipment":
		equipment_matrix()
	else:
		check(false,"explicit supported supplemental budget-matrix case")
	report["budget_matrix"] = matrix
	report["real_committed_history"] = committed_history
	var blocked: Array = []
	var worst: Variant = null
	var worst_admitted: Variant = null
	for row in matrix:
		var margin: int = row.public_headroom_bytes
		worst = margin if worst == null else mini(int(worst),margin)
		if not row.transport_admitted: blocked.append(row.scenario)
		else: worst_admitted = margin if worst_admitted == null else mini(int(worst_admitted),margin)
	report["budget_matrix_summary"] = {"scenarios":matrix.size(), "worst_candidate_public_headroom_bytes":worst, "worst_admitted_public_headroom_bytes":worst_admitted, "action_block_risk_scenarios":blocked, "playable_transport_pass":completed and failures.is_empty() and blocked.is_empty(), "safety_rejection_is_not_playable_pass":true, "fixed_public_cap":PUBLIC_CAP, "existing_wrapper_cap":WRAPPER_CAP, "model_calls":0, "network_sends":0}
	finish()

func status_matrix() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	var original: Dictionary = adapter.engine.save_data()
	if not check(original.state.turn == 0 and original.pending.is_empty() and original.receipts.is_empty() and original.state.status_foundation.instances.is_empty(), "matrix authored setup starts only in a pristine real1801 world"): return
	var initial: Dictionary = original.duplicate(true)
	# Clear author provenance: these initial statuses are scenario inputs, not
	# claimed results of source-world play. Source IDs/parameters are the actual
	# registered public vials, so NPC visibility uses its real trusted policy.
	for spec in [[F.PLAYER,"poison","item_poison_vial","poison_vial"],[F.PLAYER,"flight","item_feather_vial","feather_vial"],[NPC_ID,"poison","item_poison_vial","poison_vial"]]:
		var added: Dictionary = F.Foundation.runtime().apply_status(initial.state.status_foundation,spec[1],"actor",spec[0],spec[2],F.Content.profile(spec[3]).parameters)
		if not check(added.ok,"authored initial status validates: " + str(spec[0]) + "/" + str(spec[1])): return
		initial.state.status_foundation = added.store
	var untouched: Dictionary = initial.duplicate(true)
	untouched.state.status_foundation = original.state.status_foundation.duplicate(true)
	if not check(C.bytes(untouched) == C.bytes(original), "initial author fixture changes only status store; HP stamina coordinates inventory items RNG and history remain exact"): return
	if not check(adapter.engine.load_data(initial).ok,"authored turn0 status fixture passes real engine loading/validation"): return
	report["fixture_provenance"] = {"kind":"offline_authored_initial_condition_NOT_original_world_fact", "source_world":F.identity(adapter.state_copy()), "initial_store_specs":["player poison from registered poison_vial","player flight from registered feather_vial","keeper public poison from registered poison_vial"], "player_or_item_fields_changed":false, "seed":1, "worlds_constructed":1, "history_turn_limit":2, "seed_search":false}
	if not verify_nonempty_state(adapter,0): return
	if not source_scenario(adapter,"two_actor_statuses_no_focus",{},0): return
	if not source_scenario(adapter,"two_actor_statuses_public_npc_focus",npc_reference(adapter.state_copy()),0): return
	for turn in range(1,3):
		if not commit_observe(adapter,turn): return
		if not verify_nonempty_state(adapter,turn): return
		if not source_scenario(adapter,"two_statuses_npc_focus_real_history_" + str(turn),npc_reference(adapter.state_copy()),turn): return
	completed = true

func npc_reference(state: Dictionary) -> Dictionary:
	var npc: Dictionary = state.actors[NPC_ID]
	return {"world_id":state.world_id,"kind":"actor","id":NPC_ID,"hex":npc.hex.duplicate(),"scene_id":npc.scene_id}

func verify_nonempty_state(adapter: RefCounted, turns: int) -> bool:
	var state: Dictionary = adapter.state_copy()
	var player: Dictionary = F.Details.public_details(state,state.actors.actor_player)
	var npc: Dictionary = F.Details.public_details(state,state.actors[NPC_ID])
	var ok := check(player.available and player.rows.size() == 2 and F.status(state,"poison").get("remaining") == 3-turns and F.status(state,"flight").get("remaining") == 3-turns, "matrix really carries both nonempty player statuses after " + str(turns) + " ordinary turns")
	ok = check(npc.available and npc.rows.size() == 1 and npc.rows[0].name == "中毒" and npc.rows[0].duration.remaining == 3, "registered-source NPC poison is actually public and not aged by player turns") and ok
	return ok

func source_scenario(adapter: RefCounted, label: String, focus: Dictionary, history_count: int) -> bool:
	# The same concise explicit self-antidote intention is measured each time;
	# selected NPC is attention only, never silently substituted as the target.
	var begun: Dictionary = adapter.begin_intent("【离线作者预算矩阵】使用随身解毒剂解除自己的中毒。",focus)
	if not check(begun.ok,"matrix begins real source intention: " + label): return false
	var reply: Dictionary = F.assessment(begun.request,F.Action.ID,F.source_bindings("item_status_antidote"),["delivery","effect"])
	if not check(not reply.is_empty(),"matrix reply binds exact public actor and registered antidote facts"): return false
	var full: Dictionary = adapter.engine.model_request(adapter.active_action)
	check(full.get("status_context",{}).get("active",[]).size() == 2,"actual outgoing request contains two active status entries, not empty184-byte status metadata")
	var memory: Dictionary = full.get("memory_context",{})
	check(memory.get("facts",[]).size() == history_count and not memory.get("truncated",false),"actual request has exactly the bounded real recent receipt history")
	if not focus.is_empty():
		check(full.context.attention_focus.id == NPC_ID and full.context.attention_focus.facts.get("status_details",{}).get("rows",[]).size() == 1,"actual frozen NPC focus carries its complete public poison display packet")
	var row: Dictionary = inspect_coast_request(adapter,reply,label)
	row["expected_history_records"] = history_count
	if row.transport_admitted:
		# Exercise the production reply boundary, not just a local decoder.
		# Prepare only, then explicitly cancel below; no source die or effect.
		var scope: RefCounted = Scoped.new(adapter.engine,func(): return true,PUBLIC_CAP)
		var encoded: Dictionary = scope.model_request(adapter.active_action)
		var transformed: Dictionary = F.BudgetProbe.encoded_reply(reply,encoded)
		check(transformed.ok and transformed.reference_count > 0,"matrix reply expected values genuinely use known public $p references")
		var source_before: Dictionary = adapter.engine.save_data()
		var prepared: Dictionary = scope.prepare_assessment(transformed.reply)
		check(prepared.ok and adapter.phase() == "ready_roll","actual Scope expands expected references then validates original paths and prepares the real engine")
		if prepared.ok:
			check(C.bytes(adapter.action_copy().assessment.fact_refs) == C.bytes(reply.fact_refs),"actual frozen assessment stores exact fully expanded original fact refs")
		var source_after: Dictionary = adapter.engine.save_data()
		check(C.bytes(source_before.state) == C.bytes(source_after.state) and C.bytes(source_before.rng) == C.bytes(source_after.rng) and C.bytes(source_before.receipts) == C.bytes(source_after.receipts),"encoded reply preparation performs no roll effect tick or commit")
		row["encoded_expected_reference_count"] = transformed.reference_count
		row["real_scope_prepare_ok"] = prepared.ok
		row["source_prepare_only_no_roll_or_commit"] = true
	matrix.append(row)
	F.budget_observations.append(row.duplicate(true))
	# Continue collecting all four bounded rows even if one is safely refused.
	# Its admission failure is still a hard playable-transport assertion failure.
	check(row.transport_admitted,"PLAYABILITY_ACTION_BLOCK_RISK: nonempty " + label + " must be admitted under the unchanged65536 public cap; CONTEXT_BUDGET alone is not playable success")
	var before_cancel: Dictionary = adapter.engine.save_data()
	if not check(adapter.cancel().ok,"explicitly cancel diagnostic source intention without rolling"): return false
	var after_cancel: Dictionary = adapter.engine.save_data()
	check(C.bytes(before_cancel.state) == C.bytes(after_cancel.state) and C.bytes(before_cancel.rng) == C.bytes(after_cancel.rng) and C.bytes(before_cancel.receipts) == C.bytes(after_cancel.receipts),"matrix measurement/cancellation does not apply antidote or alter RNG/history")
	return true

func commit_observe(adapter: RefCounted, turn: int) -> bool:
	var begun: Dictionary = adapter.begin_intent("【离线作者预算矩阵】观察南潮海岸和旧灯线索，真实记录第" + str(turn) + "次行动。",npc_reference(adapter.state_copy()))
	if not check(begun.ok,"recent history comes from real ordinary begin_intent"): return false
	var reply: Dictionary = F.assessment(begun.request,"coast_observe",{"actor_id":F.PLAYER},["observe"])
	if not check(not reply.is_empty() and adapter.import_reply(reply).ok,"explicit offline observation assessment passes original pipeline"): return false
	check(adapter.action_copy().checks.size() == 1 and adapter.action_copy().checks[0].method == "direct_success","history observation uses real fixed safe-direct policy, no winning-seed selection")
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok,"recent observation rolls once, stages and commits through real engine"): return false
	var receipts: Dictionary = adapter.engine.save_data().receipts
	check(receipts.size() == turn and receipts.has(result.receipt.action_id),"recent history count binds actual committed receipts")
	committed_history.append({"action_id":result.receipt.action_id,"receipt_hash":result.receipt.receipt_hash,"turn":result.receipt.turn,"resolver":"coast_observe","provenance":result.receipt.provenance})
	return true

func inspect_coast_request(adapter: RefCounted, reply: Dictionary, label: String) -> Dictionary:
	var engine: RefCounted = adapter.engine
	var before := C.digest(engine.save_data())
	var full: Dictionary = engine.model_request(adapter.active_action)
	var scope: RefCounted = Scoped.new(engine,func(): return true,PUBLIC_CAP)
	var admitted: Dictionary = scope.model_request(adapter.active_action)
	var diagnostic: RefCounted = DiagnosticScope.new(engine,func(): return true,PUBLIC_CAP)
	var mirrored: Dictionary = diagnostic.model_request(adapter.active_action)
	var candidate: Dictionary = diagnostic.candidate
	var raw: Dictionary = diagnostic.raw_candidate
	check(diagnostic.capture_error.is_empty() and C.bytes(mirrored) == C.bytes(admitted) and C.bytes(scope.last_metrics) == C.bytes(diagnostic.last_metrics) and C.bytes(scope.last_error) == C.bytes(diagnostic.last_error),"pack-aware diagnostic capture has exactly production admission/errors/encoded metrics")
	check(not candidate.is_empty(),"real scope produced an intact encoded candidate")
	var expanded: Dictionary = PublicDictionary.expand(candidate)
	if not check(expanded.ok and C.bytes(expanded.get("request")) == C.bytes(raw),"encoded matrix request expands byte-exactly to the original unencoded scope"):
		return {"scenario":label,"transport_admitted":false,"public_headroom_bytes":PUBLIC_CAP-C.bytes(candidate).to_utf8_buffer().size(),"source_error":expanded,"action_block_risk":"dictionary expansion or original-scope equivalence failed"}
	var semantic: Dictionary = expanded.request
	check(candidate.has(PublicDictionary.FIELD) and F.BudgetProbe._reference_count(candidate) > 0 and not PublicDictionary._has_ref(semantic),"new-status matrix must actually use and completely decode the public dictionary")
	var row: Dictionary = measure_candidate(candidate,label,not admitted.is_empty())
	row["full_public_bytes"] = C.bytes(full).to_utf8_buffer().size()
	row["scope_metrics"] = scope.last_metrics.duplicate(true)
	row["source_error"] = scope.last_error.duplicate(true)
	row["capture_scope"] = "original raw scope plus pure pack reproduction; plain Scoped.new(...,65536) remains admission authority"
	row["unencoded_scope_sha256"] = C.digest(raw)
	row["dictionary"] = F.BudgetProbe.dictionary_stats(candidate,semantic)
	check(row.dictionary.expanded_public_bytes >= row.dictionary.encoded_public_bytes and row.dictionary.saved_public_bytes > 0,"A/B retains full original scoped bytes and records strictly smaller encoded request")
	check(scope.last_metrics.get("lossless_public_dictionary",{}).get("expanded_public_bytes") == row.dictionary.expanded_public_bytes and scope.last_metrics.get("lossless_public_dictionary",{}).get("saved_public_bytes") == row.dictionary.saved_public_bytes,"production metadata reports actual unencoded/encoded A/B byte counts")
	if admitted.is_empty():
		check(scope.last_error.get("code") == "CONTEXT_BUDGET" and scope.last_error.get("budget_bytes") == PUBLIC_CAP and scope.last_error.get("used_bytes") == row.scoped_public_bytes and not scope._sent_requests.has(adapter.active_action),"blocked row remains original encoded CONTEXT_BUDGET with no admitted cache or send")
		row["wrapper_is_admissible_request"] = false
		row["action_block_risk"] = "Encoded public65536 still prevents live assessment; offline progress does not establish playability"
	else:
		check(row.scoped_public_bytes <= PUBLIC_CAP and C.bytes(admitted) == C.bytes(candidate),"accepted encoded request is exact within unchanged public65536")
		row["action_block_risk"] = "none observed at this measured scene"
	var full_visible: Dictionary = full.context.facts.duplicate(true)
	full_visible.attention_focus = full.context.attention_focus
	var visible: Dictionary = semantic.context.facts.duplicate(true)
	visible.attention_focus = semantic.context.attention_focus
	for ref in reply.fact_refs:
		var original: Dictionary = C.pointer(full_visible,ref.path)
		var selected: Dictionary = C.pointer(visible,ref.path)
		check(original.ok and selected.ok and C.bytes(original.get("value")) == C.bytes(ref.expected) and C.bytes(selected.get("value")) == C.bytes(ref.expected),"decoded source fact remains complete and exact at original path: " + str(ref.path))
	for field in ["attention_focus","goal","actor_id","text_priority"]:
		check(C.bytes(candidate.context.get(field)) == C.bytes(raw.context.get(field)) and C.bytes(candidate.context.get(field)) == C.bytes(full.context.get(field)),"encoded request keeps literal context unchanged: " + field)
	for field in ["schema_version","phase","action_id","state_version","context_hash","transport_scope"]:
		check(C.bytes(candidate.get(field)) == C.bytes(raw.get(field)),"encoded request keeps literal protocol header unchanged: " + field)
	for collection in ["actors","items"]:
		check(C.bytes(semantic.context.facts.get(collection)) == C.bytes(full.context.facts.get(collection)),"decoded whole " + collection + " facts match original without omissions")
	for field in ["contract","status_context","memory_context","context_hash"]:
		check(C.bytes(semantic.get(field)) == C.bytes(full.get(field)),"decoded complete " + field + " matches original")
	check(not F.BudgetProbe._contains_internal_status(full,F.Foundation.runtime().entries) and not F.BudgetProbe._contains_internal_status(candidate,F.Foundation.runtime().entries) and not F.BudgetProbe._contains_internal_status(semantic,F.Foundation.runtime().entries),"full/encoded/decoded requests contain no full168 catalog or internal status store")
	check(C.digest(engine.save_data()) == before,"pack/expand/budget diagnostics preserve authoritative engine pending RNG and history")
	return row

func encode_request(request: Dictionary) -> Dictionary:
	return Codec.encode(request,{"model":"offline-budget-matrix"},PROVENANCE,RuntimeController.CONTRACT)

func byte_pair(request: Dictionary) -> Dictionary:
	return {"public":C.bytes(request).to_utf8_buffer().size(),"wrapper":C.bytes(encode_request(request)).to_utf8_buffer().size()}

func measure_candidate(candidate: Dictionary, label: String, admitted: bool) -> Dictionary:
	var intact_hash := C.digest(candidate)
	var expanded: Dictionary = PublicDictionary.expand(candidate)
	if not check(expanded.ok,"candidate can be losslessly expanded before diagnostic measurement"):
		return {"scenario":label,"transport_admitted":false,"public_headroom_bytes":PUBLIC_CAP-C.bytes(candidate).to_utf8_buffer().size(),"source_error":expanded}
	var semantic: Dictionary = expanded.request
	var uses_dictionary: bool = candidate.has(PublicDictionary.FIELD)
	var bytes: Dictionary = byte_pair(candidate)
	var unencoded_bytes: Dictionary = byte_pair(semantic)
	var row: Dictionary = {"scenario":label,"transport_admitted":admitted,"scoped_public_bytes":bytes.public,"wrapper_bytes":bytes.wrapper,"expanded_scoped_public_bytes":unencoded_bytes.public,"expanded_scoped_wrapper_bytes":unencoded_bytes.wrapper,"public_headroom_bytes":PUBLIC_CAP-int(bytes.public),"unencoded_public_headroom_bytes":PUBLIC_CAP-int(unencoded_bytes.public),"unencoded_would_be_admitted":unencoded_bytes.public<=PUBLIC_CAP,"wrapper_headroom_bytes":WRAPPER_CAP-int(bytes.wrapper),"wrapper_exceeds_65536_observation":bytes.wrapper > PUBLIC_CAP,"wrapper_is_admissible_request":admitted,"candidate_sha256":intact_hash,"expanded_candidate_sha256":C.digest(semantic),"wrapper_sha256":C.digest(encode_request(candidate)),"network_sends":0,"model_calls":0,"cap_changed":false,"payload_trimmed_to_fit":false,"active_status_count":semantic.get("status_context",{}).get("active",[]).size(),"history_records":semantic.get("memory_context",{}).get("facts",[]).size(),"dictionary":F.BudgetProbe.dictionary_stats(candidate,semantic),"byte_diagnostics":{}}
	check(bytes.wrapper <= WRAPPER_CAP,"complete encoded Codec envelope obeys existing4MiB wrapper cap")
	var body: Dictionary = encode_request(candidate)
	check(body.messages[1].content == C.bytes(candidate),"Codec carries complete exact encoded request")
	if uses_dictionary:
		check(body.messages[0].content.contains(PublicDictionary.SCHEMA),"Codec explains the actual public dictionary and expected-value reference contract")
	# Diagnostics begin from expanded detached facts, then use the same packing
	# algorithm. Never edit a live dictionary table or reuse an invalid hash.
	for field in ["transport_scope","status_context","memory_context"]:
		var detached: Dictionary = semantic.duplicate(true)
		detached.erase(field)
		var baseline: Dictionary = diagnostic_pair(detached,uses_dictionary)
		if check(baseline.ok,"detached " + field + " baseline repacks and expands exactly"):
			row.byte_diagnostics[field] = {"expanded_section_json_bytes":C.bytes(semantic.get(field,{})).to_utf8_buffer().size(),"public_increment_bytes":int(bytes.public)-int(baseline.public),"wrapper_increment_bytes":int(bytes.wrapper)-int(baseline.wrapper),"unencoded_public_increment_bytes":int(unencoded_bytes.public)-int(baseline.unencoded_public),"diagnostic_only_not_send_candidate":true,"expanded_then_repacked":true}
	var no_display: Dictionary = semantic.duplicate(true)
	var packet_count: int = F.BudgetProbe._remove_display_packets_for_diagnostic_only(no_display)
	var display_baseline: Dictionary = diagnostic_pair(no_display,uses_dictionary)
	if check(display_baseline.ok,"detached display baseline repacks with a new valid dictionary hash"):
		row.byte_diagnostics["status_details"] = {"packet_count":packet_count,"public_increment_bytes":int(bytes.public)-int(display_baseline.public),"wrapper_increment_bytes":int(bytes.wrapper)-int(display_baseline.wrapper),"unencoded_public_increment_bytes":int(unencoded_bytes.public)-int(display_baseline.unencoded_public),"diagnostic_only_not_send_candidate":true,"expanded_then_repacked":true}
	if semantic.has("memory_context"):
		var no_history: Dictionary = semantic.duplicate(true)
		no_history.memory_context.facts = []
		no_history.memory_context.beliefs = []
		no_history.memory_context.used_record_bytes = 0
		no_history.memory_context.truncated = false
		var history_baseline: Dictionary = diagnostic_pair(no_history,uses_dictionary)
		if check(history_baseline.ok,"detached history-record baseline repacks losslessly"):
			row.byte_diagnostics["history_records_only"] = {"records":semantic.memory_context.get("facts",[]).size(),"public_increment_bytes":int(bytes.public)-int(history_baseline.public),"wrapper_increment_bytes":int(bytes.wrapper)-int(history_baseline.wrapper),"unencoded_public_increment_bytes":int(unencoded_bytes.public)-int(history_baseline.unencoded_public),"diagnostic_only_not_send_candidate":true,"expanded_then_repacked":true}
	if semantic.has("status_context"):
		var no_active: Dictionary = semantic.duplicate(true)
		no_active.status_context.active = []
		no_active.status_context.omitted = 0
		no_active.status_context.truncated = false
		var active_baseline: Dictionary = diagnostic_pair(no_active,uses_dictionary)
		if check(active_baseline.ok,"detached active-entry baseline repacks losslessly"):
			row.byte_diagnostics["active_status_entries_only"] = {"records":semantic.status_context.active.size(),"public_increment_bytes":int(bytes.public)-int(active_baseline.public),"wrapper_increment_bytes":int(bytes.wrapper)-int(active_baseline.wrapper),"unencoded_public_increment_bytes":int(unencoded_bytes.public)-int(active_baseline.unencoded_public),"diagnostic_only_not_send_candidate":true,"expanded_then_repacked":true}
	check(C.digest(candidate) == intact_hash,"decoded/repacked marginal diagnostics preserve original actual encoded request")
	return row

func diagnostic_pair(semantic: Dictionary, use_dictionary: bool) -> Dictionary:
	return F.BudgetProbe.diagnostic_bytes(semantic,use_dictionary,{"model":"offline-budget-matrix"},RuntimeController.CONTRACT,PROVENANCE)

func equipment_matrix() -> void:
	# Separate optional process. Never sends original equipment through Coast or
	# installs status state. It measures the real saved profile with its own API.
	var path := argument("--equipment-path",EQUIPMENT_PATH)
	if not check(path == EQUIPMENT_PATH and FileAccess.file_exists(path),"only the exact provenance-pinned original equipment file may be read"): return
	var input := FileAccess.open(path,FileAccess.READ)
	if not check(input != null and input.get_length() == EQUIPMENT_BYTES,"original equipment byte size matches accepted provenance"): return
	if not check(FileAccess.get_sha256(path) == EQUIPMENT_SHA256,"original equipment SHA256 matches accepted provenance"): return
	var parsed: Variant = JSON.parse_string(input.get_as_text())
	input.close()
	if not check(parsed is Dictionary,"original equipment input is a valid JSON object"): return
	var adapter: RefCounted = Equipment.new()
	if not check(adapter.load_data(parsed).ok and C.bytes(adapter.save_data()) == C.bytes(parsed),"actual Equipment adapter loads original complete saved profile byte-exact"): return
	var state: Dictionary = adapter.state_copy()
	if not check(not state.has("status_foundation") and not state.has("status_gameplay") and adapter.phase() == "idle","original equipment is no-foundation idle profile, not a status migration fixture"): return
	var original_engine: Dictionary = adapter.engine.save_data()
	var focus: Dictionary = adapter.tile_reference(state.actors.actor_player.hex)
	var begun: Dictionary = adapter.begin_intent(adapter.sample_goal("observe",focus),focus)
	if not check(begun.ok,"original equipment builds its own bounded observation request"): return
	var full: Dictionary = adapter.engine.model_request(adapter.active_action)
	var runtime: RefCounted = EquipmentRuntime.new(adapter.engine,func(): return true,PUBLIC_CAP)
	var request: Dictionary = runtime.model_request(adapter.active_action)
	check(not request.is_empty(),"PLAYABILITY_ACTION_BLOCK_RISK: exact original equipment profile must retain admission under its65536 cap")
	if request.is_empty():
		matrix.append({"scenario":"original_equipment_own_runtime","transport_admitted":false,"public_headroom_bytes":PUBLIC_CAP-int(runtime.last_metrics.get("sent_public_bytes",0)),"source_error":runtime.last_error,"scope_metrics":runtime.last_metrics,"action_block_risk":"original equipment profile request no longer admitted"})
	else:
		check(C.bytes(request) == C.bytes(full),"EquipmentRuntime preserves exact existing public request bytes without Coast neighborhood reinterpretation")
		check(not PublicDictionary.enabled(full) and not request.has(PublicDictionary.FIELD),"old equipment branch never enables or inserts new-status dictionary encoding")
		check(not contains_status_packet(request),"no-foundation original equipment request gains no status store/context/display packet")
		var row: Dictionary = measure_candidate(request,"original_equipment_own_runtime",true)
		row["scope_metrics"] = runtime.last_metrics.duplicate(true)
		row["original_input_sha256"] = EQUIPMENT_SHA256
		row["original_profile"] = parsed.get("profile","")
		check(row.scoped_public_bytes <= PUBLIC_CAP and runtime.last_metrics.get("profile_budget_bytes") == PUBLIC_CAP,"equipment immutable profile cap remains65536")
		matrix.append(row)
	if not check(adapter.cancel().ok,"cancel equipment diagnostic intent without gameplay commit"): return
	var after: Dictionary = adapter.engine.save_data()
	check(C.bytes(after.state) == C.bytes(original_engine.state) and C.bytes(after.rng) == C.bytes(original_engine.rng) and C.bytes(after.receipts) == C.bytes(original_engine.receipts),"equipment diagnostic leaves original facts RNG receipts unchanged")
	check(FileAccess.get_sha256(path) == EQUIPMENT_SHA256,"original equipment disk file remains untouched")
	report["equipment_scope"] = "Read-only original save plus temporary in-memory begin/cancel only; no gameplay commit, migration, save or baseline byte-size guess"
	completed = true

func contains_status_packet(value: Variant) -> bool:
	if value is Dictionary:
		for key in ["status_foundation","status_gameplay","status_context","status_details"]:
			if value.has(key): return true
		for child in value.values():
			if contains_status_packet(child): return true
	elif value is Array:
		for child in value:
			if contains_status_packet(child): return true
	return false
