extends Node
## New opt-in runtime SOURCE CANDIDATE. No engine/native/dynamic cost validation.
## Caller owns source selection, audited pins, LOD/MultiMesh dirty signals.
## Only this Node's private mask World/Canvas and explicit Ground slots are owned.
const DataPass = preload("local_mask_pass_runtime.gd")
const MAX_PIXELS := 1280 * 960
const RESOLVE_SHA := "3d4cf931fe70ff32ced70a472d244b3a1a31c28283def1443ebb82d4dc53bf72"
const GROUND_SHA := "659e8bb23e6b90a92b149513dc26701ad4228f4cf404cca38b0e4c166b7f286f"
const RING_BINDINGS := ["receiver_mask", "camera_depth_span", "receiver_ring_enabled", "receiver_mask_valid", "receiver_contour_aa_enabled"]
signal build_completed(epoch: int)
signal failed(error: String)
var last_error := ""
var enabled := false
var epoch := 0
var _installed := false
var _pending := false
var _generation := 0
var _completed_epoch := -1
var _dirty_reason := ""
var _resize_pending := false
var _restage_required := false
var _data: DataPass
var _source_view: Node3D
var _camera: Camera3D
var _source_viewport: Viewport
var _sun: DirectionalLight3D
var _source_world: World3D
var _size := Vector2i.ZERO
var _ground_rows: Array = []
var _ground_shader: Shader
var _ground_names: Array = []
var _resolve_shader: Shader
var _resolve_viewport: SubViewport
var _resolve_rect: ColorRect
var _resolve_material: ShaderMaterial
var _actor_watch: Array = []
var _watch_state: Array = []
var _listeners: Array = []

func _ready() -> void:
	set_process(false)
	process_priority = 100 # Inspect after normal presentation updates; see contract.

func install(source_view: Node3D, camera: Camera3D, source_viewport: Viewport, receivers: Array, casters: Array, sun: DirectionalLight3D, ground_materials: Array, registered_source_shader_pins: Dictionary, actor_watch: Array = [], registered_opaque_casters: Dictionary = {}) -> Dictionary:
	if _installed: return _error("Uninstall before replacing source identities or reviewed pins")
	if not is_inside_tree(): return _error("Parent the runtime Node before install")
	if not is_instance_valid(source_viewport): return _error("Explicit source viewport required")
	var raster_size := Vector2i(source_viewport.get_texture().get_size())
	if raster_size.x <= 0 or raster_size.y <= 0 or raster_size.x * raster_size.y > MAX_PIXELS: return _error("Actual source raster is outside positive 1280x960 pixel cap")
	var directory: String = get_script().resource_path.get_base_dir().get_base_dir().path_join("adapters")
	_ground_shader = load(directory.path_join("ground_receiver_color.gdshader")) as Shader
	_resolve_shader = load(directory.path_join("ring_resolve.gdshader")) as Shader
	if _ground_shader == null or _ground_shader.get_mode() != Shader.MODE_SPATIAL or _ground_shader.code.sha256_text() != GROUND_SHA: return _error("Ground colour adapter shader SHA/mode changed")
	if _resolve_shader == null or _resolve_shader.get_mode() != Shader.MODE_CANVAS_ITEM or _resolve_shader.code.sha256_text() != RESOLVE_SHA: return _error("Canvas resolve shader SHA/mode changed")
	_ground_names.clear()
	for uniform: Dictionary in _ground_shader.get_shader_uniform_list(): _ground_names.append(str(uniform.name))
	for name_ in RING_BINDINGS:
		if not _ground_names.has(name_): return _error("Ground colour binding missing: " + name_)
	_data = DataPass.new()
	var staged: Dictionary = _data.stage(source_view, camera, receivers, casters, sun, {"ground": load(directory.path_join("ground_mask_data.gdshader")), "water": load(directory.path_join("water_mask_data.gdshader"))}, source_viewport, raster_size, registered_source_shader_pins, registered_opaque_casters)
	if not staged.get("ok", false): return _discard_install(str(staged.get("error", "Source staging failed")))
	var registered: Dictionary = _data.register_owned_ground_colour(_ground_shader, ground_materials)
	if not registered.get("ok", false): return _discard_install(str(registered.get("error", "Explicit Ground slot registration failed")))
	var seen: Dictionary = {}
	for value: Variant in ground_materials:
		if not value is ShaderMaterial or value.shader == null or seen.has(value.get_instance_id()): return _discard_install("Ground materials must be unique live staged ShaderMaterials")
		var parameters: Dictionary = {}
		for uniform: Dictionary in value.shader.get_shader_uniform_list():
			var name_: String = str(uniform.name); parameters[name_] = value.get_shader_parameter(name_)
		_ground_rows.append({"material": value, "shader": value.shader, "parameters": parameters, "owned": false})
		seen[value.get_instance_id()] = true
	var geometry_ids: Dictionary = {}
	for row: Variant in receivers: geometry_ids[row.source.get_instance_id()] = true
	for value: Variant in casters:
		if is_instance_valid(value): geometry_ids[value.get_instance_id()] = true
	if actor_watch.size() > 32: return _discard_install("Explicit small actor-watch list is limited to 32 nodes")
	_actor_watch.clear()
	for value: Variant in actor_watch:
		if not value is Node3D or not is_instance_valid(value) or not value.is_inside_tree() or value.get_world_3d() != source_view.get_world_3d(): return _discard_install("Actor-watch node must belong to staged source World")
		if not geometry_ids.has(value.get_instance_id()) and value != source_view and not source_view.is_ancestor_of(value): return _discard_install("Actor-watch node must belong to explicit staged source branch")
		_actor_watch.append(value)
	_source_view = source_view; _camera = camera; _source_viewport = source_viewport; _sun = sun
	_source_world = source_view.get_world_3d(); _size = raster_size
	_installed = true; enabled = false; _resize_pending = false; _restage_required = false; _generation += 1; epoch += 1
	_watch_state = _watch_snapshot()
	_connect_owned(source_viewport, "size_changed", Callable(self, "_on_viewport_size_changed"))
	_connect_owned(source_view, "tree_exiting", Callable(self, "_on_source_exiting"))
	_connect_owned(camera, "tree_exiting", Callable(self, "_on_source_exiting"))
	_connect_owned(sun, "tree_exiting", Callable(self, "_on_source_exiting"))
	set_process(true)
	last_error = ""
	return {"ok": true, "enabled": false, "source_staged": true, "raster": [_size.x, _size.y], "allocated_mask_world": false, "allocated_canvas": false, "dynamic_cost_measured": false}

func set_enabled(value: bool) -> Dictionary:
	if not _installed: return _error("Install explicit source inputs first")
	if value and _restage_required: return _error("Unknown/changed source requires uninstall and explicit restage before enabling")
	if value and _resize_pending: return _error("Call set_size with the explicit actual source raster before enabling")
	if enabled == value: return {"ok": true, "enabled": enabled}
	if not value:
		enabled = false; epoch += 1; _close_valid()
		_restore_ground_slots(); _pause_owned_updates()
		return {"ok": true, "enabled": false, "baseline_restored": true}
	var source_error := _identity_error()
	if not source_error.is_empty(): return _fail_closed(source_error)
	if not is_instance_valid(_resolve_viewport):
		var activated: Dictionary = _data.activate()
		if not activated.get("ok", false): return _fail_closed(str(activated.get("error", "Mask activation failed")))
		_create_canvas()
	_install_ground_slots()
	enabled = true
	mark_dirty("explicit enable")
	return {"ok": true, "enabled": true, "receiver_mask_valid": false, "build_pending": true}

func mark_dirty(reason: String = "caller change") -> void:
	if not _installed: return
	epoch += 1; _dirty_reason = reason
	_close_valid() # Synchronous fail-closed gate before any asynchronous work.
	if enabled: _schedule_build()

func set_size(raster_size: Vector2i) -> Dictionary:
	if not _installed: return _error("Install source before setting actual raster")
	mark_dirty("explicit source raster size")
	var resized: Dictionary = _data.set_size(raster_size)
	if not resized.get("ok", false): return _fail_closed(str(resized.get("error", "Explicit raster resize failed")))
	_size = raster_size; _resize_pending = false
	if is_instance_valid(_resolve_viewport):
		_resolve_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_resolve_viewport.size = _size; _resolve_rect.size = Vector2(_size)
	_watch_state = _watch_snapshot()
	if enabled: _schedule_build()
	return {"ok": true, "raster": [_size.x, _size.y], "receiver_mask_valid": false}

func _process(_delta: float) -> void:
	if not _installed: return
	if is_instance_valid(_source_viewport) and Vector2i(_source_viewport.get_texture().get_size()) != _size and not _resize_pending:
		_resize_pending = true; mark_dirty("actual raster changed; explicit set_size required")
	var source_error := _identity_error()
	if not source_error.is_empty(): _fail_closed(source_error); return
	var current := _watch_snapshot()
	if current != _watch_state:
		_watch_state = current
		mark_dirty("camera/Sun/explicit actor pose changed")

func _schedule_build() -> void:
	if _pending or _resize_pending: return
	_pending = true
	call_deferred("_rebuild", _generation)

func _rebuild(generation: int) -> void:
	# One pending coroutine at a time; intermediate dirty epochs coalesce.
	while _installed and enabled and not _resize_pending and generation == _generation:
		var request_epoch := epoch
		var before := _watch_snapshot()
		var source_error := _identity_error()
		if not source_error.is_empty(): _pending = false; _fail_closed(source_error); return
		var synced: Dictionary = _data.sync_frame()
		if not synced.get("ok", false): _pending = false; _fail_closed(str(synced.get("error", "Explicit source requires restaging"))); return
		await RenderingServer.frame_post_draw
		if not _build_current(generation, request_epoch, before):
			if not _installed or not enabled or generation != _generation: break
			continue
		_resolve_material.set_shader_parameter("source_mask", _data.get_mask_texture())
		_resolve_material.set_shader_parameter("camera_depth_span", _camera.far - _camera.near)
		_resolve_material.set_shader_parameter("receiver_mask_valid", true)
		_resolve_material.set_shader_parameter("ring_resolve_enabled", true)
		_resolve_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not _build_current(generation, request_epoch, before):
			if not _installed or not enabled or generation != _generation: break
			continue
		# No await between completed-texture bind and opening all Ground valid gates.
		var completed: ViewportTexture = _resolve_viewport.get_texture()
		for saved: Dictionary in _ground_rows:
			var material: ShaderMaterial = saved.material
			material.set_shader_parameter("receiver_mask", completed)
			material.set_shader_parameter("camera_depth_span", _camera.far - _camera.near)
			material.set_shader_parameter("receiver_ring_enabled", true)
			material.set_shader_parameter("receiver_contour_aa_enabled", true)
		for saved: Dictionary in _ground_rows: saved.material.set_shader_parameter("receiver_mask_valid", true)
		_completed_epoch = request_epoch; _pending = false; last_error = ""
		build_completed.emit(request_epoch)
		return
	if generation == _generation:
		_pending = false
		if _installed and enabled: _schedule_build()

func _build_current(generation: int, request_epoch: int, before: Array) -> bool:
	if not _installed or not enabled or _resize_pending or generation != _generation or request_epoch != epoch: return false
	var source_error := _identity_error()
	if not source_error.is_empty(): _fail_closed(source_error); return false
	var staged_current: Dictionary = _data.check_source_current()
	if not staged_current.get("ok", false): _fail_closed(str(staged_current.get("error", "Source changed during draw; restage"))); return false
	if not staged_current.get("pose_current", false): mark_dirty("staged geometry moved during mask/resolve draw"); return false
	var current := _watch_snapshot()
	if current != before:
		_watch_state = current; mark_dirty("source moved while mask/resolve was drawing")
		return false
	for saved: Dictionary in _ground_rows:
		if not is_instance_valid(saved.material) or saved.material.shader != _ground_shader: _fail_closed("Ground material/shader identity changed; uninstall and restage"); return false
	return true

func _identity_error() -> String:
	if not is_instance_valid(_source_view) or not is_instance_valid(_camera) or not is_instance_valid(_source_viewport) or not is_instance_valid(_sun): return "Staged source identity was freed; uninstall and restage"
	if not _source_view.is_inside_tree() or not _camera.is_inside_tree() or not _sun.is_inside_tree(): return "Staged source left tree; uninstall and restage"
	if _source_view.get_world_3d() != _source_world or _camera.get_world_3d() != _source_world or _sun.get_world_3d() != _source_world or _source_view.get_viewport() != _source_viewport or _camera.get_viewport() != _source_viewport: return "Source World/viewport/camera identity changed; uninstall and restage"
	if _source_viewport.get_camera_3d() != _camera: return "Current source camera changed; uninstall and restage"
	if _source_viewport.scaling_3d_scale != 1.0 or _source_viewport.use_taa or _source_viewport.msaa_3d != Viewport.MSAA_DISABLED or _source_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED: return "Source AA/upscaling settings changed outside admitted raster"
	if _camera.projection != Camera3D.PROJECTION_ORTHOGONAL or _camera.far <= _camera.near: return "Unsupported camera projection/depth span; uninstall and restage"
	if not _resize_pending and Vector2i(_source_viewport.get_texture().get_size()) != _size: return "Actual source raster changed; call set_size or uninstall and restage"
	if not _sun.shadow_enabled or not _sun.is_visible_in_tree(): return "Source Sun shadow/visibility changed outside admitted input"
	for node: Variant in _actor_watch:
		if not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d() != _source_world or (node != _source_view and not _source_view.is_ancestor_of(node)): return "Explicit actor-watch source changed; uninstall and restage"
	return ""

func _watch_snapshot() -> Array:
	if not is_instance_valid(_camera) or not is_instance_valid(_sun): return []
	var values: Array = [_camera.global_transform, _sun.global_transform]
	for property in DataPass.CAMERA_PROPERTIES: values.append(_camera.get(property))
	for property in DataPass.SUN_PROPERTIES: values.append(_sun.get(property))
	values.append(_sun.is_visible_in_tree())
	for node: Variant in _actor_watch:
		if is_instance_valid(node): values.append(node.global_transform); values.append(node.is_visible_in_tree())
		else: values.append(null)
	return values

func _create_canvas() -> void:
	_resolve_viewport = SubViewport.new(); _resolve_viewport.name = "OwnedDirtyMaskRingCanvas"
	_resolve_viewport.size = _size; _resolve_viewport.disable_3d = true
	_resolve_viewport.transparent_bg = true; _resolve_viewport.use_hdr_2d = false
	_resolve_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_resolve_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_resolve_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_resolve_rect = ColorRect.new(); _resolve_rect.size = Vector2(_size); _resolve_rect.color = Color.WHITE
	_resolve_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolve_material = ShaderMaterial.new(); _resolve_material.shader = _resolve_shader
	_resolve_material.set_shader_parameter("receiver_mask_valid", false)
	_resolve_material.set_shader_parameter("ring_resolve_enabled", false)
	_resolve_rect.material = _resolve_material; _resolve_viewport.add_child(_resolve_rect)
	add_child(_resolve_viewport)

func _install_ground_slots() -> void:
	for saved: Dictionary in _ground_rows:
		var material: ShaderMaterial = saved.material
		material.shader = _ground_shader
		for name_ in saved.parameters:
			if _ground_names.has(name_) and not RING_BINDINGS.has(name_): material.set_shader_parameter(name_, saved.parameters[name_])
		for name_ in ["receiver_ring_enabled", "receiver_mask_valid", "receiver_contour_aa_enabled"]: material.set_shader_parameter(name_, false)
		material.set_shader_parameter("receiver_mask", null); saved.owned = true

func _restore_ground_slots() -> void:
	for saved: Dictionary in _ground_rows:
		if not saved.owned or not is_instance_valid(saved.material): continue
		var material: ShaderMaterial = saved.material
		for name_ in _ground_names: material.set_shader_parameter(name_, null)
		material.shader = saved.shader
		for name_ in saved.parameters: material.set_shader_parameter(name_, saved.parameters[name_])
		saved.owned = false

func _close_valid() -> void:
	for saved: Dictionary in _ground_rows:
		if saved.owned and is_instance_valid(saved.material): saved.material.set_shader_parameter("receiver_mask_valid", false)
	if is_instance_valid(_resolve_material): _resolve_material.set_shader_parameter("receiver_mask_valid", false)

func _pause_owned_updates() -> void:
	if _data != null: _data.pause_updates()
	if is_instance_valid(_resolve_viewport): _resolve_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _connect_owned(object: Object, signal_name: String, callback: Callable) -> void:
	if object.has_signal(signal_name) and not object.is_connected(signal_name, callback):
		object.connect(signal_name, callback); _listeners.append({"object": object, "signal": signal_name, "callback": callback})

func _on_viewport_size_changed() -> void:
	_resize_pending = true
	mark_dirty("source viewport size changed; caller must explicitly set_size")

func _on_source_exiting() -> void:
	_fail_closed("Staged source is exiting; uninstall and restage")

func _error(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message}

func _discard_install(message: String) -> Dictionary:
	if _data != null: _data.uninstall()
	_data = null; _ground_rows.clear(); _actor_watch.clear()
	return _error(message)

func _fail_closed(message: String) -> Dictionary:
	enabled = false; epoch += 1; _restage_required = true; _close_valid(); set_process(false)
	_restore_ground_slots(); _pause_owned_updates()
	last_error = message; failed.emit(message)
	return {"ok": false, "error": message, "enabled": false, "baseline_restored": true, "restage_required": true}

func report() -> Dictionary:
	return {"installed": _installed, "enabled": enabled, "epoch": epoch, "completed_epoch": _completed_epoch, "pending": _pending, "resize_pending": _resize_pending, "restage_required": _restage_required, "dirty_reason": _dirty_reason, "raster": [_size.x, _size.y], "last_error": last_error, "default_off": true, "water_ring_covered": false, "dynamic_cost_measured": false, "engine_parsed": false, "source_only_candidate": true, "persistent_mask_plus_resolved_rgba8": is_instance_valid(_resolve_viewport)}

func uninstall() -> Dictionary:
	enabled = false; _installed = false; epoch += 1; _generation += 1
	_close_valid(); set_process(false)
	for listener: Dictionary in _listeners:
		if is_instance_valid(listener.object) and listener.object.is_connected(listener.signal, listener.callback): listener.object.disconnect(listener.signal, listener.callback)
	_listeners.clear(); _restore_ground_slots()
	if is_instance_valid(_resolve_material): _resolve_material.set_shader_parameter("source_mask", null)
	if is_instance_valid(_resolve_viewport): _resolve_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED; _resolve_viewport.free()
	_resolve_viewport = null; _resolve_rect = null; _resolve_material = null
	var result: Dictionary = _data.uninstall() if _data != null else {"ok": true}
	_data = null; _ground_rows.clear(); _actor_watch.clear(); _watch_state.clear(); _pending = false
	_source_view = null; _camera = null; _sun = null; _source_viewport = null; _source_world = null
	_ground_shader = null; _resolve_shader = null; _ground_names.clear(); _size = Vector2i.ZERO
	_completed_epoch = -1; _resize_pending = false; _restage_required = false
	return {"ok": result.get("ok", false), "baseline_restored": true, "owned_world_and_canvas_removed": true, "owned_listeners_disconnected": true}

func _exit_tree() -> void:
	uninstall()
