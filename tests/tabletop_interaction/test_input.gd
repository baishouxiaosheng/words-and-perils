extends SceneTree
## Lightweight exact-board input harness; no production terrain/cache loading.
const Guard = preload("res://view/tabletop_interaction/input_guard.gd")
var checks := 0
var failures: Array = []

class GenericHarness:
	extends "res://view/hex_board.gd"
	var orbit_calls := 0
	func _ready() -> void:
		camera = Camera3D.new(); add_child(camera)
	func _process(_delta: float) -> void: pass
	func orbit_camera(_angle: float, _pitch: float = 0.0) -> void: orbit_calls += 1
	func pick(_point: Vector2) -> Vector2i: return Vector2i(99,99)
	func pick_focus(_point: Vector2) -> Array[Dictionary]: return []

class CameraHarness:
	extends Node3D
	var orbit_calls := 0
	var pan_calls := 0
	var zoom_calls := 0
	func orbit(_x: float, _y: float) -> void: orbit_calls += 1
	func pan(_x: float, _y: float) -> void: pan_calls += 1
	func zoom(_amount: float) -> void: zoom_calls += 1

class CoastHarness:
	extends "res://view/playable_build/board.gd"
	func _ready() -> void:
		camera = Camera3D.new(); add_child(camera)
		world_view = CameraHarness.new(); add_child(world_view)
	func _process(_delta: float) -> void: pass
	func pick_focus(_point: Vector2) -> Array: return []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label); printerr("FAIL: ", label)

func button(index: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new(); event.button_index = index; event.pressed = pressed
	return event

func motion(mask: int) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new(); event.relative = Vector2(20, 10); event.button_mask = mask
	return event

func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(640, 480)
	var container := SubViewportContainer.new(); container.size = Vector2(640, 480); container.stretch = true; root.add_child(container)
	var viewport := SubViewport.new(); viewport.size = Vector2i(640, 480); container.add_child(viewport)
	var generic := GenericHarness.new(); viewport.add_child(generic)
	var coast := CoastHarness.new(); viewport.add_child(coast)
	# Disable automatic dispatch to keep assertions exact; call the production
	# handler directly with real InputEvents and live viewport/GUI focus owners.
	generic.set_process_input(false); coast.set_process_input(false)
	var editor := TextEdit.new(); editor.position = Vector2(380, 260); editor.size = Vector2(240, 180)
	editor.text = "输入 Q / E 不应旋转地图\nTyping must not control the map"; root.add_child(editor)
	await process_frame
	var key := InputEventKey.new(); key.keycode = KEY_Q; key.pressed = true
	editor.grab_focus(); await process_frame
	check(Guard.context_for(generic).keyboard_blocked, "Outer TextEdit focus is visible inside the board SubViewport")
	generic._input(key)
	check(generic.orbit_calls == 0, "Typing Q does not rotate the generated/scene camera")
	editor.release_focus(); generic._input(key)
	check(generic.orbit_calls == 1, "Q rotates when writing no longer owns keyboard focus")
	key.ctrl_pressed = true; generic._input(key)
	check(generic.orbit_calls == 1, "Ctrl-Q is not a plain camera shortcut")
	key.ctrl_pressed = false; key.echo = true; generic._input(key)
	check(generic.orbit_calls == 1, "Key repeat does not accelerate a camera shortcut")
	var line := LineEdit.new(); line.position = Vector2(380, 220); line.size.x = 240; root.add_child(line); line.grab_focus(); await process_frame
	check(Guard.context_for(coast).keyboard_blocked, "LineEdit/SpinBox-style input is protected too")
	line.release_focus()
	coast._input(button(MOUSE_BUTTON_RIGHT, true)); coast._input(motion(MOUSE_BUTTON_MASK_RIGHT))
	check(coast.world_view.orbit_calls == 1, "Coast right-drag still rotates normally")
	coast._input(motion(0))
	check(not coast.dragging and coast.world_view.orbit_calls == 1, "Lost right-button release does not leave camera dragging")
	coast._input(button(MOUSE_BUTTON_MIDDLE, true)); coast._input(motion(MOUSE_BUTTON_MASK_MIDDLE))
	check(coast.world_view.pan_calls == 1, "Coast middle-drag still pans normally")
	coast._input(motion(0))
	check(not coast.panning and coast.world_view.pan_calls == 1, "Lost middle-button release does not leave camera panning")
	generic._input(button(MOUSE_BUTTON_RIGHT, true)); generic._input(motion(MOUSE_BUTTON_MASK_RIGHT)); generic._input(motion(0))
	check(generic.orbit_calls == 2 and not generic.orbit_dragging, "Generated camera also recovers a swallowed release")
	coast._input(button(MOUSE_BUTTON_RIGHT, true)); coast._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	generic._input(button(MOUSE_BUTTON_RIGHT, true)); generic._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not coast.dragging and not generic.orbit_dragging, "Window focus loss cancels both camera gestures")
	var hud_motion := motion(0); hud_motion.position = Vector2(450, 300); hud_motion.global_position = hud_motion.position
	root.push_input(hud_motion, true); await process_frame
	check(Guard.context_for(coast).pointer_blocked, "Outer HUD surface blocks board pointer input")
	coast._input(button(MOUSE_BUTTON_WHEEL_UP, true)); coast._input(button(MOUSE_BUTTON_RIGHT, true))
	check(coast.world_view.zoom_calls == 0 and not coast.dragging, "HUD scroll/right-click cannot zoom or start map drag")
	check(not Guard.permits(button(MOUSE_BUTTON_LEFT, true), {"pointer_blocked": true}), "HUD click cannot become world attention selection")
	check(coast.world_state.is_empty() and generic.world_state.is_empty(), "All tested input remains presentation-only")
	print("TABLETOP INPUT: %d/%d passed (%s)" % [checks - failures.size(), checks, DisplayServer.get_name()])
	container.queue_free(); editor.queue_free(); line.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
