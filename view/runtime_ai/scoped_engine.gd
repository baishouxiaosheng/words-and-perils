extends RefCounted
## A transport-only public projection. The underlying frozen full context hash,
## fact values, calculator and mutation authority are never replaced.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicDictionary=preload("res://core/status_gameplay/public_dictionary.gd")
const Budget = preload("res://core/ai_gm_http/request_budget.gd")
const MAX_REQUEST_BYTES := Budget.LEGACY_BYTES # Historical API compatibility.
var _request_budget: Variant = MAX_REQUEST_BYTES
const DIRECTIONS := [[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]
var engine: RefCounted
var permitted: Callable
var last_error: Dictionary = {}
var last_metrics: Dictionary = {}
var _sent_requests: Dictionary = {}
var expanded_paths: Array = []

func _init(source: RefCounted, guard: Callable, budget_bytes: Variant = MAX_REQUEST_BYTES) -> void:
	engine = source; permitted = guard
	# This transport instance freezes one explicit budget; config edits cannot
	# rewrite an already admitted request or its response validation.
	_request_budget = budget_bytes
func state_copy() -> Dictionary: return engine.state_copy()
func action_copy(id: String) -> Dictionary: return engine.action_copy(id)
func model_request(id: String) -> Dictionary:
	if not permitted.call(): return {}
	var full: Dictionary = engine.model_request(id)
	if full.is_empty(): return {}
	var scoped: Dictionary = full.duplicate(true)
	var facts: Dictionary = full.context.facts
	var cells: Dictionary = {}
	var scene_cells: Dictionary = {}
	var acting_scene: String = facts.actors.get(full.context.actor_id, {}).get("scene_id", "")
	# All actors/items/flags/story anchors remain exact, so distant named people,
	# inventory capabilities and relevant fixed bounds are never guessed away.
	var negotiated: bool = full.get("contract",{}).has("control_reply")
	for actor in facts.actors.values():
		if negotiated and actor.id!=full.context.actor_id: _include_scene_cell(cells,scene_cells,facts,String(actor.get("scene_id","")),actor.get("hex",[]))
		else: _include_scene_neighborhood(cells,scene_cells,facts,String(actor.get("scene_id","")),actor.get("hex",[]))
	for item in facts.items.values():
		if negotiated: _include_scene_cell(cells,scene_cells,facts,String(item.get("scene_id",acting_scene)),item.get("hex",[]))
		else: _include_scene_neighborhood(cells,scene_cells,facts,String(item.get("scene_id",acting_scene)),item.get("hex",[]))
	# The plural settlement map contains the same complete site as this historical
	# compatibility alias. Omit the whole duplicate object, disclose it explicitly.
	if negotiated: scoped.context.facts.erase("settlement")
	var focus: Dictionary = full.context.attention_focus
	var focus_facts: Dictionary = focus.get("facts", {})
	var focus_scene: String = focus_facts.get("entity", {}).get("scene_id", focus_facts.get("supporting_cell", {}).get("scene_id", focus_facts.get("scene_id", acting_scene)))
	_include_scene_neighborhood(cells, scene_cells, facts, focus_scene, focus.get("hex", []))
	var entity: Dictionary = focus.get("facts", {}).get("entity", {})
	for hex in entity.get("public_facts", {}).get("support_hexes", []): _include_scene_neighborhood(cells, scene_cells, facts, String(entity.get("scene_id", focus_scene)), hex)
	for changed_entity in facts.get("environment_entities", {}).values(): _include_scene_neighborhood(cells, scene_cells, facts, String(changed_entity.get("scene_id", acting_scene)), changed_entity.get("hex", []))
	for target in facts.get("passage_targets",{}).values():
		for hex in target.endpoints: _include_scene_cell(cells,scene_cells,facts,target.scene_id,hex)
	# Authored settlements/districts remain whole, including approach anchors.
	for site in facts.get("settlements",{}).values():
		for hex in site.interior_hexes + [site.gate_inside_hex,site.gate_outside_hex]:
			if full.get("contract",{}).has("control_reply"): _include_scene_cell(cells,scene_cells,facts,site.scene_id,hex)
			else: _include_scene_neighborhood(cells,scene_cells,facts,site.scene_id,hex)
	# Authored entrance and paired return records remain whole. Their source and
	# landing cells are mandatory evidence even when the destination is another
	# scene far outside the attention neighborhood.
	for entrance in facts.get("scene_transitions", {}).values():
		_include_scene_neighborhood(cells, scene_cells, facts, String(entrance.get("source_scene_id", "")), entrance.get("source_hex", []))
		_include_scene_neighborhood(cells, scene_cells, facts, String(entrance.get("destination_scene_id", "")), entrance.get("landing_hex", []))
	# Coordinate destinations in explicit player text are included even far from
	# attention. A quoted cell ID is data, never a command or permission.
	var coordinates := RegEx.new()
	coordinates.compile("(?:[（(\\[]\\s*)?(-?[0-9]+)\\s*[,，]\\s*(-?[0-9]+)(?:\\s*[）)\\]])?")
	for matched in coordinates.search_all(String(full.context.goal)):
		_include_scene_neighborhood(cells, scene_cells, facts, acting_scene, [int(matched.get_string(1)), int(matched.get_string(2))])
	scoped.context.facts.hexes = cells
	if facts.has("scene_hexes"): scoped.context.facts.scene_hexes = scene_cells
	# Scene membership arrays can be large. Entire scene objects are omitted,
	# never field-truncated; no installed resolver requires a scene-object ref.
	var scenes_required := false
	for schema in full.get("contract", {}).get("action_schemas", {}).values():
		for required_path in schema.get("required_fact_paths", []):
			if String(required_path).begins_with("/scenes"): scenes_required = true
			elif String(required_path).begins_with("/hexes/") and not String(required_path).contains("<"):
				var exact_key: String = String(required_path).trim_prefix("/hexes/").split("/")[0]
				if facts.hexes.has(exact_key): cells[exact_key] = facts.hexes[exact_key].duplicate(true)
	scoped.context.facts.scenes = facts.scenes.duplicate(true) if scenes_required else {}
	for path in expanded_paths:
		if not path is String or not preload("res://core/ai_gm_rebuilt/creative_control.gd").allowed_path(path): continue
		var tokens: PackedStringArray = path.split("/")
		var found := C.pointer(facts,path)
		if not found.ok: continue
		if tokens.size()==3:
			if not scoped.context.facts.has(tokens[1]): scoped.context.facts[tokens[1]]={}
			scoped.context.facts[tokens[1]][tokens[2]]=found.value
		elif tokens.size()==4:
			if not scoped.context.facts.has(tokens[1]): scoped.context.facts[tokens[1]]={}
			if not scoped.context.facts[tokens[1]].has(tokens[2]): scoped.context.facts[tokens[1]][tokens[2]]={}
			scoped.context.facts[tokens[1]][tokens[2]][tokens[3]]=found.value
		else: scoped.context.facts[tokens[1]]=found.value
	# Do not repeat the selection prose here: the scope policy/omissions below
	# describe the same projection. Diagnostic metadata also spends the byte cap.
	scoped["transport_scope"] = {"schema_version":"public_transport_scope/v1", "authority_context_hash":full.context_hash,
		"full_public_request_sha256":C.digest(full), "whole_world_retained_by_engine":true,
		"omitted_duplicate_roots":["settlement"] if negotiated and facts.has("settlement") else [], "surrounding_cell_policy":"acting actor/attention/explicit coordinates get neighborhoods; other actors/items/sites retain exact cells, with bounded public expansion" if negotiated else "legacy all-object neighborhoods", "included_scene_hexes":_scene_counts(scene_cells), "total_scene_hexes":_scene_counts(facts.get("scene_hexes", {})), "included_hexes":cells.size(), "total_hexes":facts.hexes.size(), "omitted_scene_objects":0 if scenes_required else facts.scenes.size(),
		"omission_is_not_absence":true, "fact_reference_policy":"Only cite exact values visible in context.facts or /attention_focus. Omitted geometry is checked by the authoritative resolver. If necessary evidence is absent and control_reply is negotiated, use NEEDS_PUBLIC_CONTEXT; otherwise return UNSUPPORTED_INTENT. Never guess."}
	return _budget(full, scoped, id)

func narration_request(id: String) -> Dictionary:
	if not permitted.call(): return {}
	var request: Dictionary = engine.narration_request(id)
	# Live narration is only ever based on an already committed receipt.
	if request.is_empty() or request.context.get("provisional_until_commit", true): return {}
	return _budget(request, request, id + ":narration")

func _budget(full: Dictionary, scoped: Dictionary, key: String) -> Dictionary:
	var expanded_size:int=C.bytes(scoped).to_utf8_buffer().size()
	var interned:=false
	if PublicDictionary.enabled(full):
		var packed:Dictionary=PublicDictionary.pack(scoped)
		if not packed.ok:last_error=packed;_sent_requests.erase(key);return {}
		scoped=packed.request;interned=packed.packed
	var size := C.bytes(scoped).to_utf8_buffer().size()
	last_metrics = {"full_public_bytes":C.bytes(full).to_utf8_buffer().size(), "sent_public_bytes":size, "budget_bytes":_request_budget,
		"token_bound_utf8_bytes":size, "token_estimate_is_exact":false}
	if interned:last_metrics["lossless_public_dictionary"]={"schema_version":PublicDictionary.SCHEMA,"expanded_public_bytes":expanded_size,"saved_public_bytes":expanded_size-size,"intent_focus_literal_history_status_equivalent":true}
	var checked := Budget.validate(_request_budget)
	if not checked.ok:
		last_error = checked; _sent_requests.erase(key); return {}
	if size > int(_request_budget):
		last_error = Budget.exceeded(size, int(_request_budget))
		_sent_requests.erase(key); return {}
	last_error = {}; _sent_requests[key] = scoped.duplicate(true)
	return scoped

static func _scene_counts(scenes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in scenes: result[id] = scenes[id].size()
	return result
static func _include_scene_cell(outer: Dictionary, interiors: Dictionary, facts: Dictionary, scene_id: String, hex: Array) -> void:
	if hex.size()!=2 or not C.integer(hex[0]) or not C.integer(hex[1]): return
	if facts.get("scene_hexes",{}).has(scene_id):
		if not interiors.has(scene_id): interiors[scene_id]={}
		_include_cell(interiors[scene_id],facts.scene_hexes[scene_id],hex)
	else: _include_cell(outer,facts.hexes,hex)

static func _include_scene_neighborhood(outer: Dictionary, interiors: Dictionary, facts: Dictionary, scene_id: String, hex: Variant) -> void:
	var all_interiors: Dictionary = facts.get("scene_hexes", {})
	if all_interiors.has(scene_id):
		if not interiors.has(scene_id): interiors[scene_id] = {}
		_include_neighborhood(interiors[scene_id], all_interiors[scene_id], hex)
	else:
		# Legacy scenes use the existing outer map; never substitute an outer cell
		# for an explicitly registered interior cell at the same axial coordinate.
		_include_neighborhood(outer, facts.hexes, hex)

static func _include_neighborhood(cells: Dictionary, source: Dictionary, hex: Variant) -> void:
	if not hex is Array or hex.size() != 2 or not C.integer(hex[0]) or not C.integer(hex[1]): return
	_include_cell(cells, source, hex)
	for delta in DIRECTIONS: _include_cell(cells, source, [hex[0] + delta[0], hex[1] + delta[1]])
static func _include_cell(cells: Dictionary, source: Dictionary, hex: Array) -> void:
	var key := "%d,%d" % [hex[0], hex[1]]
	if source.has(key): cells[key] = source[key].duplicate(true)

func prepare_assessment(reply: Variant) -> Dictionary:
	if not permitted.call(): return C.fail("STALE_CONTEXT", "当前场景或引擎已改变，评估未应用。")
	if not reply is Dictionary: return C.fail("INVALID_ASSESSMENT", "评估必须是结构化对象。")
	var request: Dictionary = _sent_requests.get(reply.get("action_id", ""), {})
	if request.is_empty(): return C.fail("NO_REQUEST", "没有对应的公开请求。")
	if request.has(PublicDictionary.FIELD):
		var restored:Dictionary=PublicDictionary.expand(request)
		if not restored.ok:return restored
		var normalized:Dictionary=reply.duplicate(true)
		var expanded_public:Dictionary=restored.request.context.facts.duplicate(true)
		expanded_public.attention_focus=restored.request.context.attention_focus
		var remaining_expected_bytes:int=524288
		if normalized.get("fact_refs") is Array:
			for ref in normalized.fact_refs:
				if not ref is Dictionary or not ref.has("expected"):return C.fail("INVALID_FACT_REF","Expected public value required")
				if not ref.get("path") is String:return C.fail("INVALID_FACT_REF","Exact public path required")
				var actual:Dictionary=C.pointer(expanded_public,ref.path)
				if not actual.ok:return C.fail("OUT_OF_SCOPE_FACT","Original public fact path does not exist")
				var actual_bytes:int=C.bytes(actual.value).to_utf8_buffer().size()
				var expanded:Dictionary=PublicDictionary.expand_value(ref.expected,request[PublicDictionary.FIELD].values,0,mini(actual_bytes,remaining_expected_bytes))
				if not expanded.ok:return expanded
				if C.bytes(expanded.value)!=C.bytes(actual.value):return C.fail("OUT_OF_SCOPE_FACT","Expanded reference is not the exact public fact")
				remaining_expected_bytes-=int(expanded.expanded_bytes)
				ref.expected=expanded.value
		reply=normalized;request=restored.request
	if reply.get("schema_version") is String and reply.schema_version=="ai_gm_control/v1":
		var feedback: Dictionary=engine.prepare_assessment(reply)
		if feedback.get("code")=="NEEDS_PUBLIC_CONTEXT":
			var union: Array=expanded_paths.duplicate()
			for path in reply.context_paths:
				if not path in union: union.append(path)
			if union.size()>32: return C.fail("CONTEXT_BUDGET","This request already used its32 whole-public-fact expansion slots; nothing was silently dropped.")
		return feedback
	if not reply.get("fact_refs") is Array: return C.fail("INVALID_FACT_REF", "事实引用必须是数组。")
	var public: Dictionary = request.context.facts.duplicate(true)
	public.attention_focus = request.context.attention_focus
	for ref in reply.get("fact_refs", []):
		if not ref is Dictionary or not ref.get("path") is String: return C.fail("INVALID_FACT_REF", "事实引用格式无效。")
		var found := C.pointer(public, ref.path)
		if not found.ok or C.bytes(found.value) != C.bytes(ref.get("expected")): return C.fail("OUT_OF_SCOPE_FACT", "评估引用了未发送、猜测或截断的事实；未应用。")
	return engine.prepare_assessment(reply)
func validate_narration_reply(reply: Variant) -> Dictionary:
	if not permitted.call(): return C.fail("STALE_CONTEXT", "当前场景已改变，叙事未应用。")
	return engine.validate_narration_reply(reply)
