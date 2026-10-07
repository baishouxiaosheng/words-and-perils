extends Button
## Retain PopupMenu as the original command/checked/disabled data owner.
## A plain Window presents it through UIPresenter, avoiding native auto-hide.
signal about_to_popup
var _source:=PopupMenu.new()
var presenter:Node
func _init()->void:
	add_child(_source);_source.hide();toggle_mode=true
	action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS
	pressed.connect(show_popup)
func get_popup()->PopupMenu:return _source
func show_popup()->void:
	if not is_instance_valid(presenter) or disabled:return
	about_to_popup.emit();presenter.open_menu(self)
func _shortcut_input(event:InputEvent)->void:
	if is_instance_valid(presenter) and presenter.menu_is_open():return
	if event.is_pressed() and not disabled and is_visible_in_tree() and _source.activate_item_by_event(event,false):
		get_viewport().set_input_as_handled()
