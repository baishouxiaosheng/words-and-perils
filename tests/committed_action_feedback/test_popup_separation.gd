extends SceneTree
const Effect=preload("res://view/playable_build/committed_effect_node.gd")
const TestView=preload("res://tests/committed_action_feedback/camera_test_view.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);printerr("FAIL: "+title)
func run()->void:
	root.size=Vector2i(1440,900)
	var view:=TestView.new();root.add_child(view);view.camera.size=16;view._update_camera()
	var effect:=Effect.new();view.add_child(effect)
	var event:={"kind":"damage","text":"擦伤 −1","amount":1,"target_name":"潮滩劫掠者","target_id":"enemy"}
	effect.start(event,Vector3.ZERO,Vector3(0,0.58,0))
	var original:=view.camera.unproject_position(effect.label.global_position)
	# Reproduce the native failure: HUD top prevents upward placement, while
	# two adjacent nameplates straddle the clamped popup's original position.
	var area:=Rect2(Vector2(100,original.y-10),Vector2(1240,300))
	var plates:Array[Rect2]=[Rect2(original-Vector2(120,13),Vector2(240,26)),Rect2(original+Vector2(-80,10),Vector2(160,24))]
	effect.keep_label_screen_safe(view.camera,area,plates)
	check(effect.label_screen_clamped and effect.label.text.contains("潮滩劫掠者"),"displaced popup preserves actual target identity")
	check(effect.label.text.contains("擦伤 −1") and effect.event.amount==1,"graze and exact authoritative amount unchanged")
	check(area.encloses(effect.label_screen_rect),"popup including outline stays in actual HUD-safe area")
	for plate in plates:check(not effect.label_screen_rect.intersects(plate),"popup no longer overlaps adjacent actor nameplate")
	check(effect.label_screen_rect.position.y>=plates[1].end.y,"nearest available downward lane used when HUD blocks upward motion")
	var first:=effect.label_screen_rect
	var second:=Effect.new();view.add_child(second);second.start({"kind":"poison","text":"中毒","target_name":"潮滩劫掠者"},Vector3.ZERO,Vector3(0,0.58,0))
	plates.append(first.grow(3.0));second.keep_label_screen_safe(view.camera,area,plates)
	check(not second.label_screen_rect.intersects(first) and area.encloses(second.label_screen_rect),"simultaneous status feedback has a separate clear vertical lane")
	effect.sample(0.2);effect.keep_label_screen_safe(view.camera,area,plates.slice(0,2))
	for plate in plates.slice(0,2):check(not effect.label_screen_rect.intersects(plate),"normal popup float remains separated on following frames")
	effect.stop();second.stop()
	check(not effect.label_screen_rect.has_area() and not second.label_screen_rect.has_area(),"pooled cleanup releases occupied feedback rectangles")
	var file:=FileAccess.open("res://tests/committed_action_feedback/popup_separation_report.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));file.close()
	view.queue_free();await process_frame
	if failures.is_empty():print("POPUP NAMEPLATE SEPARATION PASSED: %d assertions"%checks);quit(0)
	else:quit(1)
