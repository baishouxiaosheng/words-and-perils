extends "res://view/ai_gm_playtest/adapter.gd"
const StatusContent=preload("res://core/status_gameplay/content.gd")
const StatusAction=preload("res://core/status_gameplay/action.gd")
const StatusSave=preload("res://view/status_gameplay/save.gd")
var status_gameplay_mode:=false
const CreativeActions = preload("res://core/ai_gm_rebuilt/creative_actions.gd")
const CreativeExamples = preload("res://view/playable_build/creative_examples.gd")
const GateActions = preload("res://core/ai_gm_rebuilt/settlement_actions.gd")
const SettlementExamples = preload("res://view/playable_build/settlement_examples.gd")
const CoastWorld = preload("res://view/playable_build/world.gd")
const CoastRule = preload("res://view/playable_build/rule.gd")
const ReleaseRule = preload("res://view/playable_build/rule_release_v1.gd")
const BasicActions = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const StatusBasicActions = preload("res://core/status_gameplay/basic_actions.gd")
const StatusCompositeActions = preload("res://core/status_gameplay/composite_actions.gd")
const BasicExamples = preload("res://view/playable_build/basic_examples.gd")
const AuthoredAssessments = preload("res://view/playable_build/authored_assessments.gd")
const CoastResolver = preload("res://view/playable_build/resolver.gd")
const CoastStory = preload("res://view/playable_build/story.gd")
const EffectExamples = preload("res://view/playable_build/effect_examples.gd")
const DisplayText = preload("res://view/playable_build/display_text.gd")
const Navigation = preload("res://view/playable_build/navigation.gd")
const MovementResolver = preload("res://view/playable_build/movement_resolver.gd")
const WeightedMovement = preload("res://view/playable_build/weighted_movement_resolver.gd")
const SceneTransition = preload("res://view/playable_build/scene_transition_resolver.gd")
const SceneTransitionV2 = preload("res://view/playable_build/scene_transition_resolver_v2.gd")
const CompositeActions = preload("res://core/ai_gm_rebuilt/composite_actions.gd")
const CompositeExamples = preload("res://view/playable_build/composite_examples.gd")
const NarrationLog = preload("res://view/runtime_ai/narration_log.gd")
const SceneAdapters = preload("res://view/playable_build/scene_adapters.gd")
const GenericActionsV2 = preload("res://core/ai_gm_rebuilt/generic_actions_v2.gd")
const GenericActions = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const COAST_SAVE := "user://r24_coast_adventure_save.json"
const COAST_REQUEST := "user://r24_coast_adventure_request.json"
const AUTHOR := "项目作者 · 明确署名海岸功能样例 coast_actions/v1"
var last_feedback := ""
var _narration_records: Dictionary = {}
var _provisional_narration: Dictionary = {}
var narration_log_status := "empty"
var _release_v1_test := false
func _init(seed: Variant = null, release_v1_test: bool = false, enable_status_gameplay:bool=false) -> void:
	status_gameplay_mode=enable_status_gameplay
	_release_v1_test = release_v1_test
	engine = _make_engine(seed)
func _make_engine(seed: Variant = null, legacy := false, paths := true, effects := true, basic := true, release := true, weighted := true, scenes := false, composites := true, scalar_scenes := true, gates := true, effects_v2 := true, creative := true) -> RefCounted:
	if status_gameplay_mode and (not release or (seed!=null and not _release_v1_test)):
		return GMEngine.new({}) # No new-status world may use the old disposition-authoritative test calculator
	var registry := {}
	var current_effects: bool = effects_v2 and release and (seed == null or _release_v1_test)
	for kind in (["move", "observe", "talk", "rest"] if legacy else ["move", "observe", "talk", "rest", "repair"]):
		var resolver := CoastResolver.new(kind); registry[resolver.resolver_id()] = resolver
	if paths:
		var movement := MovementResolver.new(); registry[movement.resolver_id()] = movement
	if effects:
		for kind in ["manipulate_environment","apply_condition"]:
			var resolver:RefCounted=GenericActionsV2.new(kind) if current_effects else GenericActions.new(kind);registry[resolver.resolver_id()]=resolver
	if basic:
		for kind in BasicActions.KINDS:
			var resolver:RefCounted = StatusBasicActions.new(kind) if status_gameplay_mode else BasicActions.new(kind); registry[resolver.resolver_id()] = resolver
	if release and (seed == null or _release_v1_test):
		if weighted: registry[WeightedMovement.ID] = WeightedMovement.new()
		if scenes: registry[SceneTransition.ID] = SceneTransition.new()
		if scalar_scenes: registry[SceneTransitionV2.ID_V2] = SceneTransitionV2.new()
		if composites: registry[CompositeActions.ID] = StatusCompositeActions.new() if status_gameplay_mode else CompositeActions.new()
		if gates: registry[GateActions.ID] = GateActions.new()
		if creative: registry[CreativeActions.ID] = CreativeActions.new()
	if status_gameplay_mode:
		registry.erase("coast_apply_condition_v1");registry.erase("coast_apply_condition_v2")
		registry.erase("coast_move");registry.erase(MovementResolver.ID)
		registry[StatusAction.ID]=StatusAction.new()
	var flags := ["coast_observed", "keeper_trust"] if legacy else ["coast_observed", "keeper_trust", "lamp_restored"]
	# Existing explicit seed callers keep historical test semantics. New runtime games
	# use release-v1; the opt-in release test constructor uses an honestly labelled rule.
	if seed != null and not _release_v1_test: release = false
	var calculator: RefCounted = ReleaseRule.new(registry) if release else CoastRule.new()
	if _release_v1_test and release: calculator = load("res://tests/core_gameplay/test_release_rule.gd").new(registry)
	var initial:Dictionary=CoastWorld.world(release and basic)
	if status_gameplay_mode:
		var installed:Dictionary=StatusContent.install_new_world(initial)
		initial=installed.world if installed.ok else {}
	return GMEngine.new(initial, calculator, registry, {"npc_secret_allowlist": [], "public_flag_ids": flags}, seed)
func start_scene_framework_test(seed: Variant = null) -> Dictionary:
	# Explicit new test session only. Never called by load or idle migration.
	var candidate = _make_engine(seed)
	var data: Dictionary = candidate.save_data()
	preload("res://view/playable_build/scene_framework_fixture.gd").install(data.state)
	var checked: Dictionary = candidate.load_data(C.normalized(data))
	if not checked.ok: return checked
	engine = candidate; active_action = ""; last_action = ""; narration = ""; last_feedback = ""; _narration_records.clear(); _provisional_narration.clear()
	return {"ok": true, "explicit_framework_test": true}
func story_goal() -> String: return CoastStory.goal(state_copy())
func story_complete() -> bool: return CoastStory.complete(state_copy())
func begin_intent(goal: String, focus: Dictionary = {}) -> Dictionary:
	if goal.strip_edges().is_empty(): return super.begin_intent(goal,focus)
	var upgraded := _upgrade_legacy_idle()
	if not upgraded.ok: return upgraded
	return super.begin_intent(goal,focus)
func _upgrade_legacy_idle() -> Dictionary:
	if status_gameplay_mode:return {"ok":true} # Explicit ruleset never passes through legacy auto-upgrade
	if phase() != "idle": return {"ok": true}
	var data: Dictionary = engine.save_data()
	var release: bool = data.rng.mode != "test_seed" or _release_v1_test
	var target_rule: String = "ai_gm_test_coast_release/v1" if _release_v1_test else (ReleaseRule.ID if release else "ai_gm_test_coast_actions/v1")
	var desired_effect_suffix := "_v2" if release else "_v1"
	if state_copy().flags.has("lamp_restored") and MovementResolver.ID in data.resolver_ids and ("coast_manipulate_environment"+desired_effect_suffix) in data.resolver_ids and ("coast_apply_condition"+desired_effect_suffix) in data.resolver_ids and "coast_basic_attack_v1" in data.resolver_ids and data.rule_id == target_rule and (not release or (WeightedMovement.ID in data.resolver_ids and SceneTransitionV2.ID_V2 in data.resolver_ids and CompositeActions.ID in data.resolver_ids and GateActions.ID in data.resolver_ids and CreativeActions.ID in data.resolver_ids)): return {"ok": true}
	# A fully validated idle save may adopt a new registry/rule. Pending rolls are
	# loaded under their exact original version; no inventory/actor gifts on upgrade.
	if not data.pending.is_empty(): return C.fail("PENDING_UPGRADE", "旧回合尚未结束。")
	var candidate = _make_engine(null, false, true, true, true, release)
	var trusted: Dictionary = candidate.save_data()
	if not data.state.flags.has("lamp_restored"): data.state.flags["lamp_restored"] = false
	data.policy = trusted.policy; data.resolver_ids = trusted.resolver_ids; data.rule_id = trusted.rule_id
	data.state.story_anchors = CoastWorld.world(release).story_anchors.duplicate(true)
	if not data.state.has("environment_entities"): data.state.environment_entities = {}
	for actor in data.state.actors.values():
		if not "status_tick" in actor.hooks: actor.hooks.append("status_tick")
	var valid: Dictionary = candidate.load_data(data)
	if valid.ok: engine = candidate
	return valid
func sample_goal(kind: String, focus: Dictionary = {}) -> String:
	var state := state_copy()
	if state.is_empty(): return ""
	if kind in CreativeExamples.KINDS: return CreativeExamples.goal(kind,state,focus)
	if kind in ["open_gate", "close_gate"]: return SettlementExamples.goal("open" if kind=="open_gate" else "close",state,focus)
	if kind in ["transition", "enter_scene", "return_scene"]:
		var actor: Dictionary = state.actors.actor_player
		var ids: Array = state.get("scene_transitions", {}).keys(); ids.sort()
		for id in ids:
			var entrance: Dictionary = state.scene_transitions[id]
			if entrance.source_scene_id != actor.scene_id or entrance.source_hex != actor.hex: continue
			if kind == "enter_scene" and entrance.destination_scene_id == "scene_coast": continue
			if kind == "return_scene" and entrance.destination_scene_id != "scene_coast": continue
			return AuthoredAssessments.transition_goal(state, id)
		return ""
	if kind == "move_attack": return CompositeExamples.goal(state, CompositeExamples.spec(state, focus))
	if kind in BasicExamples.KINDS: return BasicExamples.goal(kind, state, focus)
	match kind:
		"fell", "poison", "flight": return EffectExamples.goal(kind,state,focus)
		"move":
			if focus.get("kind") == "tile" and focus.get("hex") is Array and focus.hex.size()==2 and focus.hex != state.actors.actor_player.hex:
				return movement_goal(focus.hex)
			var reachable := Traversal.reachable(state, "actor_player", 1)
			var destination: Array = []
			if focus.get("kind") == "tile" and reachable.has(Traversal.key(focus.hex)) and focus.hex != state.actors.actor_player.hex and _sample_move_is_available(state,focus.hex): destination = focus.hex
			else:
				var best := 999
				for row in reachable.values():
					if row.distance != 1 or not _sample_move_is_available(state,row.hex): continue
					var dq: int = row.hex[0]-state.actors.actor_keeper.hex[0]; var dr: int = row.hex[1]-state.actors.actor_keeper.hex[1]
					var score := maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))
					if row.hex == state.actors.actor_keeper.hex: score += 2
					if score < best: best = score; destination = row.hex
			if destination.size()!=2:return ""
			return movement_goal(destination) if status_gameplay_mode else "【署名样例】步行到相邻格的干燥落脚点（%d，%d）。" % [destination[0], destination[1]]
		"observe": return "【署名样例】停下脚步，观察南潮海岸，记下旧灯附近的线索。"
		"talk": return "【署名样例】拿出一份随身果酒，向芦灯询问旧灯熄灭和船队失踪的事。"
		"repair": return CoastStory.GOAL
		"rest": return "【署名样例】原地休息片刻，恢复体力，然后继续探路。"
	return ""
func _sample_move_is_available(state:Dictionary,target:Array) -> bool:
	return Navigation.plan_weighted_route(state,"actor_player",target,int(state.actors.actor_player.stamina.current)).ok if status_gameplay_mode else Navigation.step(state.actors.actor_player.hex,target).ok
func movement_goal(target:Array) -> String:
	return ("【署名样例】按地形耗力行至（%d，%d）。" if engine.supports_resolver(WeightedMovement.ID) else "【署名样例】沿干燥路线步行到（%d，%d）。") % target
func movement_preview(target:Array) -> Dictionary:
	var state:=state_copy()
	return Navigation.plan_weighted_route(state,"actor_player",target,int(state.actors.actor_player.stamina.current)) if engine.supports_resolver(WeightedMovement.ID) else Navigation.plan_route(state,"actor_player",target,int(state.actors.actor_player.stamina.current))
func frozen_movement_preview() -> Dictionary:
	var action:=action_copy()
	if action.is_empty() or not action.get("assessment",{}).get("resolver_id","") in [MovementResolver.ID, WeightedMovement.ID, CompositeActions.ID]:return {}
	for branch in action.branches:
		if not branch.requires.get("move",false) and not (status_gameplay_mode and branch.requires.is_empty() and action.assessment.resolver_id==WeightedMovement.ID):continue
		var route:Array=[action.snapshot.actors.actor_player.hex.duplicate()];var cost:=0
		for patch in branch.patches:
			if patch.type=="actor_move" and patch.actor_id=="actor_player":route.append(patch.hex.duplicate())
			elif patch.type=="actor_pool_delta" and patch.actor_id=="actor_player" and patch.pool=="stamina" and cost == 0:cost-=int(patch.delta)
		return {"ok":true,"route":route,"cost":cost,"distance":route.size()-1,"turn_cost":1,"frozen":true}
	return {}
func _fixture_spec() -> Dictionary:
	if phase() != "awaiting_assessment": return {}
	var action := action_copy(); var snapshot: Dictionary = action.snapshot
	if snapshot.get("world_id") != CoastWorld.catalog().get("world_id") or snapshot.get("generated_world",{}).get("catalog_sha256") != CoastWorld.catalog_sha256() or snapshot.get("generated_world",{}).get("bundle_id", "") != CoastWorld.bundle_id(): return {}
	var text_: String = action.goal
	if engine.supports_resolver(CreativeActions.ID) and not CreativeExamples.find_goal(request()).is_empty(): return {"kind":"creative"}
	for operation in ["open","close"]:
		if engine.supports_resolver(GateActions.ID) and not SettlementExamples.goal(operation,snapshot,action.focus).is_empty() and text_==SettlementExamples.goal(operation,snapshot,action.focus): return {"kind":"gate","operation":operation}
	if text_.begins_with("【署名复合样例】") and engine.supports_resolver(CompositeActions.ID):
		var composite_bindings: Dictionary = CompositeExamples.spec(snapshot, action.focus)
		var composite_goal: String = CompositeExamples.goal(snapshot, composite_bindings)
		if not composite_goal.is_empty() and text_ == composite_goal: return {"kind": "move_attack", "bindings": composite_bindings}
	for id in snapshot.get("scene_transitions", {}):
		if text_ == AuthoredAssessments.transition_goal(snapshot, id): return {"kind": "transition", "entrance_id": id}
	for kind in BasicExamples.KINDS + ["enemy_response"]:
		var exact: String = BasicExamples.goal(kind, snapshot, action.focus, action.actor_id)
		if not exact.is_empty() and text_ == exact: return {"kind": kind, "basic": true}
	for kind in (["fell"] if status_gameplay_mode else ["fell","poison","flight"]):
		var exact: String=EffectExamples.goal(kind,snapshot,action.focus)
		if not exact.is_empty() and text_==exact: return {"kind":kind,"typed_effect":true}
	for kind in ["observe", "talk", "rest", "repair"]:
		if text_ == sample_goal(kind): return {"kind": kind, "bindings": {"actor_id": "actor_player", "target_actor_id": "actor_keeper"} if kind == "talk" else {"actor_id": "actor_player"}}
	var movement_spec:Dictionary=_movement_fixture_spec(snapshot,text_)
	if not movement_spec.is_empty():return movement_spec
	if not engine.supports_resolver("coast_move"):return {}
	var reachable := Traversal.reachable(snapshot, "actor_player", 1)
	for row in reachable.values():
		if row.distance == 1 and Navigation.step(snapshot.actors.actor_player.hex,row.hex).ok and text_ == "【署名样例】步行到相邻格的干燥落脚点（%d，%d）。" % [row.hex[0], row.hex[1]]:
			return {"kind": "move", "bindings": {"actor_id": "actor_player", "target_hex": row.hex.duplicate()}}
	return {}
func _movement_fixture_spec(snapshot:Dictionary,text_:String) -> Dictionary:
	if not engine.supports_resolver(MovementResolver.ID) and not engine.supports_resolver(WeightedMovement.ID):return {}
	for cell in snapshot.get("scene_hexes", {}).get(snapshot.actors.actor_player.scene_id, snapshot.hexes).values():
		var target:Array=[cell.q,cell.r]
		if text_==movement_goal(target):return {"kind":"move","resolver_id":WeightedMovement.ID if engine.supports_resolver(WeightedMovement.ID) else MovementResolver.ID,"bindings":{"actor_id":"actor_player","target_hex":target}}
	return {}
func fixture_available() -> bool: return not _fixture_spec().is_empty()
func prepare_fixture() -> Dictionary:
	var spec := _fixture_spec()
	if spec.is_empty(): return C.fail("FIXTURE_SCOPE", "仅明确署名的完整样例目标可用。任意自由文本必须获得DecisionAI或人工离线评估。")
	var built: Dictionary = AuthoredAssessments.build(request(), spec.get("bindings", {}))
	return engine.prepare_assessment(built.assessment) if built.ok else built
func enemy_response_available() -> bool:
	var state := state_copy()
	return phase() == "idle" and state.get("combat_turn", {}).get("phase", "player") == "enemy"
func combat_phase() -> Dictionary:
	return state_copy().get("combat_turn", {"phase": "player", "enemy_actor_id": "", "round": 0}).duplicate(true)
func begin_enemy_response() -> Dictionary:
	if not enemy_response_available(): return C.fail("ENEMY_RESPONSE", "当前没有可评估的邻近劫掠者反击。")
	var enemy_id: String = state_copy().combat_turn.enemy_actor_id
	var goal: String = BasicExamples.goal("enemy_response", state_copy(), {}, enemy_id)
	var result: Dictionary = engine.begin_intent(goal, {}, enemy_id)
	if result.ok: active_action = result.request.action_id; narration = ""
	return result
func record_narration(action_id: String, text: String, source := "provider") -> Dictionary:
	var recorded:Dictionary=NarrationLog.record(_narration_records,engine,action_id,text,source)
	if recorded.ok and phase()=="idle" and action_id==last_action: narration=recorded.narration
	return recorded
func has_recorded_narration(action_id: String) -> bool:
	return _narration_records.has(action_id) and not engine.committed_receipt_hash(action_id).is_empty() and _narration_records[action_id].receipt_hash==engine.committed_receipt_hash(action_id)
func narration_entries() -> Array:
	var data:Dictionary=engine.save_data();var valid:Dictionary={}
	for id in _narration_records:
		if NarrationLog._valid(_narration_records[id],data):valid[id]=_narration_records[id]
	return NarrationLog.ordered(valid)
func import_reply(reply: Dictionary) -> Dictionary:
	if reply.get("schema_version") is String and reply.schema_version=="ai_gm_control/v1":
		if not C.exact_fields(reply.get("provenance"),["provider","live","kind"]) or not reply.provenance.live is bool or reply.provenance.live or not reply.provenance.kind is String or reply.provenance.kind!="model_reply": return C.fail("OFFLINE_ONLY","Manual feedback must honestly identify an offline model reply.")
		var control:=reply.duplicate(true);control.provenance.provider="manual_offline_assessment"
		return engine.prepare_assessment(control)
	var checked:Dictionary=super.import_reply(reply)
	if not checked.ok or reply.get("schema_version")!="ai_gm_narration/v1":return checked
	if String(checked.narration).to_utf8_buffer().size()>NarrationLog.MAX_TEXT_BYTES:return C.fail("NARRATION_LOG_TEXT","可选叙事超过8 KiB，未写入历史。")
	if phase()=="staged":
		_provisional_narration={"action_id":active_action,"stage_hash":action_copy().stage_hash,"narration":checked.narration}
		return checked
	if phase()!="idle":return checked
	var recorded:=record_narration(String(reply.action_id),String(checked.narration),"manual")
	if not recorded.ok:return recorded
	checked["narration"]=recorded.narration;checked["already_recorded"]=recorded.already_recorded
	return checked
func save_file(path: String = COAST_SAVE) -> Dictionary:
	if status_gameplay_mode and path==COAST_SAVE:path=StatusSave.PATH
	var saved:Dictionary=StatusSave.save_file(engine,path) if status_gameplay_mode else super.save_file(path)
	if not saved.ok:return saved
	var prose:Dictionary=NarrationLog.save(path,_narration_records,engine)
	saved["narration_log_saved"]=prose.ok
	if not prose.ok:saved["narration_warning"]="核心进度已保存，但可选叙事历史未保存。"
	return saved
func _trace_load(stage: String) -> void:
	if not OS.has_environment("FOGBANK_LOAD_PROFILE"): return
	var memory: Dictionary={"stage":stage,"ticks_ms":Time.get_ticks_msec(),"static_bytes":OS.get_static_memory_usage(),"peak_static_bytes":OS.get_static_memory_peak_usage()}
	var status_output: Array=[]
	OS.execute("cat",PackedStringArray(["/proc/"+str(OS.get_process_id())+"/status"]),status_output)
	for line in (String(status_output[0]) if not status_output.is_empty() else "").split("\n"):
		if line.begins_with("VmRSS:") or line.begins_with("VmHWM:") or line.begins_with("VmSize:"): memory[line.split(":")[0]]=line.split(":")[1].strip_edges()
	print("LOAD_PROFILE ",JSON.stringify(memory))
func load_file(path: String = COAST_SAVE) -> Dictionary:
	if status_gameplay_mode and path==COAST_SAVE:path=StatusSave.PATH
	_trace_load("start")
	# Reject other map saves before the generic engine can publish any state.
	if not FileAccess.file_exists(path): return C.fail("LOAD_FAILED", "尚无真实海岸存档。")
	if status_gameplay_mode:
		var limited:=FileAccess.open(path,FileAccess.READ)
		if limited==null:return C.fail("STATUS_SAVE_IO","Cannot read status save")
		var file_length:int=limited.get_length();limited.close()
		if file_length>StatusSave.MAX_SAVE_BYTES:return C.fail("STATUS_SAVE_BUDGET","Status save exceeds the declared read budget")
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_trace_load("parsed_save")
	if status_gameplay_mode:
		var unwrapped:Dictionary=StatusSave.unwrap(value)
		if not unwrapped.ok:return unwrapped
		value=unwrapped.engine
	if not value is Dictionary or not value.get("state") is Dictionary or not value.state.get("flags") is Dictionary or not value.state.get("generated_world") is Dictionary: return C.fail("INVALID_SAVE", "存档状态格式无效。")
	if value.state.generated_world.get("catalog_sha256") != CoastWorld.catalog_sha256() or value.state.generated_world.get("bundle_id", "") != CoastWorld.bundle_id(): return C.fail("BUNDLE_MISMATCH", "地图版本不同，存档文件已保留。请用原版本继续保存的冒险；已锁定的回合不会被改写。")
	if value.state.get("world_id") != CoastWorld.catalog().get("world_id"): return C.fail("WORLD_MISMATCH", "这个存档属于不同的冒险世界，文件已保留。")
	# Select only our known historical registry, then validate it before publishing.
	var legacy:bool = not value.state.flags.has("lamp_restored")
	var saved_rule: String = value.get("rule_id", "")
	if not saved_rule in ["ai_gm_test_coast_actions/v1", ReleaseRule.ID, "ai_gm_test_coast_release/v1"]: return C.fail("RULE_VERSION", "未知规则版本，存档不会被重新解释。")
	var previous_test_mode: bool = _release_v1_test
	_release_v1_test = saved_rule == "ai_gm_test_coast_release/v1"
	_trace_load("before_registry_engine")
	var candidate = _make_engine(null, legacy, MovementResolver.ID in value.get("resolver_ids", []), ("coast_manipulate_environment_v1" in value.get("resolver_ids", []) or "coast_manipulate_environment_v2" in value.get("resolver_ids", [])), "coast_basic_attack_v1" in value.get("resolver_ids", []), saved_rule != "ai_gm_test_coast_actions/v1", WeightedMovement.ID in value.get("resolver_ids", []), SceneTransition.ID in value.get("resolver_ids", []), CompositeActions.ID in value.get("resolver_ids", []), SceneTransitionV2.ID_V2 in value.get("resolver_ids", []), GateActions.ID in value.get("resolver_ids", []), "coast_manipulate_environment_v2" in value.get("resolver_ids", []), CreativeActions.ID in value.get("resolver_ids", []))
	_trace_load("after_registry_engine")
	var valid:Dictionary = candidate.load_data(value)
	_trace_load("after_engine_load")
	if not valid.ok:
		_release_v1_test = previous_test_mode
		return valid
	var required_scenes: Array = [value.state.actors.actor_player.scene_id]
	if value.state.has("scene_hexes"):
		for id in value.state.scenes:
			if not id in required_scenes: required_scenes.append(id)
	for scene_id in required_scenes:
		var descriptor: Dictionary = SceneAdapters.descriptor(value.state, scene_id)
		if not descriptor.ok:
			_release_v1_test = previous_test_mode
			return descriptor
	engine = candidate
	_trace_load("published_engine")
	active_action = ""; last_action = ""; narration = ""; _provisional_narration.clear()
	for id in value.pending: active_action = id
	var latest_turn := -1
	for id in value.receipts:
		if int(value.receipts[id].turn) > latest_turn:
			latest_turn = int(value.receipts[id].turn); last_action = id
	last_feedback = CoastStory.feedback(authoritative_result(),state_copy())
	var prose:Dictionary=NarrationLog.load(path,engine)
	_narration_records=prose.records; narration_log_status=prose.status
	_trace_load("loaded_narration")
	if phase()=="idle" and _narration_records.has(last_action):narration=_narration_records[last_action].narration
	return {"ok":true,"narration_log_status":prose.status,"narration_warning":prose.get("warning","")}
func commit() -> Dictionary:
	var result := super.commit()
	if result.ok:
		last_feedback = CoastStory.feedback(authoritative_result(),state_copy())
		if not _provisional_narration.is_empty() and _provisional_narration.action_id==last_action and _provisional_narration.stage_hash==result.get("receipt",{}).get("stage_hash"):
			record_narration(last_action,_provisional_narration.narration,"manual")
		_provisional_narration.clear()
	return result
func journal_entries() -> Array:
	# Rebuild committed player-visible history from validated authoritative receipts.
	# Canceled drafts and optional prose are not treated as committed world history.
	var entries:Array=[]
	var saved:Dictionary=engine.save_data()
	var receipts:Array=saved.receipts.values()
	receipts.sort_custom(func(a,b): return int(a.turn)<int(b.turn))
	# Narrate each committed turn from its then-current chapter flags, not today's
	# ending. Later completion/trust must never rewrite an earlier clue/failure.
	var historical:Dictionary={"flags":{"coast_observed":false,"keeper_trust":false,"lamp_restored":false}, "actors": {}, "items": {}}
	for id in saved.state.actors: historical.actors[id] = {"id": id, "name": saved.state.actors[id].name}
	for id in saved.state.items: historical.items[id] = {"id": id, "name": saved.state.items[id].name}
	for receipt in receipts:
		for patch in receipt.patches:
			if patch.type=="flag_set": historical.flags[patch.flag_id]=patch.value
		var actor_name: String = "你" if receipt.actor_id == "actor_player" else historical.actors.get(receipt.actor_id, {}).get("name", receipt.actor_id)
		entries.append({"title":"%s · 第%d次行动" % [actor_name,int(receipt.turn)],"text":DisplayText.player_intent(String(receipt.goal))})
		entries.append({"title":"回合结束 · 第%d回合"%int(receipt.turn),"text":CoastStory.feedback(engine.authoritative_result(receipt.action_id),historical)})
		if _narration_records.has(receipt.action_id) and NarrationLog._valid(_narration_records[receipt.action_id],saved):
			entries.append({"title":"叙事记录 · 第%d次行动"%int(receipt.turn),"text":_narration_records[receipt.action_id].narration,"non_authoritative":true,"action_id":receipt.action_id})
	return entries
func authority_text() -> String:
	var state := state_copy()
	if state.is_empty(): return "真实地理加载失败；未创建冒险"
	var action := action_copy(); var result := authoritative_result()
	var lines: Array[String] = [_facts_line(state,"当前事实")]
	var movement:=frozen_movement_preview()
	if not movement.is_empty():lines.append("已冻结路线：%d格 · 成功消耗%d体力 · 整条路线1回合 / 巡逻1次；失败不移动、不扣步行体力。" % [movement.get("distance", movement.cost),movement.cost])
	if phase() == "ready_roll":
		var checks: Array[String] = []
		for check in action.checks: checks.append("%s：≤%d/10000" % [check.id,check.success_at_most] if check.method == "random" else "%s：%s" % [check.id,"直接成功" if check.method == "direct_success" else "直接失败"])
		lines.append("已准备，未执行 / "+"；".join(checks))
	if phase() == "rolled": lines.append(_outcome_line(action.outcomes,action.rolls)+" / 已锁定，事实未变")
	if phase() == "staged":
		lines.append(_facts_line(action.staged,"暂存未提交")); lines.append(_outcome_line(result.outcomes,result.rolls))
	elif not result.is_empty(): lines.append("上次结果 / "+_outcome_line(result.outcomes,result.rolls))
	if not last_feedback.is_empty(): lines.append(last_feedback)
	return "\n".join(lines)
func _facts_line(state: Dictionary, prefix: String) -> String:
	var a: Dictionary = state.actors.actor_player
	return "%s v%d / 回合%d：坐标(%d,%d) · 体力%d/%d · 果酒%d · 岸线%s · 芦灯%s" % [prefix,state.state_version,state.turn,a.hex[0],a.hex[1],a.stamina.current,a.stamina.max,state.items.item_wine.quantity,"已观察" if state.flags.coast_observed else "未观察","已信任" if state.flags.keeper_trust else "未信任"]

func default_save_path() -> String:return StatusSave.PATH if status_gameplay_mode else COAST_SAVE
func default_request_path() -> String:return StatusSave.REQUEST_PATH if status_gameplay_mode else COAST_REQUEST
func export_request(path:String=COAST_REQUEST) -> Dictionary:
	return super.export_request(StatusSave.REQUEST_PATH if status_gameplay_mode and path==COAST_REQUEST else path)
