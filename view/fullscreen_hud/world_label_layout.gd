extends Node
## Bounded screen-space deconfliction. Only Label3D presentation is changed.
## Real geometry, selection references, world coordinates and game facts stay put.
const Tokens = preload("res://view/chess_tokens.gd")
var board: Node3D
var _bounds_cache: Dictionary = {}
var diagnostics: Dictionary = {}

func configure(owner_board: Node3D) -> void:
	board = owner_board
	# Actors, settlements and selected creative labels finish their own updates first.
	process_priority = 100

func _process(_delta: float) -> void:
	if not is_instance_valid(board) or not is_instance_valid(board.camera): return
	var camera: Camera3D = board.camera
	var screen := Rect2(Vector2.ZERO, board.get_viewport().get_visible_rect().size)
	if screen.size.x < 1 or screen.size.y < 1: return
	var selected := ""
	if board.has_method("world_label_rows"): selected=str(board.selected_actor_id)
	elif is_instance_valid(board.entity_selection): selected = str(board.entity_selection.selected_reference.get("id", ""))
	var rows: Array = []
	if board.has_method("world_label_rows"):
		rows=board.world_label_rows(selected)
	else:
		for id in board.token_nodes:
			if not board.world_state.get("actors", {}).has(id): continue
			var token: Node3D = board.token_nodes[id]
			var plate := token.get_node_or_null("Nameplate") as Label3D
			if not is_instance_valid(plate): continue
			var anchor := Vector3(0, Tokens.height_for(id, board.world_state.actors[id]) + 0.3, 0)
			rows.append({"id": str(id), "kind": "actor", "label": plate, "anchor": anchor, "priority": -20 if id == selected else (0 if id == "actor_player" else 10), "allowed": token.is_visible_in_tree()})
		if not board.world_view.overview:
			if is_instance_valid(board.settlement_view): _append_settlements(board.settlement_view, rows, selected)
			if is_instance_valid(board.lighthouse) and is_instance_valid(board.lighthouse.title):
				rows.append({"id": "shore_landmark_lamp", "kind": "landmark", "label": board.lighthouse.title, "anchor": Vector3(0, 1.42, 0), "priority": 30, "allowed": board.lighthouse.is_visible_in_tree()})
		if is_instance_valid(board.creative_view):
			var focused_id: String = str(board.creative_view.report().get("selected_id", ""))
			for row in board.creative_view.selection_nodes():
				var plate: Label3D = row.title
				# Read renderer-owned selection, not last-frame visibility: a label
				# suppressed at the edge must recover when the camera returns.
				if str(row.id) != focused_id or board.world_view.overview:
					plate.hide(); continue
				if not plate.has_meta(&"label_anchor_local"): plate.set_meta(&"label_anchor_local", plate.position)
				rows.append({"id": str(row.id), "kind": "focused_object", "label": plate, "anchor": plate.get_meta(&"label_anchor_local"), "priority": -10, "allowed": row.node.is_visible_in_tree()})
	rows.sort_custom(func(a, b): return a.priority < b.priority if a.priority != b.priority else a.id < b.id)
	var occupied: Array[Rect2] = _hud_rectangles()
	var hud_count := occupied.size()
	var output: Array = []
	var hidden: Array = []
	var max_shift := clampf(screen.size.y * 0.08, 48.0, 120.0)
	for row in rows:
		var plate: Label3D = row.label
		plate.position = row.anchor
		plate.visible = row.allowed
		if not row.allowed or camera.is_position_behind(plate.global_position):
			plate.hide(); continue
		var natural := projected_rect(plate, camera)
		if not natural.has_area() or not screen.intersects(natural):
			plate.hide(); continue
		var base_world := plate.global_position
		var base_screen := camera.unproject_position(base_world)
		var slot := find_slot(natural, screen.grow(-8.0), occupied, max_shift)
		if not slot.get("ok", false):
			plate.hide(); hidden.append(row.id); continue
		var shift: Vector2 = slot.shift
		var local := camera.global_transform.affine_inverse() * base_world
		plate.global_position = camera.project_position(base_screen + shift, maxf(camera.near + 0.001, -local.z))
		var placed := projected_rect(plate, camera)
		occupied.append(placed.grow(3.0))
		plate.set_meta(&"readable_label_rect", placed)
		output.append({"id": row.id, "kind": row.kind, "rect": [placed.position.x, placed.position.y, placed.size.x, placed.size.y], "shift_px": [shift.x, shift.y]})
	var overlap_count := 0
	for i in range(hud_count, occupied.size()):
		for j in range(i + 1, occupied.size()):
			if occupied[i].intersects(occupied[j]): overlap_count += 1
	diagnostics = {"policy": "selected_actor,player,actors,settlements,landmarks; selected objects only", "visible_labels": output, "hidden_due_density": hidden, "overlap_count": overlap_count, "max_shift_px": max_shift, "hud_obstacles": hud_count, "gameplay_writes": false}

func _hud_rectangles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var container := board.get_viewport().get_parent()
	if not container is SubViewportContainer: return result
	var ui := container.get_parent()
	if ui == null or not ui.has_method("apply_responsive_layout"): return result
	# Both the world and HUD use the same physical client-pixel coordinates.
	for key in ["area_panel", "map_cluster", "hero_panel", "action_panel", "journal_panel", "dialogue_restore_button"]:
		var control := ui.get(key) as Control
		if is_instance_valid(control) and control.is_visible_in_tree(): result.append(control.get_global_rect().grow(4.0))
	return result

func _append_settlements(view: Node3D, rows: Array, selected: String) -> void:
	if not view.is_visible_in_tree(): return
	if is_instance_valid(view.title):
		var id: String = str(view.manifest.get("id", ""))
		rows.append({"id": id, "kind": "settlement", "label": view.title, "anchor": view._title_base_position, "priority": -15 if id == selected else 20, "allowed": true})
	for extra in view._additional_views: _append_settlements(extra, rows, selected)

static func find_slot(natural: Rect2, screen: Rect2, occupied: Array[Rect2], max_shift: float) -> Dictionary:
	var candidates: Array[Vector2] = [Vector2.ZERO]
	var step := maxf(18.0, natural.size.y + 8.0)
	for level in range(1, 5):
		var distance := minf(max_shift, step * level)
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(-0.707, -0.707), Vector2(0.707, -0.707), Vector2(-0.707, 0.707), Vector2(0.707, 0.707)]:
			candidates.append(direction * distance)
	for offset in candidates:
		var rectangle := Rect2(natural.position + offset, natural.size)
		var clamp_shift := Vector2.ZERO
		if rectangle.position.x < screen.position.x: clamp_shift.x = screen.position.x - rectangle.position.x
		elif rectangle.end.x > screen.end.x: clamp_shift.x = screen.end.x - rectangle.end.x
		if rectangle.position.y < screen.position.y: clamp_shift.y = screen.position.y - rectangle.position.y
		elif rectangle.end.y > screen.end.y: clamp_shift.y = screen.end.y - rectangle.end.y
		var shift: Vector2 = offset + clamp_shift
		if shift.length() > max_shift + 0.01: continue
		rectangle.position += clamp_shift
		if not screen.encloses(rectangle): continue
		var clear := true
		for blocker in occupied:
			if rectangle.grow(3.0).intersects(blocker): clear = false; break
		if clear: return {"ok": true, "shift": shift}
	return {"ok": false}

func projected_rect(label: Label3D, camera: Camera3D) -> Rect2:
	var font_id := label.font.get_instance_id() if label.font != null else 0
	var key := "%d|%s|%d|%.8f|%s" % [font_id, label.text, label.font_size, label.pixel_size, str(label.offset)]
	var local: Rect2
	if _bounds_cache.has(key): local = _bounds_cache[key]
	else:
		var mesh := label.generate_triangle_mesh()
		if mesh == null: return Rect2()
		var faces := mesh.get_faces()
		if faces.is_empty(): return Rect2()
		local = Rect2(Vector2(faces[0].x, faces[0].y), Vector2.ZERO)
		for vertex in faces: local = local.expand(Vector2(vertex.x, vertex.y))
		if _bounds_cache.size() >= 128: _bounds_cache.clear()
		_bounds_cache[key] = local
	var scale_ := label.global_transform.basis.get_scale().abs()
	var result := Rect2()
	var first := true
	for corner in [local.position, Vector2(local.end.x, local.position.y), local.end, Vector2(local.position.x, local.end.y)]:
		var point: Vector3 = label.global_position + camera.global_basis.x.normalized() * corner.x * scale_.x + camera.global_basis.y.normalized() * corner.y * scale_.y
		var pixel := camera.unproject_position(point)
		if first: result = Rect2(pixel, Vector2.ZERO); first = false
		else: result = result.expand(pixel)
	return result.grow(4.0)

func report() -> Dictionary:
	return diagnostics.duplicate(true)
