extends Node
## Submission dock presentation only. Layout owns size and the resting position.
## Requires Godot 4.6 recursive Control input overrides.
const DURATION := 0.28
const TRAVEL := 24.0
var host: Control
var panel: Control
var restore_button: BaseButton
var restore_mouse_down := false
var wanted := true
var phase := &"open"
var layout_goal := Vector2.ZERO
var motion_goal := Vector2.ZERO
var before_position := Vector2.ZERO
var tween: Tween
var generation := 0
var input_snapshot: Array[Dictionary] = []
var blocked_mouse: Dictionary = {}
var blocked_keys: Dictionary = {}

func _init() -> void:
	name = "HUDPanelMotion"
	set_process(false)

func bind_control(main: Control, target: Control, restore: BaseButton = null) -> void:
	host = main
	panel = target
	restore_button = restore
	wanted = panel.visible
	phase = &"open" if wanted else &"closed"
	layout_goal = panel.position
	if not wanted: _lock_input(panel)

func set_hidden(hidden: bool) -> void:
	if not is_instance_valid(panel) or wanted == (not hidden): return
	wanted = not hidden
	_start(panel.position)

func before_layout() -> void:
	if not is_instance_valid(panel): return
	before_position = panel.position
	# Other layout consumers must see the resting dock, never the slide offset.
	panel.position = layout_goal

func after_layout() -> void:
	if not is_instance_valid(panel): return
	var next_goal: Vector2 = panel.position
	var changed := not next_goal.is_equal_approx(layout_goal)
	layout_goal = next_goal
	if phase == &"closed" and not wanted: return
	if phase in [&"opening", &"closing"]:
		panel.position = before_position
		var destination := layout_goal if wanted else _closed_position()
		if not destination.is_equal_approx(motion_goal): _start(before_position)
	elif changed and wanted:
		_start(before_position)

func _closed_position() -> Vector2:
	return Vector2(layout_goal.x, maxf(host.get_viewport_rect().size.y, layout_goal.y + panel.size.y) + TRAVEL)

func _start(current: Vector2) -> void:
	if not is_instance_valid(host) or not is_instance_valid(panel): return
	var start := _closed_position() if phase == &"closed" else current
	_stop_tween()
	_lock_input(panel)
	panel.show()
	panel.position = start
	phase = &"opening" if wanted else &"closing"
	set_process(true)
	var ticket := generation
	var finish := layout_goal if wanted else _closed_position()
	motion_goal = finish
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_present.bind(ticket), start, finish, DURATION)
	tween.finished.connect(_completed.bind(ticket))
	_feedback()

func _present(value: Vector2, ticket: int) -> void:
	if ticket != generation or not is_instance_valid(panel): return
	panel.position = value
	_feedback()

func _completed(ticket: int) -> void:
	# A killed/queued old close is never allowed to hide a reopened dock.
	if ticket != generation or not is_instance_valid(panel): return
	tween = null
	panel.position = layout_goal
	panel.visible = wanted
	phase = &"open" if wanted else &"closed"
	if wanted: _restore_input()
	set_process(false)
	_feedback()

func _stop_tween() -> void:
	generation += 1
	if tween != null and tween.is_valid(): tween.kill()
	tween = null

func _lock_input(node: Node) -> void:
	# Preserve each explicit child override; root-only disabling permits children
	# with ENABLED overrides to escape the input lock. Never touch disabled/text.
	if not input_snapshot.is_empty(): return
	_capture_input(node)
	var focused: Control = panel.get_viewport().gui_get_focus_owner()
	if focused != null and (focused == panel or panel.is_ancestor_of(focused)):
		focused.release_focus()

func _capture_input(node: Node) -> void:
	if node is Control:
		var control := node as Control
		input_snapshot.append({"ref": weakref(control), "mouse": control.mouse_behavior_recursive,
			"focus": control.focus_behavior_recursive, "shortcut": control.is_processing_shortcut_input()})
		control.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		control.set_process_shortcut_input(false)
	for child in node.get_children(): _capture_input(child)

func _restore_input() -> void:
	for saved in input_snapshot:
		var control: Control = saved.ref.get_ref()
		if control == null: continue
		control.mouse_behavior_recursive = saved.mouse
		control.focus_behavior_recursive = saved.focus
		control.set_process_shortcut_input(saved.shortcut)
	input_snapshot.clear()
	# Do not re-grab focus: a held accept key must not activate on reopen.

func blocks_event(event: InputEvent) -> bool:
	var moving := phase in [&"opening", &"closing"] and is_instance_valid(panel)
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		var tail: bool = blocked_mouse.has(button.button_index)
		var inside := moving and _blocked_rect().has_point(button.position)
		if inside and button.pressed: blocked_mouse[button.button_index] = true
		if not button.pressed: blocked_mouse.erase(button.button_index)
		return inside or tail
	if event is InputEventMouseMotion:
		return moving and _blocked_rect().has_point(event.position)
	if event is InputEventKey:
		var key := event as InputEventKey
		var tail: bool = blocked_keys.has(key.keycode)
		var accept := key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
		if moving and accept and key.pressed: blocked_keys[key.keycode] = true
		if not key.pressed: blocked_keys.erase(key.keycode)
		return tail or (moving and accept)
	return false

func _blocked_rect() -> Rect2:
	var resting := Rect2(panel.global_position + layout_goal - panel.position, panel.size)
	return panel.get_global_rect().merge(resting)

func _restore_available() -> bool:
	if wanted or not is_instance_valid(host) or not is_instance_valid(panel): return false
	if not is_instance_valid(restore_button) or not restore_button.is_visible_in_tree(): return false
	if restore_button.disabled or not restore_button.can_process(): return false
	if restore_button.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE: return false
	if restore_button.get_viewport() != get_viewport(): return false
	if not host.has_method("set_map_dialogue_hidden"): return false
	if host.has_method("_api_settings_open") and bool(host.call("_api_settings_open")): return false
	return not _has_visible_window(host)

func _has_visible_window(node: Node) -> bool:
	for child in node.get_children(true):
		if child is Window and child.visible: return true
		if not child is Node3D and _has_visible_window(child): return true
	return false

func _handle_restore_mouse(event: InputEvent) -> bool:
	# The native GUI cannot see this button while the shield consumes its region.
	# Capture a complete primary click, consume both edges before board input,
	# then use Main's existing UI handler so all visibility state stays in sync.
	if event is InputEventMouseMotion: return restore_mouse_down
	if not event is InputEventMouseButton: return false
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT: return false
	if not button.pressed and restore_mouse_down:
		restore_mouse_down = false
		get_viewport().set_input_as_handled()
		if not button.canceled and not blocked_mouse.has(MOUSE_BUTTON_LEFT) and _restore_available():
			if restore_button.get_global_rect().has_point(button.position):
				host.call("set_map_dialogue_hidden", false)
		return true
	if button.pressed and not button.canceled and phase == &"closing" and not blocked_mouse.has(MOUSE_BUTTON_LEFT):
		if _restore_available() and restore_button.get_global_rect().has_point(button.position):
			restore_mouse_down = true
			return true
	return false

func _input(event: InputEvent) -> void:
	# Runs before older board handlers; STOP at GUI level alone cannot stop a
	# SubViewport/board _input handler. Consume the moving and resting footprint.
	if _handle_restore_mouse(event) or blocks_event(event): get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(host):
		restore_mouse_down = false
		_stop_tween()
		_restore_input()
		phase = &"closed"
		set_process(false)

func _feedback() -> void:
	if is_instance_valid(host) and host.has_method("_update_feedback_safe_rect"):
		host.call("_update_feedback_safe_rect")

func _exit_tree() -> void:
	restore_mouse_down = false
	_stop_tween()
	_restore_input()
	if is_instance_valid(panel):
		panel.position = layout_goal
		panel.visible = wanted
