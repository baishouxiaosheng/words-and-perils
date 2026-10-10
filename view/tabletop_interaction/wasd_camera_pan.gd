extends Node
## Presentation-only WASD camera translation. No action or actor-state writes.
## Main installs this after build_ui(); existing board input stays untouched.
## Q/E lift the character view; lifting widens the view (camera.size), never
## below the board's MIN_VIEW_SIZE (DEFAULT_VIEW_SIZE on boards without one).
const PAN_SPEED := 6.0 # World units per second, independent of camera zoom; board.pan_speed overrides.
const PAN_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]
const LIFT_RATE := 1.1 # View size e-folds per second while Q/E is held.
const LIFT_MAX := 40.0
const AXIS_EPSILON := 0.00000001
var _host: Control
var _board: Node3D
var _held: Dictionary = {}
var _release_required := true
var _windows: Array[WeakRef] = []
var _shown_speed := NAN
var _hint: Label
var _hint_tween: Tween

func _init(host: Control = null) -> void:
	_host = host

func _ready() -> void:
	name = "WASDCameraPan"
	# Observe blocked contexts too, so pause/guest mode cannot retain held keys.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_watch_existing_windows(get_tree().root)
	get_tree().node_added.connect(_watch_window)
	get_window().focus_exited.connect(_suspend)
	_watch_focus(get_viewport())

func _watch_existing_windows(parent: Node) -> void:
	# Include MenuButton/OptionButton's internal PopupMenus without walking meshes.
	for node in parent.get_children(true):
		_watch_window(node)
		if not node is Node3D: _watch_existing_windows(node)

func _watch_window(node: Node) -> void:
	if node is Window:
		_windows.append(weakref(node))
		node.visibility_changed.connect(_suspend)

func _watch_focus(viewport: Viewport) -> void:
	if not viewport.gui_focus_changed.is_connected(_on_focus_changed):
		viewport.gui_focus_changed.connect(_on_focus_changed)

func _on_focus_changed(control: Control) -> void:
	if control is TextEdit or control is LineEdit:
		_suspend()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_suspend()

func _suspend() -> void:
	_held.clear()
	_release_required = true

func _sync_board() -> void:
	var current: Node3D = _host.get("board") if is_instance_valid(_host) else null
	if not is_instance_valid(_board) or current != _board:
		_board = current
		_suspend()
		if is_instance_valid(_board) and _board.is_inside_tree():
			_watch_focus(_board.get_viewport())

func _pan_allowed() -> bool:
	if not is_instance_valid(_host) or not _host.is_inside_tree(): return false
	if get_tree().paused or not _host.can_process() or not _host.is_visible_in_tree(): return false
	if not get_window().has_focus(): return false
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META): return false
	if bool(_host.get("world_build_busy")) or bool(_host.get("generated_start_busy")): return false
	if _host.has_method("_api_settings_open") and _host.call("_api_settings_open"): return false
	if not is_instance_valid(_board) or not _board.is_inside_tree(): return false
	if not _board.can_process() or not _board.is_visible_in_tree() or not _board.is_processing_input(): return false
	if "load_error" in _board and not str(_board.get("load_error")).is_empty(): return false
	var camera: Camera3D = _board.get("camera")
	if not is_instance_valid(camera) or not camera.is_inside_tree() or not camera.is_current(): return false
	for index in range(_windows.size() - 1, -1, -1):
		var window: Window = _windows[index].get_ref()
		if window == null: _windows.remove_at(index)
		elif window.visible: return false
	var viewport: Viewport = _board.get_viewport()
	while viewport != null:
		if viewport.gui_disable_input: return false
		var focus := viewport.gui_get_focus_owner()
		if focus is TextEdit or focus is LineEdit: return false
		var container := viewport.get_parent() as SubViewportContainer
		if container == null: break
		viewport = container.get_viewport()
	return true

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	# Listen at Main's viewport before SubViewportContainer forwards the key;
	# the explicit focus/modal gate protects text editors and every popup.
	_sync_board()
	if _record_key(event, _pan_allowed()):
		get_viewport().set_input_as_handled()

func _record_key(event: InputEventKey, allowed: bool) -> bool:
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if not allowed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		_suspend()
		return false
	if not key in PAN_KEYS: return false
	if not event.pressed:
		_held.erase(key)
		return false
	# Echo or a held key from a blocked context cannot restart movement.
	if event.echo or _release_required: return false
	_held[key] = true
	return true

func _sample_keys(allowed: bool, physically_down: Dictionary) -> Vector2:
	if not allowed:
		_suspend()
		return Vector2.ZERO
	if _release_required:
		if physically_down.is_empty(): _release_required = false
		return Vector2.ZERO
	# A release consumed by a popup/GUI still stops the camera this frame.
	for key in _held.keys():
		if not physically_down.has(key): _held.erase(key)
	return Vector2(int(_held.has(KEY_D)) - int(_held.has(KEY_A)), int(_held.has(KEY_W)) - int(_held.has(KEY_S)))

func _process(delta: float) -> void:
	_sync_board()
	var physically_down: Dictionary = {}
	for key in PAN_KEYS:
		if Input.is_physical_key_pressed(key): physically_down[key] = true
	var axis := _sample_keys(_pan_allowed(), physically_down)
	_show_speed()
	var lift := int(_held.has(KEY_Q)) - int(_held.has(KEY_E))
	if (axis == Vector2.ZERO and lift == 0) or delta <= 0.0 or not is_finite(delta): return
	var camera: Camera3D = _board.get("camera")
	if lift != 0: lift_view(_board, camera, lift, delta)
	if axis == Vector2.ZERO: return
	var speed = _board.get("pan_speed")
	translate_rig(_board, camera, ground_motion(camera.global_basis, axis, float(speed) if speed != null else PAN_SPEED, delta))

func _show_speed() -> void:
	var speed = _board.get("pan_speed") if is_instance_valid(_board) else null
	if speed == null or is_equal_approx(float(speed), _shown_speed): return
	var first := is_nan(_shown_speed)
	_shown_speed = float(speed)
	if first or not is_instance_valid(_host): return
	if not is_instance_valid(_hint):
		_hint = Label.new()
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.add_theme_font_size_override("font_size", 18)
		_hint.add_theme_color_override("font_color", Color(1, 1, 1))
		_hint.add_theme_color_override("font_outline_color", Color(0.12, 0.10, 0.08, 0.9))
		_hint.add_theme_constant_override("outline_size", 6)
		_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_hint.position.y = 72
		_host.add_child(_hint)
	_hint.text = "镜头移动速度 ×%.1f" % (_shown_speed / PAN_SPEED)
	_hint.position.x = (_host.size.x - _hint.get_combined_minimum_size().x) * 0.5
	_hint.modulate.a = 1.0
	if _hint_tween: _hint_tween.kill()
	_hint_tween = _hint.create_tween()
	_hint_tween.tween_interval(0.9)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.5)

static func lift_view(board: Node3D, camera: Camera3D, direction: int, delta: float) -> bool:
	if not is_instance_valid(board) or not is_instance_valid(camera) or not "world_view" in board: return false
	var rig: Node3D = board.get("world_view")
	if not is_instance_valid(rig) or bool(rig.get("overview")): return false
	if board.has_method("_cancel_committed_camera"): board.call("_cancel_committed_camera")
	var constants: Dictionary = board.get_script().get_script_constant_map() if board.get_script() else {}
	var floor_size = constants.get("MIN_VIEW_SIZE", constants.get("DEFAULT_VIEW_SIZE"))
	var lowest := minf(float(floor_size) if floor_size != null else camera.size, camera.size)
	camera.size = clampf(camera.size * exp(direction * LIFT_RATE * delta), lowest, maxf(LIFT_MAX, camera.size))
	rig.call("_update_camera")
	return true

static func ground_motion(camera_basis: Basis, axis: Vector2, speed: float, delta: float) -> Vector3:
	var right := camera_basis.x
	var forward := -camera_basis.z
	right.y = 0.0
	forward.y = 0.0
	# A top-down view has no horizontal sightline; screen-up is the stable fallback.
	if forward.length_squared() <= AXIS_EPSILON:
		forward = camera_basis.y
		forward.y = 0.0
	if right.length_squared() <= AXIS_EPSILON: right = forward.cross(Vector3.UP)
	if forward.length_squared() <= AXIS_EPSILON: forward = Vector3.UP.cross(right)
	var direction := right.normalized() * axis.x + forward.normalized() * axis.y
	return direction.normalized() * maxf(0.0, speed) * maxf(0.0, delta)

static func translate_rig(board: Node3D, camera: Camera3D, displacement: Vector3) -> bool:
	if not is_instance_valid(board) or not is_instance_valid(camera): return false
	var rig: Node3D = board
	var focus_field := "view_focus"
	if not "view_focus" in board:
		if not "world_view" in board: return false
		rig = board.get("world_view")
		focus_field = "target"
	if not is_instance_valid(rig) or not focus_field in rig: return false
	if board.has_method("_cancel_committed_camera"): board.call("_cancel_committed_camera")
	displacement.y = 0.0
	var focus: Vector3 = rig.get(focus_field)
	# Translate the rig's retained focus AND the actual camera. Calling overview
	# fit/orbit methods here would recenter the board, or change height/heading.
	rig.set(focus_field, focus + rig.global_basis.inverse() * displacement)
	camera.global_position += displacement
	if rig.has_method("_update_budget"): rig.call("_update_budget")
	return true
