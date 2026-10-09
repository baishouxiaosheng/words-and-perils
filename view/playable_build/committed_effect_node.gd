extends Node3D
## Original, reusable low-poly effect. One MultiMesh draw plus an optional label.
## No particles, lights, bloom, screen shaders, collisions, or gameplay writes.
const PARTS := 24
const FACE = preload("res://assets/NotoSansCJK-Regular.ttc")
var drawing: MultiMeshInstance3D
var label: Label3D
var active := false
var age := 0.0
var life := 0.0
var event: Dictionary = {}
var source := Vector3.ZERO
var destination := Vector3.ZERO
var target: Node3D
var target_offset := Vector3.ZERO
var part_count := 0
var label_screen_clamped := false
var label_screen_rect := Rect2()
static var _box: BoxMesh
static var _material: StandardMaterial3D

func _init() -> void:
	if _box == null:
		_box = BoxMesh.new(); _box.size = Vector3.ONE
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.roughness = 1.0
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	drawing = MultiMeshInstance3D.new()
	drawing.multimesh = MultiMesh.new()
	drawing.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	drawing.multimesh.use_colors = true
	drawing.multimesh.mesh = _box
	drawing.multimesh.instance_count = PARTS
	drawing.multimesh.visible_instance_count = 0
	drawing.material_override = _material
	drawing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drawing)
	label = Label3D.new(); label.font = FACE; label.font_size = 36
	label.pixel_size = 0.008; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5; label.outline_modulate = Color("283332")
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = false
	add_child(label); hide(); set_process(false)

func start(data: Dictionary, from: Vector3, to: Vector3, follow: Node3D = null) -> void:
	event = data.duplicate(true); source = from; destination = to
	target = follow
	target_offset = to - follow.position if is_instance_valid(follow) else Vector3.ZERO
	age = 0.0; active = true
	life = {"melee":0.42,"ranged":0.29,"magic":0.70,"damage":0.98,"heal":0.98,"miss":0.85,"poison":1.08,"flight":1.08,"status_end":0.9}.get(str(event.kind),0.7)
	label.text = str(event.get("text", "")); label.visible = not label.text.is_empty()
	label.scale=Vector3.ONE;label_screen_clamped=false;label_screen_rect=Rect2()
	label.modulate = _color(); show(); sample(0.0)

func stop() -> void:
	active = false; target = null; event = {}; hide()
	drawing.multimesh.visible_instance_count = 0; label.text = ""; label.hide()
	label_screen_clamped=false;label_screen_rect=Rect2()

func tick(delta: float) -> bool:
	if not active: return false
	age += delta
	if age >= life: stop(); return false
	sample(age / life); return true

func _color() -> Color:
	match str(event.get("kind", "")):
		"magic", "flight": return Color("77dcdf")
		"poison": return Color("9cd769")
		"heal": return Color("79d99a")
		"damage": return Color("ffd280") if event.get("cause", "") != "poison" else Color("9cd769")
		"miss", "status_end": return Color("dae7e6")
	return Color("ffe4aa")

func sample(t: float) -> void:
	if not active: return
	if is_instance_valid(target): destination = target.position + target_offset
	part_count = 0
	var color := _color(); color.a = 1.0 - smoothstep(0.55,1.0,t)
	var kind := str(event.kind)
	var direction := destination - source; direction.y = 0
	if direction.length_squared() < 0.001: direction = Vector3.FORWARD
	direction = direction.normalized()
	var side := direction.cross(Vector3.UP).normalized()
	var whiff := bool(event.get("miss", false))
	var end := destination + (side * 0.65 if whiff else Vector3.ZERO)
	match kind:
		"melee":
			# Sweeping blade ribbon. A miss passes visibly beside the target.
			var center := end - direction * 0.16
			for i in range(10):
				var a := -1.45 + float(i) * 0.22 + t * 1.45
				var b := a + 0.21
				var p := center + side * sin(a) * 0.63 + Vector3.UP * cos(a) * 0.55
				var q := center + side * sin(b) * 0.63 + Vector3.UP * cos(b) * 0.55
				var tint := color; tint.a *= float(i+1)/10.0
				_beam(p,q,0.036*(1.0-t*0.55),tint)
		"ranged":
			# Muzzle star + fast travelling tracer, not a persistent laser.
			var a := source.lerp(end,clampf(t*2.0-0.23,0.0,1.0))
			var b := source.lerp(end,clampf(t*2.0+0.2,0.0,1.0))
			if t < 0.64: _beam(a,b,0.027,color)
			if t < 0.42:
				for i in range(5):
					var angle := TAU*float(i)/5.0
					var spoke := side*cos(angle)+Vector3.UP*sin(angle)
					_beam(source,source+spoke*0.21*(1.0-t),0.045,color)
		"magic":
			# A rotating source sigil and a compact arcing comet.
			_ring(source-Vector3.UP*0.45,0.39,0.025,color,10,t*0.9)
			var travel := clampf((t-0.10)/0.70,0.0,1.0)
			var p := source.lerp(end,travel)+Vector3.UP*sin(travel*PI)*0.62
			_cube(p,Vector3.ONE*0.16,Basis.from_euler(Vector3(t*3,t*4,t*2)),color)
			for i in range(5):
				var u := maxf(0.0,travel-float(i+1)*0.045)
				var a := source.lerp(end,u)+Vector3.UP*sin(u*PI)*0.62
				var fade := color; fade.a *= 0.70-float(i)*0.1
				_cube(a,Vector3.ONE*(0.10-float(i)*0.011),Basis.IDENTITY,fade)
		"damage":
			# Brief pale hit flash then low-poly outward sparks; no blood.
			if t < 0.18: _cube(destination,Vector3.ONE*(0.34*(1.0-t/0.18)),Basis.IDENTITY,Color(1.0,0.94,0.75,1.0))
			for i in range(8):
				var angle := TAU*float(i)/8.0
				var velocity := Vector3(cos(angle),0.9+float(i%3)*0.3,sin(angle))
				var p := destination+velocity*t*0.72-Vector3.UP*t*t*0.8
				_cube(p,Vector3(0.035,0.09,0.035)*(1.0-t*0.4),Basis.from_euler(Vector3(t*4,angle,t*3)),color)
		"poison":
			_ring(destination-Vector3.UP*0.5,0.35+t*0.16,0.025,color,12,t*0.3)
			for i in range(4):
				var a := TAU*float(i)/4.0+t
				_cube(destination+Vector3(cos(a)*0.20,t*0.42,sin(a)*0.20),Vector3.ONE*0.065,Basis.IDENTITY,color)
		"flight":
			for i in range(3):
				_ring(destination-Vector3.UP*(0.5-float(i)*0.16-t*0.24),0.30-float(i)*0.04,0.022,color,8,t*0.3)
		"heal": _ring(destination-Vector3.UP*0.45,0.30+t*0.15,0.024,color,12)
		"miss", "status_end": pass
	drawing.multimesh.visible_instance_count = part_count
	label.position = destination+Vector3(0,0.72+t*0.35,0)
	label.modulate = color

func keep_label_screen_safe(camera:Camera3D,rect:Rect2,obstacles:Array[Rect2]=[])->void:
	if not active:return
	label_screen_rect=Rect2()
	label.visible=not str(event.get("text","")).is_empty()
	if not label.visible:return
	if rect.size.x<32 or rect.size.y<32:label.hide();return
	# Floating combat text is information, not a physical surface. It remains
	# readable above terrain and HUD; a displaced label names its actual target.
	label.no_depth_test=true
	var base_text:=str(event.get("text",""))
	if label.text!=base_text:label.text=base_text
	var viewport:Rect2=camera.get_viewport().get_visible_rect()
	var pixels_per_world:=viewport.size.y/maxf(0.01,camera.size)
	var base_pixels:=float(label.font_size)*label.pixel_size*pixels_per_world
	label.scale=Vector3.ONE*maxf(1.0,18.0/maxf(1.0,base_pixels))
	var measured:=label.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)*label.pixel_size*pixels_per_world*label.scale.x
	if measured.x>rect.size.x-8.0:
		var fit:=maxf(0.05,(rect.size.x-8.0)/measured.x);label.scale*=fit;measured*=fit
	var half_height:=minf(measured.y*0.5+4.0,rect.size.y*0.5-1.0)
	var half_width:=minf(measured.x*0.5+3.0,rect.size.x*0.5-1.0)
	var point:=camera.unproject_position(label.global_position)
	var desired:=Vector2(clampf(point.x,rect.position.x+half_width,rect.end.x-half_width),clampf(point.y,rect.position.y+half_height,rect.end.y-half_height))
	desired=_clear_vertical_position(desired,Vector2(half_width,half_height),rect,obstacles)
	label_screen_clamped=not desired.is_equal_approx(point) or camera.is_position_behind(label.global_position)
	if label_screen_clamped:
		var actor_name:=str(event.get("target_name","")).left(10)
		var named:=actor_name+" "+base_text if not actor_name.is_empty() else base_text
		if label.text!=named:label.text=named
		measured=label.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)*label.pixel_size*pixels_per_world*label.scale.x
		if measured.x>rect.size.x-8.0:
			var fit:=maxf(0.05,(rect.size.x-8.0)/measured.x);label.scale*=fit;measured*=fit
		half_height=minf(measured.y*0.5+4.0,rect.size.y*0.5-1.0)
		half_width=minf(measured.x*0.5+3.0,rect.size.x*0.5-1.0)
		desired=Vector2(clampf(point.x,rect.position.x+half_width,rect.end.x-half_width),clampf(point.y,rect.position.y+half_height,rect.end.y-half_height))
		desired=_clear_vertical_position(desired,Vector2(half_width,half_height),rect,obstacles)
		var depth:=maxf(camera.near+0.1,-camera.to_local(label.global_position).z)
		label.global_position=camera.project_position(desired,depth)
	label_screen_rect=Rect2(desired-Vector2(half_width,half_height),Vector2(half_width,half_height)*2.0)

func _clear_vertical_position(point:Vector2,half:Vector2,area:Rect2,obstacles:Array[Rect2])->Vector2:
	var initial:=Rect2(point-half,half*2.0)
	var blocked:=false
	for obstacle in obstacles:
		if initial.intersects(obstacle):blocked=true;break
	if not blocked:return point
	var candidates:Array[float]=[]
	for obstacle in obstacles:
		if obstacle.end.x<=initial.position.x or obstacle.position.x>=initial.end.x:continue
		candidates.append(obstacle.position.y-half.y-6.0)
		candidates.append(obstacle.end.y+half.y+6.0)
	var best:=point;var distance:=INF
	for y in candidates:
		if y<area.position.y+half.y or y>area.end.y-half.y:continue
		var candidate:=Vector2(point.x,y);var box:=Rect2(candidate-half,half*2.0)
		var clear:=true
		for obstacle in obstacles:
			if box.intersects(obstacle):clear=false;break
		if clear and absf(y-point.y)<distance:best=candidate;distance=absf(y-point.y)
	return best

func _cube(p: Vector3, size_: Vector3, basis: Basis, color: Color) -> void:
	if part_count >= PARTS: return
	drawing.multimesh.set_instance_transform(part_count,Transform3D(basis.scaled(size_),p))
	drawing.multimesh.set_instance_color(part_count,color)
	part_count += 1

func _beam(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	if a.distance_squared_to(b) < 0.000001: return
	var basis := Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	_cube((a+b)*0.5,Vector3(width,a.distance_to(b),width),basis,color)

func _ring(center: Vector3,radius: float,width: float,color: Color,segments: int,spin := 0.0) -> void:
	for i in range(segments):
		var a := TAU*float(i)/float(segments)+spin
		var b := TAU*float(i+1)/float(segments)+spin
		_beam(center+Vector3(cos(a),0,sin(a))*radius,center+Vector3(cos(b),0,sin(b))*radius,width,color)
