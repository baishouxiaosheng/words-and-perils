extends Node3D
## One original low-poly pack. Presentation observes authoritative custody only.
const Focus = preload("res://view/generated_inventory/item_focus.gd")
const Navigation = preload("res://view/generated_adventure/navigation.gd")
const Field = preload("res://view/terrain_field.gd")
var board: Node3D
var pack: Node3D
var mesh_parts: Array[MeshInstance3D] = []
var edge_glow: MeshInstance3D
var reference: Dictionary = {}
var selected := false
var carried := false
var ground_position := Vector3.ZERO
var ground_pose: Dictionary = {}
var pose_cache: Dictionary = {}
const CARRY_OFFSET := Vector3(0.30,0.40,0.06)
func bind(owner_board: Node3D) -> void:
	board = owner_board
	name = "GeneratedInventoryPack"
	pack = Node3D.new();pack.name = "TravelBundle";add_child(pack)
	var body := CylinderMesh.new();body.top_radius=0.12;body.bottom_radius=0.15;body.height=0.27;body.radial_segments=6;body.rings=1
	part("CanvasPack",body,Vector3(0,0.145,0),Color("b4935c"))
	var flap := BoxMesh.new();flap.size=Vector3(0.25,0.045,0.16)
	part("LeatherFlap",flap,Vector3(0,0.29,0),Color("765333"))
	var roll := CylinderMesh.new();roll.top_radius=0.065;roll.bottom_radius=0.065;roll.height=0.32;roll.radial_segments=8;roll.rings=1
	var bedroll := part("Bedroll",roll,Vector3(0,0.365,0),Color("bac1a2"));bedroll.rotation.z=PI/2
	for x in [-0.075,0.075]:
		var strap := BoxMesh.new();strap.size=Vector3(0.026,0.25,0.024)
		part("Strap",strap,Vector3(x,0.165,0.14),Color("59462f"))
	var ring := TorusMesh.new();ring.inner_radius=0.17;ring.outer_radius=0.20;ring.rings=16;ring.ring_segments=6
	edge_glow=MeshInstance3D.new();edge_glow.name="SelectionRing";edge_glow.mesh=ring;edge_glow.position.y=0.018
	var highlight := StandardMaterial3D.new();highlight.albedo_color=Color("f7d48b");highlight.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;edge_glow.material_override=highlight
	pack.add_child(edge_glow);edge_glow.hide();pack.hide()
func part(name_: String,mesh: Mesh,position_: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new();node.name=name_;node.mesh=mesh;node.position=position_
	var material := StandardMaterial3D.new();material.albedo_color=color;material.roughness=0.88
	node.material_override=material;pack.add_child(node);mesh_parts.append(node)
	return node
func update_state(state: Dictionary) -> void:
	reference = Focus.make_reference(Focus.ITEM,state)
	if reference.is_empty():
		pack.hide();select({});return
	carried = state.items[Focus.ITEM].has("owner_actor_id")
	ground_pose = placement_for(reference.hex) if not carried else {}
	ground_position = ground_pose.get("position",board._source_position(reference.hex))
	var normal_:Array=ground_pose.get("normal",[0.0,1.0,0.0])
	pack.basis=Basis(Quaternion(Vector3.UP,Vector3(normal_[0],normal_[1],normal_[2])))*float(ground_pose.get("scale",1.0))
	pack.visible=carried or bool(ground_pose.get("footprint_verified",false))
	sync_position()
	# A selected same object may refresh its read-only ring after custody changes.
	edge_glow.visible=selected
func sync_position() -> void:
	if not is_instance_valid(pack) or not pack.visible or not is_instance_valid(board):return
	if carried and board.token_nodes.has("actor_player") and is_instance_valid(board.token_nodes.actor_player):
		# Follow the real rendered token's committed route, not its final cell early.
		pack.global_position=board.token_nodes.actor_player.global_position+CARRY_OFFSET
	else:pack.position=ground_position
func _process(_delta: float) -> void: sync_position()
func select(value: Dictionary) -> void:
	selected = not reference.is_empty() and value.get("kind")=="item" and value.get("id")==Focus.ITEM and value.get("world_id")==reference.world_id and value.get("catalog_version")==Focus.VERSION
	if is_instance_valid(edge_glow):edge_glow.visible=selected
func pick(point: Vector2,limit: float) -> Dictionary:
	if reference.is_empty() or not is_instance_valid(pack) or not pack.visible:return {}
	sync_position()
	var origin: Vector3=board.camera.project_ray_origin(point)
	var direction: Vector3=board.camera.project_ray_normal(point)
	var best := INF
	var position_ := Vector3.ZERO
	for part_ in mesh_parts:
		var faces: PackedVector3Array=part_.mesh.get_faces()
		var transform_: Transform3D=part_.global_transform
		for i in range(0,faces.size(),3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(origin,direction,transform_*faces[i],transform_*faces[i+1],transform_*faces[i+2])
			if not hit is Vector3:continue
			var distance: float=(hit-origin).dot(direction)
			if distance>=0.0 and distance<=limit and distance<best:best=distance;position_=hit
	if not is_finite(best):return {}
	return {"reference":reference.duplicate(true),"label":"行礼包 · "+("随身" if carried else "地上"),"distance":best,"point":position_}
func diagnostic() -> Dictionary:
	return {"visible":is_instance_valid(pack) and pack.visible,"carried":carried,"reference":reference.duplicate(true),"selected":selected,"mesh_count":mesh_parts.size(),"ground_pose":ground_pose.duplicate(true),"position":[pack.position.x,pack.position.y,pack.position.z] if is_instance_valid(pack) else []}

func placement_for(hex: Array) -> Dictionary:
	# Renderer-only footprint fit against the SAME PL triangles used by dry
	# navigation. No source/cell/custody/navigation mutation or new landing rule.
	var key: String=str(board.admitted_source.identity.content_hash)+"/"+"%d,%d"%hex
	if pose_cache.has(key):return pose_cache[key].duplicate(true)
	var center: Vector3=Field.center(Vector2i(hex[0],hex[1]))
	var tile: Dictionary=board.tiles["%d,%d"%hex]
	var n:=12 if tile.get("raw",{}).get("river",false) else 6
	var faces: Array=[]
	for side in range(6):
		var a:=Field.corner(side);var b:=Field.corner(side+1)
		for u in range(n):
			for v in range(n-u):
				var p:=center+(a*u+b*v)/n
				faces.append(surface_face([p,p+b/n,p+a/n]))
				if u+v<n-1:faces.append(surface_face([p+a/n,p+b/n,p+(a+b)/n]))
	var offsets: Array[Vector3]=[Vector3(.30,0,.04),Vector3(-.30,0,.04),Vector3(0,0,.32),Vector3(0,0,-.32),Vector3(.58,0,0),Vector3(-.58,0,0),Vector3(0,0,.58),Vector3(0,0,-.58),Vector3.ZERO]
	for scale_ in [1.0,0.75,0.5,0.25,0.125,0.0625]:
		var best: Dictionary={}
		for offset in offsets:
			var candidate:=footprint_at(center+offset,float(scale_),faces)
			if candidate.is_empty() or candidate.support_residual_spread>0.08*float(scale_) or overlaps_static_prop(candidate):continue
			if best.is_empty() or candidate.support_residual_spread<best.support_residual_spread:best=candidate
		if not best.is_empty():
			pose_cache[key]=best;return best.duplicate(true)
	# A verified point remains observable even if an exceptionally tiny dry
	# sliver cannot fit the smallest miniature. Do not render a false ground bag.
	return {"position":board._source_position(hex),"scale":0.0,"footprint_verified":false,"reason":"no_dry_miniature_footprint"}
func surface_face(points: Array) -> Dictionary:
	var polygon:=PackedVector2Array();var land: Array=[];var water: Array=[]
	for point in points:
		polygon.append(Vector2(point.x,point.z));land.append(board.terrain_field.land_height(point));water.append(board.terrain_field.water_height(point))
	return {"points":points,"polygon":polygon,"land":land,"water":water}
func footprint_at(center: Vector3,scale_: float,faces: Array) -> Dictionary:
	var polygon:=PackedVector2Array()
	for i in range(8):polygon.append(Vector2(center.x,center.z)+Vector2(cos(TAU*i/8.0),sin(TAU*i/8.0))*(0.215*scale_))
	var total:=polygon_area(polygon);var covered:=0.0;var low:=INF;var high:=-INF;var clearance:=INF
	var normal_:=Vector3.UP
	for face in faces:
		if not Geometry2D.is_point_in_polygon(Vector2(center.x,center.z),face.polygon):continue
		var p0:Vector3=face.points[0];p0.y=face.land[0]
		var p1:Vector3=face.points[1];p1.y=face.land[1]
		var p2:Vector3=face.points[2];p2.y=face.land[2]
		normal_=(p1-p0).cross(p2-p0).normalized()
		if normal_.y<0.0:normal_=-normal_
		break
	if normal_.y<=0.01:return {}
	var gx:float=-normal_.x/normal_.y;var gz:float=-normal_.z/normal_.y
	var residual_low:=INF;var residual_high:=-INF
	for face in faces:
		for clip in Geometry2D.intersect_polygons(polygon,face.polygon):
			covered+=polygon_area(clip)
			for point in clip:
				var h:float=Navigation.triangle_value(point,face.points,face.land)
				var w:float=Navigation.triangle_value(point,face.points,face.water)
				low=minf(low,h);high=maxf(high,h);clearance=minf(clearance,h-w)
				var residual:float=h-gx*(point.x-center.x)-gz*(point.y-center.z)
				residual_low=minf(residual_low,residual);residual_high=maxf(residual_high,residual)
	if covered<total-0.000001 or not is_finite(high) or clearance<=Navigation.CLEARANCE:return {}
	return {"position":Vector3(center.x,residual_high+0.012,center.z),"normal":[normal_.x,normal_.y,normal_.z],"scale":scale_,"footprint_verified":true,"height_spread":high-low,"support_residual_spread":residual_high-residual_low,"minimum_dry_clearance":clearance,"covered_area":covered,"footprint_area":total}
static func polygon_area(points: PackedVector2Array) -> float:
	var area:=0.0
	for i in range(points.size()):area+=points[i].cross(points[(i+1)%points.size()])
	return absf(area)*0.5

func overlaps_static_prop(pose: Dictionary) -> bool:
	var n:Array=pose.normal
	var transform_:=Transform3D(Basis(Quaternion(Vector3.UP,Vector3(n[0],n[1],n[2])))*float(pose.scale),pose.position)
	var volume:AABB=transform_*AABB(Vector3(-.19,0,-.17),Vector3(.38,.42,.34))
	for subject in board.attention_catalog.subjects.values():
		if subject.reference.get("kind")=="actor" or not subject.bounds.intersects(volume):continue
		for part_ in subject.parts:
			var bounds:AABB=subject.transform*part_.bounds
			# Low flat road/surface details do not represent an enclosing prop.
			if bounds.size.y>.10 and bounds.intersects(volume):return true
	return false
