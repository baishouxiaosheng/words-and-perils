extends SceneTree
## One real production action, captured with Godot's official Movie Maker.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const DisplayText=preload("res://view/playable_build/display_text.gd")
var scene:Control
var label_:Label
var checks:=0
var failures:Array=[]
var started:int=Time.get_ticks_msec()
var finished:=false
var receipt:Dictionary={}
func _initialize()->void:run.call_deferred()
func _process(_delta:float)->bool:
	if not finished and Time.get_ticks_msec()-started>150000:push_error("Offline feature movie exceeded150seconds");quit(2)
	return false
func check(value:bool,text_:String)->bool:
	checks+=1
	if not value:failures.append(text_)
	return value
func frames(count:int)->void:
	for _i in range(count):await process_frame
func click(button:Button)->void:
	var point:Vector2=button.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event);Input.flush_buffered_events()
func say(text_:String)->void:
	label_.text="Words and Perils · 候选 / 离线样例 / Jev未连接\n"+text_
func finish()->void:
	finished=true
	var result={"schema":"offline_feature_movie/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"offline_module_sha256":FileAccess.get_sha256("res://view/tabletop_interaction/offline_move_demo.gd"),"movie_feature":OS.has_feature("movie"),"viewport_width":root.size.x,"viewport_height":root.size.y,"receipt":receipt,"scope":"Actual Coast Main real GUI target selection, original full Unicode template, offline explicit confirmation and original assessment/resolver/roll-stage-commit. Movie Maker offline-rendered feature footage, not a real-time performance claim. Synthetic Godot input; no live model/Jev work."}
	var file=FileAccess.open(OS.get_environment("OFFLINE_MOVIE_REPORT"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(result,"\t"));file.close()
	print("OFFLINE_FEATURE_MOVIE_RESULT ",result.ok," checks ",checks," failures ",JSON.stringify(failures));scene.free();quit(0 if failures.is_empty() else 1)
func run()->void:
	root.gui_embed_subwindows=true
	scene=Main.instantiate();root.add_child(scene);current_scene=scene;await frames(8)
	label_=Label.new();label_.position=Vector2(290,18);label_.z_index=100;label_.add_theme_font_size_override("font_size",19);label_.add_theme_color_override("font_color",Color("fff8df"));label_.add_theme_constant_override("outline_size",4);label_.add_theme_color_override("font_outline_color",Color("473a27"));scene.add_child(label_)
	say("1 选择目的地");scene.board.focus_player();scene.goal.release_focus();await frames(25)
	var before:Dictionary=scene.playtest.engine.save_data();var player:Array=before.state.actors.actor_player.hex;var target:Array=[];var preview:Dictionary={}
	if not check(scene.coast_mode and before.state.hexes.size()==1801 and not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured(),"actual1801 Coast with no provider connection"):finish();return
	for offset in [[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]:
		var next:Array=[int(player[0])+offset[0],int(player[1])+offset[1]];var planned:Dictionary=scene.playtest.movement_preview(next)
		if planned.get("ok",false) and planned.get("route",[]).size()>1:target=next;preview=planned;break
	if not check(target.size()==2,"real legal movement destination"):finish();return
	scene.on_hex_selected(Vector2i(target[0],target[1]));await frames(35)
	var demo:Node=scene.get_node("OfflineMoveDemo");click(demo.toggle);await frames(12)
	var template:String=DisplayText.player_intent(scene.playtest.movement_goal(target))
	if not check(demo.enabled and demo.expected_text==template,"original registered complete template visible"):finish();return
	say("2 输入完整样例意图，再明确确认");scene.goal.clear();scene.goal.grab_focus();await frames(3)
	for index in range(template.length()):
		var event:=InputEventKey.new();event.pressed=true;event.unicode=template.unicode_at(index);Input.parse_input_event(event);Input.flush_buffered_events();await frames(2)
	if not check(scene.goal.text==template and scene._signed_sample_goal.is_empty() and not demo.execute_button.disabled,"real Unicode input remains unsigned before confirmation"):finish();return
	await frames(35);var original_position:Vector3=scene.board.token_nodes.actor_player.global_position
	say("3 确认离线移动：原规则结算");click(demo.execute_button);await frames(3)
	var after:Dictionary=scene.playtest.engine.save_data()
	if not check(demo.last_result.get("ok",false) and after.receipts.size()==before.receipts.size()+1,"real production commit produces one receipt"):finish();return
	receipt=after.receipts[demo.last_result.action_id]
	check(C.bytes(after.state.actors.actor_player.hex)==C.bytes(target),"real authoritative destination equals selected cell")
	check(int(before.state.actors.actor_player.stamina.current)-int(after.state.actors.actor_player.stamina.current)==int(preview.cost),"original route stamina deducted once")
	check(receipt.branch_id=="weighted_route_success" and receipt.provenance.kind=="fixture" and not receipt.provenance.live and receipt.get("rolls",[]).is_empty() and C.bytes(before.rng)==C.bytes(after.rng),"registered safe route and honest offline provenance/RNG")
	var deadline:int=Time.get_ticks_msec()+8000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<deadline:await frames(1)
	check(not scene.board.presentation.actors.actor_player.moving and scene.board.token_nodes.actor_player.global_position.distance_to(original_position)>.1,"natural production movement reaches new visible location")
	say("已完成：移动1格、按原路线扣体力、推进1回合");await frames(75)
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured() and not scene.runtime_ai.busy(),"no live provider work introduced")
	finish()
