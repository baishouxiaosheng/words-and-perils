extends RefCounted
## CPU-only identity/bounds catalog, independent of render batches and game state.
## Exact mesh prototypes are captured before batching. No physics bodies/colliders.
const BUCKET_SIZE:=4.0
var subjects:Dictionary={}
var buckets:Dictionary={}
var prototypes:Dictionary={}
var scene_bounds:=AABB()
var has_bounds:=false
var build_count:=0
var last_query:Dictionary={}

func clear_world()->void:
	subjects.clear();buckets.clear();prototypes.clear()
	scene_bounds=AABB();has_bounds=false;build_count+=1

func capture(reference:Dictionary,label:String,root:Node3D,dynamic:bool=false)->void:
	var id:=_id(reference)
	erase_subject(id)
	var parts:Array=[]
	var local_bounds:=AABB();var found:=false
	var inverse:=root.global_transform.affine_inverse() if dynamic else Transform3D.IDENTITY
	for child in root.find_children("*","MeshInstance3D",true,false):
		var node:MeshInstance3D=child
		if node.mesh==null or node.is_queued_for_deletion() or not node.visible:continue
		var key:=_prototype_key(node.mesh)
		if not prototypes.has(key):prototypes[key]={"faces":node.mesh.get_faces(),"bounds":node.mesh.get_aabb()}
		var transform_:Transform3D=inverse*node.global_transform
		var bound: AABB=transform_*prototypes[key].bounds
		local_bounds=local_bounds.merge(bound) if found else bound;found=true
		parts.append({"prototype":key,"transform":transform_,"inverse":transform_.affine_inverse(),"bounds":bound})
	if not found:return
	var transform_:Transform3D=root.global_transform if dynamic else Transform3D.IDENTITY
	var entry={"reference":reference.duplicate(true),"label":label,"parts":parts,
		"local_bounds":local_bounds,"transform":transform_,"inverse":transform_.affine_inverse(),
		"bounds":transform_*local_bounds,"anchor":root if dynamic else null,"bucket_keys":[]}
	subjects[id]=entry;_index(id,entry)

func update_reference(reference:Dictionary,label:String)->void:
	var id:=_id(reference)
	if subjects.has(id):subjects[id].reference=reference.duplicate(true);subjects[id].label=label

func erase_subject(id:String)->void:
	if not subjects.has(id):return
	_unindex(id,subjects[id]);subjects.erase(id)

func sync_actors()->void:
	for id in subjects:
		var subject:Dictionary=subjects[id]
		var anchor=subject.anchor
		if anchor==null:continue
		if not is_instance_valid(anchor):continue
		var transform_:Transform3D=anchor.global_transform
		if transform_==subject.transform:continue
		_unindex(id,subject)
		subject.transform=transform_;subject.inverse=transform_.affine_inverse()
		subject.bounds=transform_*subject.local_bounds
		_index(id,subject)

func query(origin:Vector3,direction:Vector3,max_distance:float)->Array[Dictionary]:
	var start_time:=Time.get_ticks_usec()
	sync_actors()
	var result:Array[Dictionary]=[]
	var candidates:Dictionary={}
	var traversed:=0;var triangle_tests:=0
	if has_bounds and max_distance>0.0:
		var interval:Vector2=_ray_interval(scene_bounds,origin,direction,max_distance)
		if interval.x>=0.0:
			var keys:Array[String]=_walk_buckets(origin,direction,interval.x,interval.y)
			traversed=keys.size()
			for key in keys:
				for id in buckets.get(key,[]):candidates[id]=true
			for id in candidates:
				var subject:Dictionary=subjects[id]
				if _ray_interval(subject.bounds,origin,direction,max_distance).x<0.0:continue
				var local_origin:Vector3=subject.inverse*origin
				var local_dir:Vector3=subject.inverse.basis*direction
				var nearest:=INF
				for part in subject.parts:
					if part.bounds.intersects_ray(local_origin,local_dir)==null:continue
					var ray_origin:Vector3=part.inverse*local_origin
					var ray_dir:Vector3=part.inverse.basis*local_dir
					var faces:PackedVector3Array=prototypes[part.prototype].faces
					for i in range(0,faces.size(),3):
						triangle_tests+=1
						var hit=Geometry3D.ray_intersects_triangle(ray_origin,ray_dir,faces[i],faces[i+1],faces[i+2])
						if hit==null:continue
						var point:Vector3=subject.transform*(part.transform*hit)
						var distance:float=(point-origin).dot(direction)
						if distance>=0.0 and distance<=max_distance:nearest=minf(nearest,distance)
				if is_finite(nearest):result.append({"reference":subject.reference.duplicate(true),"label":subject.label,"distance":nearest,"point":origin+direction*nearest})
	result.sort_custom(func(a,b):return a.distance<b.distance if a.distance!=b.distance else _id(a.reference)<_id(b.reference))
	last_query={"elapsed_us":Time.get_ticks_usec()-start_time,"bucket_visits":traversed,"broadphase_subjects":candidates.size(),"triangle_tests":triangle_tests,"hits":result.size()}
	return result

func _index(id:String,subject:Dictionary)->void:
	var bounds:AABB=subject.bounds
	var minimum:=Vector2i(floori(bounds.position.x/BUCKET_SIZE),floori(bounds.position.z/BUCKET_SIZE))
	var maximum:=Vector2i(floori(bounds.end.x/BUCKET_SIZE),floori(bounds.end.z/BUCKET_SIZE))
	var keys:Array=[]
	for x in range(minimum.x,maximum.x+1):
		for z in range(minimum.y,maximum.y+1):
			var key:="%d,%d"%[x,z]
			if not buckets.has(key):buckets[key]=[]
			buckets[key].append(id);keys.append(key)
	subject.bucket_keys=keys
	scene_bounds=scene_bounds.merge(bounds) if has_bounds else bounds;has_bounds=true

func _unindex(id:String,subject:Dictionary)->void:
	for key in subject.bucket_keys:
		if not buckets.has(key):continue
		buckets[key].erase(id)
		if buckets[key].is_empty():buckets.erase(key)
	subject.bucket_keys=[]

static func _id(reference:Dictionary)->String:
	return String(reference.kind)+":"+String(reference.id)

static func _prototype_key(mesh:Mesh)->String:
	if mesh is CylinderMesh:return "cylinder:%s"%_number_bits([mesh.top_radius,mesh.bottom_radius,mesh.height,mesh.radial_segments,mesh.rings,int(mesh.cap_top),int(mesh.cap_bottom),int(mesh.flip_faces)])
	if mesh is SphereMesh:return "sphere:%s"%_number_bits([mesh.radius,mesh.height,mesh.radial_segments,mesh.rings,int(mesh.is_hemisphere),int(mesh.flip_faces)])
	if mesh is BoxMesh:return "box:%s"%_number_bits([mesh.size.x,mesh.size.y,mesh.size.z,mesh.subdivide_width,mesh.subdivide_height,mesh.subdivide_depth,int(mesh.flip_faces)])
	return "mesh:"+str(mesh.get_instance_id())

static func _ray_interval(bounds:AABB,origin:Vector3,direction:Vector3,limit:float)->Vector2:
	var low:=0.0;var high:=limit
	for axis in range(3):
		if absf(direction[axis])<0.00000001:
			if origin[axis]<bounds.position[axis] or origin[axis]>bounds.end[axis]:return Vector2(-1,-1)
			continue
		var first:float=(bounds.position[axis]-origin[axis])/direction[axis]
		var second:float=(bounds.end[axis]-origin[axis])/direction[axis]
		low=maxf(low,minf(first,second));high=minf(high,maxf(first,second))
		if low>high:return Vector2(-1,-1)
	return Vector2(low,high)

static func _walk_buckets(origin:Vector3,direction:Vector3,start:float,finish:float)->Array[String]:
	# Exact 2D grid DDA traversal, including both sides of corner crossings.
	var result:Array[String]=[]
	var p:=origin+direction*start;var end:=origin+direction*finish
	var cell:=Vector2i(floori(p.x/BUCKET_SIZE),floori(p.z/BUCKET_SIZE))
	var last:=Vector2i(floori(end.x/BUCKET_SIZE),floori(end.z/BUCKET_SIZE))
	var sx:=1 if direction.x>0.0 else (-1 if direction.x<0.0 else 0)
	var sz:=1 if direction.z>0.0 else (-1 if direction.z<0.0 else 0)
	var dx:=BUCKET_SIZE/absf(direction.x) if sx!=0 else INF
	var dz:=BUCKET_SIZE/absf(direction.z) if sz!=0 else INF
	var tx:=start+(((cell.x+(1 if sx>0 else 0))*BUCKET_SIZE-p.x)/direction.x) if sx!=0 else INF
	var tz:=start+(((cell.y+(1 if sz>0 else 0))*BUCKET_SIZE-p.z)/direction.z) if sz!=0 else INF
	var maximum:=absi(last.x-cell.x)+absi(last.y-cell.y)+3
	for _step in range(maximum):
		result.append("%d,%d"%[cell.x,cell.y])
		if cell==last:break
		if tx==tz:
			result.append("%d,%d"%[cell.x+sx,cell.y]);result.append("%d,%d"%[cell.x,cell.y+sz])
			cell+=Vector2i(sx,sz);tx+=dx;tz+=dz
		elif tx<tz:cell.x+=sx;tx+=dx
		else:cell.y+=sz;tz+=dz
	return result

static func _number_bits(values:Array)->String:
	var exact:=PackedFloat64Array()
	for value in values:exact.append(float(value))
	return exact.to_byte_array().hex_encode()
