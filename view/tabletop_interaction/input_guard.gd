extends RefCounted
## Original Godot 4 presentation-only input boundary. It cannot move game entities.
## See docs/tabletop_interaction/ADAPTATION.md for Tabletop Club design references.

static func context_for(board: Node) -> Dictionary:
	var result := {"keyboard_blocked": false, "pointer_blocked": false}
	var viewport := board.get_viewport()
	while viewport != null:
		var focus := viewport.gui_get_focus_owner()
		if focus is TextEdit or focus is LineEdit:
			result.keyboard_blocked = true
		var container := viewport.get_parent() as SubViewportContainer
		if container == null: break
		var outer := container.get_viewport()
		var hovered := outer.gui_get_hovered_control()
		# Ignored decorations do not become the hovered control. A real HUD
		# control must never send selection, wheel or drag input to the board.
		if hovered != null and hovered != container and not container.is_ancestor_of(hovered):
			result.pointer_blocked = true
		viewport = outer
	return result

static func permits(event: InputEvent, context: Dictionary) -> bool:
	if event is InputEventKey:
		return not context.get("keyboard_blocked", false)
	if event is InputEventMouse:
		return not context.get("pointer_blocked", false)
	return true

static func button_held(event: InputEventMouseMotion, button: MouseButton) -> bool:
	return (event.button_mask & (1 << (int(button) - 1))) != 0

static func shortcut_allowed(event: InputEventKey) -> bool:
	return event.pressed and not event.echo and not (event.ctrl_pressed or event.meta_pressed or event.alt_pressed)
