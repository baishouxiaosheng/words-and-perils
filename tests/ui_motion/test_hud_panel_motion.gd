extends SceneTree
## UNRUN. Isolated Godot 4.6 fixture; does not certify Main, visuals, FPS or IME.
const Motion = preload("res://view/ui_motion/hud_panel_motion.gd")
class Host extends Control:
	var intents := 0
	var restores := 0
	var dialogue_hidden_for_map := false
	var journal_open := true
	var api_settings_open := false
	var journal_panel: Control
	var dialogue_restore_button: Button
	var feedback_updates := 0
	var authority := {"position": [3, 4], "rng": 37, "receipt": {"turn": 9}}
	func _update_feedback_safe_rect() -> void: feedback_updates += 1
	func submit() -> void: intents += 1
	func _api_settings_open() -> bool: return api_settings_open
	func set_map_dialogue_hidden(hidden: bool) -> void:
		if dialogue_hidden_for_map and not hidden: restores += 1
		dialogue_hidden_for_map = hidden
		get_node("HUDPanelMotion").call("set_hidden", hidden)
		journal_panel.visible = journal_open and not hidden
		dialogue_restore_button.visible = hidden
class Backstop extends Control:
	var clicks := 0
	var raw_clicks := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: raw_clicks += 1
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: clicks += 1
		accept_event()
var failures: Array[String] = []
var passed := 0
var host: Host
var panel: PanelContainer
var goal: TextEdit
var submit: Button
var business_disabled: Button
var backstop: Backstop
var motion: Motion
var restore_button: Button

func _init() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)

func finish() -> void:
	var current: Tween = motion.tween
	if current != null:
		current.pause()
		current.custom_step(Motion.DURATION + 0.01)
	await process_frame

func half() -> Vector2:
	var current: Tween = motion.tween
	current.pause()
	current.custom_step(Motion.DURATION * 0.5)
	return panel.position

func push_click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func click(point: Vector2) -> void:
	push_click(point)
	await process_frame

func enter_key() -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = down
		root.push_input(event, true)
	await process_frame

func layout(position_: Vector2, size_: Vector2) -> void:
	motion.before_layout()
	# Stand-in for the real layout's authoritative measured result, not its math.
	panel.size = size_
	panel.position = position_
	motion.after_layout()

func run() -> void:
	# Match Main: responsive layout uses actual pixels.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1000, 700)
	host = Host.new()
	host.size = Vector2(1000, 700)
	root.add_child(host)
	backstop = Backstop.new()
	backstop.size = host.size
	host.add_child(backstop)
	panel = PanelContainer.new()
	panel.position = Vector2(200, 430)
	panel.size = Vector2(600, 220)
	host.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	goal = TextEdit.new()
	goal.custom_minimum_size = Vector2(280, 150)
	goal.text = "保留草稿：观察河岸，不提交。"
	row.add_child(goal)
	submit = Button.new()
	submit.text = "提交意图"
	submit.custom_minimum_size = Vector2(130, 150)
	# Explicit ENABLED descendants must not escape the parent lock.
	submit.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	submit.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	var shortcut := Shortcut.new()
	shortcut.events = [accept]
	submit.shortcut = shortcut
	submit.pressed.connect(host.submit)
	row.add_child(submit)
	business_disabled = Button.new()
	business_disabled.text = "等待裁定"
	business_disabled.disabled = true
	row.add_child(business_disabled)
	host.journal_panel = Control.new()
	host.journal_panel.position = Vector2(20, 20)
	host.journal_panel.size = Vector2(40, 40)
	host.add_child(host.journal_panel)
	restore_button = Button.new()
	restore_button.name = "RestoreDialogue"
	restore_button.custom_minimum_size = Vector2(42, 42)
	restore_button.size = Vector2(42, 42)
	restore_button.pressed.connect(func(): host.set_map_dialogue_hidden(false))
	host.add_child(restore_button)
	host.dialogue_restore_button = restore_button
	restore_button.hide()
	await process_frame
	await process_frame
	motion = Motion.new()
	host.add_child(motion)
	motion.bind_control(host, panel, restore_button)
	var original_position: Vector2 = panel.position
	var original_size: Vector2 = panel.size
	var authority_before := JSON.stringify(host.authority)
	var draft := goal.text
	goal.grab_focus()
	motion.set_hidden(true)
	motion.tween.pause()
	check(panel.visible and motion.phase == &"closing", "close keeps visible dock for actual slide")
	check(not submit.disabled and business_disabled.disabled, "business disabled flags unchanged on close")
	check(goal.text == draft and not goal.has_focus(), "draft retained and panel focus released")
	check(submit.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE, "explicit child mouse override locked")
	check(submit.get_focus_mode_with_override() == Control.FOCUS_NONE, "explicit child focus override locked")
	check(not submit.is_processing_shortcut_input(), "button shortcut processing blocked")
	var blocked_clicks := backstop.clicks
	var blocked_raw_clicks := backstop.raw_clicks
	await click(submit.get_global_rect().get_center())
	await enter_key()
	check(host.intents == 0 and backstop.clicks == blocked_clicks, "moving click/Enter neither submit nor penetrate GUI")
	check(backstop.raw_clicks == blocked_raw_clicks, "moving click does not reach older underlying _input handler")
	var midway := half()
	check(midway.y > original_position.y, "real Tween moves dock downward at half duration")
	var old_ticket: int = motion.generation
	motion.set_hidden(false)
	motion.tween.pause()
	check(panel.position == midway and panel.visible, "half-close reverse starts at current displayed position")
	motion._completed(old_ticket)
	motion._present(Vector2(-999, -999), old_ticket)
	check(panel.visible and panel.position == midway and motion.phase == &"opening", "stale close completion and sample ignored")
	await finish()
	check(panel.visible and panel.position == original_position, "reopen ends at exact layout position")
	check(submit.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_ENABLED, "original child mouse override restored")
	check(submit.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_ENABLED and submit.shortcut == shortcut, "focus and same shortcut resource restored")
	check(not goal.has_focus() and goal.text == draft, "completion never steals focus or clears draft")
	await click(submit.get_global_rect().get_center())
	check(host.intents == 1, "one actual restored button click produces exactly one intent")
	var intent_count := host.intents
	for i in range(12):
		var before: Vector2 = panel.position
		motion.set_hidden(i % 2 == 0)
		motion.tween.pause()
		check(panel.position == before, "rapid reversal %d is continuous" % i)
		motion.tween.custom_step(Motion.DURATION * 0.12)
	await finish()
	check(panel.visible and panel.position == original_position and host.intents == intent_count, "rapid toggles settle open without action")
	motion.set_hidden(true)
	var paused_at := half()
	var next_position := Vector2(80, 330)
	var next_size := Vector2(700, 240)
	layout(next_position, next_size)
	motion.tween.pause()
	check(panel.position == paused_at and panel.size == next_size, "resize keeps displayed position and adopts exact measured size")
	check(motion.layout_goal == next_position, "resize stores authoritative destination without clamping")
	motion.set_hidden(false)
	motion.tween.pause()
	check(panel.position == paused_at, "resize-close-open reversal remains continuous")
	await finish()
	check(panel.position == next_position and panel.size == next_size, "resized reopen reaches authoritative rectangle")
	# Viewport height can change while the dock's resting position stays equal.
	# The closing endpoint must then be recomputed; checking layout_goal alone
	# would finish at the old viewport edge and hide a still-visible dock.
	motion.set_hidden(true)
	var before_height_change := half()
	var old_tween: Tween = motion.tween
	root.size = Vector2i(1000, 1000)
	await process_frame
	layout(next_position, next_size)
	motion.tween.pause()
	check(motion.tween != old_tween and panel.position == before_height_change, "same resting position viewport resize retargets continuously")
	check(motion.motion_goal.y > root.size.y, "close endpoint tracks viewport height even with equal resting position")
	var before_size_change: Vector2 = panel.position
	var taller := Vector2(next_size.x, 900)
	old_tween = motion.tween
	layout(next_position, taller)
	motion.tween.pause()
	check(motion.tween != old_tween and panel.position == before_size_change, "same resting position measured-height resize retargets continuously")
	check(motion.motion_goal.y >= next_position.y + taller.y, "close endpoint accounts for measured panel bottom")
	motion.set_hidden(false)
	motion.tween.pause()
	layout(next_position, next_size)
	await finish()
	motion.set_hidden(true)
	motion.tween.pause()
	var same_tween: Tween = motion.tween
	motion.set_hidden(true)
	layout(next_position, next_size)
	check(motion.tween == same_tween, "duplicate request and same-size relayout do not restart motion")
	await finish()
	check(not panel.visible and motion.phase == &"closed", "finished close hides only at endpoint")
	await click(submit.get_global_rect().get_center())
	await enter_key()
	check(host.intents == intent_count and goal.text == draft, "hidden click/Enter never submit or change text")
	var closed_size := Vector2(740, 260)
	layout(Vector2(60, 300), closed_size)
	check(not panel.visible and panel.size == closed_size, "closed resize stays hidden and preserves layout size")
	motion.set_hidden(false)
	motion.tween.pause()
	check(panel.position.y >= root.size.y, "fully closed reopen starts below viewport")
	# Business logic may update disabled while blocked; adapter must preserve it.
	submit.disabled = true
	await finish()
	check(submit.disabled and business_disabled.disabled, "disabled changes made during animation are preserved")
	submit.disabled = false
	await click(submit.get_global_rect().get_center())
	check(host.intents == intent_count + 1, "after hidden reopen one click yields one intent")
	# A press during animation cannot turn into a click after completion.
	motion.set_hidden(true)
	motion.tween.pause()
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	pressed.position = submit.get_global_rect().get_center()
	root.push_input(pressed, true)
	motion.set_hidden(false)
	await finish()
	pressed.pressed = false
	pressed.position = submit.get_global_rect().get_center()
	root.push_input(pressed, true)
	await process_frame
	check(host.intents == intent_count + 1, "press spanning close/reopen cannot submit on release")
	var down := InputEventKey.new()
	down.keycode = KEY_ENTER
	down.pressed = true
	motion.set_hidden(true)
	motion.tween.pause()
	root.push_input(down, true)
	motion.set_hidden(false)
	await finish()
	down.echo = true
	root.push_input(down, true)
	down.pressed = false
	down.echo = false
	root.push_input(down, true)
	await process_frame
	check(host.intents == intent_count + 1, "held accept key cannot activate after reopen")
	# Real RestoreDialogue geometry and input route, not adapter.set_hidden(false).
	root.size = Vector2i(1600, 1080)
	host.size = Vector2(1600, 1080)
	await process_frame
	restore_button.position = Vector2(779, 1022)
	restore_button.size = Vector2(42, 42)
	layout(Vector2(380, 856), Vector2(840, 198))
	await finish()
	var restore_point := restore_button.get_global_rect().get_center()
	check(restore_point == Vector2(800, 1043) and panel.get_global_rect().has_point(restore_point), "real RestoreDialogue center overlaps resting dock")
	var before_restore_intents := host.intents
	var before_restore_gui := backstop.clicks
	var before_restore_raw := backstop.raw_clicks
	host.set_map_dialogue_hidden(true)
	motion.tween.pause()
	motion.tween.custom_step(Motion.DURATION * 0.35)
	var before_restore_position: Vector2 = panel.position
	var before_restore_ticket: int = motion.generation
	check(host.dialogue_hidden_for_map and not host.journal_panel.visible and restore_button.visible, "Main UI state synchronized before RestoreDialogue input")
	# API settings veto this route; no UI callback or board event is allowed.
	host.api_settings_open = true
	push_click(restore_point)
	check(host.restores == 0 and host.dialogue_hidden_for_map, "modal API gate blocks RestoreDialogue during close")
	host.api_settings_open = false
	# A press on the dock followed by a release on Restore is not a Restore click.
	var edge := InputEventMouseButton.new()
	edge.button_index = MOUSE_BUTTON_LEFT
	edge.position = Vector2(400, 900)
	edge.pressed = true
	root.push_input(edge, true)
	edge.position = restore_point
	edge.pressed = false
	root.push_input(edge, true)
	check(host.restores == 0 and not motion.restore_mouse_down, "dock-to-Restore release cannot trigger recovery")
	# Restore down then release elsewhere must consume both edges and cancel.
	edge.position = restore_point
	edge.pressed = true
	root.push_input(edge, true)
	edge.position = Vector2(50, 50)
	edge.pressed = false
	root.push_input(edge, true)
	check(host.restores == 0 and not motion.restore_mouse_down, "Restore drag-out release cancels without leaking")
	edge.position = restore_point
	edge.pressed = true
	root.push_input(edge, true)
	edge.pressed = false
	edge.canceled = true
	root.push_input(edge, true)
	check(host.restores == 0 and not motion.restore_mouse_down, "canceled Restore release cannot request recovery")
	edge.canceled = false
	# Only actual input over the visible sibling button requests the reversal.
	push_click(restore_point)
	motion.tween.pause()
	check(host.restores == 1 and motion.wanted and motion.phase == &"opening", "actual RestoreDialogue click reverses closing exactly once")
	check(panel.position == before_restore_position, "actual RestoreDialogue reversal starts at displayed position")
	check(not host.dialogue_hidden_for_map and host.journal_panel.visible and not restore_button.visible, "RestoreDialogue click synchronizes all Main visibility state")
	check(host.intents == before_restore_intents and backstop.clicks == before_restore_gui and backstop.raw_clicks == before_restore_raw, "RestoreDialogue click neither submits nor reaches board input")
	motion._completed(before_restore_ticket)
	check(panel.visible and motion.phase == &"opening", "old close cannot hide RestoreDialogue recovery")
	push_click(restore_point)
	push_click(submit.get_global_rect().get_center())
	await enter_key()
	check(host.restores == 1 and host.intents == before_restore_intents, "hidden Restore and submission input cannot double dispatch during recovery")
	check(backstop.clicks == before_restore_gui and backstop.raw_clicks == before_restore_raw, "recovery blocks both GUI and early board input")
	check(goal.text == draft and not submit.disabled and business_disabled.disabled, "RestoreDialogue recovery preserves draft and business disabled flags")
	await finish()
	await click(submit.get_global_rect().get_center())
	check(host.intents == before_restore_intents + 1 and host.restores == 1, "after actual RestoreDialogue recovery one click yields one intent")
	check(JSON.stringify(host.authority) == authority_before, "position RNG and receipt remain byte-identical")
	check(host.feedback_updates > 0 and original_size.x > 0, "feedback bounds updated during presentation")
	motion.set_hidden(true)
	motion.tween.pause()
	var dead_ticket: int = motion.generation
	panel.free()
	motion._present(Vector2.ZERO, dead_ticket)
	motion._completed(dead_ticket)
	motion._process(0.0)
	check(motion.tween == null and motion.input_snapshot.is_empty(), "panel destruction kills Tween and releases weak snapshots")
	motion.free()
	host.free()
	# Adapter destruction while its panel survives restores presentation/input.
	var survivor := PanelContainer.new()
	survivor.position = Vector2(100, 100)
	root.add_child(survivor)
	var second: Motion = Motion.new()
	root.add_child(second)
	second.bind_control(survivor, survivor)
	second.set_hidden(true)
	second.tween.pause()
	second.set_hidden(false)
	second.free()
	check(survivor.visible and survivor.position == Vector2(100, 100), "adapter destruction settles surviving panel to current intent")
	check(survivor.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED, "adapter destruction restores surviving input override")
	survivor.free()
	print("hud_panel_motion: %d passed, %d failed" % [passed, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
