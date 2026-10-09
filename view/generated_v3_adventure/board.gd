extends Node3D
## Native V3 pixels, picking and motion share the admitted Geometry/Nav bundle.
## Never instantiates legacy HexBoard/TerrainField or regenerates a V2 map.
const Picking=preload("res://view/generated_v3_adventure/picking.gd")
var picking=Picking.new()
const Geometry=preload("res://view/generated_v3_runtime/geometry.gd")
const Presentation=preload("res://view/generated_v3_adventure/presentation.gd")
const Tokens=preload("res://view/chess_tokens.gd")
const Catalog=preload("res://view/attention_catalog.gd")
const InputGuard=preload("res://view/tabletop_interaction/input_guard.gd")
const Glow=preload("res://view/playable_build/attention_glow.gd")
signal hex_selected(hex:Vector2i)
signal focus_candidates(candidates:Array,point:Vector2)
signal hex_hovered(hex:Vector2i,terrain:String,cost:float)
var admitted_source:RefCounted
var world_state:Dictionary={}
var load_error:=""
var attention_ui_mode:=true
var camera:Camera3D
var world_view:Node3D
var terrain_root:Node3D
var token_nodes:Dictionary={}
var tiles:Dictionary={}
var presentation:Node3D
var attention_catalog=Catalog.new()
var glow:Node
var selected_hex:=Vector2i(99,99)
var hover_hex:=Vector2i(99,99)
var selected_actor_id:=""
var view_focus:=Vector3.ZERO
var camera_distance:=25.0
var orbit_pitch:=0.95
var view_angle:=0.20
var overview_mode:=false
var overview_zoom_factor:=1.0
var overview_fit_size:=30.0
var overview_close_angle:=0.20
var overview:bool:
	get:return overview_mode
var orbit_dragging:=false
var orbit_drag_button:MouseButton=MOUSE_BUTTON_NONE
var overlays:Node3D
var route_root:Node3D
var route_signature:=""
var geometry_signature:=""
var token_support_metrics:Dictionary={}
var _lighting_installed:=false
func _init(source_:RefCounted=null) -> void:admitted_source=source_
func _ready() -> void:
	world_view=self
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12.0;camera.near=.02;camera.far=250;camera.current=true;add_child(camera)
	presentation=Presentation.new();add_child(presentation)
	glow=Glow.new();add_child(glow)
	overlays=Node3D.new();overlays.name="ReadOnlyTileAttention";add_child(overlays)
	route_root=Node3D.new();route_root.name="ExactTriangleRoute";add_child(route_root)
	if admitted_source==null or admitted_source.renderer_bundle.is_empty():load_error="缺少已校验的v3地形，未显示替代地图。";return
	_install_geometry()
	get_viewport().size_changed.connect(func():if overview_mode:_fit_overview())
func _install_geometry() -> void:
	var built:Dictionary=admitted_source.renderer_bundle
	if built.get("geometry_hash","")==geometry_signature and get_meta("source_hash","")==built.get("source_hash",""):return
	if not built.get("ok",false) or built.get("source_hash")!=admitted_source.identity.content_hash or built.get("geometry_hash")!=admitted_source.identity.geometry_hash:load_error="v3显示与通行来源不一致。";return
	if is_instance_valid(terrain_root):remove_child(terrain_root);terrain_root.queue_free()
	terrain_root=Geometry.create_view(built);add_child(terrain_root)
	if not _lighting_installed:Geometry.install_lighting(self);_lighting_installed=true
	picking.build(built.ground_mesh,built.water_mesh)
	geometry_signature=built.geometry_hash;load_error=""
	set_meta("renderer_id","native_v3_exploration/v1");set_meta("source_hash",built.source_hash);set_meta("geometry_hash",built.geometry_hash)
func set_world(state:Dictionary,animate_changes:bool=false,committed_effects:Array=[]) -> void:
	if admitted_source==null or not admitted_source.validate_state(state).ok:load_error="v3地图或进度未通过校验，当前画面保留。";return
	_install_geometry()
	if not load_error.is_empty():return
	var previous:Dictionary={}
	for id in presentation.actors:previous[id]=presentation.actors[id].support
	world_state=state.duplicate(true);tiles.clear()
	for key in state.hexes:
		var cell:Dictionary=state.hexes[key];tiles[key]={"hex":Vector2i(cell.q,cell.r),"terrain":cell.terrain,"raw":cell}
	for id in state.actors:
		var actor:Dictionary=state.actors[id]
		var ground:Vector3=admitted_source.navigation.cell_center(actor.hex)
		var pose:Dictionary=token_support_pose(ground,float(actor.get("token_rotation",-16.0)))
		var support:Vector3=pose.position
		token_support_metrics[id]=pose.duplicate(true)
		if not support.is_finite():load_error="旅人没有有效的v3落脚点。";return
		if not token_nodes.has(id):
			var token:Node3D=Tokens.build(id,actor);token.rotation=pose.rotation;add_child(token);token_nodes[id]=token;presentation.register_actor(id,token,support)
		presentation.set_actor_rotation(id,pose.rotation)
		var hex_route:Array=[]
		if animate_changes and previous.has(id):
			var prior:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(previous[id].x,previous[id].z))
			if prior.get("ok",false):hex_route.append(prior.hex)
			for patch in committed_effects:
				if patch.get("type")=="actor_move" and patch.get("actor_id")==id:hex_route.append(patch.hex.duplicate())
		if hex_route.size()>1 and hex_route.back()==actor.hex:
			var points:Array=admitted_source.navigation.route_points(hex_route)
			if points.size()>1:
				points[0]=previous[id];points[points.size()-1]=support
				for i in range(1,points.size()-1):points[i]+=Vector3(0,.12,0)
				presentation.move_actor_path(id,points,hex_route.size()-1)
			else:presentation.reset_actor(id,support)
		else:presentation.reset_actor(id,support)
		attention_catalog.capture({"world_id":state.world_id,"kind":"actor","id":id,"hex":actor.hex.duplicate(),"scene_id":actor.scene_id},str(actor.name)+" · 角色",token_nodes[id],true)
	draw_overlay()
func tile_key(hex:Vector2i) -> String:return "%d,%d"%[hex.x,hex.y]
func hex_pos(hex:Vector2i) -> Vector3:return admitted_source.navigation.cell_center([hex.x,hex.y])
func _surface_hit(origin:Vector3,direction:Vector3) -> Dictionary:
	return picking.raycast(origin,direction)
func pick_focus(point:Vector2) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if world_state.is_empty() or not load_error.is_empty():return result
	var origin:=camera.project_ray_origin(point);var direction:=camera.project_ray_normal(point)
	var hit:=_surface_hit(origin,direction)
	var limit:float=float(hit.get("distance",INF))
	result=attention_catalog.query(origin,direction,limit+0.002)
	if not hit.is_empty():
		var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(hit.point.x,hit.point.z))
		if cell.get("ok",false) and world_state.hexes.has(cell.key):
			var raw:Dictionary=world_state.hexes[cell.key]
			result.append({"reference":{"world_id":world_state.world_id,"kind":"tile","id":raw.id,"hex":cell.hex,"scene_id":raw.scene_id},"label":("海面" if hit.surface=="water" else "地格")+" · (%d,%d)"%cell.hex,"distance":hit.distance,"point":hit.point})
	result.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.distance)<float(b.distance))
	return result
func pick(point:Vector2) -> Vector2i:
	var hit:=_surface_hit(camera.project_ray_origin(point),camera.project_ray_normal(point))
	if hit.is_empty():return Vector2i(99,99)
	var cell:Dictionary=admitted_source.navigation.cell_at_xz(Vector2(hit.point.x,hit.point.z))
	return Vector2i(cell.hex[0],cell.hex[1]) if cell.get("ok",false) else Vector2i(99,99)
func select_attention(reference:Dictionary) -> void:
	if not reference.get("hex") is Array:return
	selected_hex=Vector2i(reference.hex[0],reference.hex[1]);selected_actor_id=reference.id if reference.get("kind")=="actor" else ""
	presentation.select_actor(selected_actor_id);glow.select_actor(selected_actor_id,token_nodes);draw_overlay()
func clear_actor_selection() -> void:
	selected_actor_id=""
	if is_instance_valid(presentation):presentation.select_actor("")
	if is_instance_valid(glow):glow.clear()
func _line(parent:Node3D,a:Vector3,b:Vector3,width:float,color:Color) -> void:
	if a.distance_to(b)<0.0001:return
	var node:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=width;mesh.bottom_radius=width;mesh.height=a.distance_to(b);mesh.radial_segments=5
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	node.mesh=mesh;node.material_override=mat;node.position=(a+b)/2;node.quaternion=Quaternion(Vector3.UP,(b-a).normalized());node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node)
func draw_overlay() -> void:
	if not is_instance_valid(overlays):return
	for child in overlays.get_children():overlays.remove_child(child);child.queue_free()
	for hex in [selected_hex,hover_hex]:
		if not tiles.has(tile_key(hex)):continue
		var center:Vector3=admitted_source.navigation.cell_center([hex.x,hex.y]);var points:Array=[]
		for i in range(25):
			var angle:=PI/6.0+TAU*float(i)/24.0
			var point:=center+Vector3(cos(angle)*.92,0,sin(angle)*.92)
			var height:Dictionary=admitted_source.navigation.height_at_xz(Vector2(point.x,point.z))
			if height.get("ok",false):point.y=maxf(float(height.height),0.0)+.035;points.append(point)
		for i in range(1,points.size()):_line(overlays,points[i-1],points[i],.016,Color("e5c98c") if hex==selected_hex else Color("b8c992"))
func set_route_preview(route:Array) -> void:
	var signature:String=str(route)+geometry_signature
	if signature==route_signature:return
	route_signature=signature
	for child in route_root.get_children():route_root.remove_child(child);child.queue_free()
	if route.size()<2:return
	var points:Array=admitted_source.navigation.route_points(route)
	for i in range(1,points.size()):_line(route_root,points[i-1]+Vector3(0,.08,0),points[i]+Vector3(0,.08,0),.022,Color("e5c98c"))
func focus_player() -> void:
	if not world_state.get("actors",{}).has("actor_player"):return
	overview_mode=false;view_focus=admitted_source.navigation.cell_center(world_state.actors.actor_player.hex)+Vector3(0,.35,0);camera.size=12.0;orbit_camera(0,0)
func reset_camera() -> void:
	overview_mode=true;overview_close_angle=view_angle;overview_zoom_factor=1.0;_fit_overview()
func _fit_overview() -> void:
	if admitted_source==null or admitted_source.renderer_bundle.is_empty():return
	var radius:float=float(admitted_source.data.board_radius)
	view_focus=Vector3(0,0,0)
	overview_fit_size=maxf(12.0,3.6*radius+3.0)
	camera.size=overview_fit_size*overview_zoom_factor;camera.position=view_focus+Vector3(0,70,0);camera.look_at(view_focus,Vector3.FORWARD)
func orbit_camera(yaw:float,pitch:float=0.0) -> void:
	view_angle+=yaw;orbit_pitch=clampf(orbit_pitch+pitch,.4,1.30)
	if overview_mode:_fit_overview();return
	camera.position=view_focus+Vector3(sin(view_angle)*cos(orbit_pitch),sin(orbit_pitch),cos(view_angle)*cos(orbit_pitch))*camera_distance;camera.look_at(view_focus)
func _pan(delta:Vector2) -> void:
	var scale_:float=camera.size/maxf(1.0,get_viewport().get_visible_rect().size.y)
	var right:Vector3=camera.global_transform.basis.x;right.y=0;right=right.normalized()
	var forward:Vector3=camera.global_transform.basis.y;forward.y=0;forward=forward.normalized()
	view_focus+=(-right*delta.x+forward*delta.y)*scale_
	if overview_mode:
		camera.position=view_focus+Vector3(0,70,0);camera.look_at(view_focus,Vector3.FORWARD)
	else:orbit_camera(0,0)
func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index==orbit_drag_button:orbit_dragging=false;orbit_drag_button=MOUSE_BUTTON_NONE
	if not InputGuard.permits(event,InputGuard.context_for(self)):
		if event is InputEventMouse:orbit_dragging=false;orbit_drag_button=MOUSE_BUTTON_NONE
		return
	if event is InputEventMouseMotion:
		orbit_dragging=orbit_dragging and orbit_drag_button!=MOUSE_BUTTON_NONE and InputGuard.button_held(event,orbit_drag_button)
		if orbit_dragging:
			if orbit_drag_button==MOUSE_BUTTON_MIDDLE:_pan(event.relative)
			else:orbit_camera(-event.relative.x*.007,event.relative.y*.004)
			return
		var hex:=pick(event.position)
		if hex!=hover_hex:
			hover_hex=hex;draw_overlay()
			if tiles.has(tile_key(hex)):hex_hovered.emit(hex,tiles[tile_key(hex)].terrain,0.0)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:orbit_dragging=true;orbit_drag_button=event.button_index
		elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var candidates:=pick_focus(event.position)
			if not candidates.is_empty():focus_candidates.emit(candidates,event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size=clampf(camera.size+(-.7 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .7),7.5,maxf(30.0,overview_fit_size*1.5))
			if overview_mode:overview_zoom_factor=camera.size/overview_fit_size
	if event is InputEventKey and InputGuard.shortcut_allowed(event):
		if event.keycode==KEY_Q:orbit_camera(-.22)
		elif event.keycode==KEY_E:orbit_camera(.22)
func _notification(what:int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_FOCUS_OUT]:orbit_dragging=false;orbit_drag_button=MOUSE_BUTTON_NONE

func token_support_pose(center:Vector3,yaw_degrees:float=-16.0) -> Dictionary:
	# A chess sole follows a locally fitted plane; only its presentation moves.
	# Re-sample the rotated perimeter and lift by the exact remaining residual.
	var radius:float=.332
	var samples:Array=[]
	for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var h:Dictionary=admitted_source.navigation.height_at_xz(Vector2(center.x,center.z)+offset)
		samples.append(float(h.height) if h.get("ok",false) else center.y)
	var gx:float=(samples[0]-samples[1])/(2*radius);var gz:float=(samples[2]-samples[3])/(2*radius)
	var normal:=Vector3(-gx,1,-gz).normalized()
	var basis:=Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,deg_to_rad(yaw_degrees))
	var origin_y:float=center.y;var maximum_residual:=0.0;var missing:=0
	for i in range(32):
		var angle:float=TAU*float(i)/32.0
		var point:Vector3=basis*Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var height:Dictionary=admitted_source.navigation.height_at_xz(Vector2(center.x+point.x,center.z+point.z))
		if height.get("ok",false):origin_y=maxf(origin_y,float(height.height)-point.y)
		else:missing+=1
	maximum_residual=origin_y-center.y
	return {"position":Vector3(center.x,origin_y+.003,center.z),"rotation":basis.get_euler(),"center_height":center.y,"lift":maximum_residual+.003,"slope_degrees":rad_to_deg(acos(clampf(normal.y,-1,1))),"sample_count":32,"unsupported_samples":missing}
