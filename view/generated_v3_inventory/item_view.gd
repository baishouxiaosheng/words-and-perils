extends "res://view/generated_inventory/item_view.gd"
## Reuse the accepted V16 pack model; cache its raw native surface arrays for
## the new picker (Mesh.get_faces quantizes via TriangleMesh). Source-bound
## focus and the actual V3 support surface differ; no custody mutation occurs.
const EntityFocus=preload("res://core/source_entities/focus.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
var item_id:="item_travel_bundle"
var item_name:="行礼包"
var owner_actor_id:=""
var surface:RefCounted
var raw_triangle_cache:Dictionary={}
func _init(id:String="item_travel_bundle",support_surface:RefCounted=null) -> void:item_id=id;surface=support_surface
func bind(owner_board:Node3D) -> void:
	super.bind(owner_board);name="SourceItem_"+item_id.sha256_text().substr(0,12)
func update_state(state:Dictionary) -> void:
	reference=EntityFocus.make_reference(item_id,state)
	if reference.is_empty():pack.hide();select({});return
	var item:Dictionary=state.items[item_id]
	item_name=item.name;owner_actor_id=item.get("owner_actor_id","");carried=not owner_actor_id.is_empty()
	ground_pose=placement_for(reference.hex) if not carried else {}
	ground_position=ground_pose.get("position",board.admitted_source.navigation.cell_center(reference.hex))
	var normal_:Array=ground_pose.get("normal",[0.0,1.0,0.0])
	pack.basis=Basis(Quaternion(Vector3.UP,Vector3(normal_[0],normal_[1],normal_[2])))*float(ground_pose.get("scale",1.0))
	pack.visible=carried or bool(ground_pose.get("footprint_verified",false))
	sync_position();edge_glow.visible=selected
func sync_position() -> void:
	if not is_instance_valid(pack) or not pack.visible or not is_instance_valid(board):return
	if carried and board.token_nodes.has(owner_actor_id) and is_instance_valid(board.token_nodes[owner_actor_id]):pack.global_position=board.token_nodes[owner_actor_id].global_position+CARRY_OFFSET
	else:pack.position=ground_position
func select(value:Dictionary) -> void:
	selected=not reference.is_empty() and value.get("kind")=="item" and value.get("id")==item_id and value.get("world_id")==reference.world_id and value.get("catalog_version")==EntityFocus.VERSION and value.get("catalog_id")==reference.catalog_id
	if is_instance_valid(edge_glow):edge_glow.visible=selected
func _raw_faces(mesh:Mesh) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for surface_id in range(mesh.get_surface_count()):
		var arrays:Array=mesh.surface_get_arrays(surface_id)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():result.append_array(vertices)
		else:
			for index in indices:result.append(vertices[index])
	return result
func pick(point:Vector2,limit:float) -> Dictionary:
	if reference.is_empty() or not is_instance_valid(pack) or not pack.visible:return {}
	sync_position()
	var origin:Vector3=board.camera.project_ray_origin(point);var direction:Vector3=board.camera.project_ray_normal(point)
	var distance:=INF;var position_:=Vector3.ZERO
	for part_ in mesh_parts:
		if not raw_triangle_cache.has(part_):raw_triangle_cache[part_]=_raw_faces(part_.mesh)
		var faces:PackedVector3Array=raw_triangle_cache[part_];var transform_:Transform3D=part_.global_transform
		for i in range(0,faces.size(),3):
			var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,transform_*faces[i],transform_*faces[i+1],transform_*faces[i+2])
			if not hit is Vector3:continue
			var t:float=(hit-origin).dot(direction)
			if t>=0.0 and t<=limit and t<distance:distance=t;position_=hit
	if not is_finite(distance):return {}
	return {"reference":reference.duplicate(true),"label":item_name+" · "+("携带" if carried else "地上"),"distance":distance,"point":position_}
func placement_for(hex:Array) -> Dictionary:
	var identity:Dictionary=board.admitted_source.identity
	var key:String=str(identity.content_hash)+"/"+str(identity.geometry_hash)+"/"+item_id+"/"+str(hex)
	if pose_cache.has(key):return pose_cache[key].duplicate(true)
	var center:Vector3=board.admitted_source.navigation.cell_center(hex)
	if surface==null or surface.geometry_hash!=identity.geometry_hash:return {"position":center,"scale":0.0,"footprint_verified":false,"reason":"surface_identity_unavailable"}
	var offsets:Array=[Vector3(.30,0,.04),Vector3(-.30,0,.04),Vector3(0,0,.32),Vector3(0,0,-.32),Vector3(.58,0,0),Vector3(-.58,0,0),Vector3(0,0,.58),Vector3(0,0,-.58),Vector3.ZERO]
	for scale_ in [1.0,.75,.5,.25,.125,.0625]:
		var best:Dictionary={}
		for offset:Vector3 in offsets:
			var candidate:Dictionary=_v3_footprint(center+offset,float(scale_))
			if candidate.is_empty() or candidate.support_residual_spread>.08*float(scale_) or overlaps_static_prop(candidate):continue
			if best.is_empty() or candidate.support_residual_spread<best.support_residual_spread:best=candidate
		if not best.is_empty():pose_cache[key]=best;return best.duplicate(true)
	return {"position":center,"scale":0.0,"footprint_verified":false,"reason":"no_dry_miniature_footprint"}
func _v3_footprint(center:Vector3,scale_:float) -> Dictionary:
	var polygon:Array=[]
	for i in range(8):polygon.append([center.x+cos(TAU*i/8.0)*.215*scale_,center.z+sin(TAU*i/8.0)*.215*scale_])
	var checked:Dictionary=surface.support(polygon,2.0,65536.0,.0001)
	if not checked.ok:return {}
	var point:=Vector2(center.x,center.z);var plane:Array=[]
	for id in surface.candidates([point]):
		var face:Dictionary=surface.faces[id]
		if Geometry2D.is_point_in_polygon(point,PackedVector2Array(face.polygon)):plane=[face.gx,face.gz,face.k];break
	if plane.is_empty():return {}
	var gaps:Dictionary=surface.plane_gaps(polygon,plane)
	if not gaps.ok:return {}
	var normal_:=Vector3(-float(plane[0]),1.0,-float(plane[1])).normalized()
	var height:float=float(plane[0])*center.x+float(plane[1])*center.z+float(plane[2])-float(gaps.min_gap)+.012
	return {"position":Vector3(center.x,height,center.z),"normal":[normal_.x,normal_.y,normal_.z],"scale":scale_,"footprint_verified":true,"height_spread":checked.height_spread,"support_residual_spread":float(gaps.max_gap)-float(gaps.min_gap),"minimum_dry_clearance":checked.min_height,"covered_area":checked.area,"footprint_area":checked.area,"uncovered_area_upper_bound":checked.uncovered_area_upper_bound,"geometry_hash":surface.geometry_hash}
