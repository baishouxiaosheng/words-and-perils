extends RefCounted
## Offline, explicitly test-only bridge. Never send save_data/receipts/RNG to a provider.
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const Rule = preload("res://tests/experimental/ai_gm_rebuilt/test_rule_a.gd")
const Resolver = preload("res://tests/experimental/ai_gm_rebuilt/fixture_resolver.gd")
const Focus = preload("res://core/focus_contract.gd")
const FIXTURE_GOAL := "拿出一份果酒，向芦灯说明渡河的理由，请她放行。"
const FIXTURE_AUTHOR := "项目作者 · 手写功能夹具 harbor_gate_initial/v1"
const SAVE_PATH := "user://ai_gm_playtest_save.json"
const REQUEST_PATH := "user://ai_gm_playtest_request.json"
var engine: RefCounted
var active_action := ""
var last_action := ""
var narration := ""
var focus_contract = Focus.new()

func _init(seed: Variant = null) -> void:
	var registry := {}
	for variant in ["gate", "listen"]:
		var resolver := Resolver.new(variant)
		registry[resolver.resolver_id()] = resolver
	engine = GMEngine.new(Story.world(), Rule.new(), registry,
		{"npc_secret_allowlist": [], "public_flag_ids": ["gate_open", "npc_listened"]}, seed)

func state_copy() -> Dictionary: return engine.state_copy()
func attention(reference: Dictionary) -> Dictionary: return engine.attention(reference)
func action_copy() -> Dictionary: return engine.action_copy(active_action)
func phase() -> String: return String(action_copy().get("status", "idle"))
func can_cancel() -> bool: return phase() in ["awaiting_assessment", "ready_roll"]
func request() -> Dictionary:
	if phase() in ["awaiting_assessment", "ready_roll", "rolled"]:
		return engine.model_request(active_action)
	return engine.narration_request(active_action if phase() == "staged" else last_action)

func begin_intent(goal: String, focus: Dictionary = {}) -> Dictionary:
	var result: Dictionary = engine.begin_intent(goal, focus)
	if result.ok:
		active_action = result.request.action_id
		narration = ""
	return result

func fixture_available() -> bool:
	var action := action_copy()
	return phase() == "awaiting_assessment" and action.goal == FIXTURE_GOAL and C.bytes(action.snapshot) == C.bytes(Story.world())

func prepare_fixture() -> Dictionary:
	if not fixture_available():
		return C.fail("FIXTURE_SCOPE", "署名夹具只适用于指定完整意图及初始19格状态；其他输入必须导入人工离线评估。")
	var reply: Dictionary = Story.assessment(engine.model_request(active_action))
	reply.interpretation = "手写功能演示：给芦灯一份果酒，并说明渡河理由请求放行。目标来自明确文字，不来自关注。"
	reply.provenance.provider = FIXTURE_AUTHOR
	return engine.prepare_assessment(reply)

func import_reply(reply: Dictionary) -> Dictionary:
	if not C.safe(reply) or not reply.get("schema_version") is String:
		return C.fail("WRONG_PROTOCOL", "需要有限JSON及字符串版本，未更改测试状态。")
	if reply.get("schema_version") == "ai_gm_narration/v1":
		# Late narration is accepted only for the currently displayed action.
		var shown := active_action if phase() == "staged" else last_action
		if not reply.get("action_id") is String or reply.action_id != shown: return C.fail("STALE_NARRATION", "叙事不是当前显示的权威结果。")
		var result: Dictionary = engine.validate_narration_reply(reply)
		if result.ok: narration = result.narration
		return result
	if reply.get("schema_version") != "ai_gm_assessment/v1":
		return C.fail("WRONG_PROTOCOL", "测试模式仅接受 ai_gm_assessment/v1 或 ai_gm_narration/v1，旧planning/resolution不会套用。")
	var provenance: Variant = reply.get("provenance")
	if not C.exact_fields(provenance, ["provider", "live", "kind"]) or not provenance.get("provider") is String or not provenance.get("live") is bool or provenance.live or not provenance.get("kind") is String or provenance.kind != "model_reply":
		return C.fail("OFFLINE_ONLY", "人工离线JSON必须标明live=false、kind=model_reply；本模式没有实时API。署名夹具只能由专用按钮使用。")
	# File metadata cannot claim a runtime provider connection.
	var assessment := reply.duplicate(true)
	assessment.provenance.provider = "manual_offline_assessment"
	return engine.prepare_assessment(assessment)

func roll_once() -> Dictionary: return engine.roll_once(active_action)
func stage() -> Dictionary: return engine.stage(active_action)
func commit() -> Dictionary:
	var action := action_copy()
	if phase() != "staged": return C.fail("INVALID_STAGE", "请先暂存权威结果。")
	var result: Dictionary = engine.commit(active_action, action.stage_hash)
	if result.ok:
		last_action = active_action
		active_action = ""
		# Staged narrative has a different context hash after commit. Text remains
		# display-only but user must use the newly exported request for a new reply.
	return result
func cancel() -> Dictionary:
	var result: Dictionary = engine.cancel_intent(active_action)
	if result.ok: active_action = ""; narration = ""
	return result
func authoritative_result() -> Dictionary:
	return engine.authoritative_result(active_action) if not active_action.is_empty() else engine.authoritative_result(last_action)
func save_file(path: String = SAVE_PATH) -> Dictionary: return engine.save_file(path)
func load_file(path: String = SAVE_PATH) -> Dictionary:
	var result: Dictionary = engine.load_file(path)
	if not result.ok: return result
	active_action = ""; last_action = ""; narration = ""
	# Internal bookkeeping only; these records are never outward request data.
	var data: Dictionary = engine.save_data()
	for id in data.pending: active_action = id
	var latest_turn := -1
	for id in data.receipts:
		if int(data.receipts[id].turn) > latest_turn:
			latest_turn = int(data.receipts[id].turn); last_action = id
	return result

func export_request(path: String) -> Dictionary:
	var outgoing := request()
	if outgoing.is_empty(): return C.fail("NO_REQUEST", "先提交意图，或暂存/提交结果后导出可选叙事请求。")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return C.fail("EXPORT_FAILED", "无法写出请求。")
	file.store_string(JSON.stringify(outgoing, "\t", true, true)); file.close()
	return {"ok": true}

func authority_text() -> String:
	var action := action_copy()
	var state := state_copy()
	var result := authoritative_result()
	var title := "权威数值 · 尚未结算" if result.is_empty() else ("权威数值 · 暂存预览，未提交" if phase() == "staged" else "权威数值 · 已提交")
	var lines: Array[String] = [title, _facts_line(state, "当前事实")]
	if phase() == "ready_roll":
		var checks: Array[String] = []
		for check in action.checks:
			checks.append("%s：范围%d–%d，≤%d成功" % [check.id, check.roll_min, check.roll_max, check.success_at_most] if check.method == "random" else "%s：%s" % [check.id, "直接成功" if check.method == "direct_success" else "直接失败"])
		lines.append(" / ".join(checks))
	if phase() == "rolled":
		lines.append(_outcome_line(action.outcomes, action.rolls))
		lines.append("一次结果已锁定；下一步暂存，当前事实尚未改变")
	if not result.is_empty():
		if phase() == "staged": lines.append(_facts_line(action.staged, "待提交"))
		lines.append(_outcome_line(result.outcomes, result.rolls))
		var effects: Array[String] = []
		for effect in result.public_effects:
			match effect.type:
				"item_quantity_delta": effects.append("果酒%d" % effect.delta)
				"actor_pool_delta": effects.append("%s%d" % ["体力" if effect.pool == "stamina" else "生命", effect.delta])
				"flag_set": effects.append("%s=%s" % [{"gate_open": "通行开放", "npc_listened": "守卫听取"}.get(effect.flag_id, effect.flag_id), "是" if effect.value else "否"])
				_: effects.append(String(effect.type))
		lines.append("本次固定效果：" + ("，".join(effects) if not effects.is_empty() else "无事实变化"))
	return "\n".join(lines)

func _facts_line(state: Dictionary, prefix: String) -> String:
	var actor: Dictionary = state.actors.actor_player
	return "%s v%d / 回合%d：体力%d/%d，果酒%d，通行%s，守卫听取%s" % [prefix, state.state_version, state.turn, actor.stamina.current, actor.stamina.max, state.items.item_wine.quantity, "已开放" if state.flags.gate_open else "未开放", "是" if state.flags.npc_listened else "否"]

func _outcome_line(outcomes: Dictionary, rolls: Array) -> String:
	var parts: Array[String] = []
	for id in outcomes:
		var die := "直接结果"
		for roll in rolls:
			if roll.component_id == id: die = "实掷%d / 10000，已锁定" % roll.value
		parts.append("%s %s（%s）" % [id, "成功" if outcomes[id] else "失败", die])
	return " / ".join(parts)
