extends "res://view/hex_board.gd"
## Same generated renderer and camera; only the closed admitted source may supply pixels.
const InventoryPackView = preload("res://view/generated_inventory/item_view.gd")
var inventory_pack: Node3D
const Preview = preload("res://view/playable_build/route_preview.gd")
const VisualProfile = preload("res://view/generated_adventure/visual_style/profile.gd")
var visual_profile: Node
var admitted_source: RefCounted
var load_error := ""
var route_preview: Node3D
var world_view: Node3D
var overview: bool:
	get:return overview_mode
func _init(source_: RefCounted=null) -> void:admitted_source=source_
func _ready() -> void:
	super._ready();world_view=self;attention_ui_mode=true
	visual_profile=VisualProfile.attach_to(self)
	route_preview=Preview.new();add_child(route_preview)
	inventory_pack=InventoryPackView.new();add_child(inventory_pack);inventory_pack.bind(self)
	var layout=preload("res://view/fullscreen_hud/world_label_layout.gd").new();layout.name="WorldLabelLayout";layout.configure(self);add_child(layout)
func set_world(state: Dictionary,animate_changes: bool=false,committed_effects: Array=[]) -> void:
	if admitted_source==null or not admitted_source.validate_state(state).ok:
		load_error="生成来源与当前地图不一致";return
	var visible_state: Dictionary=admitted_source.render_state(state)
	var previous: Dictionary={}
	if is_instance_valid(presentation):
		for id in presentation.actors:previous[id]=presentation.actors[id].support
	# The generic old display only animates directly to the destination. Reset it
	# and replay the exact committed route instead, so no dry detour is shortcut.
	load_error="";super.set_world(visible_state,false)
	if is_instance_valid(visual_profile):visual_profile.refresh_materials()
	for id in state.actors:
		var target: Vector3=_source_position(state.actors[id].hex)
		var waypoints: Array=[]
		if animate_changes and previous.has(id):
			for patch in committed_effects:
				if patch.get("type")=="actor_move" and patch.get("actor_id")==id:waypoints.append(_source_position(patch.hex))
		if not waypoints.is_empty() and waypoints.back().is_equal_approx(target):
			presentation.reset_actor(id,previous[id]);presentation.move_actor_path(id,waypoints,0.85)
		else:presentation.reset_actor(id,target)
	if is_instance_valid(inventory_pack):inventory_pack.update_state(state)
func pick_focus(point: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var visual_limit:=INF
	for candidate in super.pick_focus(point):
		visual_limit=minf(visual_limit,float(candidate.distance))
		if candidate.reference.get("kind") in ["actor","tile"]:
			candidate.reference.scene_id="scene_generated";result.append(candidate)
	if is_instance_valid(inventory_pack):
		var origin:=camera.project_ray_origin(point);var direction:=camera.project_ray_normal(point)
		var terrain_hit: Dictionary=_surface_hit(origin,direction)
		var limit: float=float(terrain_hit.get("distance",INF))+0.012
		var item_hit: Dictionary=inventory_pack.pick(point,minf(limit,visual_limit+0.001))
		if not item_hit.is_empty():result.append(item_hit)
	result.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.distance)<float(b.distance))
	return result
func select_attention(reference: Dictionary) -> void:
	super.select_attention(reference)
	if is_instance_valid(inventory_pack):inventory_pack.select(reference)
func clear_actor_selection() -> void:
	super.clear_actor_selection()
	if is_instance_valid(inventory_pack):inventory_pack.select({})
func set_route_preview(route: Array) -> void:
	if not is_instance_valid(route_preview):return
	var points: Array=[]
	for hex in route:
		var point:=hex_pos(Vector2i(hex[0],hex[1]));point.y=float(admitted_source.navigation.support_heights.get("%d,%d"%hex,0.0));points.append(point)
	route_preview.show_route(points)

func _source_position(hex: Array) -> Vector3:
	var point:=hex_pos(Vector2i(hex[0],hex[1]))
	point.y=float(admitted_source.navigation.support_heights.get("%d,%d"%hex,0.0))
	return point
func _update_overview_names() -> void:
	# Size only; the shared actor/site/HUD avoidance pass owns all label placement.
	if not is_instance_valid(camera):return
	var pixels_per_world:=get_viewport().get_visible_rect().size.y/maxf(0.01,camera.size)
	for node in find_children("*","Label3D",true,false):
		var plate: Label3D=node
		if not plate.has_meta("near_position"):plate.set_meta("near_position",plate.position)
		if not plate.has_meta("near_scale"):plate.set_meta("near_scale",plate.scale)
		var base: Vector3=plate.get_meta("near_scale")
		var nominal: float=float(plate.font_size)*plate.pixel_size*base.y*plate.get_parent().global_transform.basis.y.length()*pixels_per_world
		plate.scale=base*(maxf(1.0,OVERVIEW_NAME_MIN_PX/maxf(0.01,nominal)) if overview_mode else 1.0)
func world_label_rows(selected: String) -> Array:
	var result: Array=[]
	for node in find_children("*","Label3D",true,false):
		var plate: Label3D=node
		var kind: String=plate.get_meta("overview_kind","")
		if kind not in ["actor","site"]:continue
		if not plate.has_meta("near_position"):plate.set_meta("near_position",plate.position)
		var id: String=str(plate.get_parent().name)
		if kind=="actor":
			for actor_id in token_nodes:
				if token_nodes[actor_id]==plate.get_parent():id=actor_id;break
		result.append({"id":id,"kind":"actor" if kind=="actor" else "settlement","label":plate,"anchor":plate.get_meta("near_position"),"priority":(-20 if id==selected else (0 if id=="actor_player" else 10)) if kind=="actor" else 20,"allowed":plate.get_parent().is_visible_in_tree()})
	return result

func _update_overview_water() -> void:
	var previous_mode:=water_material_mode
	super._update_overview_water()
	if previous_mode!=water_material_mode and is_instance_valid(visual_profile):visual_profile.refresh_water()
