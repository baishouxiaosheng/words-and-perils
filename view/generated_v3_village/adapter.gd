extends "res://view/generated_v3_inventory/adapter.gd"
## Independent combined village and inventory save/request namespace.
## Save admission exactly reproduces placement before building an overlay.
const VillageSource = preload("res://view/generated_v3_village/source.gd")
const VillageResolver = preload("res://view/generated_v3_village/resolver.gd")
const VillageRule = preload("res://view/generated_v3_village/rule.gd")
const VillageExamples = preload("res://view/generated_v3_village/assessments.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
const VILLAGE_SAVE_SCHEMA := "generated_v3_village_inventory_save/v1"
const VILLAGE_SAVE := "user://generated_v3_village_inventory_v1.json"
const VILLAGE_REQUEST := "user://generated_v3_village_inventory_request_v1.json"
const VILLAGE_AUTHOR := VillageExamples.AUTHOR
func _install(generated: Dictionary, renderer_profile: String = Source.RENDERER_PROFILE) -> Dictionary:
	var candidate := VillageSource.new()
	var checked := candidate.admit(generated,renderer_profile)
	if not checked.ok: return checked
	var next_engine := _engine_for(candidate)
	checked = next_engine.ready()
	if not checked.ok: return checked
	_publish(candidate,next_engine,{})
	return {"ok":true,"identity":source.identity.duplicate(true),"admission":gameplay_admission.duplicate(true)}
func _engine_for(candidate: RefCounted) -> RefCounted:
	var registry := {}
	for kind in ["move","observe","rest","drop_item","pickup_item"]:
		var resolver := VillageResolver.new(candidate,kind); registry[resolver.resolver_id()] = resolver
	return GMEngine.new(candidate.world,VillageRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]})
func default_save_path() -> String: return VILLAGE_SAVE
func default_request_path() -> String: return VILLAGE_REQUEST
func supported_focus_kinds() -> Array: return ["tile","actor","item","settlement","building","road"]
func static_reference(id: String, clicked_hex: Array = []) -> Dictionary:
	return StaticFocus.make_reference(id,state_copy(),clicked_hex) if ready().ok else {}
func sample_goal(kind: String, focus: Dictionary = {}) -> String:
	return VillageExamples.goal(kind,focus.get("hex",state_copy().get("actors",{}).get("actor_player",{}).get("hex",[])))
func fixture_available() -> bool: return phase() == "awaiting_assessment" and VillageExamples.build(request()).ok
func prepare_fixture() -> Dictionary:
	if phase() != "awaiting_assessment": return C.fail("V3_VILLAGE_EXAMPLE_SCOPE","请先提交完整的探索或行囊示例。")
	var built := VillageExamples.build(request())
	return engine.prepare_assessment(built.assessment) if built.ok else built
func save_data() -> Dictionary:
	return {"schema_version":VILLAGE_SAVE_SCHEMA,"profile":VillageSource.PROFILE,"source":source.data.duplicate(true),"renderer_profile":source.identity.renderer_profile,"geometry_hash":source.identity.geometry_hash,"identity":source.identity.duplicate(true),"placement_manifest":source.placement_result.manifest.duplicate(true),"engine":engine.save_data()} if ready().ok else {}
func _check_destination(path: String, request_file: bool = false) -> Dictionary:
	if path.is_empty() or path.get_file() in PROTECTED_FILENAMES + [GENERATED_SAVE.get_file(),V3_REQUEST.get_file(),INVENTORY_SAVE.get_file(),INVENTORY_REQUEST.get_file()]: return C.fail("V3_VILLAGE_NAMESPACE","请使用村落与行囊版本的独立文件，旧旅程不会被覆盖。")
	var destination := ProjectSettings.globalize_path(path).simplify_path()
	var counterpart := ProjectSettings.globalize_path(VILLAGE_SAVE if request_file else VILLAGE_REQUEST).simplify_path()
	if destination == counterpart: return C.fail("V3_VILLAGE_NAMESPACE","请求文件和行囊进度必须分开保存。")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null or file.get_length() > MAX_SAVE_BYTES: return C.fail("V3_VILLAGE_NAMESPACE","无法验证已有文件，未覆盖。")
		var existing: Variant = JSON.parse_string(file.get_as_text()); file.close()
		if request_file:
			if not _is_village_request(existing): return C.fail("V3_VILLAGE_NAMESPACE","已有文件不是此版本的请求，未覆盖。")
		elif not existing is Dictionary or existing.get("schema_version") != VILLAGE_SAVE_SCHEMA or existing.get("profile") != VillageSource.PROFILE:
			return C.fail("V3_VILLAGE_NAMESPACE","已有文件不属于此村落与行囊版本，未覆盖。")
	return {"ok":true}
static func _is_village_request(value: Variant) -> bool:
	if not value is Dictionary or not C.safe(value) or value.get("schema_version") != "ai_gm_rebuilt/v1" or value.get("phase") not in ["assessment","narration"] or not value.get("context") is Dictionary or not value.get("contract") is Dictionary or not value.get("action_id") is String or not value.get("context_hash") is String: return false
	for field in ["state","source","engine","rng","pending","receipts"]:
		if value.has(field): return false
	var tokens: PackedStringArray = value.action_id.split(":action_")
	if tokens.size() != 2 or not tokens[0].begins_with(VillageSource.WORLD_PREFIX) or not Source.valid_hash(tokens[0].trim_prefix(VillageSource.WORLD_PREFIX)) or not tokens[1].is_valid_int() or int(tokens[1]) < 1 or str(int(tokens[1])) != tokens[1]: return false
	if C.digest(value.context) != value.context_hash: return false
	if value.phase == "assessment":
		var facts: Variant = value.context.get("facts")
		if not facts is Dictionary or not facts.get("generated_source") is Dictionary: return false
		return facts.get("world_id") == tokens[0] and facts.generated_source.get("source_contract") == Source.ID and facts.generated_source.get("profile") == VillageSource.PROFILE and facts.generated_source.get("projection_id") == VillageSource.PROJECTION_ID and value.contract.get("calculator") == VillageRule.VILLAGE_ID
	var result: Variant = value.context.get("authoritative_result")
	return value.get("reply_schema") == "ai_gm_narration/v1" and result is Dictionary and result.get("schema_version") == "ai_gm_result/v1" and result.get("action_id") == value.action_id
func load_data(value: Variant) -> Dictionary:
	if not C.exact_fields(value,SAVE_FIELDS+["placement_manifest"]) or not C.safe(value) or value.schema_version != VILLAGE_SAVE_SCHEMA or value.profile != VillageSource.PROFILE or not value.source is Dictionary or not value.engine is Dictionary or not value.identity is Dictionary or not value.placement_manifest is Dictionary or not value.renderer_profile is String or not Source.valid_hash(value.geometry_hash): return C.fail("V3_VILLAGE_SAVE_SCHEMA","进度不属于此村落与行囊版本；旧进度请在原模式打开。")
	if C.bytes(value).to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("V3_SAVE_BUDGET","进度资料过大，现有旅程未改变。")
	if source != null and (value.source.get("content_hash") != source.identity.content_hash or value.renderer_profile != source.identity.renderer_profile): return C.fail("V3_SAVE_SOURCE","这份进度属于另一张地图，请单独打开。")
	var candidate := VillageSource.new()
	var checked := candidate.admit(value.source,value.renderer_profile,value.placement_manifest)
	if not checked.ok: return checked
	if value.geometry_hash != candidate.identity.geometry_hash or C.bytes(value.identity) != C.bytes(candidate.identity): return C.fail("V3_VILLAGE_SAVE_IDENTITY","地图、精确地形、村落或行囊目录身份不一致，请使用原版本。")
	checked = candidate.validate_state(value.engine.get("state"))
	if not checked.ok: return checked
	if value.engine.get("receipts") is Dictionary:
		for receipt in value.engine.receipts.values():
			if not receipt is Dictionary: return C.fail("V3_HISTORY","行动记录无效。")
			var focus: Variant = receipt.get("attention_focus",{})
			if focus is Dictionary and focus.get("kind") == "tile":
				var found := false
				for cell in candidate.world.hexes.values():
					if cell.id == focus.get("id"): found = C.bytes(cell) == C.bytes(focus.get("facts")); break
				if not found: return C.fail("V3_HISTORY","历史地格记录与原地图不一致。")
	var next_engine := _engine_for(candidate)
	checked = next_engine.load_data(value.engine)
	if not checked.ok: return checked
	checked = candidate.validate_history(value.engine)
	if not checked.ok: return checked
	_publish(candidate,next_engine,{})
	return {"ok":true,"exact_pending":not active_action.is_empty()}

func movement_preview(target: Array) -> Dictionary:
	return VillageResolver.local_result(super.movement_preview(target))
func frozen_movement_preview() -> Dictionary:
	var result: Dictionary = super.frozen_movement_preview()
	if not result.is_empty():
		result["placement_hash"] = source.identity.placement_hash
		result["effective_navigation_hash"] = source.identity.effective_navigation_hash
	return result
