extends RefCounted
## Fixed-scale, exact-mesh supported roadside pawn. Never changes source or routes.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const Tokens=preload("res://view/chess_tokens.gd")
const ID="v3_roadside_npc_placement/v1"
const ROLE="roadside_guide_0"
const SCALE=1.0/4.0 # Full plinth radius .38, measured footprint .095; fixed for every source.
const CLEARANCE=.38 # Full traveler plinth, stricter than the base .35 sole corridor.
const MAX_SPREAD=.055
static func build(source: RefCounted,npc_id: String) -> Dictionary:
	var manifest: Dictionary=source.placement_result.manifest
	var site: Dictionary=manifest.settlements[0]
	var hex: Array=site.entry_hex.duplicate()
	var center: Vector3=source.navigation.cell_center(hex)
	var surface: RefCounted=source.placement_result.surface
	var token: Node3D=Tokens.build(npc_id,{"role":"villager","faction":"friendly"})
	var points: Array=[];_vertices(token,Transform3D.IDENTITY,points);token.free()
	if points.is_empty():return C.fail("NPC_ASSET","村民棋子没有可验证的模型。")
	var projected: Array=[];var low: Array=[];var radius=0.0;var ymin=INF;var ymax=-INF
	for p: Vector3 in points:
		p*=SCALE;projected.append(Vector2(p.x,p.z));radius=maxf(radius,Vector2(p.x,p.z).length());ymin=minf(ymin,p.y);ymax=maxf(ymax,p.y)
	for p: Vector3 in points:
		if p.y*SCALE<=ymin+.025:low.append(Vector2(p.x,p.z)*SCALE)
	if radius>.101 or low.size()<3:return C.fail("NPC_ASSET_BOUNDS","村民模型超出固定占地，未缩小或改变地图。")
	var full_local: Array=Surface.expanded([Vector2.ZERO],radius);var low_local: Array=Surface.hull(low)
	var attempted=0;var rejected={}
	# Axial corner pockets. Ordered finite list, no camera or random input.
	for radius_ in [.9375,.90625,.96875,.875]:
		for i in range(6):
			attempted+=1
			var angle=PI/6.0+i*TAU/6.0
			var p=Vector2(Surface.quantize(center.x+cos(angle)*radius_),Surface.quantize(center.z+sin(angle)*radius_))
			var at: Dictionary=source.navigation.cell_at_xz(p)
			if not at.ok or C.bytes(at.hex)!=C.bytes(hex):continue
			var full: Array=[];var sole: Array=[]
			for q in full_local:full.append(q+p)
			for q in low_local:sole.append(q+p)
			full=Surface.quantized_enclosure(full);sole=Surface.quantized_enclosure(sole)
			var support: Dictionary=surface.support(full,.55,MAX_SPREAD,.01)
			if not support.ok:rejected[support.get("code","support")]=rejected.get(support.get("code","support"),0)+1;continue
			var envelope: Array=Surface.expanded(full,CLEARANCE)
			var blocked=false
			for a in source.navigation.allowed:
				var pa: Vector3=source.navigation.cell_center(Planner.hex_(a))
				for b in source.navigation.allowed[a]:
					if a>=b:continue
					var pb: Vector3=source.navigation.cell_center(Planner.hex_(b))
					if Surface.segment_hits(Vector2(pa.x,pa.z),Vector2(pb.x,pb.z),envelope):blocked=true;break
				if blocked:break
			if blocked:rejected["corridor"]=rejected.get("corridor",0)+1;continue
			for building in manifest.buildings:
				if Surface.area(Surface.clip(full,Surface.as_points(building.footprint)))>0.00000001:blocked=true;break
			if blocked:continue
			var y=Surface.ceil_q(float(support.max_height)-ymin+.002)
			var gaps: Dictionary=surface.plane_gaps(sole,[0.0,0.0,y+ymin])
			if not gaps.ok or gaps.min_gap<0.0 or gaps.max_gap>MAX_SPREAD+.003:continue
			var position=Vector3(p.x,y,p.y)
			var witness={"schema_version":ID,"placement_hash":manifest.placement_hash,"settlement_id":site.id,"role":ROLE,"hex":hex,"position_q40":Planner.exact_coordinate_row(position),"position_scale":Planner.COORDINATE_SCALE,"support_witness":{"source_hash":source.data.content_hash,"geometry_hash":source.identity.geometry_hash,"scale":SCALE,"yaw":0,"footprint":Surface.as_json(full),"bounds":{"radius":Surface.ceil_q(radius),"min_y":Surface.floor_q(ymin),"max_y":Surface.ceil_q(ymax)},"support":support,"sole_gaps":gaps,"clearance_radius":CLEARANCE,"corridors_clear":true,"fixed_candidate":attempted-1}}
			var reservation={"source_hash":source.data.content_hash,"geometry_hash":source.identity.geometry_hash,"placement_hash":manifest.placement_hash,"actor_id":npc_id,"hex":hex,"footprint":Surface.as_json(full),"position_q40":witness.position_q40,"position_scale":Planner.COORDINATE_SCALE,"scale":SCALE}
			return {"ok":true,"placement_witness":C.normalized(witness),"reservations":C.normalized([reservation]),"metrics":{"attempted":attempted,"rejected":rejected,"native_vertex_count":points.size(),"sole_footprint":Surface.as_json(sole)},"raw_geometry":geometry_record(points)}
	return {"ok":false,"code":"NPC_PLACEMENT_UNAVAILABLE","errors":["入口没有满足固定支撑与通路净空的村民位置；请选择另一张地图。"],"diagnostics":{"attempted":attempted,"rejected":rejected}}
static func _vertices(node: Node, parent: Transform3D, result: Array) -> void:
	var transform=parent
	if node is Node3D:transform=parent*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		for i in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(i)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:result.append(transform*vertex)
	for child in node.get_children():_vertices(child,transform,result)
static func position(witness: Dictionary) -> Vector3:
	var p: Array=witness.position_q40
	return Vector3(p[0],p[1],p[2])/float(witness.position_scale)

static func geometry_record(points: Array) -> Dictionary:
	var packed=PackedVector3Array(points);var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(packed.to_byte_array())
	var rows:Array=[]
	for p in packed:rows.append([p.x,p.y,p.z])
	return {"vertices":rows,"float32_sha256":hash_.finish().hex_encode(),"token_source_sha256":FileAccess.get_sha256("res://view/chess_tokens.gd"),"fixed_scale":SCALE,"indexed":false,"scope":"all emitted raw surface vertices with node transforms; duplicate vertices retained"}
