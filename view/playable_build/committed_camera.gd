extends Node
## One bounded presentation-only framing pass for fresh committed combat.
## Existing camera angles and deliberate overview are preserved. Any manual
## camera input cancels immediately and releases the pending visual clock.
const DURATION := 0.60
const MANUAL_HOLD_MS := 2500
const CUE_FONT = preload("res://assets/NotoSansCJK-Regular.ttc")
var view: Node3D
var camera: Camera3D
var safe_rect := Rect2()
var safe_rect_supplied := false
var cue_labels:Array[Label]=[]
var cue_ages:Array[float]=[]
var active := false
var progress := 0.0
var from_target := Vector3.ZERO
var to_target := Vector3.ZERO
var from_size := 6.0
var to_size := 6.0
var held_until := 0
var framed_actions := 0
var canceled_actions := 0
var last_reason := "idle"
var pair_key := ""
func configure(world_view: Node3D, camera_: Camera3D) -> void:
	view=world_view;camera=camera_;set_process(false)
	var layer:=CanvasLayer.new();layer.name="CommittedCombatCues";layer.layer=2;add_child(layer)
	for i in range(2):
		var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text=true
		label.add_theme_font_override("font",CUE_FONT);label.add_theme_font_size_override("font_size",18)
		label.add_theme_color_override("font_color",Color("fff1c4"));label.add_theme_color_override("font_outline_color",Color("273537"));label.add_theme_constant_override("outline_size",5)
		layer.add_child(label);label.hide();cue_labels.append(label);cue_ages.append(-1.0)
func set_safe_rect(rect: Rect2) -> void:
	safe_rect=rect;safe_rect_supplied=true
func raw_rect() -> Rect2:
	if not is_instance_valid(camera):return Rect2()
	var viewport:Rect2=camera.get_viewport().get_visible_rect()
	var rect:=safe_rect.intersection(viewport)
	if not safe_rect_supplied:rect=Rect2(viewport.size*Vector2(0.04,0.16),viewport.size*Vector2(0.72,0.46))
	if rect.size.x<48 or rect.size.y<48:return Rect2()
	return rect.grow(-12.0)
func usable_rect() -> Rect2:
	var rect:=raw_rect()
	if not rect.has_area():return rect
	var band:=minf(60.0,rect.size.y*0.25)
	return Rect2(rect.position+Vector2(0,band),rect.size-Vector2(0,band))
func effects_ready() -> bool:return not active
func cancel(manual := true) -> void:
	if active:canceled_actions+=1
	active=false;last_reason="manual_camera" if manual else "reset"
	if manual:held_until=Time.get_ticks_msec()+MANUAL_HOLD_MS
	else:
		held_until=0
		for i in range(cue_labels.size()):cue_labels[i].hide();cue_ages[i]=-1.0
	set_process(_has_cues())
func consider(events: Array, tokens: Dictionary, motion: Node3D, route_points:Array[Vector3]=[]) -> bool:
	if not is_instance_valid(view) or not is_instance_valid(camera):return false
	if view.overview:last_reason="preserved_overview";return false
	if Time.get_ticks_msec()<held_until:last_reason="manual_camera_hold";return false
	if camera.projection!=Camera3D.PROJECTION_ORTHOGONAL:last_reason="preserved_projection";return false
	var ids:Array=[]
	for event in events:
		if not event.get("kind","") in ["melee","ranged","magic"]:continue
		for id in [event.get("source_id",""),event.get("target_id","")]:
			if tokens.has(id) and is_instance_valid(tokens[id]) and not id in ids:ids.append(id)
	if not route_points.is_empty() and tokens.has("actor_player") and not "actor_player" in ids:ids.append("actor_player")
	if ids.size()<2 and route_points.is_empty():return false
	ids.sort();var key:="|".join(ids)
	if active and key==pair_key and route_points.is_empty():return true
	var points:Array[Vector3]=[]
	for id in ids:
		_add_actor_bounds(points,tokens[id].global_position)
		if is_instance_valid(motion) and motion.actors.has(id) and motion.actors[id].moving:
			var track:Dictionary=motion.actors[id]
			_add_actor_bounds(points,tokens[id].get_parent().to_global(motion.actor_support(track,track.support)))
	for point in route_points:_add_actor_bounds(points,point)
	if points.is_empty():return false
	var rect:=usable_rect()
	if rect.size.x<48 or rect.size.y<48:last_reason="no_presentation_area";return false
	var needed:=false
	for point in points:
		if camera.is_position_behind(point) or not rect.has_point(camera.unproject_position(point)):needed=true;break
	if not needed:last_reason="already_visible";return false
	var right:=camera.global_basis.x;var up:=camera.global_basis.y
	var minimum:=Vector2(INF,INF);var maximum:=Vector2(-INF,-INF);var center:=Vector3.ZERO
	for point in points:
		var xy:=Vector2(right.dot(point),up.dot(point))
		minimum=minimum.min(xy);maximum=maximum.max(xy);center+=point
	center/=float(points.size())
	var middle:=(minimum+maximum)*0.5
	center+=right*(middle.x-right.dot(center))+up*(middle.y-up.dot(center))
	var viewport:Rect2=camera.get_viewport().get_visible_rect()
	var span:=maximum-minimum
	var required:=maxf(span.x*viewport.size.y/rect.size.x,span.y*viewport.size.y/rect.size.y)*1.08
	var size_goal:=maxf(camera.size,clampf(required,4.0,28.0))
	var pixel_world:=size_goal/viewport.size.y
	var offset:=rect.get_center()-viewport.get_center()
	var target_goal:=center-right*offset.x*pixel_world+up*offset.y*pixel_world
	# A deliberately distant free camera is left alone; named feedback remains
	# screen-safe. Ordinary player-view encounters fit comfortably in this bound.
	if view.target.distance_to(target_goal)>maxf(18.0,camera.size*3.0):last_reason="preserved_distant_view";return false
	from_target=view.target;to_target=target_goal;from_size=camera.size;to_size=size_goal
	progress=0.0;active=true;pair_key=key;framed_actions+=1;last_reason="fresh_committed_combat"
	set_process(true);return true
func _add_actor_bounds(points:Array[Vector3],position:Vector3)->void:
	for height in [0.0,2.05]:
		for side in [-0.48,0.48]:points.append(position+Vector3.UP*height+camera.global_basis.x*side)
func _process(delta:float)->void:
	_tick_cues(delta)
	if not active:
		if not _has_cues():set_process(false)
		return
	if not is_instance_valid(view) or not is_instance_valid(camera):cancel(false);return
	progress=minf(1.0,progress+delta/DURATION)
	var eased:=progress*progress*(3.0-2.0*progress)
	view.target=from_target.lerp(to_target,eased);camera.size=lerpf(from_size,to_size,eased)
	view._update_camera()
	if progress>=1.0:active=false;set_process(_has_cues());last_reason="framing_complete"
func _has_cues()->bool:
	for age in cue_ages:
		if age>=0.0:return true
	return false
func show_cue(event:Dictionary)->void:
	if not event.get("kind","") in ["melee","ranged","magic"]:return
	var rect:=raw_rect()
	if rect.size.x<180 or rect.size.y<80:return
	var index:=0
	var rows:=2 if rect.size.y>=160 else 1
	for i in range(rows):
		if cue_ages[i]<0.0:index=i;break
		if cue_ages[i]>cue_ages[index]:index=i
	var source:=str(event.get("source_name","")).left(8);var target:=str(event.get("target_name","")).left(8)
	var kind:String={"melee":"攻击","ranged":"射击","magic":"施法"}.get(event.kind,"攻击")
	var outcome:String={"miss":"未命中","graze":"擦伤","hit":"命中"}.get(str(event.get("outcome","")),"")
	var text:="%s → %s · %s · %s"%[source,target,kind,outcome]
	var width:=CUE_FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
	var size:=clampi(floori(18.0*minf(1.0,(rect.size.x-8.0)/maxf(1.0,width))),12,18)
	if CUE_FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>rect.size.x-8.0:
		text="%s→%s %s·%s"%[source.left(2)+("…" if source.length()>2 else ""),target.left(3)+("…" if target.length()>3 else ""),kind,outcome]
		size=12
		if CUE_FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>rect.size.x-8.0:
			text="%s…→%s… %s·%s"%[source.left(1),target.left(1),kind,outcome]
	cue_labels[index].add_theme_font_size_override("font_size",size);cue_labels[index].text=text
	cue_ages[index]=0.0;_tick_cues(0.0);set_process(true)
func _tick_cues(delta:float)->void:
	var rect:=raw_rect();var rows:=2 if rect.size.y>=160 else 1
	for i in range(cue_labels.size()):
		if cue_ages[i]<0.0:continue
		cue_ages[i]+=delta
		if cue_ages[i]>=1.10:cue_labels[i].hide();cue_ages[i]=-1.0;continue
		cue_labels[i].visible=rect.size.x>=180 and rect.size.y>=80 and i<rows
		cue_labels[i].position=rect.position+Vector2(0,i*28)
		cue_labels[i].size=Vector2(rect.size.x,28)
		cue_labels[i].modulate.a=1.0-smoothstep(0.8,1.1,cue_ages[i])
func report()->Dictionary:
	var texts:Array=[]
	for label in cue_labels:
		if label.visible:texts.append(label.text)
	return {"active":active,"framed_actions":framed_actions,"canceled_actions":canceled_actions,"last_reason":last_reason,"safe_rect":[usable_rect().position.x,usable_rect().position.y,usable_rect().size.x,usable_rect().size.y],"visible_combat_cues":texts,"gameplay_writes":false}
