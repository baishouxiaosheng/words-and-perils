extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Budget = preload("res://core/ai_gm_http/request_budget.gd")
const Scope = preload("res://view/runtime_ai/scoped_engine.gd")
const Legacy = preload("res://tests/runtime_ai_capacity/baseline/scoped_engine.gd")
const Runtime = preload("res://view/runtime_ai/controller.gd")
const ConnectionPanel = preload("res://view/runtime_ai/connection_panel.gd")
const Adapter = preload("res://view/playable_build/adapter.gd")
const Content = preload("res://view/playable_build/settlement_content.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Mock = preload("res://tests/ai_gm_http/mock_transport.gd")
const KEY = "synthetic-capacity-marker-not-a-real-key"
const LONG = "只观察围寨，不开门。我想看清城门、围墙与城内街区的现状，分辨附近有哪些已经公开的人物和物品。保持原地，不移动，不消耗物品，也不把关注某个目标当成执行动作的许可。"
const OUT = "res://artifacts/runtime_ai_capacity_20261004/"
var checks := 0
var failures: Array = []
var measurements: Array = []
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL: "+label)
func _initialize() -> void: run.call_deferred()
func config(cap: Variant = 65536) -> Dictionary:
	return {"endpoint":"https://example.invalid/v1/chat/completions", "model":"provided-test-model", "reasoning_effort":"low", "max_completion_tokens":2048, "public_request_budget_bytes":cap}
func boundary_tests() -> void:
	for cap in [65536, 98304, 70001, 131072]:
		for size in [cap-1, cap, cap+1]:
			var req: Dictionary = {"context":{"goal":"围寨\"\\😀"}}
			req.context.goal += "x".repeat(size-C.bytes(req).to_utf8_buffer().size())
			var exact := C.bytes(req)
			var scope := Scope.new(null, func(): return true, cap)
			var admitted: Dictionary = scope._budget(req, req, "utf8")
			check(scope.last_metrics.sent_public_bytes == size and scope.last_metrics.budget_bytes == cap, "exact UTF8 measurement %d/%d" % [size,cap])
			check(admitted.is_empty() == (size > cap) and scope._sent_requests.has("utf8") == (size <= cap), "strict boundary admission %d/%d" % [size,cap])
			check(C.bytes(req) == exact, "boundary no truncation %d/%d" % [size,cap])
			if size > cap: check(scope.last_error.get("used_bytes") == size and scope.last_error.get("budget_bytes") == cap, "exact refusal diagnostic")
	for value in [0,-1,131073,65536.5,null,"98304",true,false,INF,NAN]:
		check(not Budget.validate(value).ok, "invalid cap rejected "+str(value))
	for value in [1,65536,98304,70001,131072]: check(Budget.validate(value).bytes == value, "valid exact cap "+str(value))
func compare_projection(a: RefCounted, label: String, goal: String) -> void:
	check(a.begin_intent(goal, Catalog.make_reference(Content.manifest().id, a.state_copy())).ok, label+" begin")
	var frozen := C.bytes(a.engine.save_data())
	var full: Dictionary = a.request()
	var old := Legacy.new(a.engine, func(): return true)
	var compat := Scope.new(a.engine, func(): return true)
	var city := Scope.new(a.engine, func(): return true, Budget.CITY_BYTES)
	var old_req: Dictionary = old.model_request(a.active_action)
	var compat_req: Dictionary = compat.model_request(a.active_action)
	var city_req: Dictionary = city.model_request(a.active_action)
	check(not city_req.is_empty(), label+" city96 admits complete request")
	check(C.bytes(old_req) == C.bytes(compat_req) and old.last_metrics.sent_public_bytes == city.last_metrics.sent_public_bytes, label+" legacy64 exact compatibility")
	check(compat_req.is_empty() == (city.last_metrics.sent_public_bytes > 65536), label+" legacy failure side by side")
	check(city_req.context.goal == goal and city_req.context.text_priority == "explicit_player_text" and C.bytes(city_req.context.attention_focus) == C.bytes(full.context.attention_focus), label+" exact goal and focus priority")
	check(city_req.context_hash == full.context_hash and city_req.transport_scope.authority_context_hash == full.context_hash and city_req.transport_scope.full_public_request_sha256 == C.digest(full), label+" exact authority and full request identities")
	check(C.bytes(city_req.contract) == C.bytes(full.contract) and C.bytes(city_req.memory_context) == C.bytes(full.memory_context), label+" exact instructions and complete public recall")
	for field in ["actors","items","flags","story_anchors","environment_entities","settlements","scene_transitions","passage_targets"]:
		check(C.bytes(city_req.context.facts.get(field)) == C.bytes(full.context.facts.get(field)), label+" complete "+field)
	for forbidden in ['"rng"','"seed"','"receipts"','"snapshot"','"private_notes"','"secrets"',KEY]: check(not C.bytes(city_req).contains(forbidden), label+" privacy "+forbidden)
	check(C.bytes(a.engine.save_data()) == frozen, label+" exact untouched state RNG pending receipts")
	check(a.save_file("user://capacity_pending.json").ok, label+" pending save")
	var restored := Adapter.new()
	check(restored.load_file("user://capacity_pending.json").ok and C.bytes(restored.engine.save_data()) == frozen, label+" exact pending restore")
	var restored_scope := Scope.new(restored.engine, func(): return true, Budget.CITY_BYTES)
	check(C.bytes(restored_scope.model_request(restored.active_action)) == C.bytes(city_req), label+" exact restored request")
	check(C.bytes(Scope.new(restored.engine, func(): return true).model_request(restored.active_action)) == C.bytes(compat_req), label+" save never smuggles enlarged cap")
	measurements.append({"label":label,"bytes":city.last_metrics.sent_public_bytes,"legacy_admitted":not compat_req.is_empty(),"city_admitted":not city_req.is_empty(),"memory_records":full.memory_context.facts.size(),"memory_bytes":full.memory_context.used_record_bytes})
	check(a.cancel().ok, label+" cancel")
func finish(a: RefCounted, goal: String) -> bool:
	for result in [a.begin_intent(goal), a.prepare_fixture(), a.roll_once(), a.stage(), a.commit()]:
		if not result.ok: printerr(JSON.stringify(result)); return false
	return true
func runtime_ui_tests(a: RefCounted) -> void:
	var runtime := Runtime.new(); root.add_child(runtime); runtime.bind_adapter(a)
	var mock := Mock.new(); runtime.set_transport(mock)
	var omitted := config(); omitted.erase("public_request_budget_bytes")
	check(runtime.configure(omitted,KEY).ok and runtime.client.public_configuration().public_request_budget_bytes == 65536, "omitted config remains64")
	for cap in [1,65536,98304,70001,131072]:
		check(runtime.configure(config(cap),KEY).ok and runtime.client.public_configuration().public_request_budget_bytes == cap, "client exact cap "+str(cap))
	var previous: Dictionary = runtime.client.public_configuration()
	for cap in [0,-1,131073,1.5,null,"98304",true]:
		check(not runtime.configure(config(cap),KEY).ok and C.bytes(runtime.client.public_configuration()) == C.bytes(previous), "invalid client config keeps old config "+str(cap))
	runtime.configure(config(65536),KEY); runtime.connection_enabled = true
	check(a.begin_intent(LONG,Catalog.make_reference(Content.manifest().id,a.state_copy())).ok,"runtime long intent begins")
	var frozen := C.bytes(a.engine.save_data())
	check(runtime.request_assessment().get("code") == "CONTEXT_BUDGET" and mock.sent.is_empty(), "legacy runtime refuses long city with zero sends")
	var panel := ConnectionPanel.new(); root.add_child(panel); panel.bind_runtime(runtime)
	panel.endpoint_input.text = "https://example.invalid/v1/chat/completions"; panel.model_input.text = "provided-test-model"; panel.reasoning_input.text = "low"
	panel.budget_profile_input.select(1); panel.budget_profile_input.item_selected.emit(1)
	panel.key_input.text = KEY; panel._apply()
	check(runtime.client.public_configuration().public_request_budget_bytes == 65536 and mock.sent.is_empty(), "unconsented Apply cannot enlarge cap")
	panel.consent_input.button_pressed = true; panel.key_input.text = KEY; panel._apply()
	check(runtime.connection_enabled and runtime.client.public_configuration().public_request_budget_bytes == 98304 and mock.sent.is_empty(), "explicit city Apply consent no send")
	check(C.bytes(a.engine.save_data()) == frozen,"applying cap preserves frozen pending identity")
	var started: Dictionary = runtime.request_assessment()
	check(started.ok and mock.sent.size() == 1, "explicit city request sends one mock")
	var summary: Dictionary = runtime.client.request_summary()
	var body: Dictionary = JSON.parse_string(mock.sent.back().body)
	var sent: Dictionary = JSON.parse_string(body.messages[1].content)
	check(C.bytes(sent).to_utf8_buffer().size() == summary.public_request_bytes and summary.public_request_budget_bytes == 98304 and summary.request_bytes > summary.public_request_bytes, "canonical public and wrapped wire bytes distinct")
	check(C.bytes(sent) == C.bytes(runtime._scope.model_request(a.active_action)), "wire embedded public request exact")
	check(body.messages[0].content.contains(Runtime.CONTRACT), "wire retains full trusted instructions")
	check(body.model == "provided-test-model" and body.reasoning_effort == "low" and body.max_completion_tokens == 2048, "selected model reasoning output unchanged")
	check(runtime.configure(config(131072),KEY).get("code") == "BUSY" and runtime.client.request_summary().public_request_budget_bytes == 98304, "inflight cap immutable")
	check(not runtime.request_assessment().ok and mock.sent.size() == 1, "double click no send")
	check(panel.budget_usage_label.text.contains(str(summary.public_request_bytes)) and panel.budget_usage_label.text.contains("98304"), "UI exact usage versus chosen cap")
	runtime.cancel(); check(not runtime.busy() and C.bytes(a.engine.save_data()) == frozen, "cancel unchanged pending")
	var old_scope: RefCounted = runtime._scope
	runtime.configure(config(1),KEY)
	check(not old_scope.model_request(a.active_action).is_empty() and old_scope.last_metrics.budget_bytes == 98304, "old scope keeps frozen cap after settings change")
	check(runtime.request_assessment().get("code") == "CONTEXT_BUDGET" and mock.sent.size() == 1, "explicit lower cap honored next request")
	runtime.configure(config(98304),KEY)
	var reentry: Dictionary = {"ran":false}
	runtime.changed.connect(func():
		if runtime.busy() and not runtime.client.busy() and not reentry.ran:
			reentry.ran = true; runtime.client.configure(config(131072),KEY))
	check(runtime.request_assessment().get("code") == "CONFIG_CHANGED" and mock.sent.size() == 1 and reentry.ran, "pre-send reentrant enlargement refuses without send")
	runtime.configure(config(98304),KEY); runtime.connection_enabled = true
	var consent_reentry := {"ran":false}
	runtime.changed.connect(func():
		if runtime.busy() and not runtime.client.busy() and not consent_reentry.ran:
			consent_reentry.ran = true; runtime.connection_enabled = false)
	check(runtime.request_assessment().get("code") == "CONSENT_REQUIRED" and mock.sent.size() == 1, "pre-send consent withdrawal blocks")
	runtime.connection_enabled = true
	var replacement := {"ran":false,"started":false}
	runtime.changed.connect(func():
		if runtime.busy() and not runtime.client.busy() and not replacement.ran:
			replacement.ran = true; runtime.cancel(); replacement.started = runtime.request_assessment().get("ok",false))
	check(runtime.request_assessment().get("code") == "STALE_CONTEXT" and replacement.started and mock.sent.size() == 2 and runtime.busy(), "nested replacement retains its own active operation")
	check(not runtime._operation.is_empty() and runtime.client.busy(), "outer request cannot clear replacement completion identity")
	runtime.cancel(); runtime.configure(config(131072),KEY)
	var reopened := ConnectionPanel.new(); root.add_child(reopened); reopened.bind_runtime(runtime)
	check(reopened.budget_profile_input.selected == 2 and reopened.budget_bytes_input.text == "131072" and not reopened.consent_input.button_pressed and not runtime.connection_enabled, "reopen hydrates exact applied cap without consent")
	var other := Runtime.new(); root.add_child(other); other.configure(config(70001),KEY)
	reopened.consent_input.button_pressed = true; reopened._dirty = false; reopened.bind_runtime(other)
	check(reopened.budget_bytes_input.text == "70001" and not reopened.consent_input.button_pressed and reopened._dirty and not other.connection_enabled, "different client cannot inherit consent")
	reopened.budget_profile_input.select(2); reopened.budget_profile_input.item_selected.emit(2)
	for text in ["0","-1","131073","1.2","98304oops","999999999999999999999999"]:
		reopened.budget_bytes_input.text = text
		check(not Budget.validate(reopened._selected_budget_bytes()).ok,"UI invalid exact text "+text)
	reopened.budget_bytes_input.text = "70001"; check(reopened._selected_budget_bytes() == 70001,"UI arbitrary exact cap no clamp")
	reopened._clear(); check(reopened.budget_profile_input.selected == 0 and not other.client.configured(),"clear offline legacy display")
	reopened.budget_profile_input.select(1); reopened.budget_profile_input.item_selected.emit(1)
	reopened.bind_runtime(other)
	check(reopened.budget_profile_input.selected == 0 and reopened.budget_bytes_input.text == "65536" and reopened._dirty, "unconfigured rebind resets legacy display")
	check(C.bytes(a.engine.save_data()) == frozen,"all config tests preserve authority")
	a.cancel()
	runtime.configure(config(1),KEY); runtime.connection_enabled = true
	var committed := C.bytes(a.engine.save_data()); var sends := mock.sent.size()
	check(runtime.request_narration().get("code") == "CONTEXT_BUDGET" and mock.sent.size() == sends, "narration exact lower cap refuses before send")
	runtime.configure(config(98304),KEY)
	check(runtime.request_narration().ok and runtime.client.request_summary().public_request_budget_bytes == 98304, "committed narration uses selected cap")
	runtime.cancel(); check(C.bytes(a.engine.save_data()) == committed, "narration admission and cancel preserve committed save")
	panel.queue_free(); reopened.queue_free(); runtime.queue_free(); other.queue_free()
func run() -> void:
	boundary_tests()
	var a := Adapter.new(751,true)
	compare_projection(a,"baseline_city","只观察围寨，不开门。")
	compare_projection(a,"long_chinese_intent",LONG)
	for i in range(9):
		var goal: String
		match i:
			0: goal = a.movement_goal(Content.manifest().gate_outside_hex)
			1,6: goal = a.sample_goal("open_gate")
			2,5,8: goal = a.sample_goal("rest")
			3: goal = a.movement_goal(Content.manifest().gate_inside_hex)
			4: goal = a.sample_goal("close_gate")
			7: goal = a.movement_goal(Content.manifest().gate_outside_hex)
		if not finish(a,goal): check(false,"real journey commit "+str(i+1)); break
		if i in [0,2,5,8]: compare_projection(a,"after_%d_commits"%(i+1),"只观察围寨，不开门。")
	runtime_ui_tests(a)
	await process_frame
	DirAccess.remove_absolute("user://capacity_pending.json")
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"measurements":measurements,"live_api":false,"policy":{"legacy":65536,"city":98304,"ceiling":131072}}
	var f := FileAccess.open(OUT+"policy_report.json",FileAccess.WRITE); f.store_string(JSON.stringify(report,"\t")); f.close()
	print("CAPACITY_POLICY ",checks-failures.size(),"/",checks); quit(0 if failures.is_empty() else 1)
