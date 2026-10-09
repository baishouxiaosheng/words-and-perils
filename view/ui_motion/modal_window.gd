extends Window
## Two explicit Main dialogs use this presentation shell. Their existing
## confirmed/canceled callbacks retain business ownership; only hide is delayed.
const Presets=preload("res://view/ui_motion/presets.gd")
var presentation_kind:StringName=&"standard"
var presentation_options:Dictionary={}
signal confirmed
signal canceled
var dialog_hide_on_ok:=true
var dialog_autowrap:=false
var dialog_close_on_escape:=true
var ok_button_text:String="OK":
	set(value):ok_button_text=value;ok_button.text=value
var cancel_button_text:String="":
	set(value):cancel_button_text=value;cancel_button.text=value;cancel_button.visible=not value.is_empty()
var background:=Panel.new()
var buttons:=HBoxContainer.new()
var ok_button:=Button.new()
var cancel_button:=Button.new()
var message:=Label.new()
func _init()->void:
	visible=false;transient=true;exclusive=true;wrap_controls=false
	set_meta(&"ui_motion_modal",true);configure(presentation_kind,presentation_options)
	set_flag(Window.FLAG_MINIMIZE_DISABLED,true);set_flag(Window.FLAG_MAXIMIZE_DISABLED,true)
	add_child(background,false,Node.INTERNAL_MODE_FRONT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(buttons,false,Node.INTERNAL_MODE_BACK)
	buttons.add_spacer(true);buttons.add_child(cancel_button);buttons.add_child(ok_button)
	buttons.add_theme_constant_override("separation",14)
	ok_button.text=ok_button_text;cancel_button.hide()
	for button:Button in [ok_button,cancel_button]:button.custom_minimum_size=Vector2(96,44)
	ok_button.pressed.connect(_confirm);cancel_button.pressed.connect(_cancel)
	add_child(message,false,Node.INTERNAL_MODE_FRONT);message.hide()
	close_requested.connect(_cancel)
	size_changed.connect(_layout)
	visibility_changed.connect(func():
		if visible:_layout();ok_button.grab_focus())
func configure(kind:StringName,options:Dictionary={})->void:
	if Presets.profile(kind,options).is_empty():return
	presentation_kind=kind;presentation_options=options.duplicate(true)
	set_meta(&"ui_motion_kind",kind);set_meta(&"ui_motion_options",presentation_options)
func adapted_extent(bounds:Vector2)->Vector2i:
	return Vector2i(Presets.geometry(presentation_kind,bounds,Vector2.ZERO,presentation_options).size)
func set_content(content:Control)->void:
	var scroll:ScrollContainer
	if content is ScrollContainer:scroll=content
	else:
		scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(column)
		column.add_child(content)
	add_child(scroll);_layout()
func get_ok_button()->Button:return ok_button
func get_cancel_button()->Button:return cancel_button
func get_label()->Label:return message
func _confirm()->void:
	if get_meta(&"ui_motion_closing",false):return
	confirmed.emit()
	if dialog_hide_on_ok:request_motion_close()
	set_input_as_handled()
func _cancel()->void:
	if get_meta(&"ui_motion_closing",false):return
	canceled.emit();request_motion_close();set_input_as_handled()
func request_motion_close()->void:
	if not visible or get_meta(&"ui_motion_closing",false):return
	var callback:Variant=get_meta(&"ui_motion_request_close",null)
	if callback is Callable and callback.is_valid():callback.call()
	else:hide()
func _input(event:InputEvent)->void:
	if visible and has_focus() and dialog_close_on_escape and event.is_action_pressed(&"ui_close_dialog",false,true):
		_cancel()
func _notification(what:int)->void:
	if what==NOTIFICATION_THEME_CHANGED and is_inside_tree():_layout.call_deferred()
func _layout()->void:
	if not is_inside_tree():return
	var paper:StyleBox=get_theme_stylebox("panel","AcceptDialog")
	background.add_theme_stylebox_override("panel",paper);background.size=Vector2(size)
	var left:float=paper.get_margin(SIDE_LEFT);var right:float=paper.get_margin(SIDE_RIGHT)
	var top:float=paper.get_margin(SIDE_TOP);var bottom:float=paper.get_margin(SIDE_BOTTOM)
	buttons.position=Vector2(left,maxf(top,size.y-bottom-44));buttons.size=Vector2(maxf(1,size.x-left-right),44)
	for child in get_children():
		if child is Control and not child.is_set_as_top_level():
			child.position=Vector2(left,top);child.size=Vector2(maxf(1,size.x-left-right),maxf(1,buttons.position.y-top-14))
