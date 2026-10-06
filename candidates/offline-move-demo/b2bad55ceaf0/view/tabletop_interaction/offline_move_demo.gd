extends Node
## Explicit, finite offline movement demonstration. No NLP or provider request.
## Main owns all submission/assessment/commit stages; source rules are unchanged.
const DisplayText=preload("res://view/playable_build/display_text.gd")
var _host:Control
var enabled:=false
var _dispatching:=false
var _busy:=false
var _observed_key:=""
var toggle:Button
var execute_button:Button
var hint:Label
var expected_text:=""
var expected_signed:=""
var expected_focus:Dictionary={}
var last_result:Dictionary={}
func _init(host:Control=null)->void:_host=host
func _ready()->void:
	name="OfflineMoveDemo"
	var box:=VBoxContainer.new();box.name="OfflineMoveDemoControls";box.add_theme_constant_override("separation",4)
	_host.goal.get_parent().get_parent().add_child(box)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);box.add_child(row)
	toggle=_host.compact_button("离线移动演示",func():pass);toggle.toggle_mode=true;toggle.toggled.connect(_set_enabled);row.add_child(toggle)
	toggle.tooltip_text="显式启用有限代码演示；只接受下方给出的完整移动句，不连接模型。"
	execute_button=_host.compact_button("确认离线移动",_execute);execute_button.visible=false;row.add_child(execute_button)
	hint=_host.label("",15);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL;hint.visible=false;box.add_child(hint)
	_host.goal.text_changed.connect(_input_changed)
	_host.goal.text_set.connect(_input_changed)
	_host.apply_responsive_layout.call_deferred()
func _process(_delta:float)->void:
	if not is_instance_valid(_host):return
	var board:Node=_host.board if is_instance_valid(_host.board) else null
	var revision:Variant=board.get("world_state").get("state_version",-1) if board!=null else -1
	var key:=str([enabled,_host.coast_mode,_host._mode_epoch,_host.selected_focus,revision,_host.runtime_ai.connection_enabled,_host.runtime_ai.busy()])
	if key!=_observed_key:_observed_key=key;_refresh()
func _offline_error()->String:
	if not _host.coast_mode or _host.playtest==null:return "仅当前真实海岸支持这个离线演示。"
	if _host.runtime_ai.connection_enabled or _host.runtime_ai.busy():return "请先在接口设置中主动关闭连接；演示不会替你切换或发送请求。"
	if _host.world_build_busy or _host.generated_start_busy:return "地图仍在准备，请稍候。"
	if _host._api_settings_open():return "请先关闭接口设置。"
	return ""
func _set_enabled(value:bool)->void:
	if value:
		var error:=_offline_error()
		if not error.is_empty():toggle.set_pressed_no_signal(false);_host.set_status(error);return
	enabled=value
	_refresh();_host.apply_responsive_layout.call_deferred()
func _plan()->Dictionary:
	var error:=_offline_error()
	if not error.is_empty():return {"ok":false,"error":error}
	if _host.playtest.phase()!="idle":return {"ok":false,"error":"先完成或取消当前行动；不会重复提交或扣费。"}
	if _host._waiting_enemy_phase():return {"ok":false,"error":"当前必须先处理敌方回合；离线移动不会创建另一行动。"}
	var focus:Dictionary=_host.selected_focus.duplicate(true)
	if focus.get("kind")!="tile" or not focus.get("hex") is Array or focus.hex.size()!=2:return {"ok":false,"error":"先点击一个目标地格；不会替你挑选邻格。"}
	var resolved:Dictionary=_host.playtest.attention(focus)
	if not resolved.get("ok",false):return {"ok":false,"error":"所选目标已失效，请重新选择。"}
	var state:Dictionary=_host.playtest.state_copy()
	if focus.get("world_id")!=state.world_id:return {"ok":false,"error":"目标不属于当前世界，请重新选择。"}
	if state.actors.actor_player.scene_id!="scene_coast":return {"ok":false,"error":"此录制入口只支持海岸地格。"}
	var preview:Dictionary=_host.playtest.movement_preview(focus.hex)
	if not preview.get("ok",false) or preview.get("route",[]).size()<2:return {"ok":false,"error":"目标是当前位置或路线不可达，未移动或扣费。"}
	var signed:String=_host.playtest.movement_goal(focus.hex)
	if not DisplayText.is_signed_sample(signed):return {"ok":false,"error":"当前规则没有登记这个离线移动模板。"}
	return {"ok":true,"focus":focus,"signed":signed,"text":DisplayText.player_intent(signed),"preview":preview,"world_id":state.world_id,"state_version":state.state_version,"adapter":_host.playtest.get_instance_id()}
func _input_changed()->void:
	if is_instance_valid(execute_button):execute_button.disabled=_busy or expected_text.is_empty() or _host.goal.text!=expected_text
func _refresh()->void:
	if not is_instance_valid(toggle):return
	execute_button.visible=enabled;hint.visible=enabled
	if not enabled:
		expected_text="";expected_signed="";expected_focus.clear();return
	var plan:=_plan()
	if not plan.ok:
		expected_text="";expected_signed="";expected_focus.clear();execute_button.disabled=true
		hint.text="离线代码演示 · 未调用模型\n"+str(plan.error);return
	expected_text=plan.text;expected_signed=plan.signed;expected_focus=plan.focus.duplicate(true)
	hint.text="离线代码演示 · 未调用模型\n请完整输入：%s\n目标（%d，%d） · %d格 · 体力消耗%d · 整段1回合"%[expected_text,plan.focus.hex[0],plan.focus.hex[1],plan.preview.route.size()-1,plan.preview.cost]
	execute_button.disabled=_busy or _host.goal.text!=expected_text
func handle_end_turn()->bool:
	if not enabled or _dispatching or not _host.coast_mode:return false
	# Existing pending/locked stages retain their original recovery controls.
	if _host.playtest!=null and _host.playtest.phase()!="idle":return false
	_execute();return true
func _reject(text_:String)->void:
	last_result={"ok":false,"error":text_};_host.set_status(text_);_refresh()
func _execute()->void:
	if not enabled or _busy:return
	var plan:=_plan()
	if not plan.ok:_reject(plan.error);return
	var original:String=_host.goal.text
	if original!=plan.text:
		_reject("此离线演示只接受显示的完整移动句；未修改你的原文，也未执行。")
		return
	# User explicitly confirms this exact visible sentence against the selected
	# coordinate and current legal path. Do not relax global signed-draft rules.
	_busy=true;execute_button.disabled=true
	_host._signed_sample_goal=plan.signed;_host._signed_sample_display=original
	_dispatching=true;_host.end_turn();_dispatching=false
	var action_id:String=_host.playtest.active_action
	var action:Dictionary=_host.playtest.action_copy()
	if _host.playtest.get_instance_id()!=plan.adapter or _host.playtest.phase()!="awaiting_assessment" or action.get("goal")!=plan.signed or action.get("actor_id")!="actor_player":
		_busy=false;_reject("离线意图未按预期建立，保留当前阶段；没有额外提交。")
		return
	if not _host.playtest.fixture_available():
		_busy=false;_reject("原规则未接受完整署名模板，行动仍等待评估。")
		return
	_host.playtest_fixture()
	var saved:Dictionary=_host.playtest.engine.save_data()
	var receipt:Dictionary=saved.get("receipts",{}).get(action_id,{})
	last_result={"ok":not receipt.is_empty(),"action_id":action_id,"original_input":original,"signed_goal":plan.signed,"target":plan.focus.hex.duplicate(),"preview_cost":plan.preview.cost,"receipt_hash":receipt.get("receipt_hash",""),"live":false}
	_busy=false
	if receipt.is_empty():_host.set_status("原规则尚未完成提交，请查看当前阶段；不会再扣一次费用。")
	else:_host.set_status("离线代码演示完成 · 原规则已提交一次 · 未调用模型。")
	_refresh();_host.apply_responsive_layout.call_deferred()
