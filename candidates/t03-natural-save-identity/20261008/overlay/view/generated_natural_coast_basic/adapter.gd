extends "res://view/ai_gm_playtest/adapter.gd"
## Isolated opt-in natural-coast authority. Only unchanged transaction/cost machinery is shared.
const Source = preload("res://view/generated_natural_coast_basic/source.gd")
const GeneratedRule = preload("res://view/generated_natural_coast_basic/rule.gd")
const GeneratedResolver = preload("res://view/generated_natural_coast_basic/resolver.gd")
const Examples = preload("res://view/generated_natural_coast_basic/assessments.gd")
const SAVE_SCHEMA := "natural_coast_basic_save/v1"
const GENERATED_SAVE := "user://natural_coast_basic_v1.json"
const V3_REQUEST := "user://natural_coast_basic_request_v1.json"
const MAX_SAVE_BYTES := 24 * 1024 * 1024
const MAX_REQUEST_BYTES := 64 * 1024
const MAX_GOAL_BYTES := 4096
const CoastEngine = preload("res://view/generated_natural_coast_basic/engine.gd")
const ItemResolver = preload("res://view/generated_natural_coast_basic/item_resolver.gd")
const EntityFocus = preload("res://core/source_entities/focus.gd")
const AUTHOR := Examples.AUTHOR
const SAVE_FIELDS := ["schema_version","profile","source","renderer_profile","geometry_hash","identity","engine"]
const PROTECTED_FILENAMES := ["ai_gm_playtest_save.json","ai_gm_playtest_request.json","r24_coast_adventure_save.json","generated_adventure_v1.json","generated_adventure_v2.json","generated_inventory_v1.json","r24_coast_adventure_request.json","generated_adventure_request_v1.json"]
var source: RefCounted
var admission: Dictionary = {}
var gameplay_admission: Dictionary = {}
var last_feedback := ""

func _init(generated: Dictionary = {}, renderer_profile: String = Source.RENDERER_PROFILE) -> void:
	# A blank adapter has no authority; it cannot inherit the test adapter's world.
	engine = null
	if not generated.is_empty(): admission = _install(generated,renderer_profile)
func start_source(generated: Dictionary, renderer_profile: String = Source.RENDERER_PROFILE) -> Dictionary:
	if source != null or engine != null: return C.fail("V3_ALREADY_STARTED","请另开一张地图；现有旅程不会被替换。")
	admission = _install(generated,renderer_profile)
	return admission.duplicate(true)
func _install(generated: Dictionary, renderer_profile: String = Source.RENDERER_PROFILE) -> Dictionary:
	var candidate := Source.new()
	var checked := candidate.admit(generated,renderer_profile)
	if not checked.ok: return checked
	var next_engine := _engine_for(candidate)
	var engine_check: Dictionary = next_engine.ready()
	if not engine_check.ok: return engine_check
	_publish(candidate,next_engine,checked)
	return {"ok":true,"identity":source.identity.duplicate(true),"admission":gameplay_admission.duplicate(true)}
func _engine_for(candidate: RefCounted) -> RefCounted:
	var registry := {}
	for kind in ["move","observe","rest"]:
		var resolver := GeneratedResolver.new(candidate,kind); registry[resolver.resolver_id()] = resolver
	for kind in ["drop_item","pickup_item"]:
		var resolver := ItemResolver.new(candidate,kind); registry[resolver.resolver_id()] = resolver
	return CoastEngine.new(candidate.world,GeneratedRule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]})
func _publish(candidate: RefCounted, next_engine: RefCounted, checked: Dictionary) -> void:
	source = candidate; engine = next_engine; admission = {"ok":true}
	gameplay_admission = {"status":"exact_natural_coast_geometry_navigation_validated","identity":source.identity.duplicate(true),"start":source.world.actors.actor_player.hex.duplicate(),"component_size":source.spawn_component.size(),"navigation":checked.get("navigation",source.navigation.diagnostics).duplicate(true)}
	active_action = ""; last_action = ""; narration = ""; last_feedback = ""
	var saved: Dictionary = engine.save_data()
	for id in saved.pending: active_action = id
	var turn_ := -1
	for id in saved.receipts:
		if int(saved.receipts[id].turn) > turn_: turn_ = int(saved.receipts[id].turn); last_action = id
func ready() -> Dictionary:
	return engine.ready() if engine != null and source != null else (admission.duplicate(true) if not admission.is_empty() else C.fail("V3_SOURCE_REQUIRED","请先选择通过校验的新地形地图。"))
func state_copy() -> Dictionary: return engine.state_copy() if engine != null and source != null else {}
func action_copy() -> Dictionary: return engine.action_copy(active_action) if engine != null and source != null else {}
func request() -> Dictionary: return super.request() if ready().ok else {}
func authoritative_result() -> Dictionary: return super.authoritative_result() if ready().ok else {}
func default_save_path() -> String: return "user://natural_coast_basic_v1_%s.json" % (source.data.recipe.id if source != null else "coastal_range")
func default_request_path() -> String: return "user://natural_coast_basic_request_v1_%s.json" % (source.data.recipe.id if source != null else "coastal_range")
func restarted() -> RefCounted:
	var candidate = get_script().new()
	if ready().ok: candidate.start_source(source.data,source.identity.renderer_profile)
	return candidate
func supported_focus_kinds() -> Array: return ["tile","actor","item"]
func attention(reference: Dictionary) -> Dictionary:
	if not ready().ok: return ready()
	if not reference.is_empty() and reference.get("kind") not in supported_focus_kinds(): return C.fail("V3_FOCUS_KIND","目前可以查看旅人、地格或行礼包。")
	return super.attention(reference)
func tile_reference(hex: Array) -> Dictionary:
	if not ready().ok or hex.size() != 2 or not C.integer(hex[0]) or not C.integer(hex[1]): return {}
	var state := state_copy(); var key: String = "%d,%d" % hex
	if not state.hexes.has(key): return {}
	return {"world_id":state.world_id,"kind":"tile","id":state.hexes[key].id,"hex":hex.duplicate(),"scene_id":Source.SCENE}
func begin_intent(goal: String, focus: Dictionary = {}) -> Dictionary:
	if not ready().ok: return ready()
	if goal.to_utf8_buffer().size() > MAX_GOAL_BYTES: return C.fail("V3_INTENT_BUDGET","行动描述过长，请缩短后再提交。")
	if not focus.is_empty() and focus.get("kind") not in supported_focus_kinds(): return C.fail("V3_FOCUS_KIND","此版本只支持旅人、地格与行礼包目标。")
	var checked: Dictionary = source.validate_state(state_copy())
	if not checked.ok: return checked
	var result: Dictionary = super.begin_intent(goal,focus)
	if result.ok and C.bytes(result.request).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		engine.cancel_intent(active_action); active_action = ""
		return C.fail("V3_REQUEST_BUDGET","行动资料超出长度限制；未评估或执行。")
	return result
func sample_goal(kind: String, focus: Dictionary = {}) -> String:
	return Examples.goal(kind,focus.get("hex",state_copy().get("actors",{}).get("actor_player",{}).get("hex",[])))
func fixture_available() -> bool: return phase() == "awaiting_assessment" and Examples.build(request()).ok
func prepare_fixture() -> Dictionary:
	if phase() != "awaiting_assessment": return C.fail("V3_EXAMPLE_SCOPE","请先提交完整的探索示例。")
	var built := Examples.build(request())
	return engine.prepare_assessment(built.assessment) if built.ok else built
func import_reply(reply: Dictionary) -> Dictionary:
	if not ready().ok: return ready()
	if not C.safe(reply) or C.bytes(reply).to_utf8_buffer().size() > MAX_REQUEST_BYTES: return C.fail("V3_REPLY_BUDGET","评估资料过长或格式无效。")
	if reply.get("narration") is String and reply.narration.to_utf8_buffer().size() > 8192: return C.fail("V3_NARRATION_BUDGET","叙述过长，尚未记录。")
	if reply.get("schema_version") == "ai_gm_narration/v1": return super.import_reply(reply)
	if reply.get("schema_version") != "ai_gm_assessment/v1": return C.fail("V3_REPLY_SCHEMA","需要完整的行动评估，不能直接修改世界。")
	var provenance: Variant = reply.get("provenance")
	if not C.exact_fields(provenance,["provider","live","kind"]) or not provenance.provider is String or provenance.provider.strip_edges().is_empty() or provenance.live != false or not provenance.live is bool or provenance.kind != "model_reply": return C.fail("V3_OFFLINE_REPLY","导入评估必须标明离线来源；内置示例请使用示例按钮。")
	var assessment := reply.duplicate(true); assessment.provenance.provider = "manual_offline_assessment"
	return engine.prepare_assessment(assessment)
func movement_preview(target: Array) -> Dictionary:
	if not ready().ok: return ready()
	var state := state_copy()
	return source.navigation.plan(state,target,int(state.actors.actor_player.stamina.current))
func frozen_movement_preview() -> Dictionary:
	var action := action_copy()
	if action.get("assessment",{}).get("resolver_id") != "natural_coast_move_v1": return {}
	for branch in action.branches:
		if not branch.requires.get("move",false): continue
		var route: Array = [action.snapshot.actors.actor_player.hex.duplicate()]; var cost := 0
		for patch in branch.patches:
			if patch.type == "actor_move": route.append(patch.hex.duplicate())
			elif patch.type == "actor_pool_delta": cost -= int(patch.delta)
		return {"ok":true,"route":route,"cost":cost,"distance":route.size()-1,"turn_cost":1,"frozen":true,"source_hash":source.identity.content_hash,"geometry_hash":source.identity.geometry_hash}
	return {}
func roll_once() -> Dictionary:
	if not ready().ok: return ready()
	var checked: Dictionary = source.validate_state(state_copy())
	return super.roll_once() if checked.ok else checked
func stage() -> Dictionary:
	if not ready().ok: return ready()
	var checked: Dictionary = source.validate_state(state_copy())
	return super.stage() if checked.ok else checked
func cancel() -> Dictionary: return super.cancel() if ready().ok else ready()
func commit() -> Dictionary:
	if not ready().ok: return ready()
	var physical: Dictionary = source.validate_state(state_copy())
	if not physical.ok: return physical
	if active_action.is_empty() and not last_action.is_empty():
		var receipt: Dictionary = engine.save_data().receipts.get(last_action,{})
		if not receipt.is_empty(): return engine.commit(last_action,receipt.stage_hash)
	var result: Dictionary = super.commit()
	if result.ok: last_feedback = _committed_feedback(engine.save_data().receipts.get(last_action,{}))
	return result
func _committed_feedback(receipt: Dictionary) -> String:
	for patch in receipt.get("patches",[]):
		if patch.get("type") == "item_relocate": return "已拾回行礼包。" if patch.owner_actor_id == "actor_player" else "已把行礼包放在（%d，%d）。" % patch.hex
	var moved: Array = []; var observed := ""; var stamina_delta := 0
	for patch in receipt.get("patches",[]):
		if patch.get("type") == "actor_move": moved = patch.hex
		elif patch.get("type") == "actor_pool_delta" and patch.get("pool") == "stamina": stamina_delta += int(patch.delta)
		elif patch.get("type") == "flag_set" and patch.get("flag_id") == "last_observed_cell": observed = str(patch.value)
	if not moved.is_empty(): return "已走到（%d，%d），消耗%d点体力。" % [moved[0],moved[1],-stamina_delta]
	if source.data.cells.has(observed):
		var cell: Dictionary = source.data.cells[observed]
		var labels := {"grassland":"草原","dry_steppe":"干旱草原","desert":"荒漠","temperate_forest":"温带森林","jungle":"密林","alpine":"高山带","wetland":"湿地","ocean":"海域"}
		return "已观察（%d，%d）：%s。观察记录已保存。" % [cell.q,cell.r,labels.get(cell.biome,cell.biome)]
	if stamina_delta > 0:
		var actor: Dictionary = state_copy().actors.actor_player
		return "休息后恢复%d点体力，当前%d/%d。" % [stamina_delta,actor.stamina.current,actor.stamina.max]
	return "本次行动已提交。"
func save_data() -> Dictionary:
	return {"schema_version":SAVE_SCHEMA,"profile":Source.PROFILE,"source":source.data.duplicate(true),"renderer_profile":source.identity.renderer_profile,"geometry_hash":source.identity.geometry_hash,"identity":source.identity.duplicate(true),"engine":engine.save_data()} if ready().ok else {}
func _check_destination(path: String, request_file: bool = false) -> Dictionary:
	if path.is_empty() or (not path.get_file().begins_with("natural_coast_basic_request_" if request_file else "natural_coast_basic_save_") and path != (default_request_path() if request_file else default_save_path())): return C.fail("V3_SAVE_NAMESPACE","请使用此版本的独立文件，旧旅程不会被覆盖。")
	var destination := ProjectSettings.globalize_path(path).simplify_path()
	var counterpart := ProjectSettings.globalize_path(default_save_path() if request_file else default_request_path()).simplify_path()
	if destination == counterpart: return C.fail("V3_SAVE_NAMESPACE","请求文件和进度文件必须分开保存。")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null: return C.fail("V3_SAVE_NAMESPACE","无法验证已有文件，未覆盖。")
		if file.get_length() > MAX_SAVE_BYTES:
			file.close()
			return C.fail("V3_SAVE_NAMESPACE","无法验证已有文件，未覆盖。")
		var encoded := file.get_as_text(); var read_error: Error = file.get_error(); file.close()
		if read_error not in [OK,ERR_FILE_EOF]: return C.fail("V3_SAVE_NAMESPACE","无法完整验证已有文件，未覆盖。")
		var existing: Variant = JSON.parse_string(encoded)
		if request_file:
			if not _is_v3_request(existing): return C.fail("V3_SAVE_NAMESPACE","已有文件不是此版本的请求文件，未覆盖。")
		else:
			# Match every existing runtime signature before opening a temporary file.
			# Equal generator content does not authorize cross-distribution overwrite.
			if not C.exact_fields(existing,SAVE_FIELDS) or not C.safe(existing) or existing.schema_version != SAVE_SCHEMA or existing.profile != Source.PROFILE or not existing.source is Dictionary or not existing.identity is Dictionary or not existing.engine is Dictionary:
				return C.fail("V3_SAVE_NAMESPACE","已有文件不属于此探索版本，未覆盖。")
			if C.bytes(existing.source) != C.bytes(source.data) or existing.source.get("content_hash") != source.identity.content_hash or existing.renderer_profile != source.identity.renderer_profile or existing.geometry_hash != source.identity.geometry_hash or C.bytes(existing.identity) != C.bytes(source.identity) or not engine.matches_save_identity(existing.engine):
				return C.fail("V3_SAVE_NAMESPACE","已有进度属于另一精确运行版本，请使用原版本继续；未覆盖。")
	return {"ok":true}
static func _is_v3_request(value: Variant) -> bool:
	if not value is Dictionary or not C.safe(value) or value.get("schema_version") != "ai_gm_rebuilt/v1" or value.get("phase") not in ["assessment","narration"] or not value.get("context") is Dictionary or not value.get("contract") is Dictionary or not value.get("action_id") is String or not value.get("context_hash") is String: return false
	if value.has("state") or value.has("source") or value.has("engine") or value.has("rng") or value.has("pending") or value.has("receipts"): return false
	var tokens: PackedStringArray = value.action_id.split(":action_")
	if tokens.size() != 2 or not tokens[0].begins_with("natural_coast_basic_v1_") or not Source.valid_hash(tokens[0].trim_prefix("natural_coast_basic_v1_")) or not tokens[1].is_valid_int() or int(tokens[1]) < 1 or str(int(tokens[1])) != tokens[1]: return false
	if C.digest(value.context) != value.context_hash: return false
	if value.phase == "assessment":
		var facts: Variant = value.context.get("facts")
		if not facts is Dictionary or not facts.get("generated_source") is Dictionary: return false
		return facts.get("world_id") == tokens[0] and facts.generated_source.get("source_contract") == Source.ID and facts.generated_source.get("profile") == Source.PROFILE and facts.generated_source.get("projection_id") == Source.PROJECTION_ID and value.contract.get("calculator") == GeneratedRule.V3_ID
	var result: Variant = value.context.get("authoritative_result")
	return value.get("reply_schema") == "ai_gm_narration/v1" and result is Dictionary and result.get("schema_version") == "ai_gm_result/v1" and result.get("action_id") == value.action_id
func save_file(path: String = "") -> Dictionary:
	if not ready().ok: return ready()
	if path.is_empty(): path = default_save_path()
	var checked := _check_destination(path)
	if not checked.ok: return checked
	checked = source.validate_state(state_copy())
	if not checked.ok: return checked
	var encoded := C.bytes(save_data())
	if encoded.to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("V3_SAVE_BUDGET","进度资料超出此版本限制，原文件未改变。")
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return C.fail("SAVE_FAILED","无法写入临时进度文件。")
	file.store_string(encoded); file.flush()
	var write_error := file.get_error(); file.close()
	if write_error != OK: return C.fail("SAVE_FAILED","临时进度文件未写完，原进度文件保留。")
	if DirAccess.rename_absolute(path+".tmp",path) != OK: return C.fail("SAVE_FAILED","保存未完成，原进度文件保留。")
	return {"ok":true,"path":path}
func load_file(path: String = "") -> Dictionary:
	if path.is_empty(): path = default_save_path()
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return C.fail("LOAD_FAILED","没有找到此版本的探索进度。")
	if file.get_length() > MAX_SAVE_BYTES: file.close(); return C.fail("V3_SAVE_BUDGET","进度文件超出此版本限制。")
	var text_ := file.get_as_text(); file.close()
	return load_data(JSON.parse_string(text_))
func load_data(value: Variant) -> Dictionary:
	if source != null and phase() != "idle": return C.fail("COAST_PENDING_LOAD","请先完成当前行动，或在尚未锁定时明确取消，再读取进度；不会自动丢弃待处理行动。")
	if not C.exact_fields(value,SAVE_FIELDS) or not C.safe(value) or value.schema_version != SAVE_SCHEMA or value.profile != Source.PROFILE or not value.source is Dictionary or not value.engine is Dictionary or not value.identity is Dictionary or not value.renderer_profile is String or not Source.valid_hash(value.geometry_hash): return C.fail("V3_SAVE_SCHEMA","进度不属于此探索版本；旧版本进度请在原模式打开。")
	if C.bytes(value).to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("V3_SAVE_BUDGET","进度资料过大，现有旅程未改变。")
	if source != null and (value.source.get("content_hash") != source.identity.content_hash or value.renderer_profile != source.identity.renderer_profile): return C.fail("V3_SAVE_SOURCE","这份进度属于另一张地图，请单独打开。")
	var candidate := Source.new(); var checked := candidate.admit(value.source,value.renderer_profile)
	if not checked.ok: return checked
	if value.geometry_hash != candidate.identity.geometry_hash or C.bytes(value.identity) != C.bytes(candidate.identity): return C.fail("V3_SAVE_GEOMETRY","进度中的地图与精确地形身份不一致，请使用原版本。")
	checked = candidate.validate_state(value.engine.get("state"))
	if not checked.ok: return checked
	# Historical selected cell descriptors are immutable V3 source facts too.
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
func export_request(path: String = "") -> Dictionary:
	if path.is_empty(): path = default_request_path()
	var checked := _check_destination(path,true)
	if not checked.ok: return checked
	return super.export_request(path)
func render_state() -> Dictionary: return source.render_state(state_copy()) if ready().ok else {}
func authority_text() -> String:
	var state := state_copy()
	if state.is_empty(): return "地图尚未通过校验"
	var actor: Dictionary = state.actors.actor_player
	return "固定规则 · 回合%d · 坐标(%d,%d) · 体力%d/%d · 已观察%d次\n%s" % [state.turn,actor.hex[0],actor.hex[1],actor.stamina.current,actor.stamina.max,state.flags.observations,last_feedback]
func journal_entries() -> Array:
	if not ready().ok: return []
	var receipts: Array = engine.save_data().receipts.values(); receipts.sort_custom(func(a,b): return int(a.turn) < int(b.turn))
	var entries: Array = []
	for receipt in receipts: entries.append({"title":"第%d次行动" % int(receipt.turn),"text":receipt.goal})
	return entries

func item_reference(id: String = Source.ITEM) -> Dictionary:
	return EntityFocus.make_reference(id,state_copy()) if ready().ok else {}
