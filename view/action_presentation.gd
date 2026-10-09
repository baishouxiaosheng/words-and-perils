extends Node3D
## Visual-only presentation. Canonical state is never read or mutated here.
## Motion targets arrive only after a verified state commit. No narration parsing.
signal movement_finished(actor_id: String)
const SELECT_LIFT := 0.20
var actors: Dictionary = {}
var effects: Array[Dictionary] = []
var selected_id := ""
var effects_enabled := true
var surface_height_sampler:Callable

func display_support_at(source:Vector3)->Vector3:
	if surface_height_sampler.is_valid():source.y=surface_height_sampler.call(Vector2(source.x,source.z),source.y)
	return source

func set_actor_display_offset(actor_id:String,offset:Vector3)->void:
	if not actors.has(actor_id):return
	var track:Dictionary=actors[actor_id];track.display_offset=offset
	if not track.moving:track.node.position=actor_support(track,track.support)+Vector3(0,SELECT_LIFT if track.selected else 0,0)

func actor_support(track:Dictionary,source:Vector3)->Vector3:
	return display_support_at(source+Vector3(track.get("display_offset",Vector3.ZERO)))

func ground_position(actor_id:String)->Vector3:
	if not actors.has(actor_id):return Vector3.ZERO
	var track:Dictionary=actors[actor_id]
	var p:Vector3=track.node.position
	p.y=float(track.get("ground_source_y",track.support.y)) if track.moving else track.support.y
	return display_support_at(p)


func register_actor(actor_id: String, token: Node3D, support: Vector3) -> void:
	actors[actor_id] = {"node":token,"support":support,"rotation":token.rotation,"moving":false,"selected":false,"progress":0.0,"duration":0.0,"from":support,"to":support,"generation":0,"display_offset":Vector3.ZERO,"foot_radius":float(token.get_meta("token_foot_radius",0.38))*maxf(absf(token.scale.x),absf(token.scale.z))}
	token.position = display_support_at(support)

func forget_actor(actor_id: String) -> void:
	actors.erase(actor_id)
	if selected_id == actor_id: selected_id = ""

func select_actor(actor_id: String) -> void:
	selected_id = actor_id if actors.has(actor_id) else ""
	for id in actors:
		actors[id].selected = id == selected_id

func reset_actor(actor_id: String, support: Vector3) -> void:
	if not actors.has(actor_id): return
	var track: Dictionary = actors[actor_id]
	track.generation += 1
	track.moving = false
	track.route = []
	track.route_index = 0
	track.support = support
	track.from = support
	track.to = support
	track.selected = false
	track.node.position = actor_support(track,support)
	track.node.rotation = track.rotation
	if selected_id == actor_id: selected_id = ""

func move_actor(actor_id: String, final_position: Vector3, clearance: float = 1.25) -> void:
	move_actor_path(actor_id,[final_position],clearance)

func move_actor_path(actor_id:String, waypoints:Array, clearance:float=1.25)->void:
	if not actors.has(actor_id) or waypoints.is_empty():return
	for point in waypoints:
		if not point is Vector3:return
	var track:Dictionary=actors[actor_id]
	# A newer committed action starts at the previous authoritative endpoint.
	# Never draw a shortcut from a half-played old route across obstacles.
	if track.moving:
		track.node.position=actor_support(track,track.support)
		track.node.rotation=track.rotation
	track.generation+=1
	track.route=waypoints.duplicate()
	track.route_index=0
	track.arc=maxf(clearance,0.72)
	track.selected=false
	# support is always the authoritative final destination, even mid-animation.
	var origin:Vector3=track.support
	track.support=waypoints.back()
	_begin_route_segment(track,origin)
	if selected_id==actor_id:selected_id=""

func _begin_route_segment(track:Dictionary, origin:Vector3)->void:
	track.from_visual=track.node.position
	track.from=origin
	track.to=track.route[track.route_index]
	track.progress=0.0
	track.duration=clampf(origin.distance_to(track.to)*0.12+0.75,0.95,1.65)
	track.moving=true

func cancel_all() -> void:
	for id in actors:
		reset_actor(id,actors[id].support)
	for effect in effects:
		if is_instance_valid(effect.node): effect.node.queue_free()
	effects.clear()
	selected_id = ""

func _process(delta: float) -> void:
	for id in actors:
		var track: Dictionary = actors[id]
		if not is_instance_valid(track.node): continue
		if track.moving:
			track.progress += delta/track.duration
			var t := minf(1.0,track.progress)
			# A hand-like lift/translation/release: rise, broad arc, slight settle.
			if t < 0.83:
				var travel := clampf(t/0.83,0.0,1.0)
				var eased := travel*travel*(3.0-2.0*travel)
				var source_p:Vector3=track.from.lerp(track.to,eased)
				track.ground_source_y=source_p.y
				var p: Vector3 = track.from_visual.lerp(actor_support(track,track.to),eased)
				var floor_p:=display_support_at(Vector3(p.x,source_p.y,p.z))
				p.y=maxf(p.y,floor_p.y)+sin(travel*PI)*track.arc
				track.node.position = p
				track.node.rotation = track.rotation+Vector3(0.035*sin(travel*PI),0,0.025*sin(travel*TAU))
			else:
				var settle := (t-0.83)/0.17
				track.ground_source_y=track.to.y
				track.node.position = actor_support(track,track.to)+Vector3(0,sin(settle*PI)*0.022*(1.0-settle),0)
				track.node.rotation = track.rotation+Vector3(sin(settle*TAU*1.5)*0.065*(1.0-settle),0,cos(settle*TAU)*0.035*(1.0-settle))
				# Keep the scaled radial base above its visible support plane while
				# rocking. Clearance decays to zero with the upright landing.
				var basis := Basis.from_euler(track.node.rotation)
				var tilt := Vector2(basis.x.y,basis.z.y).length()
				track.node.position.y += minf(float(track.foot_radius)*tilt,0.06)
			if t >= 1.0:
				track.moving = false
				track.node.position = actor_support(track,track.to)
				track.node.rotation = track.rotation
				track.route_index+=1
				if track.route_index<track.route.size():
					_begin_route_segment(track,track.to)
				else:
					track.route=[]
					movement_finished.emit(String(id))
		else:
			var target: Vector3 = actor_support(track,track.support)+Vector3(0,SELECT_LIFT if track.selected else 0.0,0)
			track.node.position = track.node.position.lerp(target,1.0-exp(-delta*15.0))
			track.node.rotation = track.rotation
	var expired: Array[int] = []
	for i in range(effects.size()):
		var effect: Dictionary = effects[i]
		effect.age += delta
		var t := minf(1.0,effect.age/effect.life)
		if is_instance_valid(effect.node):
			_update_effect(effect,t)
		if t >= 1.0:
			if is_instance_valid(effect.node): effect.node.queue_free()
			expired.append(i)
	for i in range(expired.size()-1,-1,-1): effects.remove_at(expired[i])

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _mesh(parent: Node3D, mesh: Mesh, color: Color, position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(color)
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _ring(parent: Node3D,radius: float,width: float,color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(48):
		var a := float(i)*TAU/48.0
		var b := float(i+1)*TAU/48.0
		for v in [Vector3(cos(a),0,sin(a))*radius,Vector3(cos(a),0,sin(a))*(radius-width),Vector3(cos(b),0,sin(b))*radius,Vector3(cos(b),0,sin(b))*radius,Vector3(cos(a),0,sin(a))*(radius-width),Vector3(cos(b),0,sin(b))*(radius-width)]:
			surface.add_vertex(v)
	return _mesh(parent,surface.commit(),color)

func _beam(parent: Node3D,a: Vector3,b: Vector3,radius: float,color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 8
	var node := _mesh(parent,mesh,color,(a+b)*0.5)
	if a.distance_to(b)>0.001: node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return node

func play_effect(kind: String, source: Vector3, destination: Vector3, showcase: bool=false) -> void:
	if not effects_enabled or not kind in ["magic","gunfire","melee","hit"]: return
	var root := Node3D.new()
	root.name = ("Showcase_" if showcase else "Resolved_")+kind
	root.set_meta("showcase_only",showcase)
	add_child(root)
	var life := 0.80 if kind=="magic" else (0.32 if kind=="gunfire" else 0.48)
	var effect := {"node":root,"kind":kind,"from":source,"to":destination,"age":0.0,"life":life,"parts":[]}
	if kind=="magic":
		root.position = source+Vector3(0,0.06,0)
		_ring(root,0.60,0.035,Color("8acbb9"))
		_ring(root,0.44,0.020,Color("d5e5b0")).rotation_degrees.x=62
		for i in range(6):
			var a := float(i)*TAU/6.0
			var orb := SphereMesh.new();orb.radius=0.045;orb.height=0.09
			_mesh(root,orb,Color("d9efc1"),Vector3(cos(a)*0.57,0.03,sin(a)*0.57))
		# A segmented curved ribbon travels across the table rather than a ball.
		for i in range(12):
			var a := source.lerp(destination,float(i)/12.0)+Vector3(0,sin(float(i)/12.0*PI)*0.70+0.45,0)
			var b := source.lerp(destination,float(i+1)/12.0)+Vector3(0,sin(float(i+1)/12.0*PI)*0.70+0.45,0)
			_beam(root,a-root.position,b-root.position,0.018,Color("9edccb"))
	elif kind=="gunfire":
		var a := source+Vector3(0,0.82,0)
		var b := destination+Vector3(0,0.70,0)
		_beam(root,a,b,0.020,Color("ffe0a1"))
		var flash := SphereMesh.new();flash.radius=0.13;flash.height=0.26
		var burst := _mesh(root,flash,Color("fff0be"),a)
		burst.scale=Vector3(1.5,0.5,1.0)
		for i in range(5):
			var angle := float(i)*TAU/5.0
			_beam(root,a,a+Vector3(cos(angle)*0.22,sin(angle)*0.22,0.02),0.024,Color("d49b5d"))
	elif kind=="melee":
		root.position=destination+Vector3(0,0.45,0)
		var side := (destination-source).normalized().cross(Vector3.UP)
		for i in range(8):
			var a := -0.85+float(i)*0.18
			var b := a+0.18
			var p := side*sin(a)*0.75+Vector3(0,cos(a)*0.6,0)
			var q := side*sin(b)*0.75+Vector3(0,cos(b)*0.6,0)
			_beam(root,p,q,0.030,Color("f1d6a6"))
	else:
		root.position=destination+Vector3(0,0.12,0)
		_ring(root,0.30,0.045,Color("c68666"))
		for i in range(9):
			var shard := BoxMesh.new();shard.size=Vector3(0.035,0.10,0.035)
			var a := float(i)*TAU/9.0
			var part := _mesh(root,shard,Color("d7b58a"),Vector3(cos(a)*0.20,0.10,sin(a)*0.20))
			effect.parts.append({"node":part,"velocity":Vector3(cos(a),1.5,sin(a))*0.65,"origin":part.position})
	effects.append(effect)

func _update_effect(effect: Dictionary,t: float) -> void:
	var root: Node3D = effect.node
	if effect.kind=="magic":
		for child in root.get_children():
			if child is MeshInstance3D and child.mesh is SphereMesh:
				child.position.y=0.03+sin(t*TAU*1.5+child.position.x)*0.06
	elif effect.kind=="hit":
		for part in effect.parts:
			part.node.position=part.origin+part.velocity*t+Vector3(0,-1.7*t*t,0)
			part.node.rotation=Vector3(t*3,t*2,t*4)
		root.scale=Vector3.ONE*(1.0+t*0.35)
	for child in root.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			child.material_override.albedo_color.a=1.0-pow(t,1.5)
