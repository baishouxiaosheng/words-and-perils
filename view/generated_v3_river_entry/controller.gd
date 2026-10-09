extends CanvasLayer
## One-process overlay. Native integration/resource acceptance is still pending.
## Host authority and controls remain owned by Main; no source/adapter migration.
signal returned(result: Dictionary)
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Session = preload("res://view/generated_v3_river_entry/session.gd")
const EntryView = preload("res://view/generated_v3_river_entry/view.gd")
var session := Session.new()
var view: Control
var _host: Node
var _host_viewport: SubViewport
var _host_mode: int
var _viewport_mode: int
var _viewport_input_disabled: bool
var _focus_before: WeakRef
var _ui_reader: Callable
var _ui_bytes := ""
var _root_control: Control
var _feedback: Label
var _parked := false
var _releasing := false
var _retiring_view: WeakRef
var _retiring_adapter: WeakRef
var metrics: Dictionary = {}

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

func open(host: Node, host_adapter: RefCounted, status: Dictionary, host_viewport: SubViewport, ui_reader: Callable) -> Dictionary:
	if _releasing:return C.fail("RIVER_RELEASING","实验显示正在释放，请稍后再进入。")
	if blocks_host_input(): return C.fail("RIVER_DUPLICATE_OVERLAY","实验已经打开。")
	if not is_instance_valid(host) or not is_instance_valid(host_viewport) or not ui_reader.is_valid():
		return C.fail("RIVER_HOST_VIEW","原旅程显示或焦点不能验证，未打开实验。")
	var ui: Variant = ui_reader.call()
	if not ui is Dictionary or not C.safe(ui): return C.fail("RIVER_HOST_UI","原旅程焦点不能验证，未打开实验。")
	metrics = {"before_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"native_resource_gate":"pending; viewport suspension is not resource release"}
	var checked: Dictionary = session.enter(host_adapter,status,Session.ENTRY_ID)
	if not checked.ok: return checked
	_host=host;_host_viewport=host_viewport;_ui_reader=ui_reader;_ui_bytes=C.bytes(ui)
	_host_mode=host.process_mode;_viewport_mode=host_viewport.render_target_update_mode;_viewport_input_disabled=host_viewport.gui_disable_input
	var focus: Control=host.get_viewport().gui_get_focus_owner()
	_focus_before=weakref(focus) if is_instance_valid(focus) else null
	# No await between admission and host parking. Always-process overlay stays live.
	host_viewport.gui_disable_input=true;host_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	host.process_mode=Node.PROCESS_MODE_DISABLED;_parked=true
	_root_control=Control.new();_root_control.theme=host.get("theme") if host is Control else null;_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root_control.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(_root_control)
	var background:=ColorRect.new();background.color=Color("f2dfa6");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root_control.add_child(background)
	var column:=VBoxContainer.new();column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_root_control.add_child(column)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=48;column.add_child(header)
	var back:=Button.new();back.text="返回原旅程";back.custom_minimum_size=Vector2(160,42);back.pressed.connect(request_return);header.add_child(back)
	_feedback=Label.new();_feedback.text="离线河流测试 · 原旅程已暂停，返回后继续";_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(_feedback)
	view=EntryView.new();view.theme=host.get("theme") if host is Control else null;view.entry_session=session;view.size_flags_vertical=Control.SIZE_EXPAND_FILL;view.admitted.connect(_on_admitted);view.admission_failed.connect(_on_admission_failed);column.add_child(view)
	# A menu-confirm key must not target a navigation action in the new view.
	# Start on a neutral container; Tab still reaches ordinary guest controls.
	view.focus_mode=Control.FOCUS_ALL;view.grab_focus()
	return {"ok":true,"entry_id":Session.ENTRY_ID,"host_parked":true,"scope":"separate experimental session; current host authority unchanged"}

func blocks_host_input() -> bool: return _parked or session.is_open()

func _on_admitted() -> void:
	metrics["entered_static_bytes"]=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	metrics["river_geometry_hash"]=session.river.source.identity.geometry_hash
	metrics["river_water_hash"]=session.river.source.identity.water_hash

func _on_admission_failed(result: Dictionary) -> void:
	# Let the guest's signal stack unwind before queuing its subtree for deletion.
	_close_failed_view.call_deferred(result)

func _close_failed_view(result: Dictionary) -> void:
	var closed: Dictionary=close()
	returned.emit(result if closed.ok else closed)

func request_return() -> void:
	var result: Dictionary=close()
	if not result.ok:
		if is_instance_valid(_feedback):_feedback.text="；".join(result.get("errors",["暂不能返回"]))
		return
	returned.emit(result)

func close() -> Dictionary:
	if not blocks_host_input():return C.fail("RIVER_NOT_OPEN","实验当前未打开。")
	if not _ui_reader.is_valid() or C.bytes(_ui_reader.call())!=_ui_bytes:
		return C.fail("RIVER_HOST_FOCUS_DRIFT","原旅程焦点或草稿发生变化，未用旧副本覆盖。")
	_retiring_view=weakref(view) if is_instance_valid(view) else null
	_retiring_adapter=weakref(session.river) if session.river!=null else null
	var checked: Dictionary=session.leave()
	if not checked.ok:return checked
	metrics["before_release_static_bytes"]=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_releasing=true
	if is_instance_valid(view):
		if view.admitted.is_connected(_on_admitted):view.admitted.disconnect(_on_admitted)
		if view.admission_failed.is_connected(_on_admission_failed):view.admission_failed.disconnect(_on_admission_failed)
	if is_instance_valid(_root_control):_root_control.queue_free()
	_root_control=null;view=null;_feedback=null
	_host_viewport.gui_disable_input=_viewport_input_disabled;_host_viewport.render_target_update_mode=_viewport_mode
	_host.process_mode=_host_mode;_parked=false
	var focus: Variant=_focus_before.get_ref() if _focus_before!=null else null
	if is_instance_valid(focus) and focus.is_inside_tree():focus.grab_focus()
	_host=null;_host_viewport=null;_ui_reader=Callable();_ui_bytes="";_focus_before=null
	_measure_released.call_deferred()
	return checked

func _measure_released() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	metrics["returned_static_bytes"]=int(Performance.get_monitor(Performance.MEMORY_STATIC))
	metrics["guest_adapter_released"]=session.river==null and (_retiring_adapter==null or _retiring_adapter.get_ref()==null)
	metrics["guest_view_released"]=view==null and _root_control==null and (_retiring_view==null or _retiring_view.get_ref()==null)
	_releasing=false

func _unhandled_key_input(event: InputEvent) -> void:
	if blocks_host_input() and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		request_return();get_viewport().set_input_as_handled()
