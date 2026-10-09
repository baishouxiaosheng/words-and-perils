extends "res://tests/generated_v3_npc/test_main.gd"
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
const Examples=preload("res://view/generated_v3_npc/assessments.gd")
const RUNTIME_OUT="res://artifacts/runtime_npc_main/"
const KEY="synthetic-main-npc-test-only"
var trace_rows=[]
func envelope(reply:Dictionary)->String:return C.bytes({"choices":[{"finish_reason":"stop","message":{"content":C.bytes(reply)}}]})
func outgoing(mock:Node)->Dictionary:return JSON.parse_string(JSON.parse_string(mock.sent.back().body).messages[1].content)
func assessed(request:Dictionary,kind:String="talk")->Dictionary:
	var prototype=request.duplicate(true);prototype.context.goal=Examples.goal(kind,request.context.attention_focus.get("hex",request.context.facts.actors.actor_player.hex))
	var made:Dictionary=Examples.build(prototype)
	if not made.ok:return {}
	made.assessment.provenance={"provider":"mock_test_transport","live":false,"kind":"model_reply"};return made.assessment
func prose(request:Dictionary,text_:String="离线测试叙述：问路已经结算，入口位置以旅途笔记为准。")->Dictionary:
	return {"schema_version":"ai_gm_narration/v1","action_id":request.action_id,"state_version":request.state_version,"context_hash":request.context_hash,"narration":text_}
func record(label:String):
	trace_rows.append({"label":label,"phase":app.playtest.phase(),"world_id":app.playtest.state_copy().world_id,"turn":app.playtest.state_copy().turn,"authority_sha256":C.digest(app.playtest.save_data()),"rng_sha256":C.digest(app.playtest.engine.save_data().rng),"runtime_epoch":app.runtime_ai._epoch,"runtime_operation":app.runtime_ai._operation.duplicate(true),"prose_entries":app._runtime_adapter().narration_entries().size() if app.generated_v3_npc_mode else -1,"mock_only":true})
func shot(name_:String):
	await frames();await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image();var path=RUNTIME_OUT+name_+".png"
	check(image.save_png(path)==OK,"PNG "+name_)
	var decoded=Image.load_from_file(path);check(decoded.get_size()==Vector2i(1280,720) and root.size==decoded.get_size() and app.viewport.size==decoded.get_size(),"actual1280x720 root/world/PNG "+name_)
	shots.append({"name":name_,"width":decoded.get_width(),"height":decoded.get_height()})
func run():
	DirAccess.make_dir_recursive_absolute(RUNTIME_OUT);root.size=Vector2i(1280,720)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	app.v3_radius_choice.select(0);app.v3_village_choice.button_pressed=true;await app.start_v3_from_dialog();await frames()
	var old:RefCounted=app.playtest;var old_authority=C.bytes(old.save_data());app.set_player_intent("旧村落保留的草稿",false)
	app.v3_adventure_style.select(1);app.v3_vegetation_choice.button_pressed=true;await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_npc_mode and app.playtest.ready().ok and app.board.load_error.is_empty(),"current village adventure with forest enters real Main"):finish_runtime_main();return
	check(app.runtime_connection_panel.visible and app.runtime_ai._adapter.adapter==app.playtest,"real connection panel binds only view facade")
	check(not app.runtime_ai.automatic_assessment_enabled(),"new window starts offline")
	var npc_hex:Array=app.playtest.state_copy().actors[app.playtest.source.npc_id].hex
	if not check(await walk(npc_hex),"legitimate assessed walking reaches NPC"):finish_runtime_main();return
	if app.playtest.state_copy().actors.actor_player.stamina.current<2:check(sample("rest"),"rest before two paid conversations")
	close_camera(npc_hex);app._apply_focus(app.playtest.npc_reference())
	app.set_player_intent("请告诉我进村的道路，我想记住你的指引。",false);app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and not app.runtime_ai.busy(),"offline natural text waits honestly")
	app.cancel_pending();check(app.playtest.phase()=="idle","offline waiting can cancel")
	var runtime:Node=app.runtime_ai;var mock=Mock.new();runtime.set_transport(mock)
	var panel:Control=app.runtime_connection_panel
	panel.endpoint_input.text="https://example.invalid/v1/chat/completions";panel.model_input.text="provided-synthetic-model";panel.key_input.text=KEY;panel.consent_input.button_pressed=true;panel._apply();await frames()
	check(mock.sent.is_empty() and runtime.connection_enabled and not runtime.automatic_assessment_enabled(),"apply settings sends nothing; manual request remains available")
	check(panel.key_input.text.is_empty() and panel.key_input.secret,"synthetic credential field cleared after memory-only apply")
	check(app.relay_note.text.contains("离线测试") and not app.relay_note.text.contains("服务已验证"),"mock channel is visibly not a live provider claim")
	app.show_help();check(not app.journal.get_parsed_text().contains("物品互动尚未开放"),"current adventure help does not fall through older exploration copy")
	app.show_ai_connection();await frames();await shot("connection_manual");app.advanced_dialog.hide()
	var before=C.bytes(app.playtest.save_data());var send_count=mock.sent.size()
	app.set_player_intent("误贴凭据 "+KEY,false);app.end_turn()
	check(C.bytes(app.playtest.save_data())==before and mock.sent.size()==send_count and app.playtest.phase()=="idle","credential-like goal rejected before journal/request/save creation")
	app._apply_focus(app.playtest.npc_reference());app.set_player_intent("请告诉我从这里进入村落的道路。",false);app.end_turn()
	check(app.next_step_label.text.contains("请求评估"),"manual configured request is discoverable without automatic setting")
	var exact:Dictionary=app.playtest.request();var frozen=C.bytes(app.playtest.save_data());record("manual_pending")
	if not check(not panel.assessment_button.disabled and panel.narration_button.disabled and panel._phase=="awaiting_assessment","actual manual button enabled only for current pending assessment"):finish_runtime_main();return
	panel.assessment_button.pressed.emit();var request=outgoing(mock);var token:int=mock.sent.back().request_id
	check(panel.assessment_button.disabled and panel.narration_button.disabled,"both request buttons disabled while transport busy")
	check(C.bytes(request)==C.bytes(exact) and C.bytes(app.playtest.save_data())==frozen,"real panel sends exact frozen request without acting")
	var pending_adapter:RefCounted=app.playtest;var pending_epoch:int=runtime._epoch
	app.on_tool_selected(19)
	check(app.generated_v3_npc_mode and app.playtest==pending_adapter and runtime.busy() and runtime._epoch==pending_epoch and C.bytes(app.playtest.save_data())==frozen,"UI refuses assessment-pending mode switch and preserves active request")
	app._apply_focus(app.playtest.item_reference());app.end_turn()
	check(mock.sent.size()==1 and C.bytes(app.playtest.request())==C.bytes(exact),"selection and repeated primary click cannot resend or retarget")
	panel.automatic_narration_input.button_pressed=true
	var turn:int=app.playtest.state_copy().turn;var rng=C.bytes(app.playtest.engine.save_data().rng)
	mock.respond(token,envelope(assessed(request)));await frames()
	if not check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,"real Main validates locks stages commits exactly once"):finish_runtime_main();return
	check(C.bytes(app.playtest.engine.save_data().rng)==rng,"safe direct conversation preserves RNG")
	check(mock.sent.size()==2 and outgoing(mock).phase=="narration" and not outgoing(mock).context.provisional_until_commit,"real Main asks optional prose only after commit")
	var committed=C.bytes(app.playtest.save_data());var nr=outgoing(mock);var ntoken:int=mock.sent.back().request_id
	mock.respond(token,envelope(assessed(request)));check(C.bytes(app.playtest.save_data())==committed,"late duplicate cannot commit twice")
	mock.respond(ntoken,envelope(prose(nr)));await frames()
	check(app._runtime_adapter().narration_entries().size()==1 and C.bytes(app.playtest.save_data())==committed,"Main records exactly one display-only narration")
	check(panel.assessment_button.disabled and panel.narration_button.disabled and panel._phase=="committed","recorded committed receipt disables both duplicate request buttons")
	check(not app.playtest.learned_notes().is_empty() and app.playtest.state_copy().npc_state.contacts[app.playtest.source.npc_id].conversation_count==1,"real typed knowledge persists")
	app.show_npc_notes();await shot("learned_notes");app.npc_notes_dialog.hide();record("committed_with_prose")
	send_count=mock.sent.size();check(not runtime.request_narration().ok and mock.sent.size()==send_count,"same committed receipt cannot trigger repeated narration cost")
	var text_before=app.playtest.narration
	check(app.apply_playtest_reply(prose(nr,"手工重复文字不能覆盖首次叙述。")) and app.playtest.narration==text_before and app._runtime_adapter().narration_entries().size()==1,"manual prose shares idempotent view log")
	app.save_game();check(app.last_save_result.ok and app.last_save_result.narration_log_saved,"Main saves unchanged core plus sidecar")
	var path:String=app.playtest.default_save_path();check(not FileAccess.get_file_as_string(path).contains(KEY) and not FileAccess.get_file_as_string(path).contains("离线测试叙述"),"core save has neither credential nor display prose")
	app.load_game();await frames();check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==committed and app._runtime_adapter().narration_entries().size()==1,"Main load recovers exact core and receipt-bound sidecar")
	check(app.journal.get_parsed_text().contains("离线测试叙述"),"loaded display history is visible")
	if not app.journal_open:app.toggle_journal()
	await shot("loaded_history");if app.journal_open:app.toggle_journal()
	# Same primary entry now supports automatic interpretation; no new profile.
	panel.automatic_assessment_input.button_pressed=true;panel.automatic_narration_input.button_pressed=false
	app._apply_focus(app.playtest.npc_reference());app.set_player_intent("再确认一次村口的道路，请不要替我移动。",false)
	var knowledge=C.bytes(app.playtest.state_copy().npc_state.learned_facts);turn=app.playtest.state_copy().turn;send_count=mock.sent.size();app.end_turn()
	check(mock.sent.size()==send_count+1 and app.playtest.phase()=="awaiting_assessment","primary free-text action automatically requests when explicitly enabled")
	request=outgoing(mock);token=mock.sent.back().request_id;mock.respond(token,envelope(assessed(request)));await frames()
	check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1 and C.bytes(app.playtest.state_copy().npc_state.learned_facts)==knowledge,"second assessed talk pays one turn but preserves first proof")
	check(panel.status_label.text.contains("回合已结算") and not panel.status_label.text.contains("尚未结算") and panel.status_label.tooltip_text.contains("上次接口消息"),"connection panel states current committed phase with separate historical transport message")
	var previous_transport_message:String=panel.status_label.tooltip_text;app.sync_playtest_request()
	check(panel.status_label.tooltip_text==previous_transport_message,"repeated UI sync preserves historical transport diagnostic")
	app.show_ai_connection();await frames();app.advanced_scroll.ensure_control_visible(panel.status_label);await frames();await shot("committed_connection");app.advanced_dialog.hide()
	app._apply_focus(app.playtest.npc_reference());app.show_focus_details();check(app.focus_details_text.text.contains("自由意图需要有效评估"),"NPC details accepts connected or imported assessment without misleading copy");await shot("repeat_contact");app.focus_details_dialog.hide()
	# Pending save/load replaces engine/transport generation without losing the
	# frozen goal/focus or admitting a delayed same-action response.
	app.set_player_intent("我先观察脚边，不要移动。",false);app._apply_focus(app.playtest.tile_reference(app.playtest.state_copy().actors.actor_player.hex));app.end_turn()
	request=outgoing(mock);token=mock.sent.back().request_id;var pending=C.bytes(app.playtest.save_data());app.save_game();app.load_game();await frames()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==pending and not runtime.busy(),"pending save/load exact and invalidates old transport")
	check(not panel.assessment_button.disabled and panel.narration_button.disabled,"pending load refreshes real retry button phase")
	mock.respond(token,envelope(assessed(request,"observe")));check(C.bytes(app.playtest.save_data())==pending,"late pre-load reply cannot freeze or commit a new engine")
	var retry:Dictionary=runtime.request_assessment();request=outgoing(mock);mock.respond(retry.request_id,envelope(assessed(request,"observe")));await frames()
	check(app.playtest.phase()=="idle" and app.playtest.state_copy().flags.observations>0,"loaded pending intent can receive one new valid assessment")
	record("recovered_pending_committed")
	# An explicit offline example remains offline even with auto mode enabled.
	send_count=mock.sent.size();app.fill_generated_sample("observe");app.end_turn()
	check(mock.sent.size()==send_count and app.playtest.fixture_available(),"explicit example does not silently become a provider request")
	app.cancel_pending()
	check(panel.assessment_button.disabled and not panel.narration_button.disabled and panel._phase=="committed","cancel refreshes buttons to latest unrecorded receipt")
	# Switching views preserves the old session and the current narration log.
	var new_authority=C.bytes(app.playtest.save_data());var new_adapter:RefCounted=app.playtest;app.set_player_intent("新村庄草稿",false)
	var late_narration:Dictionary=runtime.request_narration();var late_request:Dictionary=outgoing(mock)
	check(late_narration.ok and runtime.busy(),"unrecorded committed receipt starts optional narration before mode switch")
	app.on_tool_selected(19);await frames()
	check(app.playtest==old and C.bytes(old.save_data())==old_authority and app.goal.text=="旧村落保留的草稿","old village authority and draft restored")
	var old_status:String=app.status_label.text;var old_journal:String=app.journal.text
	mock.respond(late_narration.request_id,envelope(prose(late_request,"迟到文字不得泄漏到另一个冒险。")))
	check(not runtime.busy() and app.status_label.text==old_status and app.journal.text==old_journal and C.bytes(old.save_data())==old_authority,"late optional prose cannot leak status journal or authority across UI mode switch")
	app.on_tool_selected(27);await frames()
	check(app.playtest==new_adapter and C.bytes(app.playtest.save_data())==new_authority and app.goal.text=="新村庄草稿" and app._runtime_adapter().narration_entries().size()==1,"current adventure and view narration survive mode return")
	await shot("returned_adventure");record("mode_return")
	var identity=C.bytes(app.playtest.source.identity)
	app.reset_playtest();await frames()
	check(app.playtest.state_copy().turn==0 and C.bytes(app.playtest.source.identity)==identity and app._runtime_adapter().narration_entries().is_empty(),"same source/profile restart clears optional old prose and knowledge")
	check(not runtime.busy(),"restart has no leftover request")
	finish_runtime_main()
func finish_runtime_main():
	FileAccess.open(RUNTIME_OUT+"main_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"screenshots":shots,"trace":trace_rows,"transport_live":false,"network_calls":0,"scope":"real Main callbacks with synthetic HTTP only; original V19 authority/profile unchanged"},"\t"))
	print("RUNTIME_NPC_MAIN ",checks," ",failures);quit(0 if failures.is_empty() else 1)
