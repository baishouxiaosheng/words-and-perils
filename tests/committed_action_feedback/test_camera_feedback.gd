extends SceneTree
const CameraControl=preload("res://view/playable_build/committed_camera.gd")
const Router=preload("res://view/playable_build/committed_effect_router.gd")
const TestView=preload("res://tests/committed_action_feedback/camera_test_view.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures:Array[String]=[]
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);printerr("FAIL: "+title)
func _initialize()->void:call_deferred("run")
func state(version:int)->Dictionary:return {"world_id":"camera_test","state_version":version,"actors":{"a":{"name":"旅人","health":{"current":12},"statuses":{}},"b":{"name":"敌人","health":{"current":12},"statuses":{}}}}
func receipt(version:int)->Dictionary:
	var value:={"action_id":"camera_test:action_%d"%version,"actor_id":"a","before_version":version-1,"after_version":version,"stage_hash":"frozen_test","patches":[{"type":"combat_event","actor_id":"a","target_actor_id":"b","weapon_item_id":"test_weapon","presentation_kind":"ranged","outcome":"miss"}],"hook_patches":[]}
	value.receipt_hash=C.digest(value);return value
func run()->void:
	root.size=Vector2i(1440,900)
	var view:=TestView.new();root.add_child(view);view._update_camera()
	var a:=Node3D.new();var b:=Node3D.new();view.add_child(a);view.add_child(b);b.position=Vector3(0,1,-7)
	var tokens:={"a":a,"b":b}
	var control:=CameraControl.new();root.add_child(control);control.configure(view,view.camera);control.set_safe_rect(Rect2(240,130,880,450))
	var router:=Router.new();view.add_child(router);router.feedback_camera=view.camera;router.safe_rect_provider=Callable(control,"usable_rect");router.framing_gate=Callable(control,"effects_ready");router.event_started.connect(control.show_cue)
	var before:=state(0);var after:=state(1);router.reset_to(before)
	var events:=Router.events_for(receipt(1),before,after)
	check(not control.usable_rect().has_point(view.camera.unproject_position(b.global_position+Vector3(0,1.3,0))),"normal focused camera initially excludes distant target")
	var old_target:Vector3=view.target;var old_size:float=view.camera.size;var old_pitch:float=view.pitch;var old_yaw:float=view.yaw
	check(control.consider(events,tokens,null),"fresh combat requests bounded frame when participant is offscreen")
	check(view.target==old_target and view.camera.size==old_size,"framing never jumps before animation")
	check(router.consume(receipt(1),before,after,tokens).ok and router.active_count()==0,"real effect clock waits for camera frame")
	router._process(0.2);check(router.emitted_effects==0,"short firearm does not expire while camera moves")
	control._process(0.3)
	check(view.target!=old_target and control.active,"camera moves smoothly through an intermediate pose")
	control._process(0.3)
	check(not control.active and control.effects_ready(),"camera releases effects after fixed bounded duration")
	check(view.pitch==old_pitch and view.yaw==old_yaw,"camera framing preserves player camera angles")
	for actor in [a,b]:
		check(control.usable_rect().has_point(view.camera.unproject_position(actor.global_position+Vector3(0,0.5,0))),"participant body lies in actual HUD-safe rectangle")
		check(control.usable_rect().has_point(view.camera.unproject_position(actor.global_position+Vector3(0,1.65,0))),"participant popup anchor lies in actual HUD-safe rectangle")
	router._process(0.0);check(router.emitted_effects==1 and router.active_count()==1,"framed firearm starts once with full visual lifetime")
	router._process(0.14)
	check(control.report().visible_combat_cues.size()==1 and control.report().visible_combat_cues[0].contains("旅人") and control.report().visible_combat_cues[0].contains("敌人"),"real effect-start emits a named outcome cue independent of terrain occlusion")
	check(router.emitted_effects==2,"truthful miss popup follows firearm delay")
	var labels:Array=router.slots.filter(func(slot):return slot.active and slot.label.visible)
	check(labels.size()==1 and control.usable_rect().has_point(view.camera.unproject_position(labels[0].label.global_position)),"miss label is screen-safe against HUD")
	router._process(2.0)
	check(not control.consider(events,tokens,null) and control.framed_actions==1,"already-visible participants never reframe repeatedly")
	var stable:Vector3=view.target
	check(not router.consume(receipt(1),before,after,tokens).ok and view.target==stable,"duplicate receipt never moves the camera")
	view.overview=true;view.target=Vector3(0,0.45,0);view.camera.size=6;view._update_camera();stable=view.target
	check(not control.consider(events,tokens,null) and view.target==stable,"deliberate overview is preserved")
	view.overview=false;control.cancel(false)
	check(control.consider(events,tokens,null),"another real offscreen action can frame")
	control._process(0.2);control.cancel(true);stable=view.target;control._process(1.0)
	check(view.target==stable and control.effects_ready(),"manual cancel stops camera immediately and releases FX")
	check(not control.consider(events,tokens,null),"manual camera input holds off rapid automatic reframing")
	view.target=Vector3(0,0.45,0);view.camera.size=6;view._update_camera()
	router.consume(receipt(2),state(1),state(2),tokens);router._process(0.14)
	labels=router.slots.filter(func(slot):return slot.active and slot.label.visible)
	check(labels.size()==1 and labels[0].label_screen_clamped and labels[0].label.text.contains("敌人"),"displaced feedback names the real target after manual cancel")
	check(control.usable_rect().has_point(view.camera.unproject_position(labels[0].label.global_position)),"offscreen target feedback remains inside HUD-safe area")
	check(C.bytes(before)==C.bytes(state(0)) and C.bytes(after)==C.bytes(state(1)),"camera and label feedback never change game facts")
	control.set_safe_rect(Rect2());router._process(0.1);control._process(0.1)
	check(not control.usable_rect().has_area() and not labels[0].label.visible and control.report().visible_combat_cues.is_empty(),"explicit no-space region suppresses overlays instead of inventing HUD space")
	router.reset_to(state(2));control.cancel(false)
	check(router.active_count()==0 and router.pending.is_empty() and not control.active,"load clears both visual queue and camera frame")
	control.set_safe_rect(Rect2(240,130,880,450));view.target=Vector3(0,0.45,0);view.camera.size=6;view._update_camera()
	var route:Array[Vector3]=[Vector3.ZERO,Vector3(-2,1,-3),Vector3(-3,1,-6),Vector3(-2,0,-9)]
	check(control.consider([],{"actor_player":a},null,route),"fresh committed player-only route frames its full extent")
	var next_route:Array[Vector3]=[Vector3.ZERO,Vector3(2,1,-4),Vector3(3,0,-10)]
	check(control.consider([],{"actor_player":a},null,next_route) and control.framed_actions>=4,"a newer committed route replaces an active older camera goal")
	control._process(0.6)
	for point in next_route:check(control.usable_rect().has_point(view.camera.unproject_position(point+Vector3(0,1,0))),"committed route waypoint remains inside HUD-safe camera")
	control.cancel(false);view.overview=true;stable=view.target
	check(not control.consider([],{"actor_player":a},null,route) and view.target==stable,"deliberate overview also suppresses route framing")
	view.overview=false
	check(not control.consider([],tokens,null),"no direct route or combat metadata never requests framing")
	control.set_safe_rect(Rect2(240,130,220,300));control.show_cue({"kind":"magic","outcome":"hit","source_name":"潮滩劫掠者","target_name":"旅人"})
	check(control.report().visible_combat_cues.size()==1 and control.report().visible_combat_cues[0].contains("施法") and control.report().visible_combat_cues[0].contains("命中"),"narrow cue retains actual attack kind and outcome")
	var result:={"checks":checks,"failures":failures,"camera":control.report(),"popup_target_identity":labels[0].label.text if not labels.is_empty() else ""}
	var file:=FileAccess.open("res://tests/committed_action_feedback/camera_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	view.queue_free();control.queue_free();await process_frame
	if failures.is_empty():print("COMMITTED CAMERA FEEDBACK PASSED: %d assertions"%checks);quit(0)
	else:quit(1)
