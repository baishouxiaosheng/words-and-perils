extends Node
## One bounded menu presenter, reading original PopupMenu data at every open.
## The original id/index callbacks run once, after the common close animation.
const Surface=preload("res://view/ui_motion/menu_surface.gd")
const Presets=preload("res://view/ui_motion/presets.gd")
var presenter:Node
var host:Control
var owner_button:Button
var surface:Window
var scroll:ScrollContainer
var column:VBoxContainer
var stack:Array=[]
var rows:Dictionary={}
var selected:=-1
var closing:=false
var pending:Dictionary={}
var revision:=0
var hover_timer:=Timer.new()
var hover_index:=-1
var hover_revision:=-1
var search_text:=""
var search_time:=0
var presentation_handoff:=false
func bind(ui:Node,main:Control)->void:
	presenter=ui;host=main;hover_timer.one_shot=true;add_child(hover_timer)
	hover_timer.timeout.connect(_hover_open)
func is_open()->bool:return is_instance_valid(surface) and surface.visible
func open(button:Button)->void:
	if closing and is_instance_valid(surface):
		presentation_handoff=true;pending.clear();closing=false;presenter.prepare_reopen(surface);presentation_handoff=false
	elif is_open():close();return
	owner_button=button;revision+=1;pending.clear();stack=[{"source":button.get_popup(),"title":"菜单","selected":-1}]
	if not is_instance_valid(surface):
		surface=Surface.new();surface.name="ManagedToolsMenu";surface.menu_owner=self;host.add_child(surface)
		surface.canceled.connect(back);surface.visibility_changed.connect(_visibility)
		surface.focus_exited.connect(_outside)
		surface.set_meta(&"ui_motion_anchor",Callable(self,"_anchor"))
		scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",4);scroll.add_child(column);surface.set_content(scroll)
		presenter.watch(surface)
	_build();presenter.layout_window(surface);surface.show();surface.grab_focus()
	owner_button.set_pressed_no_signal(true);_focus.call_deferred(selected,revision)
func _source()->PopupMenu:return stack.back().source if not stack.is_empty() else null
func _anchor(bounds:Vector2,extent:Vector2)->Vector2:
	var point:Vector2=owner_button.get_global_rect().end if is_instance_valid(owner_button) else bounds*0.5
	return Vector2(point.x-extent.x,point.y+8.0)
func _build()->void:
	hover_timer.stop();hover_index=-1;rows.clear();search_text=""
	for child:Node in column.get_children():column.remove_child(child);child.queue_free()
	var source:PopupMenu=_source()
	var header:=Label.new();header.text=str(stack.back().title);header.add_theme_color_override("font_color",Color("344740"));column.add_child(header)
	for index in range(source.item_count):
		if source.is_item_separator(index):
			if not source.get_item_text(index).is_empty():
				var label:=Label.new();label.text=source.get_item_text(index);label.add_theme_color_override("font_color",Color("675e4b"));column.add_child(label)
			column.add_child(HSeparator.new());continue
		var button:=Button.new();var prefix:=""
		if source.is_item_checkable(index):prefix=("● " if source.is_item_radio_checkable(index) else "✓ ") if source.is_item_checked(index) else "　 "
		button.text=prefix+source.get_item_text(index)+( "  ›" if source.get_item_submenu_node(index)!=null else "")
		button.icon=source.get_item_icon(index);button.tooltip_text=source.get_item_tooltip(index)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.custom_minimum_size=Vector2(0,38)
		button.disabled=source.is_item_disabled(index);button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		for color_name:String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(color_name,Color("344740"))
		button.pressed.connect(_activate.bind(index));button.mouse_entered.connect(_hover.bind(index))
		button.focus_entered.connect(_selected.bind(index))
		column.add_child(button);rows[index]=button
	surface.cancel_button_text="返回" if stack.size()>1 else "关闭"
	var paper:StyleBox=surface.get_theme_stylebox("panel","AcceptDialog")
	var content_height:float=column.get_combined_minimum_size().y+paper.get_margin(SIDE_TOP)+paper.get_margin(SIDE_BOTTOM)+44.0+14.0+8.0
	surface.configure(&"small",{"preferred":Vector2(420,content_height)})
	selected=int(stack.back().selected)
	if not rows.has(selected) or rows[selected].disabled:selected=_next(-1,1)
	scroll.scroll_vertical=0
func _focus(index:int,expected_revision:int=-1)->void:
	if expected_revision>=0 and expected_revision!=revision:return
	if not is_open() or closing or not rows.has(index) or rows[index].disabled:return
	selected=index;stack.back().selected=index;rows[index].grab_focus();scroll.ensure_control_visible(rows[index])
func _selected(index:int)->void:
	if closing or not is_open() or not rows.has(index):return
	selected=index;stack.back().selected=index;scroll.ensure_control_visible(rows[index])
func _next(from:int,direction:int)->int:
	var source:PopupMenu=_source()
	for step in range(1,source.item_count+1):
		var index:int=posmod(from+step*direction,source.item_count)
		if not source.is_item_separator(index) and not source.is_item_disabled(index):return index
	return -1
func _hover(index:int)->void:
	if closing or not is_open() or not rows.has(index) or rows[index].disabled:return
	selected=index;stack.back().selected=index;hover_timer.stop()
	if _source().get_item_submenu_node(index)!=null:
		hover_index=index;hover_revision=revision;hover_timer.start(_source().submenu_popup_delay)
func _hover_open()->void:
	if hover_revision==revision and not closing and is_open() and selected==hover_index:_activate(hover_index)
func _activate(index:int)->void:
	if closing or not is_open():return
	var source:PopupMenu=_source()
	if index<0 or index>=source.item_count or source.is_item_disabled(index) or source.is_item_separator(index):return
	var submenu:PopupMenu=source.get_item_submenu_node(index)
	if submenu!=null:
		if stack.size()>=8:return
		stack.back().selected=index;stack.append({"source":submenu,"title":source.get_item_text(index),"selected":-1})
		revision+=1;_build();presenter.layout_window(surface);_focus.call_deferred(selected,revision);return
	var id:int=source.get_item_id(index)
	pending={"source":source,"index":index,"id":id if id>=0 else index,"revision":revision+1}
	close(false)
func back()->void:
	if closing:return
	if stack.size()>1:
		stack.pop_back();revision+=1;_build();presenter.layout_window(surface);_focus.call_deferred(selected,revision)
	else:close()
func close(clear_action:bool=true)->void:
	if clear_action:pending.clear()
	if not is_open() or closing:return
	closing=true;revision+=1;hover_timer.stop();surface.request_motion_close()
func cancel()->void:
	pending.clear();hover_timer.stop();revision+=1
	if is_open():close()
func _visibility()->void:
	if surface.visible:return
	closing=false;hover_timer.stop()
	var action:Dictionary=pending;pending={}
	if is_instance_valid(owner_button):owner_button.set_pressed_no_signal(false)
	var root_source:PopupMenu=stack.front().source if not stack.is_empty() else null
	if is_instance_valid(root_source):root_source.popup_hide.emit()
	stack.clear()
	if action.is_empty():
		if is_instance_valid(owner_button):owner_button.grab_focus()
		return
	# Let the old embedded Window finish its visibility/input handoff before
	# the unchanged command opens a different modal Window. No re-show occurs.
	_dispatch.call_deferred(action)
func _dispatch(action:Dictionary)->void:
	if not is_inside_tree() or action.revision!=revision or is_open():return
	var source:PopupMenu=action.source;var index:int=action.index
	if not is_instance_valid(source) or index>=source.item_count or source.is_item_disabled(index) or source.is_item_separator(index):return
	var id:int=source.get_item_id(index)
	if (id if id>=0 else index)!=action.id:return
	source.id_pressed.emit(action.id);source.index_pressed.emit(index)
func relayout()->void:
	if is_open() and not closing:presenter.layout_window(surface)
func _outside()->void:
	# Embedded exclusive Windows do not receive an outside mouse event; the
	# embedder first transfers focus. Keep the Window lock until eased exit ends.
	if not presentation_handoff and is_open() and not closing:close()
func handle_input(event:InputEvent)->bool:
	if closing:return true
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not Rect2(Vector2.ZERO,Vector2(surface.size)).has_point(event.position):close();return true
	if not event is InputEventKey or not event.pressed:return false
	match event.keycode:
		KEY_ESCAPE,KEY_LEFT:back();return true
		KEY_UP:_focus(_next(selected,-1));return true
		KEY_DOWN:_focus(_next(selected,1));return true
		KEY_HOME:_focus(_next(-1,1));return true
		KEY_END:_focus(_next(0,-1));return true
		KEY_PAGEUP,KEY_PAGEDOWN:
			var direction:int=-1 if event.keycode==KEY_PAGEUP else 1
			for _i in range(5):_focus(_next(selected,direction))
			return true
		KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
			# Footer Cancel/Back keeps the shell's original button semantics.
			if rows.has(selected) and surface.gui_get_focus_owner()==rows[selected]:_activate(selected);return true
			return false
		KEY_RIGHT:
			if selected>=0 and _source().get_item_submenu_node(selected)!=null:_activate(selected)
			return true
		KEY_F11:
			if not event.echo:host.toggle_fullscreen()
			return true
	if event.unicode>=32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var now:int=Time.get_ticks_msec()
		search_text=(search_text if now-search_time<1000 else "")+String.chr(event.unicode).to_lower();search_time=now
		var source:PopupMenu=_source()
		for step in range(1,source.item_count+1):
			var index:int=posmod(selected+step,source.item_count)
			if rows.has(index) and not rows[index].disabled and source.get_item_text(index).to_lower().begins_with(search_text):_focus(index);return true
	return false
func _exit_tree()->void:
	pending.clear();hover_timer.stop()
