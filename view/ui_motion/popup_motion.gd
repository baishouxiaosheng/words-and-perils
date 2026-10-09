extends Node
## Explicit Main popups only. Their existing modal/close handlers remain owners.
## Each original layout writer supplies its final target through the small seam.
const Presets=preload("res://view/ui_motion/presets.gd")
var entries:Dictionary={}
func watch(window:Window)->void:
	if not is_instance_valid(window) or entries.has(window.get_instance_id()):return
	var id:int=window.get_instance_id()
	entries[id]={"window":weakref(window),"goal":window.position,"before":window.position,"opening":false,"closing":false,"tween":null,"profile":Presets.profile(window.get_meta(&"ui_motion_kind",&"standard"),window.get_meta(&"ui_motion_options",{}))}
	window.visibility_changed.connect(_visibility.bind(id))
	window.set_meta(&"ui_motion_before_layout",_before_layout.bind(id))
	window.set_meta(&"ui_motion_after_layout",_after_layout.bind(id))
	if window.has_meta(&"ui_motion_modal"):window.set_meta(&"ui_motion_request_close",request_close.bind(id))
func _window(id:int)->Window:
	return entries[id].window.get_ref() if entries.has(id) else null
func _kill(row:Dictionary)->void:
	if row.tween!=null and row.tween.is_valid():row.tween.kill()
	row.tween=null;row.opening=false;row.closing=false
func _restore_input(window:Window,row:Dictionary)->void:
	if not row.has("input_snapshot"):return
	window.gui_disable_input=row.input_snapshot.gui_disable_input;window.process_mode=row.input_snapshot.process_mode
	row.erase("input_snapshot")
func cancel_all()->void:
	for id:int in entries:
		var row:Dictionary=entries[id];var closing:bool=row.closing
		_kill(row)
		var window:Window=_window(id)
		if not is_instance_valid(window):continue
		if closing:window.hide()
		_restore_input(window,row);window.remove_meta(&"ui_motion_closing");window.position=row.goal
func request_close(id:int)->void:
	var window:Window=_window(id)
	if not is_instance_valid(window) or not window.visible:return
	var row:Dictionary=entries[id]
	if row.closing:return
	_kill(row);row.closing=true
	row.input_snapshot={"gui_disable_input":window.gui_disable_input,"process_mode":window.process_mode}
	window.gui_disable_input=true;window.process_mode=Node.PROCESS_MODE_DISABLED;window.set_meta(&"ui_motion_closing",true)
	var tween:Tween=create_tween();row.tween=tween
	Presets.ease(tween)
	tween.tween_property(window,"position",row.goal+Vector2i(0,int(row.profile.travel)),float(row.profile.duration))
	tween.finished.connect(func():
		if not is_instance_valid(window):return
		window.hide();_restore_input(window,row);window.remove_meta(&"ui_motion_closing"))
func prepare_reopen(window:Window)->void:
	if not is_instance_valid(window) or not entries.has(window.get_instance_id()):return
	var row:Dictionary=entries[window.get_instance_id()]
	if not row.closing:return
	row.reopen_from=window.position;_kill(row);_restore_input(window,row)
	window.remove_meta(&"ui_motion_closing");window.hide()
func _visibility(id:int)->void:
	var window:Window=_window(id)
	if not is_instance_valid(window):return
	var row:Dictionary=entries[id]
	if not window.visible:
		_kill(row);_restore_input(window,row);window.remove_meta(&"ui_motion_closing");window.position=row.goal;return
	var goal:Vector2i=window.position
	var start:Vector2i=goal+Vector2i(0,48 if window is PopupMenu else int(row.profile.travel))
	if row.has("reopen_from"):start=row.reopen_from;row.erase("reopen_from")
	_start(id,goal,start)
func _start(id:int,goal:Vector2i,start:Vector2i)->void:
	var window:Window=_window(id)
	if not is_instance_valid(window) or not window.visible:return
	var row:Dictionary=entries[id];_kill(row);row.goal=goal;row.opening=true
	window.position=start
	var tween:Tween=create_tween();row.tween=tween
	Presets.ease(tween)
	tween.tween_property(window,"position",goal,float(row.profile.duration))
	tween.finished.connect(func():
		if entries.has(id):entries[id].opening=false;entries[id].tween=null)
func _before_layout(id:int)->void:
	var window:Window=_window(id)
	if is_instance_valid(window):entries[id].before=window.position
func _after_layout(id:int)->void:
	var window:Window=_window(id)
	if not is_instance_valid(window) or not window.visible:return
	var row:Dictionary=entries[id];var goal:Vector2i=window.position
	if row.closing:window.position=row.before;return
	if row.opening and goal==row.goal:
		window.position=row.before;return
	if goal!=row.goal:_start(id,goal,row.before)
func _exit_tree()->void:
	for id:int in entries:
		var row:Dictionary=entries[id];_kill(row)
		var window:Window=_window(id)
		if is_instance_valid(window):
			_restore_input(window,row);window.remove_meta(&"ui_motion_closing")
			window.position=row.goal
			window.remove_meta(&"ui_motion_request_close")
			window.remove_meta(&"ui_motion_before_layout");window.remove_meta(&"ui_motion_after_layout")
