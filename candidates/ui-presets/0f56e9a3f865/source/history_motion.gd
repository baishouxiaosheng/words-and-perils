extends Node
## One source-owned HUD panel. Responsive layout computes its destination;
## this node owns only the presented position between synchronous layout calls.
const Presets=preload("res://view/ui_motion/presets.gd")
var profile:Dictionary=Presets.profile(&"drawer")
var wanted_intent:Callable
var host:Control
var panel:Control
var tween:Tween
var phase:="closed"
var wanted:=false
var layout_goal:=Vector2.ZERO
var before_position:=Vector2.ZERO
var original_mouse_filter:int
func bind_control(main:Control,target:Control,intent:Callable,rule:Dictionary)->void:
	host=main;panel=target;wanted_intent=intent;profile=rule
	original_mouse_filter=panel.mouse_filter
	wanted=bool(wanted_intent.call())
	phase="open" if wanted else "closed";layout_goal=panel.position
	set_process(false)
func before_layout()->void:
	if is_instance_valid(panel):before_position=panel.position
func after_layout()->void:
	if not is_instance_valid(panel) or not is_instance_valid(host):return
	var next:bool=bool(wanted_intent.call())
	var box:Rect2=Presets.geometry(&"drawer",host.get_viewport_rect().size,panel.size,profile)
	panel.size=box.size
	var lower:Vector2=Vector2.ONE*float(profile.margin)
	var upper:Vector2=(host.get_viewport_rect().size-panel.size-lower).max(lower)
	var goal:Vector2=panel.position.clamp(lower,upper)
	var same_goal:bool=goal.is_equal_approx(layout_goal)
	var changed:bool=next!=wanted
	layout_goal=goal;wanted=next
	if phase=="closed" and not next:
		panel.hide();panel.mouse_filter=original_mouse_filter;return
	if phase in ["opening","closing"] and not changed and same_goal:
		panel.show();panel.position=before_position;return
	if phase=="open" and next and same_goal:
		panel.show();panel.position=goal;return
	var start:Vector2=before_position
	if phase=="closed":start=Vector2(goal.x,host.get_viewport_rect().size.y+float(profile.travel))
	var finish:Vector2=goal if next else Vector2(goal.x,host.get_viewport_rect().size.y+float(profile.travel))
	if tween!=null and tween.is_valid():tween.kill()
	# Keep the moving panel present throughout close so it still intercepts
	# clicks in its actual rectangle; this read-only drawer never submits actions.
	panel.show();panel.position=start;panel.mouse_filter=Control.MOUSE_FILTER_STOP
	phase="opening" if next else "closing"
	set_process(true)
	tween=create_tween();Presets.ease(tween)
	tween.tween_property(panel,"position",finish,float(profile.duration))
	tween.finished.connect(_completed)
func _completed()->void:
	tween=null
	if not is_instance_valid(panel):set_process(false);return
	phase="open" if wanted else "closed"
	panel.visible=wanted;panel.mouse_filter=original_mouse_filter
	if wanted:panel.position=layout_goal
	set_process(false)
	if is_instance_valid(host):host._update_feedback_safe_rect()
func _process(_delta:float)->void:
	if not is_instance_valid(host) or not is_instance_valid(panel):
		if tween!=null and tween.is_valid():tween.kill()
		set_process(false);return
	host._update_feedback_safe_rect()
func cancel()->void:
	if tween!=null and tween.is_valid():tween.kill()
	tween=null;set_process(false)
	if is_instance_valid(panel):
		panel.mouse_filter=original_mouse_filter;panel.visible=wanted
		if wanted:panel.position=layout_goal
	phase="open" if wanted else "closed"
func _exit_tree()->void:cancel()
