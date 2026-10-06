extends Node
## Short, read-only selection feedback. Main installs this after build_ui().
## Never handles input or changes a token/pack root, world state or a shared resource.
const ACTOR_HOP := 0.10
const ITEM_HOP := 0.055
const HOP_DURATION := 0.28
const PULSE_DURATION := 0.34
const MAX_ROUTE_PULSES := 8
var _host: Control
var _board: Node3D
var _focus_key := ""
var _route_key := ""
var _revision := ""
var _windows: Array[WeakRef] = []
var _motion_root: Node3D
var _motion_actor := ""
var _parts: Array[Dictionary] = []
var _motion_tween: Tween
var _pulse_tween: Tween
var _route_tween: Tween
var _pulse_nodes: Array[MeshInstance3D] = []
var _route_nodes: Array[MeshInstance3D] = []

func _init(host: Control = null) -> void:
	_host = host

func _ready() -> void:
	name = "SelectionMotion"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 40 # After presentation and carried-item positioning.
	_watch_windows(get_tree().root)
	get_tree().node_added.connect(_watch_window)
	get_window().focus_exited.connect(cancel)

func _watch_windows(parent: Node) -> void:
	for child in parent.get_children(true):
		_watch_window(child)
		if not child is Node3D: _watch_windows(child)

func _watch_window(node: Node) -> void:
	if node is Window and not node.visibility_changed.is_connected(_on_window_visibility):
		_windows.append(weakref(node))
		node.visibility_changed.connect(_on_window_visibility)

func _on_window_visibility() -> void:
	# Hiding the overlap chooser may precede its valid selection callback.
	# Polling consumes blocked selections without replaying them on close.
	cancel()

func _exit_tree() -> void:
	cancel()

func _allowed() -> bool:
	if not is_instance_valid(_host) or not _host.is_inside_tree(): return false
	if get_tree().paused or not _host.can_process() or not _host.is_visible_in_tree(): return false
	if not get_window().has_focus(): return false
	if bool(_host.get("world_build_busy")) or bool(_host.get("generated_start_busy")): return false
	if _host.has_method("_api_settings_open") and _host.call("_api_settings_open"): return false
	if not is_instance_valid(_board) or not _board.is_inside_tree(): return false
	if not _board.can_process() or not _board.is_visible_in_tree() or not _board.is_processing_input(): return false
	if "load_error" in _board and not str(_board.get("load_error")).is_empty(): return false
	for index in range(_windows.size() - 1, -1, -1):
		var window: Window = _windows[index].get_ref()
		if window == null: _windows.remove_at(index)
		elif window.visible: return false
	var viewport: Viewport = _board.get_viewport()
	while viewport != null:
		if viewport.gui_disable_input: return false
		var container := viewport.get_parent() as SubViewportContainer
		if container == null: break
		viewport = container.get_viewport()
	return true

static func focus_key(reference: Dictionary) -> String:
	if reference.is_empty(): return ""
	# Actor/item custody and position refreshes are not fresh user selections.
	return str([reference.get("world_id", ""), reference.get("kind", ""), reference.get("id", ""), reference.get("catalog_version", ""), reference.get("hex", []) if reference.get("kind") == "tile" else []])

func _process(_delta: float) -> void:
	if not is_instance_valid(_host): cancel(); return
	var current: Node3D = _host.get("board") if is_instance_valid(_host.get("board")) else null
	var reference: Dictionary = _host.get("selected_focus")
	var preview: Dictionary = _host.get("movement_preview")
	var replaced := not is_instance_valid(_board) or current != _board
	if replaced: cancel(); _board = current
	var state: Dictionary = _board.get("world_state") if is_instance_valid(_board) else {}
	var revision := str([state.get("world_id", ""), state.get("state_version", -1)])
	_observe(reference, preview, revision, _allowed(), replaced)

func _observe(reference: Dictionary, preview: Dictionary, revision: String, allowed: bool, replaced: bool = false) -> void:
	var next_focus := focus_key(reference)
	var next_route := str(preview.get("route", [])) if preview.get("ok", false) else ""
	if replaced or revision != _revision or not allowed:
		cancel()
		_focus_key = next_focus; _route_key = next_route; _revision = revision
		return
	if not _parts.is_empty() and (not is_instance_valid(_motion_root) or not _motion_root.is_visible_in_tree() or _actor_moving(_motion_actor)):
		_cancel_motion()
	if next_focus != _focus_key:
		_cancel_motion(); _clear_pulses(false); _clear_pulses(true)
		_focus_key = next_focus
		if not reference.is_empty(): _show_selection(reference)
	if next_route != _route_key:
		_clear_pulses(true)
		_route_key = next_route
		if not next_route.is_empty(): _show_route()

func _actor_moving(id: String) -> bool:
	if id.is_empty() or not is_instance_valid(_board): return false
	var presenter: Node = _board.get("presentation")
	if not is_instance_valid(presenter): return false
	var tracks: Dictionary = presenter.get("actors")
	return bool(tracks.get(id, {}).get("moving", false))

func _show_selection(reference: Dictionary) -> void:
	var id := str(reference.get("id", ""))
	if reference.get("kind") == "actor":
		var tokens: Dictionary = _board.get("token_nodes")
		var token: Node3D = tokens.get(id)
		var state: Dictionary = _board.get("world_state")
		var actor: Dictionary = state.get("actors", {}).get(id, {})
		if is_instance_valid(token) and token.is_visible_in_tree() and not _actor_moving(id):
			if float(actor.get("health", {}).get("current", 1)) > 0:
				_begin_motion(token, id, ACTOR_HOP, 0.0)
			else: _show_pulse(token.global_position, 0.38)
		return
	if reference.get("kind") == "item":
		var item := _item_root(id)
		if is_instance_valid(item) and item.is_visible_in_tree():
			var state: Dictionary = _board.get("world_state")
			var owner_id := str(state.get("items", {}).get(id, {}).get("owner_actor_id", ""))
			if not _actor_moving(owner_id): _begin_motion(item, owner_id, ITEM_HOP, 0.04)
			return
	# Trees, settlements, environment props and non-rendered items get an owned
	# marker only. Never modify a shared MultiMesh, material, mesh or building.
	var anchor: Variant = _display_anchor(reference)
	if anchor is Vector3: _show_pulse(anchor, 0.62 if reference.get("kind") == "tile" else 0.36)

func _item_root(id: String) -> Node3D:
	if "inventory_packs" in _board:
		var packs: Dictionary = _board.get("inventory_packs")
		var view: Node = packs.get(id)
		if is_instance_valid(view): return view.get("pack") as Node3D
	if "inventory_pack" in _board:
		var view: Node = _board.get("inventory_pack")
		if is_instance_valid(view) and "reference" in view and view.get("reference").get("id") == id:
			return view.get("pack") as Node3D
	if "creative_view" in _board:
		var view: Node = _board.get("creative_view")
		if is_instance_valid(view):
			var items: Dictionary = view.get("item_nodes")
			return items.get(id, {}).get("node") as Node3D
	return null

func _display_anchor(reference: Dictionary) -> Variant:
	var hex: Array = reference.get("hex", [])
	if hex.size() != 2: return null
	if _board.has_method("_position"):
		var view: Node3D = _board.get("world_view")
		if is_instance_valid(view):
			var content: Node3D = view.get("content_root")
			if is_instance_valid(content): return content.to_global(_board.call("_position", hex))
	if "admitted_source" in _board:
		var source: RefCounted = _board.get("admitted_source")
		if source != null:
			var point: Vector3 = source.navigation.cell_center(hex)
			point.y = maxf(point.y, 0.0) # Match the V3 selected-cell waterline display.
			return _board.to_global(point)
	return null # No guessed geometry for an unsupported renderer.

func _begin_motion(root: Node3D, actor_id: String, height: float, swell: float) -> void:
	_cancel_motion()
	_motion_root = root; _motion_actor = actor_id
	_collect_parts(root)
	if _parts.is_empty(): return
	_motion_tween = create_tween()
	_motion_tween.tween_method(_apply_motion.bind(height, swell), 0.0, 1.0, HOP_DURATION)
	_motion_tween.tween_callback(_cancel_motion)

func _collect_parts(parent: Node) -> void:
	# Stop at the first mesh so nested selection shells follow exactly once.
	# The existing actor/item renderers use static MeshInstance3D descendants.
	for child in parent.get_children():
		if child is MultiMeshInstance3D or child is Label3D: continue
		if child is MeshInstance3D:
			if child.visible and child.mesh != null and child.name != "SelectionRing":
				_parts.append({"node": child, "base": child.transform, "parent_id": parent.get_instance_id()})
		elif child is Node3D and child.is_visible_in_tree():
			_collect_parts(child)

static func envelope(progress: float) -> float:
	# One short rise and settle, with exact zero at both endpoints.
	if progress <= 0.0 or progress >= 1.0: return 0.0
	return sin(PI * progress)

func _apply_motion(progress: float, height: float, swell: float) -> void:
	var amount := envelope(progress)
	for part in _parts:
		if not _owns_part(part): continue
		var node: MeshInstance3D = part.node
		var parent := node.get_parent() as Node3D
		if parent == null or absf(parent.global_basis.determinant()) < 0.000001: continue
		var posed: Transform3D = part.base
		# Work from the saved transform, never from the previous animated frame.
		# Uniform item swell is bounded to 4%; global hop stays vertical on slopes.
		posed.basis = posed.basis.scaled(Vector3.ONE * (1.0 + swell * amount))
		posed.origin *= 1.0 + swell * amount
		posed.origin += parent.global_basis.inverse() * Vector3(0, height * amount, 0)
		node.transform = posed

func _owns_part(part: Dictionary) -> bool:
	if not is_instance_valid(part.get("node")): return false
	var node: Node = part.node
	if node.is_queued_for_deletion(): return false
	var parent := node.get_parent()
	return parent != null and parent.get_instance_id() == part.parent_id

func _cancel_motion() -> void:
	if _motion_tween != null: _motion_tween.kill(); _motion_tween = null
	for part in _parts:
		if _owns_part(part): part.node.transform = part.base
	_parts.clear(); _motion_root = null; _motion_actor = ""

func _show_route() -> void:
	var route: Node3D
	if "route_preview" in _board: route = _board.get("route_preview")
	elif "route_root" in _board: route = _board.get("route_root")
	if not is_instance_valid(route) or not route.is_visible_in_tree(): return
	var segments: Array[MeshInstance3D] = []
	for child in route.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh: segments.append(child)
	if segments.is_empty(): return
	# Sample already-drawn segments; no pathfinding, costs or terrain reassessment.
	var count := mini(MAX_ROUTE_PULSES, segments.size())
	for i in range(count):
		var index := roundi(float(i) * float(segments.size() - 1) / maxf(1.0, count - 1))
		var segment := segments[index]
		var endpoint: Vector3 = segment.global_transform * Vector3(0, segment.mesh.height * 0.5, 0)
		_route_nodes.append(_make_pulse(endpoint, 0.13))
	_apply_route(0.0)
	_route_tween = create_tween()
	_route_tween.tween_method(_apply_route, 0.0, 1.0, PULSE_DURATION + 0.10)
	_route_tween.tween_callback(_clear_pulses.bind(true))

func _show_pulse(at: Vector3, radius: float) -> void:
	_pulse_nodes.append(_make_pulse(at + Vector3(0, 0.045, 0), radius))
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(_apply_pulse, 0.0, 1.0, PULSE_DURATION)
	_pulse_tween.tween_callback(_clear_pulses.bind(false))

func _make_pulse(at: Vector3, radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SelectionFeedbackOnly"
	var ring := TorusMesh.new()
	ring.inner_radius = radius; ring.outer_radius = radius + 0.025
	ring.rings = 24; ring.ring_segments = 4
	node.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f5d994")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_board.add_child(node); node.global_position = at
	return node

func _apply_pulse(progress: float) -> void:
	for i in range(_pulse_nodes.size()):
		if not is_instance_valid(_pulse_nodes[i]): continue
		var node := _pulse_nodes[i]
		node.scale = Vector3.ONE * (0.90 + 0.20 * progress)
		_set_pulse_alpha(node, 1.0 - progress)

func _apply_route(progress: float) -> void:
	for i in range(_route_nodes.size()):
		if not is_instance_valid(_route_nodes[i]): continue
		var node := _route_nodes[i]
		var local := clampf((progress - float(i) / maxf(1.0, _route_nodes.size()) * 0.22) / 0.78, 0.0, 1.0)
		node.scale = Vector3.ONE * (0.85 + 0.30 * local)
		_set_pulse_alpha(node, envelope(local) * 0.85)

func _set_pulse_alpha(node: MeshInstance3D, alpha: float) -> void:
	# Each marker owns this material. Material alpha also works in Compatibility.
	var material := node.material_override as StandardMaterial3D
	var color := material.albedo_color
	color.a = alpha; material.albedo_color = color

func _clear_pulses(route: bool) -> void:
	var tween := _route_tween if route else _pulse_tween
	if tween != null: tween.kill()
	var nodes := _route_nodes if route else _pulse_nodes
	for i in range(nodes.size()):
		if is_instance_valid(nodes[i]): nodes[i].hide(); nodes[i].queue_free()
	nodes.clear()
	if route: _route_tween = null
	else: _pulse_tween = null

func cancel() -> void:
	_cancel_motion(); _clear_pulses(false); _clear_pulses(true)
