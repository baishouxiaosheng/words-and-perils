extends SceneTree
## Isolated math/rig/latch tests; live focus extraction and Main remain separate.
## Install at res://tests/camera_wasd/test_camera_wasd.gd for scheduled native QA.
const Pan = preload("res://view/tabletop_interaction/wasd_camera_pan.gd")
var failures: Array[String] = []
var checks := 0

class FocusBoard:
	extends Node3D
	var view_focus := Vector3(2, 3, 4)
	var camera: Camera3D
	var offset := Vector3(7, 10, 13)
	func rebuild_camera() -> void:
		camera.position = view_focus + offset

class CoastRig:
	extends Node3D
	var target := Vector3(2, 3, 4)
	var budget_updates := 0
	func _update_budget() -> void:
		budget_updates += 1

class CoastBoard:
	extends Node3D
	var world_view: CoastRig
	var camera: Camera3D
	var framing_active := true
	var cancel_count := 0
	var actor_position := Vector3(11, 12, 13)
	func _cancel_committed_camera() -> void:
		framing_active = false
		cancel_count += 1

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _near(actual: Vector3, expected: Vector3, label: String) -> void:
	_check(actual.distance_to(expected) < 0.00001, label)

func _basis(yaw: float, pitch: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)

func _key(key: int, pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	return event

func _run() -> void:
	_test_ground_motion()
	_test_latches()
	_test_focus_rig()
	_test_coast_rig()
	print("CAMERA_WASD_RESULT ",JSON.stringify({"suite": "camera_wasd", "ok":failures.is_empty(), "checks": checks, "failures": failures, "scope":"mathematics, translated rig and generic blocked-context latch stimuli only; no real Main or live focus/modal interaction", "network_calls":0}))
	quit(0 if failures.is_empty() else 1)

func _test_ground_motion() -> void:
	for yaw in [0.0, PI / 2.0, PI, -PI / 2.0, 0.73]:
		for pitch in [0.4, 0.72, 1.3]:
			var basis := _basis(yaw, pitch)
			var forward := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			var label := "yaw=%s pitch=%s" % [yaw, pitch]
			_near(Pan.ground_motion(basis, Vector2(0, 1), 6, 0.25), forward * 1.5, "W projected forward " + label)
			_near(Pan.ground_motion(basis, Vector2(0, -1), 6, 0.25), -forward * 1.5, "S projected back " + label)
			_near(Pan.ground_motion(basis, Vector2(1, 0), 6, 0.25), right * 1.5, "D projected right " + label)
			_near(Pan.ground_motion(basis, Vector2(-1, 0), 6, 0.25), -right * 1.5, "A projected left " + label)
			var diagonal: Vector3 = Pan.ground_motion(basis, Vector2(1, 1), 6, 0.25)
			_check(absf(diagonal.length() - 1.5) < 0.00001, "diagonal normalized " + label)
			_check(diagonal.y == 0.0, "motion exactly horizontal " + label)
	var timing_basis := _basis(0.6, 0.72)
	_near(Pan.ground_motion(timing_basis, Vector2(1, 1), 6, 1.0 / 60.0) * 60.0, Pan.ground_motion(timing_basis, Vector2(1, 1), 6, 1.0), "delta-time invariant")
	_near(Pan.ground_motion(timing_basis, Vector2.ZERO, 6, 1), Vector3.ZERO, "opposing keys cancel")
	_near(Pan.ground_motion(timing_basis, Vector2.ONE, 6, 0), Vector3.ZERO, "zero delta")
	for yaw in [0.0, PI / 2.0, 0.63]:
		var topdown := _basis(yaw, PI / 2.0)
		_near(Pan.ground_motion(topdown, Vector2(0, 1), 6, 1), Vector3(-sin(yaw), 0, -cos(yaw)) * 6, "top-down screen-up fallback")

func _test_latches() -> void:
	var input := Pan.new()
	for reason in ["TextEdit", "LineEdit", "modal", "PopupMenu", "settings delayed close", "paused", "guest", "disabled scene", "hidden board", "application focus out", "board replacement"]:
		input._suspend()
		input._sample_keys(true, {})
		_check(input._record_key(_key(KEY_W), true), "fresh W allowed before " + reason)
		_check(input._sample_keys(true, {KEY_W: true}) == Vector2(0, 1), "moves before " + reason)
		_check(input._sample_keys(false, {KEY_W: true}) == Vector2.ZERO, "blocked during " + reason)
		_check(input._sample_keys(true, {KEY_W: true}) == Vector2.ZERO, "held key cannot resume after " + reason)
		_check(not input._record_key(_key(KEY_W, true, true), true), "echo cannot resume after " + reason)
		_check(input._sample_keys(true, {}) == Vector2.ZERO, "release rearms after " + reason)
		_check(input._record_key(_key(KEY_W), true), "fresh press accepted after " + reason)
		_check(input._sample_keys(true, {KEY_W: true}) == Vector2(0, 1), "fresh press moves after " + reason)
	input._suspend()
	input._sample_keys(true, {})
	input._record_key(_key(KEY_W), true)
	input._record_key(_key(KEY_D), true)
	_check(input._sample_keys(true, {KEY_W: true, KEY_D: true}) == Vector2.ONE, "diagonal key state")
	_check(input._sample_keys(true, {}) == Vector2.ZERO, "GUI-consumed release is pruned")
	input._record_key(_key(KEY_W), true)
	input._record_key(_key(KEY_S), true)
	_check(input._sample_keys(true, {KEY_W: true, KEY_S: true}) == Vector2.ZERO, "opposite held keys cancel")
	for modifier in ["ctrl_pressed", "alt_pressed", "meta_pressed"]:
		input._suspend()
		input._sample_keys(true, {})
		var modified := _key(KEY_W)
		modified.set(modifier, true)
		_check(not input._record_key(modified, true), "shortcut not accepted " + modifier)
		_check(input._sample_keys(true, {KEY_W: true}) == Vector2.ZERO, "shortcut leaves no held key " + modifier)
	input._suspend()
	input._sample_keys(true, {})
	_check(not input._record_key(_key(KEY_Q), true), "Q orbit binding untouched")
	_check(not input._record_key(_key(KEY_E), true), "E orbit binding untouched")
	input.free()

func _test_focus_rig() -> void:
	var board := FocusBoard.new()
	root.add_child(board)
	# The focus is local-space, while the requested plane is global XZ.
	board.rotation = Vector3(0.2, 0.7, 0.1)
	board.scale = Vector3(1.2, 0.8, 1.5)
	board.camera = Camera3D.new()
	board.add_child(board.camera)
	board.rebuild_camera()
	var initial := board.camera.global_position
	var initial_focus := board.to_global(board.view_focus)
	var delta := Vector3(1, 0, -2)
	_check(Pan.translate_rig(board, board.camera, delta), "legacy/V3 focus rig accepted")
	_near(board.camera.global_position, initial + delta, "global camera translated")
	_near(board.to_global(board.view_focus), initial_focus + delta, "local focus transformed correctly")
	_check(is_equal_approx(board.camera.global_position.y, initial.y), "global height preserved with transformed rig")
	board.rebuild_camera()
	_near(board.camera.global_position, initial + delta, "next rig rebuild retains pan")
	board.free()

func _test_coast_rig() -> void:
	var board := CoastBoard.new()
	root.add_child(board)
	board.world_view = CoastRig.new()
	board.add_child(board.world_view)
	board.camera = Camera3D.new()
	board.world_view.add_child(board.camera)
	var offset := Vector3(3, 100, 7)
	board.camera.position = board.world_view.target + offset
	var initial := board.camera.global_position
	var initial_actor := board.actor_position
	var initial_basis := board.camera.global_basis
	_check(Pan.translate_rig(board, board.camera, Vector3(2, 0, -3)), "coast target rig accepted")
	_near(board.camera.global_position, initial + Vector3(2, 0, -3), "coast translated")
	_check(board.camera.global_basis.is_equal_approx(initial_basis), "camera heading unchanged")
	_check(board.cancel_count == 1 and not board.framing_active, "existing manual framing cancel called")
	_check(board.world_view.budget_updates == 1, "coast visibility budget refreshed")
	_near(board.actor_position, initial_actor, "player remains unmoved")
	board.camera.position = board.world_view.target + offset
	_near(board.camera.global_position, initial + Vector3(2, 0, -3), "coast retained target survives rebuild")
	board.free()
