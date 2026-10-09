extends RefCounted
## Read-only native enemy footprint validation at the committed location.
## A failure blocks candidate display acceptance; it never changes authority/nav.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Placement=preload("res://view/generated_v3_enemy/placement.gd")
static func fit(source:RefCounted,state:Dictionary)->Dictionary:
	if source==null or not source.validate_state(state).get("ok",false):return C.fail("ACTOR_RENDER_SOURCE","Invalid admitted actor world.")
	var id:String=source.enemy_id;var actor:Dictionary=state.actors[id]
	var record:Dictionary=source.enemy_placement_result.get("raw_geometry",{})
	if record.get("token_source_sha256")!=FileAccess.get_sha256("res://view/chess_tokens.gd") or not record.get("vertices") is Array:return C.fail("ACTOR_RENDER_GEOMETRY","Native full-size token geometry is unavailable.")
	var points:Array=[];var projected:Array=[];var low:Array=[];var ymin=INF;var ymax=-INF
	for row in record.vertices:
		if not row is Array or row.size()!=3:return C.fail("ACTOR_RENDER_GEOMETRY","Malformed native vertex record.")
		var p=Vector3(row[0],row[1],row[2]);points.append(p);projected.append(Vector2(p.x,p.z));ymin=minf(ymin,p.y);ymax=maxf(ymax,p.y)
	if points.is_empty() or Placement.geometry_record(points).float32_sha256!=record.get("float32_sha256"):return C.fail("ACTOR_RENDER_GEOMETRY","Native vertex identity changed.")
	for p:Vector3 in points:
		if p.y<=ymin+.025:low.append(Vector2(p.x,p.z))
	var full:Array=Surface.hull(projected);var sole:Array=Surface.hull(low)
	if not Surface.valid_polygon(full) or not Surface.valid_polygon(sole):return C.fail("ACTOR_RENDER_FOOTPRINT","Invalid full token footprint.")
	var center:Vector3=source.navigation.cell_center(actor.hex);var offset=Vector2(center.x,center.z)
	if not center.is_finite():return C.fail("ACTOR_RENDER_CENTER","No exact native cell center.")
	for i in full.size():full[i]+=offset
	for i in sole.size():sole[i]+=offset
	full=Surface.quantized_enclosure(full);sole=Surface.quantized_enclosure(sole)
	var surface:RefCounted=source.placement_result.surface
	var support:Dictionary=surface.support(full,Placement.MAX_GRADIENT,Placement.MAX_SPREAD,Placement.DRY_CLEARANCE)
	if not support.get("ok",false):return C.fail("ACTOR_RENDER_SUPPORT","Full-size enemy at committed hex lacks the original dry support limits.")
	for building in source.placement_result.manifest.buildings:
		if Surface.area(Surface.clip(full,Surface.as_points(building.footprint)))>.00000001:return C.fail("ACTOR_RENDER_BUILDING","Native enemy footprint overlaps a building.")
	for reservation in source.npc_reservations:
		if Surface.area(Surface.clip(full,Surface.as_points(reservation.footprint)))>.00000001:return C.fail("ACTOR_RENDER_NPC","Native enemy footprint overlaps the stationary NPC.")
	var y:float=Surface.ceil_q(float(support.max_height)-ymin+.002)
	var gaps:Dictionary=surface.plane_gaps(sole,[0.0,0.0,y+ymin])
	if not gaps.get("ok",false) or gaps.min_gap<0.0 or gaps.max_gap>Placement.MAX_SPREAD+.003:return C.fail("ACTOR_RENDER_SOLE","Native sole support is outside the original limits.")
	var base=Vector3(center.x,y,center.z)
	var bounds=AABB(Vector3(INF,y+ymin,INF),Vector3.ZERO);var high=Vector3(-INF,y+ymax,-INF)
	for p:Vector2 in full:
		bounds.position.x=minf(bounds.position.x,p.x);bounds.position.z=minf(bounds.position.z,p.y);high.x=maxf(high.x,p.x);high.z=maxf(high.z,p.y)
	bounds.size=high-bounds.position
	return {"ok":true,"position":base,"rotation":Vector3.ZERO,"scale":1.0,"hex":actor.hex.duplicate(),"full_area_witness":{"support":support,"sole_gaps":gaps,"footprint":Surface.as_json(full),"raw_geometry_sha256":record.float32_sha256},"body_bounds":bounds,"downed_occupied":actor.health.current<=0}
static func route(source:RefCounted,before:Dictionary,after:Dictionary,effects:Array)->Dictionary:
	var id:String=source.enemy_id
	if before.is_empty():return {"ok":true}
	var prior:Array=before.actors[id].hex;var destinations:Array=[]
	for patch in effects:
		if patch.get("type")=="actor_move" and patch.get("actor_id")==id:destinations.append(patch.hex)
	if destinations.is_empty():return {"ok":before.actors[id].hex==after.actors[id].hex}
	for next:Array in destinations:
		var proof:Dictionary=Placement._edge_support(source.navigation,source.placement_result.surface,source.placement_result.manifest,source.npc_reservations,"%d,%d"%prior,"%d,%d"%next)
		if not proof.get("ok",false):return C.fail("ACTOR_RENDER_ROUTE","Committed enemy route has no full-foot dry sweep proof; no visual substitute was used.")
		prior=next
	return {"ok":prior==after.actors[id].hex}
