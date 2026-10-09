extends "res://view/hex_board.gd"
## Seven authored dry hexes reuse the existing generic renderer. This is test content.
const SceneAdapters = preload("res://view/playable_build/scene_adapters.gd")
const Preview = preload("res://view/playable_build/route_preview.gd")
var world_view: Node3D
var overview: bool:
	get: return overview_mode
var load_error := ""
var route_preview: Node3D
func _ready() -> void:
	super._ready()
	world_view=self
	attention_ui_mode=true
	route_preview=Preview.new();add_child(route_preview)
func set_world(state: Dictionary, animate_changes: bool = false) -> void:
	var scene_id: String = state.actors.actor_player.scene_id
	var registered := SceneAdapters.descriptor(state,scene_id)
	if not registered.ok or not registered.get("framework_fixture",false):load_error="场景显示配置不匹配";return
	var visible_state := SceneAdapters.projection(state,scene_id)
	super.set_world(visible_state,animate_changes)
func set_route_preview(route: Array) -> void:
	if not is_instance_valid(route_preview):return
	var points: Array=[]
	for hex in route:points.append(hex_pos(Vector2i(hex[0],hex[1]))+Vector3(0,terrain_field.support_height(Vector2i(hex[0],hex[1])),0))
	route_preview.show_route(points)
func pick_focus(point: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary]=super.pick_focus(point)
	for candidate in candidates:
		candidate.reference.scene_id=world_state.actors.actor_player.scene_id
	return candidates
func reset_camera() -> void:
	# Generic Board only enters overview for large generated worlds. This explicit
	# local scene still needs a real overview state so main can toggle back.
	if tiles.is_empty() or not is_instance_valid(camera):return
	if not overview_mode:overview_close_angle=view_angle
	overview_mode=true;overview_zoom_factor=1.0
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera_distance=20.0;view_angle=0.0;orbit_pitch=PI/2.0
	_fit_topdown();_update_chunk_visibility()
