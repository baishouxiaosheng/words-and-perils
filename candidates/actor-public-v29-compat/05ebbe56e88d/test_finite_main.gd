extends SceneTree
## Finite real Main chain; authored replies, original tickets/RNG/resolvers only.
const Main=preload("res://main.tscn")
const F=preload("res://tests/actor_status_entry/entry_fixture.gd")
const OldEnemy=preload("res://view/generated_v3_enemy/adapter.gd")
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const MAIN_SHA="05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f"
var app
var f=F.new()
var mock
var checks=0
var failures:Array=[]
var actions:Array=[]
var world_id=""
var saved_status:Dictionary={}
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);printerr("ACTOR_FINITE_FAIL ",label)
	return ok
func frames(n:int=2)->void:
	for _i in n:await process_frame
func manual(reply:Dictionary)->bool:
	app.show_import();app.import_text.text=C.bytes(reply);app.import_decision()
	await frames()
	return expect(not app.import_dialog.visible and app.import_error_label.text.is_empty(),"actual manual import accepts bound typed reply")
func action(kind:String,extra:Dictionary={})->Dictionary:
	var before:Dictionary=app.playtest.state_copy()
	var who:String=app.playtest.current_actor_id()
	var draft:String=app.goal.text
	if who==F.PLAYER:
		app.set_player_intent("Finite authored ordinary intention: "+kind)
		app.submit_button.pressed.emit();await frames()
	else:
		app._begin_required_enemy_turn();await frames()
		if not expect(app.playtest.decision_pending(),"actual enemy slot prepares its own proposal"):return {}
		if not await manual(f.proposal(app.playtest.request(),"Finite authored hostile intention: "+kind)):return {}
		expect(app.goal.text==draft,"enemy proposal preserves player editor")
	if not expect(app.playtest.phase()=="awaiting_assessment" and app.playtest.action_copy().actor_id==who,"actual Main awaits exact actor assessment"):return {}
	var id:String=app.playtest.active_action
	var accepted_before:int=app.board.committed_effects.accepted_receipts
	if not await manual(f.assessment(app.playtest.request(),kind,extra)):return {}
	if not expect(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==before.turn+1,"Main performs original roll-stage-commit exactly once"):return {}
	var receipt:Dictionary=app.playtest.committed(id)
	if not expect(not receipt.is_empty() and receipt.actor_id==who,"real committed receipt belongs to exact actor"):return {}
	var record:Dictionary=app.playtest.public_receipt_record(id)
	expect(not record.is_empty() and record.action_id==id,"real public status record binds committed action")
	expect(app.actor_render_error.is_empty() and app.board.visible,"actual source-bound board remains admitted")
	var count:int=app.board.committed_effects.accepted_receipts
	expect(count==accepted_before+1,"fresh status receipt presented once")
	var dup:Dictionary=app.board.present_status_receipt(receipt,before,record)
	expect(not dup.get("presented",true) and app.board.committed_effects.accepted_receipts==count,"duplicate status/death-capable receipt cannot replay effects")
	actions.append({"actor_id":who,"kind":kind,"action_id":id,"receipt_hash":receipt.receipt_hash,"turn":receipt.turn})
	expect(mock.sent.is_empty(),"manual finite actions never request a model")
	return receipt
func configure_real_controls()->bool:
	var p=app.runtime_connection_panel
	app.show_ai_connection();await frames()
	expect(p.settings_dialog.visible and p.role_fields.size()==2,"actual P1 modal uses two real roles")
	for role in ["decision","narration"]:
		var field:Dictionary=p.role_fields[role]
		field.preset.select(0);field.preset.item_selected.emit(0)
		field.model_choice.select(0);field.model_choice.item_selected.emit(0)
		field.endpoint.text="https://offline.invalid/v1/chat/completions"
		field.model.text="finite-actor-fixture";field.model.text_changed.emit(field.model.text)
		field.key.text="SYNTHETIC_ONLY_NOT_A_KEY_"+role
		field.budget.text="65536";field.timeout.value=30.0
		field.reasoning.text="";field.local.button_pressed=false;field.json_mode.button_pressed=false
		field.token_parameter.select(0)
	p.enable_input.button_pressed=true
	p.assessment_draft_input.button_pressed=false;p.narration_draft_input.button_pressed=false
	p.settings_dialog.confirmed.emit();await frames()
	return expect(not p.settings_dialog.visible and app.runtime_ai.connection_enabled and not app.runtime_ai.automatic_assessment and not app.runtime_ai.automatic_narration and not app.runtime_ai.intention_consent and mock.sent.is_empty(),"real P1 Save honors both unchecked automatic flags and does not grant separate intention consent")
func run()->void:
	var expected:String=OS.get_environment("FOGBANK_ACTOR_FINITE_USER_DIR")
	if not expect(not expected.is_empty() and OS.get_user_data_dir()==expected,"fresh exact isolated user directory"):finish();return
	if not expect(FileAccess.get_sha256("res://main.gd")==MAIN_SHA,"exact approved new Main"):finish();return
	root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
	app=Main.instantiate();root.add_child(app);current_scene=app;await frames(6)
	if not expect(app.coast_mode and app.playtest.state_copy().hexes.size()==1801,"real default Coast Main remains current public1801"):finish();return
	var coast=app.playtest;var coast_before:String=C.bytes(coast.save_data())
	mock=Mock.new()
	if not expect(app.runtime_ai.set_transport(mock).get("ok",false) and not mock.info().live,"no-network mock installed before any role configuration"):finish();return
	if not await configure_real_controls():finish();return
	if not f.admit():failures.append_array(f.failures);finish();return
	var old=OldEnemy.new(f.source_data)
	if not expect(old.ready().get("ok",false),"original generated source admitted"):finish();return
	app._switch_mode_to("generated_v3_enemy",old);await frames()
	app.on_tool_selected(app.ACTOR_STATUS_ENTRY_NEW);await frames()
	if not expect(app.actor_status_mode and app.playtest.core.source.identity.profile_hash==F.FROZEN_PROFILE,"actual advanced menu enters frozen public status profile"):finish();return
	world_id=app.playtest.state_copy().world_id
	expect(not app.actor_action_panel.consent.button_pressed and not app.runtime_ai.intention_consent,"actor consent starts separately false")
	var receipt:Dictionary=await action("status_source",{"target_actor_id":F.PLAYER,"source_id":"item_feather_vial"})
	if receipt.is_empty():finish();return
	saved_status=app.playtest.save_data()
	app.save_game()
	if not expect(app.last_save_result.get("ok",false),"actual status Main writes independent save"):finish();return
	app.load_game();await frames()
	if not expect(app.last_load_result.get("ok",false) and C.bytes(app.playtest.save_data())==C.bytes(saved_status),"actual status Main reopens identical profile facts/RNG/records"):finish();return
	var target:Array=app.playtest.core.source.base.enemy_placement_result.attack_anchor_hex
	var plan:Dictionary=app.playtest.source.navigation.plan(app.playtest.state_copy(),target,32)
	if not expect(plan.get("ok",false) and plan.route.size()<=33,"original source navigation supplies bounded real contact route"):finish();return
	for index in range(1,plan.route.size()):
		if app.playtest.current_actor_id()==F.ENEMY:break
		var preview:Dictionary=app.playtest.movement_preview(plan.route[index])
		if not preview.get("ok",false):
			if (await action("rest")).is_empty():finish();return
		if (await action("move",{"target_hex":plan.route[index]})).is_empty():finish();return
	if not expect(app.playtest.current_actor_id()==F.ENEMY and app._waiting_enemy_phase(),"real committed player movement reaches actual enemy slot"):finish();return
	var blocked:Dictionary=app.runtime_ai.request_intention()
	expect(not blocked.get("ok",false) and mock.sent.is_empty(),"P1 global configuration does not bypass unchecked actor intention consent")
	if (await action("observe",{"target_hex":app.playtest.state_copy().actors[F.ENEMY].hex})).is_empty():finish();return
	if not expect(app.playtest.current_actor_id()==F.PLAYER,"true player-enemy-player scheduler round trip"):finish();return
	app.save_game();saved_status=app.playtest.save_data();app.load_game();await frames()
	if not expect(app.last_save_result.get("ok",false) and app.last_load_result.get("ok",false) and C.bytes(app.playtest.save_data())==C.bytes(saved_status),"post enemy turn status save/reopen retains real authority"):finish();return
	app.switch_coast();await frames()
	if not expect(app.coast_mode and app.playtest==coast and C.bytes(coast.save_data())==coast_before,"actual Coast return preserves original independent adventure"):finish();return
	app.on_tool_selected(app.ACTOR_STATUS_ENTRY_CONTINUE);await frames()
	expect(app.actor_status_mode and app.last_load_result.get("ok",false) and C.bytes(app.playtest.save_data())==C.bytes(saved_status),"real Continue status menu reopens independent saved source profile after Coast")
	expect(mock.sent.is_empty() and not app.runtime_ai.intention_consent,"all finite paths remain no-network and no additional actor consent")
	finish()
func finish()->void:
	var report={"schema":"actor_v29_finite_main/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"profile_hash":F.FROZEN_PROFILE,"world_id":world_id,"actions":actions,"network_calls":0,"scope":"real Main menus, real P1 Save flags, original source/status resolver/scheduler/tickets/RNG/commit, independent save/reopen and Coast return; finite headless logic, no OS/GPU, live model, broad22-matrix or actual-death outcome claim"}
	var out=FileAccess.open(OS.get_environment("FOGBANK_ACTOR_FINITE_REPORT"),FileAccess.WRITE)
	if out==null:printerr("ACTOR_FINITE_REPORT_FAILED");quit(2);return
	out.store_string(JSON.stringify(report,"\t"));out.close()
	if is_instance_valid(app):app.free()
	print("ACTOR_FINITE_MAIN_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
