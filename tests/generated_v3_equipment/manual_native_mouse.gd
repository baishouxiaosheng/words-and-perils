extends SceneTree
## Real native mouse gear controls; actual offline assessed preparation only.
const Main=preload("res://main.tscn")
const A=preload("res://view/generated_v3_equipment/adapter.gd")
const E=preload("res://view/generated_v3_equipment/assessments.gd")
const Old=preload("res://view/generated_v3_npc/adapter.gd")
const Prior=preload("res://view/generated_v3_enemy/adapter.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Mock=preload("res://tests/ai_gm_http/mock_transport.gd")
const OUT="res://artifacts/generated_v3_equipment/native_mouse/"
var app:Node
var mock:Node
var checks=0
var failures:Array=[]
var events:Array=[]
var rows:Array=[]
var profiles:Array=[]
var stage_name="setup"
var kind=""
var sent_seen=0
var finished=false
var initial_pending=""
var save_result:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("EQUIPMENT_MOUSE_FAIL ",label_)
	return value
func frames(n:int=4)->void:
	for i in range(n):await process_frame
func gui(event:InputEvent,label_:String,b:Button)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		events.append({"button":label_,"pressed":event.pressed,"physical_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"disabled":b.disabled,"phase":app.playtest.phase(),"turn":app.playtest.state_copy().turn})
func released(label_:String)->void:
	events.append({"button":label_,"released_signal":true,"physical_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"phase":app.playtest.phase(),"turn":app.playtest.state_copy().turn})
func capture(label_:String)->void:
	await frames()
	var start:int=Time.get_ticks_msec()
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Time.get_ticks_msec()-start<2000:await process_frame
	var state:Dictionary=app.playtest.state_copy()
	var row:Dictionary={"label":label_,"stage":stage_name,"kind":kind,"phase":app.playtest.phase(),"turn":state.turn,"health":state.actors.actor_player.health.current,"enemy_health":state.actors.actor_village_hostile.health.current,"blade_owner":state.items.item_raider_blade.owner_actor_id,"weapon":state.actors.actor_player.equipment.weapon,"blade_revision":state.items.item_raider_blade.custody_revision,"staff_revision":state.items.item_coast_staff.custody_revision,"physical_pressed":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"goal":app.goal.text,"status":app.runtime_connection_panel.status_label.text,"request_disabled":app.runtime_connection_panel.assessment_button.disabled,"cancel_disabled":app.runtime_connection_panel.cancel_button.disabled,"sends":mock.sent.size() if is_instance_valid(mock) else 0,"authority_hash":C.digest(app.playtest.save_data())}
	rows.append(row);FileAccess.open(OUT+"current.json",FileAccess.WRITE).store_string(JSON.stringify(row,"\t"));print("EQUIPMENT_MOUSE_STATE ",JSON.stringify(row))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label_+".png")
func complete(a:RefCounted,kind_:String,focus:Dictionary={})->bool:
	var begun:Dictionary=a.begin_enemy_response() if kind_=="enemy_attack" else a.begin_intent(a.sample_goal(kind_,focus),focus)
	if not check(begun.ok,"prepared begin "+kind_):return false
	var built:Dictionary=E.build(a.request())
	if not check(built.ok,"prepared offline assessment "+kind_):return false
	var reply:Dictionary=built.assessment;reply.provenance={"provider":"explicit-offline-native-setup","live":false,"kind":"model_reply"}
	if kind_ in ["attack","enemy_attack"]:
		for component in reply.components:component.parameters={"A":4,"D":0,"P":2} if kind_=="attack" else {"A":0,"D":4,"P":-2}
	var imported:Dictionary=a.import_reply(reply)
	if not check(imported.ok,"prepared import "+kind_+" "+str(imported.get("code",""))):return false
	for step in ["roll_once","stage","commit"]:
		var result:Dictionary=a.call(step)
		if not check(result.ok,"prepared assessed commit "+kind_+" "+str(result.get("code",""))):return false
	return true
func prepare_old(a:RefCounted,mode:String,menu:int,draft:String)->bool:
	app._switch_mode_to(mode,a);await frames()
	app._apply_focus(a.tile_reference(a.state_copy().actors.actor_player.hex));app.fill_generated_sample("observe");app.end_turn();app.playtest_fixture();await frames()
	if not check(a.phase()=="idle" and not a.last_action.is_empty(),mode+" genuine old receipt"):return false
	var facade:RefCounted=app._runtime_adapter()
	check(facade.record_narration(a.last_action,mode+"_UNSAVED_NOTE","manual").ok,mode+" optional note retained")
	app.set_player_intent(draft,false)
	check(a.save_file().ok,mode+" old isolated disk save")
	profiles.append({"adapter":a,"menu":menu,"mode":mode,"draft":draft,"facade":facade,"action":a.last_action,"bytes":C.bytes(a.save_data()),"file_hash":FileAccess.get_sha256(a.default_save_path())})
	return true
func show_gear()->void:
	stage_name="sample"
	app.show_advanced();await frames()
	var b:Button=app.generated_v3_equipment_panel.get(kind+"_button")
	check(not b.disabled,"current gear sample control enabled "+kind)
	app.advanced_scroll.ensure_control_visible(b);await capture("ready_sample_"+kind)
func show_request()->void:
	stage_name="request";app.show_ai_connection();await frames();app.advanced_scroll.ensure_control_visible(app.runtime_connection_panel.assessment_button)
	await capture("ready_request_"+kind)
func deliver(index:int)->void:
	var sent:Dictionary=mock.sent[index]
	var request:Dictionary=JSON.parse_string(JSON.parse_string(sent.body).messages[1].content)
	if index==0:
		var start:int=Time.get_ticks_msec()
		while not sent.request_id in mock.cancellations and Time.get_ticks_msec()-start<90000:await create_timer(.2).timeout
		await create_timer(3.0).timeout
	else:await create_timer(1.0).timeout
	if finished:return
	var built:Dictionary=E.build(request)
	if not check(built.ok,"real mouse frozen goal builds explicit mock response "+str(index)):return
	built.assessment.provenance={"provider":"mock_test_transport","live":false,"kind":"model_reply"}
	var before:String=C.bytes(app.playtest.save_data())
	mock.respond(sent.request_id,C.bytes({"choices":[{"finish_reason":"stop","message":{"content":C.bytes(built.assessment)}}]}))
	if sent.request_id in mock.cancellations:check(C.bytes(app.playtest.save_data())==before,"cancelled late gear response preserves authority")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1280,720));root.size=Vector2i(1280,720);DisplayServer.window_set_title("Equipment Native Mouse QA - Local Mock")
	var raw:Dictionary=G.generate(726381,4,"coastal_range")
	if not await prepare_old(Old.new(raw.source),"generated_v3_npc",29,"原交谈版本的未提交草稿"):finish();return
	var prior:RefCounted=Prior.new();prior.start_source(raw.source)
	if not await prepare_old(prior,"generated_v3_enemy",30,"原近战版本的未提交草稿"):finish();return
	var current:RefCounted=A.new();current.feature_options={"vegetation":true}
	if not check(current.start_source(raw.source).ok,"new vegetation-enabled source admitted"):finish();return
	var anchor:Array=current.source.enemy_placement_result.attack_anchor_hex
	if not complete(current,"move",current.tile_reference(anchor)):finish();return
	var attempts:int=0
	while current.state_copy().actors.actor_village_hostile.health.current>0 and current.state_copy().actors.actor_player.health.current>0 and attempts<20:
		attempts+=1
		var action:String="enemy_attack" if current.enemy_response_available() else ("attack" if current.state_copy().actors.actor_player.stamina.current>0 else "rest")
		if not complete(current,action,current.enemy_reference() if action=="attack" else {}):finish();return
	if not check(current.state_copy().actors.actor_village_hostile.health.current==0 and current.state_copy().actors.actor_player.health.current>2,"legitimate prepared encounter leaves downed owner and live player"):finish();return
	app._switch_mode_to("generated_v3_equipment",current);await frames()
	if not check(app.generated_v3_equipment_mode and app.board.load_error.is_empty() and app.board.vegetation_view!=null,"native equipment board and vegetation valid"):finish();return
	app.board.view_focus=current.source.navigation.cell_center(anchor);app.board.camera_distance=7.5;app.board.overview_mode=false;app.board.orbit_camera(0,0)
	mock=Mock.new();app.runtime_ai.set_transport(mock)
	var panel:Node=app.runtime_connection_panel
	panel.endpoint_input.text="https://example.invalid/v1/chat/completions";panel.model_input.text="explicit-local-mock";panel.key_input.text="synthetic-native-qa-only";panel.consent_input.button_pressed=true;panel.timeout_input.value=120;panel._apply()
	check(mock.sent.is_empty() and panel.key_input.text.is_empty(),"configuration does not send and clears synthetic key field")
	for pair in [[panel.assessment_button,"assessment"],[panel.cancel_button,"cancel"],[app.submit_button,"end_turn"],[app.generated_v3_equipment_panel.pickup_blade_button,"pickup_blade"],[app.generated_v3_equipment_panel.equip_blade_button,"equip_blade"],[app.generated_v3_equipment_panel.equip_staff_button,"equip_staff"]]:
		var b:Button=pair[0];var label_:String=pair[1];b.gui_input.connect(func(event:InputEvent):gui(event,label_,b));b.button_up.connect(func():released(label_))
	var start:int=Time.get_ticks_msec()
	for action in ["pickup_blade","equip_blade","equip_staff"]:
		kind=action
		var before:String=C.bytes(current.save_data());var before_turn:int=current.state_copy().turn
		app.set_player_intent("",false);await show_gear()
		while app.goal.text!=current.sample_goal(kind) and Time.get_ticks_msec()-start<420000:await create_timer(.15).timeout
		if not check(app.goal.text==current.sample_goal(kind),"real sample clicked "+kind):finish();return
		check(C.bytes(current.save_data())==before,"sample click only fills text "+kind)
		app.advanced_dialog.hide();stage_name="submit";await capture("ready_end_turn_"+kind)
		while current.phase()=="idle" and Time.get_ticks_msec()-start<420000:await create_timer(.15).timeout
		if not check(current.phase()=="awaiting_assessment" and current.state_copy().turn==before_turn,"actual primary mouse creates pending only "+kind):finish();return
		initial_pending=C.bytes(current.save_data());await show_request()
		var cancelled_checked:bool=false
		while current.state_copy().turn==before_turn and Time.get_ticks_msec()-start<420000:
			await create_timer(.2).timeout
			while sent_seen<mock.sent.size():
				var index:int=sent_seen;sent_seen+=1
				check(panel.assessment_button.disabled and not panel.cancel_button.disabled,"real request busy controls "+str(index));deliver.call_deferred(index)
			if action=="pickup_blade" and not mock.cancellations.is_empty() and not cancelled_checked:
				cancelled_checked=true;check(C.bytes(current.save_data())==initial_pending,"real Cancel keeps frozen pending exactly");await capture("cancelled_pickup_pending")
		if not check(current.state_copy().turn==before_turn+1 and current.phase()=="idle","one committed turn per mouse request "+kind):finish();return
		check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"physical mouse released after commit "+kind)
		if kind=="pickup_blade":check(current.state_copy().items.item_raider_blade.owner_actor_id=="actor_player" and current.state_copy().actors.actor_player.equipment.weapon=="item_coast_staff","mouse pickup changes custody only")
		else:check(current.state_copy().actors.actor_player.equipment.weapon==("item_raider_blade" if kind=="equip_blade" else "item_coast_staff"),"mouse equip selects exact requested weapon "+kind)
		var committed:String=C.bytes(current.save_data());check(current.commit().get("already_committed",false) and C.bytes(current.save_data())==committed,"duplicate commit changes nothing "+kind)
		app.advanced_dialog.hide();await capture("committed_"+kind)
	var facade:RefCounted=app._runtime_adapter();check(facade.record_narration(current.last_action,"GEAR_UNSAVED_NOTE","manual").ok,"equipment note recorded")
	app.set_player_intent("装备版本的未提交草稿",false)
	for row in profiles:
		app.on_tool_selected(row.menu);await frames()
		check(app.playtest==row.adapter and app.goal.text==row.draft,"distinct old session and draft "+row.mode)
		check(app._runtime_adapter()==row.facade and row.facade.has_recorded_narration(row.action),"distinct unsaved narration cache "+row.mode)
		check(C.bytes(row.adapter.save_data())==row.bytes and FileAccess.get_sha256(row.adapter.default_save_path())==row.file_hash,"old authority and disk untouched "+row.mode)
		var loaded:RefCounted=Old.new() if row.menu==29 else Prior.new();check(loaded.load_file().ok and C.bytes(loaded.save_data())==row.bytes,"old actual disk still loads "+row.mode)
	app.on_tool_selected(27);await frames()
	check(app.playtest==current and app.goal.text=="装备版本的未提交草稿" and app._runtime_adapter()==facade and facade.has_recorded_narration(current.last_action),"new entry returns exact equipment session/draft/narration")
	var exact:String=C.bytes(current.save_data());app.save_game();app.load_game();await frames()
	save_result={"save":app.last_save_result,"load":app.last_load_result,"path":ProjectSettings.globalize_path(app.playtest.default_save_path())}
	check(app.last_save_result.ok and app.last_load_result.ok and C.bytes(app.playtest.save_data())==exact,"native new gear exact actual disk reload")
	check(app.board.committed_effects.pending.is_empty() and app.board.committed_effects.active_count()==0,"gear disk reload replays no combat VFX")
	check(not app.playtest.movement_preview(app.playtest.state_copy().actors.actor_village_hostile.hex).ok,"looted downed cell still blocked after disk reload")
	await capture("reloaded_equipment")
	finish()
func finish()->void:
	if finished:return
	finished=true
	for name_ in ["pickup_blade","equip_blade","equip_staff","assessment","cancel"]:
		var found:bool=false
		for event in events:
			if event.button==name_ and event.get("released_signal",false) and not event.physical_pressed:found=true
		check(found,"actual native released control "+name_)
	var primary_down:int=0
	for event in events:
		if event.button=="end_turn" and event.get("pressed",false) and event.physical_pressed:primary_down+=1
	check(primary_down>=3,"three actual primary button mouse presses")
	check(is_instance_valid(mock) and mock.sent.size()==4,"four mock sends: cancelled pickup then three commits")
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"events":events,"save_result":save_result,"mock_only":true,"network_calls":0,"scope":"real gear sample/end-turn/request/cancel mouse flow; setup combat and profile-switch checks use explicit callbacks; normal RNG, no provider"},"\t"))
	print("EQUIPMENT_NATIVE_MOUSE ",checks," ",failures);quit(0 if failures.is_empty() else 1)
