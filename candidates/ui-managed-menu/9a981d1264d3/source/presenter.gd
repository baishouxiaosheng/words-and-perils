extends Node
## Uniform lifecycle entry point; Window and source-owned Control adapters
## preserve their existing close, focus, and responsive-layout ownership.
const Presets=preload("res://view/ui_motion/presets.gd")
const WindowAdapter=preload("res://view/ui_motion/popup_motion.gd")
const ControlAdapter=preload("res://view/ui_motion/history_motion.gd")
var windows:Node
var drawers:Dictionary={}
var host:Control
var history:Node
var menus:Node
var entries:Dictionary:
	get:return windows.entries if is_instance_valid(windows) else {}
func bind(main:Control)->void:
	host=main
	menus=preload("res://view/ui_motion/managed_menu.gd").new();add_child(menus);menus.bind(self,main)
	windows=WindowAdapter.new();add_child(windows)
	history=register_drawer(main.journal_panel,func():return main.journal_open and not main.dialogue_hidden_for_map)
	main.get_viewport().size_changed.connect(_bounds_changed)
func register_drawer(panel:Control,intent:Callable,options:Dictionary={})->Node:
	if panel.get_parent() is Container or not intent.is_valid():return null
	if drawers.has(panel.get_instance_id()):return drawers[panel.get_instance_id()]
	var adapter:Node=ControlAdapter.new();add_child(adapter)
	adapter.bind_control(host,panel,intent,Presets.profile(&"drawer",options))
	drawers[panel.get_instance_id()]=adapter
	return adapter
func watch(window:Window)->void:windows.watch(window)
func open(window:Window)->void:
	if not is_instance_valid(window) or not window.has_method("adapted_extent"):return
	watch(window);prepare_reopen(window)
	var extent:Vector2i=window.call("adapted_extent",host.get_viewport_rect().size)
	window.popup_centered(extent)
func layout_window(window:Window)->void:
	var box:Rect2=Presets.geometry(window.get_meta(&"ui_motion_kind"),host.get_viewport_rect().size,Vector2.ZERO,window.get_meta(&"ui_motion_options",{}))
	var anchor:Variant=window.get_meta(&"ui_motion_anchor",null)
	if anchor is Callable and anchor.is_valid():box=Presets.anchored_geometry(window.get_meta(&"ui_motion_kind"),host.get_viewport_rect().size,anchor.call(host.get_viewport_rect().size,box.size),window.get_meta(&"ui_motion_options",{}))
	windows._before_layout(window.get_instance_id());window.size=Vector2i(box.size);window.position=Vector2i(box.position);windows._after_layout(window.get_instance_id())
func open_menu(button:Button)->void:menus.open(button)
func close_menus()->void:menus.close()
func menu_is_open()->bool:return is_instance_valid(menus) and menus.is_open()
func _bounds_changed()->void:
	for id:int in windows.entries:
		var window:Window=windows._window(id)
		if not is_instance_valid(window) or not window.visible or not window.has_meta(&"ui_motion_kind"):continue
		layout_window(window)
func prepare_reopen(window:Window)->void:windows.prepare_reopen(window)
func before_layout()->void:
	for adapter:Node in drawers.values():adapter.before_layout()
func after_layout()->void:
	for adapter:Node in drawers.values():adapter.after_layout()
	if is_instance_valid(menus):menus.relayout()
func close(window:Window)->void:windows.request_close(window.get_instance_id())
func sync_drawer(panel:Control)->void:
	# The source UI changes its intent first, then this adapter presents it.
	if drawers.has(panel.get_instance_id()):drawers[panel.get_instance_id()].after_layout()
func cancel()->void:
	if is_instance_valid(menus):menus.cancel()
	windows.cancel_all()
	for adapter:Node in drawers.values():adapter.cancel()

