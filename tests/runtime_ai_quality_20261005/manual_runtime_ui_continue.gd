extends SceneTree
## Independent UI observer with a disclosed local mock server only.
## F7 supplies one explicit synthetic server reply. F8 records. F9 exits.
## All game actions, settings application, navigation and selection use the UI.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
var app:Control
var mock:Node
var out=""
var rows:Array=[]
var server_events:Array=[]
var busy=false
var closing=false
var keys:Dictionary={}
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	run.call_deferred()
func frames(n:int=3):
	for i in range(n):await process_frame
func run():
	if out.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	app=load("res://main.tscn").instantiate();app.startup_legacy=true;root.add_child(app);await frames(8)
	mock=Mock.new();app.runtime_ai.set_transport(mock)
	var panel=app.runtime_connection_panel
	# Synthetic configuration is visible but unapplied. No real credentials.
	panel.endpoint_input.text="https://example.invalid/v1/chat/completions"
	panel.model_input.text="qa-local-mock-no-network"
	panel.key_input.text="synthetic-qa-manual-runtime"
	panel.timeout_input.value=8
	panel.consent_input.button_pressed=false
	panel._mark_dirty()
	# Disclosed continuation setup only; the first pass already exercised menu loading.
	app.continue_v3_npc_adventure();await frames(4)
	auto_accept_quit=false;root.close_requested.connect(finish);process_frame.connect(poll)
	await record("start")
	print("MANUAL_RUNTIME_READY F7=mock reply F8=record F9=finish; provider is local mock only")
func poll():
	if closing:return
	for key in [KEY_F7,KEY_F8,KEY_F9]:
		var now=Input.is_physical_key_pressed(key)
		if now and not keys.get(key,false):
			if key==KEY_F7:server_reply.call_deferred()
			elif key==KEY_F8:record.call_deferred("manual_"+str(rows.size()))
			else:finish.call_deferred()
		keys[key]=now
func server_reply():
	if not app.runtime_ai.client.busy() or mock.sent.is_empty():return
	var summary:Dictionary=app.runtime_ai.client.request_summary()
	var sent:Dictionary=mock.sent.back()
	if sent.request_id!=summary.request_id:return
	var body:Dictionary=JSON.parse_string(sent.body)
	var request:Dictionary=JSON.parse_string(body.messages[1].content)
	var reply:Dictionary={"schema_version":"ai_gm_narration/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"离线测试叙事：旅人完成了本次观察。实际位置、体力与观察记录以游戏回执为准。"}
	if request.phase=="assessment":
		var facts:Dictionary=request.context.facts
		var actor:Dictionary=facts.actors.actor_player
		var hex:Array=actor.hex
		var cell:Dictionary=facts.hexes["%d,%d"%hex]
		reply={"schema_version":"ai_gm_assessment/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":"离线测试：准备观察脚下的地格，行动尚未发生。","interpretation":"人工编写的本地模拟回复，将明确的观察意图限定为当前地格观察；不是实时模型理解能力证据。","resolver_id":"generated_v3_observe_v1","bindings":{"actor_id":"actor_player","target_hex":hex},"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","cell"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":actor},{"id":"cell","path":"/hexes/%d,%d"%hex,"expected":cell}],"provenance":{"provider":"mock_test_transport","live":false,"kind":"model_reply"}}
	var index=server_events.size()
	FileAccess.open(out.path_join("server_%d_http.json"%index),FileAccess.WRITE).store_string(sent.body)
	FileAccess.open(out.path_join("server_%d_reply.json"%index),FileAccess.WRITE).store_string(C.bytes(reply))
	FileAccess.open(out.path_join("server_%d_engine.json"%index),FileAccess.WRITE).store_string(C.bytes(app.playtest.request()))
	server_events.append({"request_id":summary.request_id,"action_id":request.action_id,"phase":request.phase,"request_hash":C.digest(request),"live":false})
	mock.respond(summary.request_id,C.bytes({"choices":[{"finish_reason":"stop","message":{"content":C.bytes(reply)}}]}))
func record(label_:String):
	if busy or not is_instance_valid(app):return
	busy=true;await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image();var p=out.path_join(label_+".png")
	var ok=img.save_png(p)==OK
	var adapter=app.playtest
	var state:Dictionary=adapter.state_copy() if adapter!=null else {}
	var save:Dictionary=adapter.save_data() if adapter!=null and adapter.has_method("save_data") else {}
	var request:Dictionary=adapter.request() if adapter!=null else {}
	var action:Dictionary=adapter.action_copy() if adapter!=null else {}
	var panel=app.runtime_connection_panel
	var row={"label":label_,"png":p,"png_saved":ok,"root":[root.size.x,root.size.y],"world_raster":[app.viewport.size.x,app.viewport.size.y],"png_size":[img.get_width(),img.get_height()],"preview":app.is_map_preview(),"profile":state.get("generated_world",{}).get("profile",""),"phase":adapter.phase() if adapter!=null else "preview","turn":state.get("turn",-1),"authority_hash":C.digest(save),"world_hash":C.digest(state),"actor":state.get("actors",{}).get("actor_player",{}).duplicate(true),"flags":state.get("flags",{}).duplicate(true),"action_hash":C.digest(action),"rng_hash":C.digest(save.get("engine",{}).get("rng",{})),"request_hash":C.digest(request),"request_bytes":C.bytes(request).to_utf8_buffer().size(),"frozen_focus":action.get("focus",{}),"selected_focus":app.selected_focus.duplicate(true),"draft":app.goal.text,"status":app.status_label.text,"phase_label":app.phase_label.text,"next_step":app.next_step_label.text,"legend":app.mode_legend.text,"relay_note":app.relay_note.text,"advanced_visible":app.advanced_dialog.visible,"runtime_busy":app.runtime_ai.busy(),"runtime_result":app.runtime_ai.last_result.duplicate(true),"runtime_metrics":app.runtime_ai.last_metrics.duplicate(true),"request_summary":app.runtime_ai.client.request_summary(),"sent_count":mock.sent.size(),"cancelled_tokens":mock.cancellations.duplicate(),"configured":app.runtime_ai.client.configured(),"consent":panel.consent_input.button_pressed,"automatic_assessment":app.runtime_ai.automatic_assessment,"automatic_narration":app.runtime_ai.automatic_narration,"panel_status":panel.status_label.text,"panel_buttons":{"assessment_disabled":panel.assessment_button.disabled,"narration_disabled":panel.narration_button.disabled,"cancel_disabled":panel.cancel_button.disabled},"last_save":app.last_save_result.duplicate(true),"last_load":app.last_load_result.duplicate(true)}
	if app.generated_v3_npc_mode:row["narration_entries"]=app._runtime_adapter().narration_entries()
	rows.append(row);write_report(false);busy=false
func write_report(done:bool):
	FileAccess.open(out.path_join("manual_report.json"),FileAccess.WRITE).store_string(JSON.stringify({"completed":done,"transport":"mock_test_transport","transport_live":false,"network_calls":0,"scope":"Corrected mouse/keyboard continuation. Test setup loads the exact preserved checkpoint through the normal continue callback and prefills visible synthetic settings; it never applies settings or performs a game action. F7 is an explicit local mock response, not a model call.","records":rows,"mock_server_events":server_events},"\t"))
func finish():
	if closing:return
	closing=true
	while busy:await process_frame
	await record("final");write_report(true)
	print("MANUAL_RUNTIME_COMPLETE records=",rows.size()," mocked_replies=",server_events.size())
	app.queue_free();await frames();quit(0)
