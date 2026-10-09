extends Node3D
## Presentation wrapper: canonical r24 source, unchanged core facts, existing tokens.
const InputGuard = preload("res://view/tabletop_interaction/input_guard.gd")
const View = preload("res://private_main_visual/world_view.gd")
const Cache = preload("res://view/integrated_ecology_world/performance_variant/runtime_adapter.gd")
const CoastWorld = preload("res://view/playable_build/world.gd")
const Tokens = preload("res://view/chess_tokens.gd")
const Batcher = preload("res://view/static_batcher.gd")
const Presentation = preload("res://view/action_presentation.gd")
const CommittedEffects = preload("res://view/playable_build/committed_effect_router.gd")
const CommittedCamera = preload("res://view/playable_build/committed_camera.gd")
const RoutePreview = preload("res://view/playable_build/route_preview.gd")
const Lamp = preload("res://view/playable_build/lighthouse_marker.gd")
const SettlementView = preload("res://view/playable_build/settlement_view.gd")
const CreativeView = preload("res://view/playable_build/creative_view.gd")
const EntityCatalog = preload("res://view/playable_build/entity_catalog.gd")
const EntitySelection = preload("res://view/playable_build/entity_selection.gd")
const AttentionGlow = preload("res://view/playable_build/attention_glow.gd")
const NameStyle = preload("res://view/world_name_style.gd")
const River = preload("res://view/river_overlay_preview/river_overlay.gd")
const RIVER_PATH := "res://artifacts/river_overlay_portfix_20261002/optimized_same_footprint/render_cache_manifest_PENDING.json"
const RIVER_SHA := "7f30e7f76a00a78e626b3453ab13b0b1c8e95bc3771467d196b8c867871bbb76"
signal focus_candidates(candidates: Array, point: Vector2)
signal hex_hovered(hex: Vector2i, terrain: String, cost: float)
var world_view: Node3D
var camera: Camera3D
var world_state: Dictionary = {}
var tiles: Dictionary = {}
var support: Dictionary = {}
var token_nodes: Dictionary = {}
var presentation: Node3D
var committed_feedback: Node3D
var committed_camera: Node
var route_preview:Node3D
var name_style: Node
var selected_hex := Vector2i(99,99)
var hover_hex := Vector2i(99,99)
var selected_actor_id := ""
var attention_ui_mode := true
var load_error := ""
var lighthouse:Node3D
var settlement_view: Node3D
var creative_view: Node3D
var entity_selection: Node3D
var attention_glow:Node
var marker: MeshInstance3D
var dragging := false
var panning := false
var hover_elapsed := 0.0
var pending_hover := Vector2.ZERO
var hover_dirty := false
var label_signature := ""
var river_overlay: Node3D
var river_status := "未安装"
var contact_shadows: Dictionary = {}
func _ready() -> void:
	world_view = View.new(); add_child(world_view)
	var data := Cache.load_cache()
	if not data.ok: load_error = str(data.get("error","cache加载失败")); return
	world_view.show_cache(data); camera = world_view.camera
	if not world_view.compact_load_error.is_empty(): load_error = world_view.compact_load_error
	if not world_view.enable_world_canopies("natural_v2"): load_error += " / 全图植被："+world_view.whole_canopy_error
	_install_river()
	for row in CoastWorld.catalog().get("cells",[]):
		if row.has("support"):
			var p: Array = row.support.position; support["%d,%d" % [row.q,row.r]] = Vector3(p[0],p[1],p[2])
	presentation = Presentation.new(); add_child(presentation)
	presentation.surface_height_sampler=Callable(world_view,"presentation_height_at_xz")
	committed_feedback = CommittedEffects.new(); committed_feedback.name = "CommittedActionFeedback"
	world_view.content_root.add_child(committed_feedback)
	committed_feedback.motion_presenter = presentation
	committed_camera=CommittedCamera.new();committed_camera.name="CommittedCombatFraming";add_child(committed_camera)
	committed_camera.configure(world_view,camera)
	committed_feedback.feedback_camera=camera
	committed_feedback.safe_rect_provider=Callable(committed_camera,"usable_rect")
	committed_feedback.framing_gate=Callable(committed_camera,"effects_ready")
	committed_feedback.event_started.connect(committed_camera.show_cue)
	attention_glow = AttentionGlow.new(); add_child(attention_glow)
	lighthouse=Lamp.new();world_view.content_root.add_child(lighthouse)
	settlement_view=SettlementView.new();settlement_view.name="SourceBoundSettlement";world_view.content_root.add_child(settlement_view);settlement_view.configure(self)
	name_style = NameStyle.new(); add_child(name_style)
	creative_view = CreativeView.new(); creative_view.name = "SourceBoundCreativeObjects"; world_view.content_root.add_child(creative_view); creative_view.configure(self)
	if lighthouse.title!=null: name_style.attach(lighthouse.title)
	marker = MeshInstance3D.new(); marker.name = "FocusOnly_NoGameplayEffect"
	var ring := TorusMesh.new(); ring.inner_radius = 0.75; ring.outer_radius = 0.79; ring.rings = 32; ring.ring_segments = 5; marker.mesh = ring
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color("edc789"); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world_view.content_root.add_child(marker); marker.hide()
	entity_selection = EntitySelection.new(); entity_selection.name = "EnvironmentalSelection"; add_child(entity_selection)
	call_deferred("_configure_entity_selection")
	get_viewport().size_changed.connect(_resize_camera)
	var label_layout = preload("res://view/fullscreen_hud/world_label_layout.gd").new()
	label_layout.name = "WorldLabelLayout"; label_layout.configure(self); add_child(label_layout)
func _configure_entity_selection() -> void:
	if is_instance_valid(entity_selection): entity_selection.configure(self)

func tile_key(hex: Vector2i) -> String: return "%d,%d" % [hex.x,hex.y]
func _source_position(h: Array) -> Vector3:
	var key := "%d,%d" % [h[0],h[1]]
	return support.get(key,Vector3(sqrt(3)*(float(h[0])+float(h[1])/2),0,float(h[1])*1.5))
func _position(h:Array)->Vector3:
	var p:=_source_position(h)
	if is_instance_valid(world_view):p.y=world_view.presentation_height_at_xz(Vector2(p.x,p.z),p.y)
	return p
func set_route_preview(route:Array)->void:
	if not is_instance_valid(world_view):return
	if not is_instance_valid(route_preview):
		route_preview=RoutePreview.new();route_preview.name="ReadOnly_AssessedRoutePreview";world_view.content_root.add_child(route_preview)
	var points:Array=[]
	for hex in route:
		if not hex is Array or hex.size()!=2:return
		points.append(_position(hex))
	route_preview.show_route(points)

func set_world(state: Dictionary, animate_changes := false, committed_effects:Array = []) -> void:
	set_route_preview([])
	world_state = state.duplicate(true); tiles = state.get("hexes",{})
	if not animate_changes:
		if is_instance_valid(committed_feedback): committed_feedback.reset_to(state)
		if is_instance_valid(committed_camera): committed_camera.cancel(false)
	if not is_instance_valid(presentation): return
	# A load may remove optional authored actors. Dispose their old presentation
	# identities before names, picking and effect routing see the new roster.
	for id in token_nodes.keys():
		if state.actors.has(id): continue
		if selected_actor_id == id: clear_actor_selection()
		presentation.forget_actor(id)
		if is_instance_valid(token_nodes[id]): token_nodes[id].queue_free()
		token_nodes.erase(id)
		if contact_shadows.has(id):
			if is_instance_valid(contact_shadows[id]): contact_shadows[id].queue_free()
			contact_shadows.erase(id)
	for id in state.actors:
		var actor: Dictionary = state.actors[id]; var target := _source_position(actor.hex)
		if not token_nodes.has(id):
			var token := Tokens.build(id,actor); token.scale = Vector3.ONE * 0.62
			world_view.content_root.add_child(token); Batcher.merge_under(token); token_nodes[id] = token
			presentation.register_actor(id,token,target)
			_make_contact_shadow(id,target)
			var plate := Label3D.new(); plate.name = "Nameplate"; plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plate.font_size = 32; plate.pixel_size = 0.007; plate.position = Vector3(0,Tokens.height_for(id,actor)+0.3,0)
			token.add_child(plate)
		else:
			var track: Dictionary = presentation.actors[id]
			if animate_changes and track.support.distance_to(target)>0.01:
				var waypoints:Array=[]
				for effect in committed_effects:
					if effect.get("type")=="actor_move" and effect.get("actor_id")==id and effect.get("hex") is Array:
						waypoints.append(_source_position(effect.hex))
				if not waypoints.is_empty() and waypoints.back().is_equal_approx(target):presentation.move_actor_path(id,waypoints,0.75)
				else:presentation.move_actor(id,target,0.75)
			elif not animate_changes: presentation.reset_actor(id,target)
		var nameplate: Label3D = token_nodes[id].get_node("Nameplate")
		nameplate.text = "%s  %d/%d" % [actor.name,actor.health.current,actor.health.max]; name_style.attach(nameplate)
	_update_actor_spacing(state)
	if is_instance_valid(lighthouse):
		lighthouse.update_state(state,_position(state.actors.actor_keeper.hex),world_view.overview)
		name_style.attach(lighthouse.title)
	if is_instance_valid(settlement_view): settlement_view.sync_state(state)
	if is_instance_valid(creative_view): creative_view.sync_state(state)
	if is_instance_valid(entity_selection): entity_selection.sync_state(state)
	draw_overlay()
func _update_actor_spacing(state:Dictionary)->void:
	# Same-cell offsets are display only, bounded by the active dry token footprint.
	var groups:Dictionary={}
	for id in state.actors:
		var h:Array=state.actors[id].hex;var key:="%d,%d"%h
		if not groups.has(key):groups[key]=[]
		groups[key].append(str(id))
	for ids:Array in groups.values():
		ids.sort();var offsets:Array=[]
		if ids.size()>1:
			var h:Array=state.actors[ids[0]].hex;var source:=_source_position(h);var owner:="hex:%d,%d"%h
			for attempt in range(6):
				var candidates:Array=[];var fits:=true
				for i in range(ids.size()):
					var angle:=TAU*float(i)/float(ids.size())+PI*float(attempt)/6.0
					var offset:=Vector3(cos(angle),0,sin(angle))*(.33 if ids.size()==2 else .40)
					if not world_view.display_anchor_is_dry(Vector2(source.x+offset.x,source.z+offset.z),owner):fits=false;break
					if is_instance_valid(world_view.faceted_mountains):
						var context:Dictionary=world_view.faceted_mountains.source_context_at_xz(world_view,Vector2(source.x+offset.x,source.z+offset.z))
						if context.get("ok",false):offset.y=float(context.height)-source.y
					candidates.append(offset)
				if fits:offsets=candidates;break
		for i in range(ids.size()):
			presentation.set_actor_display_offset(ids[i],offsets[i] if offsets.size()==ids.size() else Vector3.ZERO)
			var token:Node3D=token_nodes[ids[i]];token.set_meta("same_cell_stack",ids.size() if offsets.is_empty() else 1)
		if ids.size()>1 and offsets.is_empty():
			var plate:Label3D=token_nodes[ids[0]].get_node("Nameplate")
			plate.text+=" · 同格 %d 人"%ids.size()
			# Existing pick_focus returns every coincident actor to the choice list.

func focus_player() -> void:
	_cancel_committed_camera(false)
	if world_state.is_empty() or not is_instance_valid(camera): return
	world_view.overview = false; world_view.scope_name = "adventure"; world_view.target = _position(world_state.actors.actor_player.hex)+Vector3(0,0.45,0)
	world_view.distance = 12; world_view.pitch = 0.72; world_view.yaw = 0.2; camera.size = 6.0; camera.projection = Camera3D.PROJECTION_ORTHOGONAL; world_view._update_camera()
func reset_camera() -> void:
	_cancel_committed_camera()
	if is_instance_valid(camera): world_view.set_scope("whole")
func _resize_camera() -> void:
	_cancel_committed_camera(false)
	if is_instance_valid(camera) and world_view.overview: world_view.set_scope("whole")
func select_attention(reference: Dictionary) -> void:
	if reference.get("hex") is Array: selected_hex = Vector2i(reference.hex[0],reference.hex[1])
	selected_actor_id = reference.id if reference.get("kind") == "actor" else ""
	presentation.select_actor(selected_actor_id)
	attention_glow.select_actor(selected_actor_id,token_nodes)
	if is_instance_valid(entity_selection): entity_selection.select(reference)
	draw_overlay()
func clear_actor_selection() -> void:
	selected_actor_id = ""
	if is_instance_valid(presentation): presentation.select_actor("")
	if is_instance_valid(attention_glow): attention_glow.clear()
	if is_instance_valid(entity_selection): entity_selection.clear()
func draw_overlay() -> void:
	if not is_instance_valid(marker): return
	marker.visible = tiles.has(tile_key(selected_hex))
	if marker.visible:
		marker.position = _position([selected_hex.x,selected_hex.y])+Vector3(0,0.04,0)
func pick_focus(point: Vector2) -> Array:
	var found: Array = []
	if not is_instance_valid(camera): return found
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var hit: Dictionary = world_view.inspect(point)
	var max_distance := INF
	if hit.get("ok"):
		var p: Array = hit.get("visual_position", hit.position)
		max_distance = origin.distance_to(world_view.content_root.to_global(Vector3(p[0],p[1],p[2])))
	# Exact mesh hits for characters and existing props. No per-object physics nodes.
	if is_instance_valid(entity_selection):
		found.append_array(entity_selection.pick(point, max_distance))
		for id in token_nodes:
			var actor_hit: Dictionary = entity_selection.hit_node(token_nodes[id], origin, direction)
			if actor_hit.is_empty() or actor_hit.distance > max_distance+0.03: continue
			found.append({"reference": {"world_id": world_state.world_id, "kind": "actor", "id": id, "hex": world_state.actors[id].hex.duplicate()}, "label": world_state.actors[id].name+" · 角色", "distance": actor_hit.distance})
	if hit.get("ok"):
		var key: String = String(hit.canonical_hex).trim_prefix("hex:")
		if tiles.has(key):
			var cell: Dictionary = tiles[key]
			if hit.get("visual_surface") == "faceted_mountain":
				var id := EntityCatalog.mountain_id(str(hit.get("visual_mountain_region", "")))
				var reference := EntityCatalog.make_reference(id, world_state, [cell.q,cell.r])
				if not reference.is_empty() and EntityCatalog.supports_hex(EntityCatalog.descriptor(id), reference.hex):
					found.append({"reference": reference, "label": "山群 · 可见山面", "distance": max_distance})
			found.sort_custom(func(a,b): return a.distance < b.distance)
			found.append({"reference":{"world_id":world_state.world_id,"kind":"tile","id":cell.id,"hex":[cell.q,cell.r]},"label":"(%d,%d) · %s%s" % [cell.q,cell.r,cell.terrain," · 暂不可步行" if cell.ground_blocked else ""],"distance":max_distance+0.1})
	return found
func _input(event: InputEvent) -> void:
	# Always release first, even when a HUD control has taken the pointer.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: dragging = false
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
	if not InputGuard.permits(event, InputGuard.context_for(self)):
		if event is InputEventMouse: dragging = false; panning = false
		return
	if not is_instance_valid(camera): return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_cancel_committed_camera()
	if event is InputEventMouseButton and (event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]):_cancel_committed_camera()
	if event is InputEventMouseMotion:
		# A release outside this SubViewport may never reach _input. The next
		# motion's button mask is authoritative for this presentation gesture.
		dragging = dragging and InputGuard.button_held(event, MOUSE_BUTTON_RIGHT)
		panning = panning and InputGuard.button_held(event, MOUSE_BUTTON_MIDDLE)
		if dragging:
			_cancel_committed_camera()
			world_view.orbit(event.relative.x*0.007,event.relative.y*0.004); return
		if panning:
			_cancel_committed_camera()
			world_view.pan(event.relative.x,event.relative.y); return
		if get_viewport().get_visible_rect().has_point(event.position):
			pending_hover = event.position
		# Source picking is click-only. Raw pointer motion never scans all triangles.
		hover_dirty = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: dragging = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = event.pressed
		if not event.pressed: return
		if event.button_index == MOUSE_BUTTON_LEFT:
			var candidates := pick_focus(event.position)
			if not candidates.is_empty(): focus_candidates.emit(candidates,event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: world_view.zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: world_view.zoom(1)
func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		dragging = false; panning = false

func _process(delta: float) -> void:
	if is_instance_valid(entity_selection) and not entity_selection.ready_catalog:
		_configure_entity_selection()
	# Avoid source-triangle picking on every raw pointer event.
	hover_elapsed += delta
	if hover_dirty and hover_elapsed > 0.18 and is_instance_valid(camera):
		hover_elapsed = 0; hover_dirty = false
		var hit: Dictionary = world_view.inspect(pending_hover)
		if hit.get("ok"):
			var key: String = String(hit.canonical_hex).trim_prefix("hex:")
			if tiles.has(key):
				var cell: Dictionary = tiles[key]; var h := Vector2i(cell.q,cell.r)
				if h != hover_hex: hover_hex = h; hex_hovered.emit(h,String(cell.terrain),0)
	for id in contact_shadows:
		if presentation.actors.has(id):
			var track: Dictionary = presentation.actors[id]
			var display_ground:Vector3=presentation.ground_position(id)
			contact_shadows[id].position = display_ground+Vector3(0,.013,0)
			contact_shadows[id].transparency = clampf((track.node.position.y-display_ground.y)*0.5,0,0.7)
	_update_names()
	if is_instance_valid(lighthouse) and lighthouse.title!=null: lighthouse.title.visible=not world_view.overview
func _update_names() -> void:
	if not is_instance_valid(camera): return
	var scale_per_world := get_viewport().get_visible_rect().size.y / maxf(0.01,camera.size)
	var occupied: Array[Rect2] = []
	for id in token_nodes:
		var token: Node3D = token_nodes[id]; var plate: Label3D = token.get_node("Nameplate")
		var base_position := Vector3(0,Tokens.height_for(id,world_state.actors[id])+0.3,0)
		plate.position = base_position
		var px: float = 32*0.007*0.62*scale_per_world
		plate.scale = Vector3.ONE * maxf(1.0,14.0/maxf(0.01,px))
		if world_view.overview:
			var original: Vector3 = token.global_transform * base_position
			var screen := camera.unproject_position(original)
			var measured: Vector2 = plate.font.get_string_size(plate.text,HORIZONTAL_ALIGNMENT_LEFT,-1,32)
			var extent := measured * 0.007 * 0.62 * plate.scale.x * scale_per_world
			var size_: Vector2 = get_viewport().get_visible_rect().size
			var rectangle := Rect2()
			for offset in [Vector2(0,18),Vector2(0,-18),Vector2(0,-40),Vector2(0,-62),Vector2(0,40),Vector2(0,62),Vector2(65,-18),Vector2(-65,-18)]:
				var candidate: Vector2 = screen+offset
				candidate.x = clampf(candidate.x,extent.x*0.5+8,size_.x-extent.x*0.5-8)
				candidate.y = clampf(candidate.y,extent.y*0.5+8,size_.y-extent.y*0.5-8)
				rectangle = Rect2(candidate-extent*0.5,extent).grow(4)
				if not occupied.any(func(r): return r.intersects(rectangle)): break
			occupied.append(rectangle)
			var delta: Vector2 = rectangle.get_center()-screen
			plate.global_position = original+camera.global_basis.x*(delta.x/scale_per_world)-camera.global_basis.y*(delta.y/scale_per_world)
			plate.set_meta("overview_label_rect",rectangle)

func set_presentation_safe_rect(rect:Rect2)->void:
	if is_instance_valid(committed_camera):committed_camera.set_safe_rect(rect)
func _cancel_committed_camera(manual:=true)->void:
	if is_instance_valid(committed_camera):committed_camera.cancel(manual)
func _committed_player_route_points(receipt:Dictionary,before_state:Dictionary)->Array[Vector3]:
	var points:Array[Vector3]=[]
	if receipt.get("actor_id","")!="actor_player" or not before_state.get("actors",{}).has("actor_player"):return points
	var previous:=_source_position(before_state.actors.actor_player.hex)
	# Direct frozen patches only: never patrol hooks, read-only previews or text.
	for patch in receipt.get("patches",[]):
		if patch.get("type","")!="actor_move" or patch.get("actor_id","")!="actor_player" or not patch.get("hex") is Array:continue
		var next:=_source_position(patch.hex)
		for fraction in [0.0,0.5,1.0]:
			var source:Vector3=previous.lerp(next,fraction)
			points.append(world_view.content_root.to_global(presentation.display_support_at(source)+Vector3(0,0.75,0)))
		previous=next
	return points
func present_committed_receipt(receipt: Dictionary, before_state: Dictionary, _frozen_action: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(committed_feedback): return {"ok":false,"presented":false}
	if committed_feedback._fresh(receipt,before_state,world_state) and is_instance_valid(committed_camera):
		if dragging or panning:committed_camera.cancel(true)
		committed_camera.consider(CommittedEffects.events_for(receipt,before_state,world_state),token_nodes,presentation,_committed_player_route_points(receipt,before_state))
	return committed_feedback.consume(receipt,before_state,world_state,token_nodes)

func showcase_effect(_kind: String) -> void:
	# Default gameplay never fabricates attacks from debug/showcase buttons.
	# Authored combat must resolve through the ordinary committed receipt path.
	pass

func _install_river() -> void:
	if FileAccess.get_sha256(RIVER_PATH) != RIVER_SHA:
		river_status = "试河cache未匹配，未显示"; return
	var overlay := River.new(); world_view.content_root.add_child(overlay)
	if not overlay.load_cache(RIVER_PATH,{}): river_status = overlay.last_error; overlay.queue_free(); return
	var result: Dictionary = world_view.install_river_overlay(overlay)
	if not result.get("ok",false): river_status = str(result); overlay.queue_free(); return
	river_overlay = overlay; river_status = "真实局部试河 · 只读观景"
func view_river() -> bool:
	_cancel_committed_camera()
	if not is_instance_valid(river_overlay): return false
	var contract: Dictionary = river_overlay.get_integration_contract()
	var box: Array = contract.footprint_bounds_xz
	world_view.overview = false; world_view.scope_name = "river_readonly"
	world_view.target = Vector3((box[0]+box[2])*0.5,0.52,(box[1]+box[3])*0.5)
	world_view.distance = 8; world_view.pitch = 0.9; world_view.yaw = 0.1; camera.size = 4.0
	world_view._update_camera(); return true

func _make_contact_shadow(id: String, target: Vector3) -> void:
	# Visual-only contact darkening sized to the scaled token base (0.38 x 0.62),
	# not the unscaled legacy disc. Alpha is kept low: the TABS contact shader
	# multiplies it by 2.15.
	var radius := 0.38*0.62*1.1
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(32):
		var a := float(i)*TAU/32.0; var b := float(i+1)*TAU/32.0
		for pair in [[Vector3.ZERO,0.14],[Vector3(cos(a),0,sin(a))*radius,0.0],[Vector3(cos(b),0,sin(b))*radius,0.0]]:
			surface.set_color(Color(0.10,0.09,0.07,pair[1])); surface.add_vertex(pair[0])
	var shadow := MeshInstance3D.new(); shadow.name = "ContactShadow_"+id; shadow.mesh = surface.commit()
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow.material_override = mat; shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world_view.content_root.add_child(shadow); contact_shadows[id] = shadow; shadow.position = target+Vector3(0,0.013,0)
