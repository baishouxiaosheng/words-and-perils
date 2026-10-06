extends SceneTree
## Synthetic real GUI events; no OS/IME or live-provider claim.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const DisplayText=preload("res://view/playable_build/display_text.gd")
const MAIN_SHA="6e2f62e76db2f4a64a9bbdf4d348a32588d1cb991e6d869bff4c730e12e61e5c"
var checks:=0
var failures:Array=[]
var events:=0
var scene:Control
var demo:Node
var receipt:Dictionary={}
var before:Dictionary={}
var after:Dictionary={}
var typed_text:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->bool:
	checks+=1
	if not ok:failures.append(label_);printerr("OFFLINE_MOVE_FAIL ",label_)
	return ok
func frames(count:int=3)->void:
	for _i in range(count):await process_frame
func click(button:Button)->void:
	var point:Vector2=button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event);Input.flush_buffered_events();events+=1
func type_text(text_:String)->void:
	scene.goal.clear();scene.goal.grab_focus();await frames()
	for index in range(text_.length()):
		var event:=InputEventKey.new();event.pressed=true;event.unicode=text_.unicode_at(index)
		Input.parse_input_event(event);Input.flush_buffered_events();events+=1
	await frames()
func pick_actor()->Dictionary:
	var actor:Node3D=scene.board.token_nodes.actor_player
	for child in actor.find_children("*","MeshInstance3D",true,false):
		if child.mesh==null or not child.is_visible_in_tree() or child.name=="SelectedEdgeGlow":continue
		var point:Vector2=scene.board.camera.unproject_position(child.global_transform*child.mesh.get_aabb().get_center())
		for row in scene.board.pick_focus(point):
			if row.get("reference",{}).get("kind")=="actor" and row.reference.get("id")=="actor_player":return row
	return {}
func run()->void:
	var expected:=OS.get_environment("FOGBANK_OFFLINE_MOVE_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/")!=expected:
		printerr("OFFLINE_MOVE_REFUSED isolated user directory mismatch");quit(2);return
	if FileAccess.file_exists("user://r24_coast_adventure_save.json"):
		printerr("OFFLINE_MOVE_REFUSED fresh test directory required");quit(2);return
	if not check(FileAccess.get_sha256("res://main.gd")==MAIN_SHA,"exact independent offline-demo Main successor"):
		quit(2);return
	root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
	scene=Main.instantiate();root.add_child(scene);current_scene=scene;await frames(6)
	if not check(scene.coast_mode and Bundle.ready() and scene.playtest.engine.rule_id()=="coast_release/v1","real Main admits current production Coast rules"):
		finish();return
	before=scene.playtest.engine.save_data()
	check(before.state.hexes.size()==1801 and before.state.world_id==Bundle.document("catalog").world_id,"real1801 world/source identity")
	demo=scene.get_node_or_null("OfflineMoveDemo")
	if not check(demo!=null and not demo.enabled and not demo.toggle.button_pressed,"offline mode exists and is not silently enabled"):
		finish();return
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured(),"fresh runtime has no key or enabled connection")
	scene.board.focus_player();scene.goal.release_focus();await frames()
	var actor_hit:=pick_actor()
	if not check(not actor_hit.is_empty(),"actual actor mesh picker provides selection"):
		finish();return
	scene.board.focus_candidates.emit([actor_hit],Vector2.ZERO);await frames()
	check(scene.selected_focus.get("id")=="actor_player","actual connected focus signal selects player piece")
	click(demo.toggle);await frames()
	check(demo.enabled and demo.hint.visible and demo.hint.text.contains("未调用模型"),"real GUI toggle visibly enables finite offline code demo")
	check(demo.expected_text.is_empty() and demo.execute_button.disabled,"actor selection alone cannot become an implicit movement target")
	click(scene.submit_button);await frames()
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(before),"no-target real submit event preserves complete state and RNG")
	var player:Array=before.state.actors.actor_player.hex;var target:Array=[];var preview:Dictionary={}
	for offset in [[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]:
		var next:Array=[int(player[0])+offset[0],int(player[1])+offset[1]]
		var planned:Dictionary=scene.playtest.movement_preview(next)
		if planned.get("ok",false) and planned.get("route",[]).size()>1:target=next;preview=planned;break
	if not check(target.size()==2,"original navigation offers a legal recorded destination"):
		finish();return
	var blocked:Array=[]
	for cell in before.state.hexes.values():
		if cell.get("terrain")=="ocean":blocked=[cell.q,cell.r];break
	if not check(blocked.size()==2 and not scene.playtest.movement_preview(blocked).get("ok",false),"actual world provides an unreachable ocean target"):
		finish();return
	scene.on_hex_selected(Vector2i(blocked[0],blocked[1]));await frames()
	check(demo.expected_text.is_empty() and demo.execute_button.disabled,"unreachable real target has no executable template")
	click(scene.submit_button);await frames()
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(before),"unreachable target rejection keeps all authority and RNG exact")
	scene.on_hex_selected(Vector2i(target[0],target[1]));await frames()
	var template:String=DisplayText.player_intent(scene.playtest.movement_goal(target))
	check(demo.expected_text==template and demo.hint.text.contains(str(preview.cost)),"HUD shows exact registered natural sentence and actual path cost")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(demo.execute_button.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(demo.hint.get_global_rect()),"720-high actual HUD template and confirm control are visible")
	await type_text("移动到选中位置")
	check(scene.goal.text=="移动到选中位置" and demo.execute_button.disabled,"real Unicode key events enter an unsupported whole sentence without auto-signing")
	click(scene.submit_button);await frames()
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(before) and scene.goal.text=="移动到选中位置","unknown sentence rejected without rewriting input or changing any authority")
	await type_text(template);typed_text=scene.goal.text
	check(typed_text==template and scene._signed_sample_goal.is_empty() and not demo.execute_button.disabled,"real typed exact template stays unsigned until explicit offline confirmation")
	# Test only the consent guard; no key or provider configuration is installed.
	scene.runtime_ai.connection_enabled=true;await frames()
	click(scene.submit_button);await frames()
	check(C.bytes(scene.playtest.engine.save_data())==C.bytes(before) and scene.runtime_ai.connection_enabled,"enabled-connection guard rejects without silently switching it off")
	scene.runtime_ai.connection_enabled=false;await frames()
	check(not demo.execute_button.disabled,"manual return to disconnected state restores explicit confirmation")
	var geometry_before:Vector3=scene.board.token_nodes.actor_player.global_position
	click(demo.execute_button);await frames()
	after=scene.playtest.engine.save_data()
	if not check(demo.last_result.get("ok",false) and after.receipts.size()==before.receipts.size()+1,"real offline confirmation commits exactly one production receipt"):
		finish();return
	receipt=after.receipts[demo.last_result.action_id]
	check(demo.last_result.original_input==typed_text and DisplayText.player_intent(receipt.goal)==typed_text,"original exact visible input preserved by unchanged signed-goal display contract")
	check(receipt.goal==scene.playtest.movement_goal(target) and receipt.actor_id=="actor_player","receipt records only the selected player's registered exact movement goal")
	check(C.bytes(after.state.actors.actor_player.hex)==C.bytes(target),"actual authoritative actor destination equals selected target")
	check(int(before.state.actors.actor_player.stamina.current)-int(after.state.actors.actor_player.stamina.current)==int(preview.cost),"actual stamina decreases by the original route cost once")
	check(int(after.state.turn)==int(before.state.turn)+1 and int(after.state.state_version)==int(before.state.state_version)+1,"whole legal route commits exactly one turn/state version")
	check(scene.playtest.engine.supports_resolver("coast_move_route_v3") and receipt.branch_id=="weighted_route_success" and receipt.provenance.kind=="fixture" and not receipt.provenance.live,"actual registered weighted route branch and honestly authored offline fixture provenance retained")
	check(receipt.get("rolls",[]).is_empty() and C.bytes(after.rng)==C.bytes(before.rng),"registered safe-direct movement creates no fabricated dice and preserves RNG")
	var has_cost:=false;var moves:=0
	for patch in receipt.patches:
		if patch.get("type")=="actor_pool_delta" and patch.get("actor_id")=="actor_player" and patch.get("pool")=="stamina":has_cost=int(patch.delta)==-int(preview.cost)
		if patch.get("type")=="actor_move" and patch.get("actor_id")=="actor_player":moves+=1
	check(has_cost and moves==preview.route.size()-1,"real receipt contains original cost patch and ordered route movement patches")
	# Give existing production presentation a bounded chance to finish naturally.
	var deadline:=Time.get_ticks_msec()+5000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<deadline:await frames(1)
	check(not scene.board.presentation.actors.actor_player.moving and scene.board.token_nodes.actor_player.global_position.distance_to(geometry_before)>0.1,"real production movement animation finishes at a different display location")
	var committed_bytes:=C.bytes(scene.playtest.engine.save_data())
	click(scene.submit_button);click(demo.execute_button);await frames()
	check(C.bytes(scene.playtest.engine.save_data())==committed_bytes,"repeated clicks after completed/cleared input cannot commit or charge twice")
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured() and not scene.runtime_ai.busy(),"finite demo completed with no connection keys or provider work")
	finish()
func finish()->void:
	var report:Dictionary={"schema":"offline_move_demo_real_main/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"display_backend":DisplayServer.get_name(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"module_sha256":FileAccess.get_sha256("res://view/tabletop_interaction/offline_move_demo.gd"),"synthetic_gui_events":events,"typed_template":typed_text,"receipt":receipt,"before_state_sha256":C.bytes(before).sha256_text(),"after_state_sha256":C.bytes(after).sha256_text(),"network_calls":0,"scope":"actual Coast Main, real Control Unicode/mouse events, original signed template/fixture/resolver/roll-stage-commit and natural production movement; no OS input/IME or live model claim"}
	var path:=OS.get_environment("FOGBANK_OFFLINE_MOVE_TEST_REPORT")
	if path.is_empty():path="user://offline_move_main.json"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:printerr("OFFLINE_MOVE_REPORT_WRITE_FAILED");quit(2);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	if is_instance_valid(scene):scene.free()
	print("OFFLINE_MOVE_MAIN_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
