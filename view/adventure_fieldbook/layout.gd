extends RefCounted
## Native-pixel HUD zones only. Never scales the world viewport/canvas.
const EDGE := 18.0
const GAP := 10.0

func scale_for(size: Vector2) -> float:
	return clampf(minf(size.y / 1080.0, size.x / 1600.0), 0.8, 1.5)

## hero_size is measured screen pixels. All output rectangles use screen pixels.
func rects(size: Vector2, expanded: bool = false, hero_size: Vector2 = Vector2(300, 170)) -> Dictionary:
	var factor: float = scale_for(size)
	var edge: float = EDGE * factor
	var gap: float = GAP * factor
	var hero_dims: Vector2 = hero_size.min((size - Vector2.ONE * edge * 2.0).max(Vector2.ONE))
	var hero := Rect2(Vector2(edge, size.y - hero_dims.y - edge), hero_dims)
	var map_dims := Vector2(230, 260) * factor
	map_dims = map_dims.min((size - Vector2.ONE * edge * 2.0).max(Vector2.ONE))
	var map := Rect2(Vector2(size.x - map_dims.x - edge, edge), map_dims)
	var width: float = minf(850.0 * factor, size.x - 2.0 * (hero_dims.x + edge + gap))
	var narrow: bool = width < 380.0 * factor
	if narrow: width = size.x - edge * 2.0
	width = maxf(1.0, width)
	var height: float = (310.0 if expanded else 228.0) * factor
	height = minf(height, maxf(1.0, size.y - edge * 2.0))
	var action := Rect2(Vector2((size.x - width) * 0.5, size.y - height - edge), Vector2(width, height))
	if narrow: hero.position.y = maxf(edge, action.position.y - hero.size.y - gap)
	var history_height: float = minf(300.0 * factor, maxf(0.0, action.position.y - gap - edge))
	var history := Rect2(Vector2(action.position.x, action.position.y - gap - history_height), Vector2(width, history_height))
	return {"hero": hero, "map": map, "action": action, "history": history}

func _field_control(obj: Object, field: String) -> Control:
	if field in obj:
		var value = obj.get(field)
		if value is Control: return value as Control
	return null

func _place(node: Control, rectangle: Rect2) -> void:
	if node == null: return
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = rectangle.position
	node.size = rectangle.size

func apply_to(scene: Control) -> void:
	var bounds: Vector2 = scene.get_viewport_rect().size
	var factor: float = scale_for(bounds)
	var expanded: bool = bool(scene.get("intent_expanded")) if "intent_expanded" in scene else false
	var opened: bool = bool(scene.get("journal_open")) if "journal_open" in scene else false
	var hidden: bool = bool(scene.get("dialogue_hidden_for_map")) if "dialogue_hidden_for_map" in scene else false
	var hero: Control = _field_control(scene, "hero_panel")
	var dimensions := Vector2(300, 170) * factor
	if hero != null: dimensions = dimensions.max(hero.get_combined_minimum_size())
	var zones: Dictionary = rects(bounds, expanded, dimensions)
	_place(hero, zones.hero)
	_place(_field_control(scene, "map_cluster"), zones.map)
	var action: Control = _field_control(scene, "action_panel")
	if action != null:
		var rectangle: Rect2 = zones.action
		rectangle.size.y = maxf(rectangle.size.y, action.get_combined_minimum_size().y)
		rectangle.position.y = bounds.y - rectangle.size.y - EDGE * factor
		_place(action, rectangle)
		action.visible = not hidden
		var history: Rect2 = zones.history
		history.size.y = minf(history.size.y, maxf(0.0, rectangle.position.y - GAP * factor - EDGE * factor))
		history.position.y = rectangle.position.y - GAP * factor - history.size.y
		zones.history = history
	var journal: Control = _field_control(scene, "journal_panel")
	_place(journal, zones.history)
	if journal != null: journal.visible = opened and not hidden
	var restore: Control = _field_control(scene, "dialogue_restore_button")
	if restore != null:
		restore.visible = hidden
		var dims: Vector2 = restore.get_combined_minimum_size().max(Vector2.ONE * 36.0 * factor)
		_place(restore, Rect2(Vector2((bounds.x - dims.x) / 2.0, bounds.y - dims.y - EDGE * factor), dims))
