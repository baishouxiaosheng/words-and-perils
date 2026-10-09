extends RefCounted
## Independent status-entry facade. Frozen status authority owns every action,
## journal, required public record, draw, stage token, receipt and save schema.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Core = preload("res://view/actor_status_profile_v1/adapter.gd")
const Source = preload("res://view/actor_status_profile_v1/source.gd")
const ActorProjection = preload("res://view/actor_status_profile_v1/projection.gd")
const Policy = preload("res://view/actor_action_profile_v2/policy.gd")
const RenderSource = preload("res://view/actor_status_entry_v1/render_source.gd")
const Focus = preload("res://core/focus_contract.gd")
const ItemFocus = preload("res://core/source_entities/focus.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const NarrationLog = preload("res://view/runtime_ai/narration_log.gd")
const StatusDetails = preload("res://view/status_gameplay/details.gd")
const Domain = preload("res://view/actor_status_profile_v1/domain.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const SAVE_PATH = "user://actor_status_v1.json"
const REQUEST_PATH = "user://actor_status_v1_request.json"
const INTENT_REQUEST_PATH = "user://actor_status_v1_intent_request.json"
const MAX_REQUEST_BYTES = 65536
var core: RefCounted = Core.new()
var source: RefCounted
var engine: RefCounted:
	get: return core.engine
var active_action: String:
	get: return core.scheduler.active_action_id()
var last_action := ""
var narration := ""
var last_feedback := ""
var focus_contract = Focus.new()
var admission: Dictionary = {}
var gameplay_admission: Dictionary = {}
var narration_log_status := "empty"
var _phase := "idle"
var _slot: Dictionary = {}
var _binding_epoch := 0
var _narration_records: Dictionary = {}

func _init(generated: Variant = null) -> void:
	if generated != null and not (generated is Dictionary and generated.is_empty()):
		admission = start_source(generated)

func profile_id() -> String: return Source.PROFILE
func proposal_schema() -> String: return "actor_status_intent_proposal/v1"
func ready() -> Dictionary:
	if source != null and engine != null: return engine.ready()
	return admission.duplicate(true) if not admission.is_empty() else C.fail("ACTOR_SOURCE_REQUIRED", "请先开启独立行动者冒险。")
func start_source(generated: Variant, renderer_profile: String = RenderSource.RENDERER_PROFILE) -> Dictionary:
	if source != null or engine != null: return C.fail("ACTOR_ALREADY_STARTED", "请新开独立冒险，现有世界不会替换。")
	if renderer_profile != RenderSource.RENDERER_PROFILE: return C.fail("ACTOR_RENDERER", "此版本只接受原 structured_v1 地形。")
	var candidate = Core.new()
	var checked: Dictionary = candidate.start_source(generated)
	if checked.get("ok", false): _publish(candidate)
	else: admission = checked.duplicate(true)
	return checked
func _publish(candidate: RefCounted) -> void:
	core = candidate
	source = RenderSource.new(core.source)
	_binding_epoch += 1
	admission = {"ok": true}
	gameplay_admission = {"status": "actor_status_v1_source_validated", "profile": profile_id(), "identity": core.source.identity.duplicate(true)}
	last_action = ""; narration = ""; last_feedback = ""; _narration_records.clear(); narration_log_status = "empty"
	var latest := -1
	for receipt in engine.save_data().receipts.values():
		if int(receipt.turn) > latest:
			latest = int(receipt.turn); last_action = str(receipt.action_id)
	refresh_runtime_state()
func refresh_runtime_state() -> void:
	# Call at event boundaries, including a runtime scope's direct core callback.
	_phase = core.scheduler.phase() if engine != null else "idle"
	_slot = core.scheduler.next_slot() if engine != null else {}
func state_copy() -> Dictionary: return engine.state_copy() if engine != null else {}
func action_copy() -> Dictionary: return engine.action_copy(active_action) if engine != null and not active_action.is_empty() else {}
func phase() -> String: return _phase
func current_actor_id() -> String: return str(_slot.get("actor_id", ""))
func current_slot() -> Dictionary: return _slot.duplicate(true)
func decision_pending() -> bool: return not core.decision.grant.is_empty()
func can_cancel() -> bool: return decision_pending() or phase() in ["awaiting_assessment", "ready_roll"]
func enemy_response_available() -> bool:
	return ready().get("ok", false) and phase() == "idle" and _slot.get("ok", false) and current_actor_id() == Source.ACTORS[1]
func decision_request(now_ms: int = -1, ttl_ms: int = 0) -> Dictionary:
	if not ready().get("ok", false): return ready()
	var result: Dictionary = core.decision.request(_now(now_ms), ttl_ms)
	refresh_runtime_state()
	return result
func decision_request_copy() -> Dictionary: return core.decision.grant.duplicate(true)
func accept_decision(reply: Variant, now_ms: int = -1) -> Dictionary:
	if not ready().get("ok", false): return ready()
	if not C.safe(reply) or not Core.GMEngine.valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return C.fail("DECISION_BUDGET", "意图候选必须遵守完整且有界的公开文本协议。")
	var result: Dictionary = core.decision.accept(reply, _now(now_ms))
	if result.get("ok", false): narration = ""
	refresh_runtime_state()
	return result
func begin_intent(goal: String, focus: Dictionary = {}) -> Dictionary:
	if not ready().get("ok", false): return ready()
	# The user-facing editor never submits as the enemy, even during its slot.
	var result: Dictionary = core.begin_intent("actor_player", goal, focus)
	if result.get("ok", false): narration = ""
	refresh_runtime_state()
	return result
func issue_assessment_ticket(now_ms: int = -1, ttl_ms: int = 0) -> Dictionary:
	if not ready().get("ok", false): return ready()
	return core.scheduler.issue_assessment_ticket(_now(now_ms), ttl_ms)
func accept_assessment(reply: Variant, ticket: Dictionary, now_ms: int = -1) -> Dictionary:
	if not ready().get("ok", false): return ready()
	var result: Dictionary = core.scheduler.accept_assessment(reply, ticket, _now(now_ms))
	refresh_runtime_state()
	return result
func invalidate_transport() -> void:
	core.scheduler.invalidate_transport()
	core.decision.invalidate()
	_binding_epoch += 1
	refresh_runtime_state()
func import_reply(reply: Dictionary) -> Dictionary:
	if not ready().get("ok", false): return ready()
	if not C.safe(reply) or not Core.GMEngine.valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return C.fail("ACTOR_REPLY_BUDGET", "导入需要完整、有限且不超过64 KiB的JSON。")
	var schema: String = str(reply.get("schema_version", ""))
	if schema == "ai_gm_narration/v1": return import_narration(reply)
	# Manual import wins transport ownership. Main also cancels the HTTP owner.
	core.scheduler.invalidate_transport()
	if schema == "actor_status_intent_proposal/v1":
		# Keep the exact grant until Decision.accept verifies and consumes it.
		return accept_decision(reply)
	core.decision.invalidate()
	if schema != "ai_gm_assessment/v1": return C.fail("ACTOR_REPLY_SCHEMA", "只接受本次意图、行动评估或回执叙事协议。")
	var provenance: Variant = reply.get("provenance")
	if not C.exact_fields(provenance, ["provider", "live", "kind"]) or not provenance.provider is String or provenance.provider.strip_edges().is_empty() or not provenance.live is bool or provenance.live or provenance.kind != "model_reply":
		return C.fail("ACTOR_OFFLINE_REPLY", "人工导入评估必须标明 live=false、kind=model_reply。")
	var assessment: Dictionary = reply.duplicate(true)
	assessment.provenance.provider = "manual_offline_assessment"
	var ticket: Dictionary = issue_assessment_ticket()
	if not ticket.get("ok", false): return ticket
	return accept_assessment(assessment, ticket.ticket)
func roll_once() -> Dictionary:
	if not ready().get("ok", false): return ready()
	var result: Dictionary = core.scheduler.roll_once(active_action)
	refresh_runtime_state(); return result
func stage() -> Dictionary:
	if not ready().get("ok", false): return ready()
	var result: Dictionary = core.scheduler.stage(active_action)
	refresh_runtime_state(); return result
func commit() -> Dictionary:
	if not ready().get("ok", false): return ready()
	if active_action.is_empty():
		var previous: Dictionary = committed(last_action)
		return core.commit(last_action, str(previous.stage_hash)) if not previous.is_empty() else C.fail("INVALID_STAGE", "请先暂存本次结果。")
	var action: Dictionary = action_copy()
	if action.get("status") != "staged": return C.fail("INVALID_STAGE", "请先暂存本次结果。")
	# This MUST remain core.commit with the exact frozen token, never Engine.commit.
	var id := active_action
	var result: Dictionary = core.commit(id, str(action.stage_hash))
	if result.get("ok", false):
		last_action = id
		last_feedback = _receipt_feedback(result.get("receipt", {}))
	refresh_runtime_state(); return result
func cancel() -> Dictionary:
	if not ready().get("ok", false): return ready()
	if active_action.is_empty():
		var had_grant := decision_pending()
		invalidate_transport()
		return {"ok": true, "cancelled": had_grant, "decision_only": true}
	var result: Dictionary = core.cancel()
	if result.get("ok", false): narration = ""
	_binding_epoch += 1
	refresh_runtime_state(); return result
func request() -> Dictionary:
	if not ready().get("ok", false): return {}
	if decision_pending(): return decision_request_copy()
	if phase() in ["awaiting_assessment", "ready_roll", "rolled"]: return engine.model_request(active_action)
	return engine.narration_request(active_action if phase() == "staged" else last_action)
func public_facts(actor_id: String = "") -> Dictionary:
	return ActorProjection.facts(state_copy(), current_actor_id() if actor_id.is_empty() else actor_id) if ready().get("ok", false) else {}
func authoritative_result() -> Dictionary:
	return engine.authoritative_result(active_action if not active_action.is_empty() else last_action) if engine != null else {}
func committed(action_id: String = "") -> Dictionary:
	return engine.save_data().receipts.get(last_action if action_id.is_empty() else action_id, {}).duplicate(true) if engine != null else {}
func narration_request(action_id: String = "") -> Dictionary:
	var id := last_action if action_id.is_empty() else action_id
	return engine.narration_request(id) if engine != null and not engine.committed_receipt_hash(id).is_empty() else {}
func receipt_binding(action_id: String) -> Dictionary:
	var outgoing: Dictionary = narration_request(action_id)
	if outgoing.is_empty(): return {}
	return {"view_instance": str(get_instance_id()), "epoch": _binding_epoch, "world_id": state_copy().world_id, "action_id": action_id, "receipt_hash": engine.committed_receipt_hash(action_id), "request_hash": C.digest(outgoing), "context_hash": outgoing.context_hash}
func accept_narration(reply: Variant, binding: Dictionary = {}, origin: String = "provider") -> Dictionary:
	if not ready().get("ok", false): return ready()
	if not reply is Dictionary or not reply.get("action_id") is String: return C.fail("INVALID_NARRATION", "叙事需要已提交回执身份。")
	var actual: Dictionary = receipt_binding(reply.action_id)
	# RefCounted instance IDs can exceed canonical JSON's exact numeric range.
	# Keep that opaque ID as a string; never compare two unsafe empty encodings.
	if actual.is_empty() or not C.safe(actual): return C.fail("STALE_NARRATION", "当前回执绑定不是完整可传输身份。")
	if binding.is_empty():
		if origin != "manual": return C.fail("NARRATION_BINDING_REQUIRED", "接口叙事必须持有当前回执绑定。")
	else:
		if not C.exact_fields(binding, actual.keys()) or not C.safe(binding) or not binding.view_instance is String or not C.integer(binding.epoch) or binding.epoch < 0: return C.fail("STALE_NARRATION", "叙事绑定类型无效。")
		if C.bytes(C.normalized(binding)) != C.bytes(actual): return C.fail("STALE_NARRATION", "叙事不再属于该世界的已提交回执。")
	var checked: Dictionary = engine.validate_narration_reply(reply)
	if not checked.get("ok", false): return checked
	return record_narration(reply.action_id, str(checked.narration), origin)
func import_narration(reply: Dictionary) -> Dictionary: return accept_narration(reply, {}, "manual")
func record_narration(action_id: String, text: String, origin: String = "provider") -> Dictionary:
	if not ready().get("ok", false): return ready()
	if not Core.GMEngine.valid_transport_strings(text): return C.fail("NARRATION_TEXT", "叙事含不可传输的控制字符。")
	var recorded: Dictionary = NarrationLog.record(_narration_records, engine, action_id, text, origin)
	if recorded.get("ok", false):
		narration_log_status = "recorded"
		if action_id == last_action: narration = str(recorded.narration)
	return recorded
func has_recorded_narration(action_id: String) -> bool: return _narration_records.has(action_id)
func narration_entries() -> Array: return NarrationLog.ordered(_narration_records)
func save_sidecar(path: String = SAVE_PATH) -> Dictionary:
	if not ready().get("ok", false): return ready()
	if path.get_file() != SAVE_PATH.get_file(): return C.fail("ACTOR_SAVE_NAMESPACE", "叙事只绑定本版本进度。")
	return NarrationLog.save(path, _narration_records, engine)
func load_sidecar(path: String = SAVE_PATH) -> Dictionary:
	if not ready().get("ok", false): return ready()
	if path.get_file() != SAVE_PATH.get_file(): return C.fail("ACTOR_SAVE_NAMESPACE", "叙事只绑定本版本进度。")
	var result: Dictionary = NarrationLog.load(path, engine)
	if result.get("ok", false):
		_narration_records = result.records.duplicate(true); narration_log_status = str(result.status)
		narration = str(_narration_records.get(last_action, {}).get("narration", ""))
	return result
func supported_focus_kinds() -> Array: return ["tile", "actor", "item"]
func attention(reference: Dictionary) -> Dictionary:
	if not ready().get("ok", false): return ready()
	var state: Dictionary = state_copy()
	# The player-facing inspector uses the same filtered observer set as its HUD.
	# It never invokes the old global ModelView on status-domain authority.
	if not ActorProjection.visible_focus(state, "actor_player", reference): return C.fail("ACTOR_VISIBILITY", "关注对象不在玩家的公开范围。")
	var resolved: Dictionary = focus_contract.resolve(reference, state)
	if not resolved.get("ok", false): return resolved
	return {"ok": true, "focus": ModelView.focus_view(resolved.focus, ActorProjection.facts(state, "actor_player")), "readonly": true}
func tile_reference(hex: Array) -> Dictionary:
	if not ready().get("ok", false) or hex.size() != 2 or not C.integer(hex[0]) or not C.integer(hex[1]): return {}
	var state: Dictionary = state_copy()
	var cell: Dictionary = state.hexes.get("%d,%d" % hex, {})
	if cell.is_empty(): return {}
	return {"world_id": state.world_id, "kind": "tile", "id": cell.id, "hex": hex.duplicate(), "scene_id": cell.scene_id}
func actor_reference(actor_id: String) -> Dictionary:
	if not ready().get("ok", false): return {}
	var state: Dictionary = state_copy()
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty(): return {}
	return {"world_id": state.world_id, "kind": "actor", "id": actor.id, "hex": actor.hex.duplicate(), "scene_id": actor.scene_id}
func enemy_reference() -> Dictionary: return actor_reference(Source.ACTORS[1])
func item_reference(id: String = RenderSource.ITEM) -> Dictionary:
	# Only a registered source-entity descriptor produces item focus. Existing
	# weapons still use exact assessment bindings; no synthetic weapon reference.
	return ItemFocus.make_reference(id, state_copy()) if ready().get("ok", false) else {}
func movement_preview(target: Array) -> Dictionary:
	if not ready().get("ok", false): return ready()
	var state: Dictionary = state_copy()
	var id := current_actor_id()
	if not _slot.get("ok", false) or not state.actors.has(id): return _slot.duplicate(true)
	var reference: Dictionary = tile_reference(target)
	if reference.is_empty() or not ActorProjection.visible_focus(state, id, reference): return C.fail("ACTOR_VISIBILITY", "目的地不在当前行动者可见范围。")
	var nav: RefCounted = core.source.navigation
	var edge := func(from: Array, to: Array) -> Dictionary:
		if Policy.occupied(state, to, id): return C.fail("ACTOR_OCCUPIED", "活着或倒下的人物仍占据实际地格。")
		return nav.step(from, to)
	var admitted: Dictionary = core.source.validate_state(state)
	if not admitted.get("ok", false): return admitted
	var lifted: Dictionary = Domain.lift(state)
	if not lifted.get("ok", false): return lifted
	var result: Dictionary = Traversal.plan(lifted.world, id, target, int(state.actors[id].stamina.current), edge)
	if result.get("ok", false):
		result["actor_id"] = id
		result["source_hash"] = source.renderer_identity.content_hash
		result["geometry_hash"] = source.renderer_identity.geometry_hash
	return result
func frozen_movement_preview() -> Dictionary:
	var action: Dictionary = action_copy()
	if action.get("assessment", {}).get("resolver_id") != "actor_status_move_v1" or action.get("branches", []).size() != 1: return {}
	var id: String = action.actor_id
	for branch in action.get("branches", []):
		if branch.get("id") != "move_success" or not branch.get("requires") is Dictionary or not branch.requires.is_empty(): continue
		var route: Array = [action.snapshot.actors[id].hex.duplicate()]
		var cost := 0
		for patch in branch.patches:
			if patch.get("actor_id") != id: continue
			if patch.type == "actor_move": route.append(patch.hex.duplicate())
			elif patch.type == "actor_pool_delta" and patch.pool == "stamina": cost -= int(patch.delta)
		var renderer: Dictionary = source.renderer_identity
		return {"ok": true, "actor_id": id, "route": route, "cost": cost, "distance": route.size()-1, "turn_cost": 1, "frozen": true, "source_hash": renderer.content_hash, "geometry_hash": renderer.geometry_hash, "placement_hash": renderer.placement_hash, "effective_navigation_hash": renderer.get("effective_navigation_hash", "")}
	return {}
func render_state() -> Dictionary: return source.render_state(state_copy()) if ready().get("ok", false) else {}
func status_details(actor_id: String = "actor_player") -> Array[String]:
	return StatusDetails.status_lines({"status_details": status_payload(actor_id)})
func status_payload(actor_id: String = "actor_player") -> Dictionary:
	var public: Dictionary = public_facts("actor_player")
	var actor: Dictionary = public.get("actors", {}).get(actor_id, {})
	# PublicStatus.details was already applied by this observer projection, and
	# includes the one fixed legacy poison row. Never append legacy rows twice.
	return actor.get("status_details", {"available": false, "rows": []}).duplicate(true)
func movement_is_flight(actor_id: String = "") -> bool:
	if not ready().get("ok", false): return false
	var state: Dictionary = state_copy()
	var id: String = current_actor_id() if actor_id.is_empty() else actor_id
	if not core.source.validate_state(state).get("ok", false): return false
	var lifted: Dictionary = Domain.lift(state)
	return lifted.get("ok", false) and lifted.world.actors.has(id) and preload("res://core/ai_gm_rebuilt/traversal.gd").flight(lifted.world.actors[id], lifted.world)
func public_receipt_record(action_id: String) -> Dictionary:
	if not ready().get("ok", false) or engine.committed_receipt_hash(action_id).is_empty(): return {}
	# Required save evidence is published only by core.commit or exact replay.
	# This does not read mutable current statuses to refill historical events.
	return engine._record_for_receipt(action_id)
func fixture_available() -> bool: return false
func prepare_fixture() -> Dictionary: return C.fail("ACTOR_EXTERNAL_ASSESSMENT", "每个行动都需要独立有效评估，没有内置裁定。")
func sample_goal(_kind: String, _focus: Dictionary = {}) -> String: return ""
func learned_notes() -> String: return "此独立版本尚未开放交谈；静态村落只用于地图展示。"
func authority_text() -> String:
	var state: Dictionary = state_copy()
	if state.is_empty(): return "独立行动状态冒险尚未通过校验"
	var actors: Dictionary = public_facts("actor_player").get("actors", {})
	var acting: Dictionary = actors.get(current_actor_id(), {})
	var lines: Array[String] = ["固定规则 · 回合%d · 当前行动者：%s" % [int(state.turn), str(acting.get("name", "当前不可见人物"))]]
	for id in Source.ACTORS:
		if not actors.has(id): continue
		var actor: Dictionary = actors[id]
		lines.append("%s ·（%d，%d）· 生命%d/%d · 体力%d/%d%s" % [actor.name, actor.hex[0], actor.hex[1], actor.health.current, actor.health.max, actor.stamina.current, actor.stamina.max, " · 已倒下，仍占格" if actor.health.current <= 0 else ""])
	var action: Dictionary = action_copy()
	if not action.is_empty() and actors.has(action.actor_id): lines.append("%s · %s" % [str(actors[action.actor_id].name), str(action.goal)])
	elif decision_pending(): lines.append("等待当前行动者提出意图，尚未评估或消耗回合")
	if not last_feedback.is_empty() and actors.has(committed().get("actor_id", "")): lines.append(last_feedback)
	return "\n".join(lines)
func _receipt_feedback(receipt: Dictionary) -> String:
	if receipt.is_empty(): return "本次行动已提交。"
	var state: Dictionary = state_copy()
	var actor: Dictionary = public_facts("actor_player").get("actors", {}).get(receipt.actor_id, {})
	if actor.is_empty(): return "本次行动已提交。"
	return "%s的行动已提交：%s" % [str(actor.get("name", receipt.actor_id)), str(receipt.goal)]
func journal_entries() -> Array:
	if not ready().get("ok", false): return []
	var receipts: Array = engine.save_data().receipts.values()
	receipts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.turn) < int(b.turn))
	var entries: Array = []
	var actors: Dictionary = state_copy().actors
	for receipt in receipts:
		entries.append({"title": "第%d次行动 · %s" % [int(receipt.turn), str(actors.get(receipt.actor_id, {}).get("name", receipt.actor_id))], "text": receipt.goal, "action_id": receipt.action_id})
	return entries
func default_save_path() -> String: return SAVE_PATH
func default_request_path() -> String: return INTENT_REQUEST_PATH if decision_pending() else REQUEST_PATH
func default_intention_request_path() -> String: return INTENT_REQUEST_PATH
func save_data() -> Dictionary: return core.save_data()
func save_file(path: String = "") -> Dictionary:
	if not ready().get("ok", false): return ready()
	if path.is_empty(): path = default_save_path()
	if path.get_file() != SAVE_PATH.get_file(): return C.fail("ACTOR_SAVE_NAMESPACE", "只写入 actor_status_v1.json，旧版本进度保留。")
	if FileAccess.file_exists(path):
		var existing: Variant = _read_json(path, Core.MAX_BYTES)
		if not existing is Dictionary or existing.get("schema_version") != Core.SAVE or existing.get("profile") != profile_id(): return C.fail("ACTOR_SAVE_NAMESPACE", "目标文件属于其他版本，未覆盖。")
	var checked: Dictionary = source.validate_state(state_copy())
	if not checked.get("ok", false): return checked
	if C.bytes(save_data()).to_utf8_buffer().size() > Core.MAX_BYTES: return C.fail("ACTOR_SAVE_BUDGET", "进度超过本版本24 MiB限制。")
	var result: Dictionary = core.save_file(path)
	if result.get("ok", false): result["path"] = path
	return result
func load_file(path: String = "") -> Dictionary:
	if path.is_empty(): path = default_save_path()
	var value: Variant = _read_json(path, Core.MAX_BYTES)
	if value == null:
		invalidate_transport()
		return C.fail("ACTOR_LOAD_FILE", "无法读取本版本完整进度，现有世界保留。")
	return load_data(value)
func load_data(value: Variant) -> Dictionary:
	# Rejected loads cannot publish a partially admitted engine/source. Outstanding
	# callbacks are invalidated even when the detached candidate is rejected.
	invalidate_transport()
	var candidate = Core.new()
	var checked: Dictionary = candidate.load_data(value)
	if not checked.get("ok", false): return checked
	_publish(candidate)
	return {"ok": true, "exact_pending": not active_action.is_empty(), "profile": profile_id()}
func restarted() -> RefCounted:
	invalidate_transport()
	var candidate = get_script().new()
	if ready().get("ok", false): candidate.start_source(source.data)
	return candidate
func export_request(path: String = "") -> Dictionary:
	var outgoing: Dictionary = request()
	if outgoing.is_empty(): return C.fail("NO_REQUEST", "先取得当前意图请求或提交行动。")
	var decision_only: bool = outgoing.get("schema_version") == "actor_status_intent_proposal/v1"
	var expected: String = INTENT_REQUEST_PATH if decision_only else REQUEST_PATH
	if path.is_empty(): path = expected
	if path.get_file() != expected.get_file(): return C.fail("ACTOR_REQUEST_NAMESPACE", "意图、评估请求和进度必须使用各自独立文件名。")
	if not _is_public_request(outgoing, decision_only): return C.fail("ACTOR_REQUEST_SCHEMA", "请求不属于本版本完整公开协议。")
	if FileAccess.file_exists(path) and not _is_public_request(_read_json(path, MAX_REQUEST_BYTES), decision_only): return C.fail("ACTOR_REQUEST_NAMESPACE", "已有文件不属于本版本请求，未覆盖。")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return C.fail("EXPORT_FAILED", "无法写入请求文件。")
	file.store_string(C.bytes(outgoing)); file.flush()
	var error := file.get_error(); file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK: return C.fail("EXPORT_FAILED", "请求文件未完成，原文件保留。")
	return {"ok": true, "path": path, "network_calls": 0}
static func _is_public_request(value: Variant, intention: bool) -> bool:
	if not value is Dictionary or not C.safe(value) or not Core.GMEngine.valid_transport_strings(value) or C.bytes(value).to_utf8_buffer().size() > MAX_REQUEST_BYTES: return false
	for key in ["state", "source", "engine", "rng", "pending", "receipts", "journal"]:
		if value.has(key): return false
	if not value.get("context") is Dictionary or value.get("context_hash") != C.digest(value.context): return false
	if intention:
		if not C.exact_fields(value, ["schema_version", "proposal_id", "actor_id", "state_version", "context_hash", "issued_ms", "expires_ms", "context"]) or value.schema_version != "actor_status_intent_proposal/v1": return false
		return _has_profile_facts(value.context)
	if value.get("schema_version") != "ai_gm_rebuilt/v1" or not value.get("action_id") is String or not value.get("contract") is Dictionary or value.get("phase") not in ["assessment", "narration"]: return false
	var action_id: String = value.action_id
	var tokens: PackedStringArray = action_id.split(":action_")
	if tokens.size() != 2 or not tokens[0].begins_with(Source.PREFIX): return false
	if not _valid_hash(tokens[0].trim_prefix(Source.PREFIX)): return false
	if not tokens[1].is_valid_int() or int(tokens[1]) < 1 or str(int(tokens[1])) != tokens[1]: return false
	if value.phase == "assessment": return _has_profile_facts(value.context)
	var result: Variant = value.context.get("authoritative_result")
	return value.get("reply_schema") == "ai_gm_narration/v1" and result is Dictionary and result.get("schema_version") == "ai_gm_result/v1" and result.get("action_id") == action_id
static func _has_profile_facts(context: Dictionary) -> bool:
	var facts: Variant = context.get("facts")
	if not facts is Dictionary: return false
	var marker: Variant = facts.get("actor_action_identity")
	return marker is Dictionary and marker.get("schema_version") == Source.PROFILE
static func _valid_hash(value: String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
static func _read_json(path: String, maximum: int) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	if file.get_length() > maximum: file.close(); return null
	var text := file.get_as_text(); file.close()
	return JSON.parse_string(text)
static func _now(value: int) -> int: return Time.get_ticks_msec() if value < 0 else value
