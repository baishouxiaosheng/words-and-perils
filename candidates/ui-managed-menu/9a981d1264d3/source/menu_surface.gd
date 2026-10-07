extends "res://view/ui_motion/modal_window.gd"
## Same Window lifecycle and presets as settings; only menu input differs.
var menu_owner:Node
func _init()->void:
	super()
	borderless=true;dialog_close_on_escape=false;dialog_hide_on_ok=false
	configure(&"small")
	ok_button.hide();cancel_button_text="关闭"
	for color_name:String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:cancel_button.add_theme_color_override(color_name,Color("344740"))
func _cancel()->void:
	# A submenu cancel returns to its parent data; a root cancel requests the
	# shared Window close. Never hide the reused surface after a Back action.
	if get_meta(&"ui_motion_closing",false):return
	canceled.emit();set_input_as_handled()
func _input(event:InputEvent)->void:
	if visible and not get_meta(&"ui_motion_closing",false) and is_instance_valid(menu_owner):
		if menu_owner.handle_input(event):set_input_as_handled()
