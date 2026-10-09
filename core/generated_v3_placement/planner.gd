extends RefCounted
## Explicit source-bound, deterministic placement. No source/mesh mutation.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Assets=preload("res://core/generated_v3_placement/asset_catalog.gd")
const ID="generated_v3_placement/v1"
const PROFILE="dry_village/v1"
const CLEARANCE=.35
const COORDINATE_SCALE=1099511627776
const BUILDING_GRADIENT=.18
const BUILDING_SPREAD=.06
const ROAD_GRADIENT=.45
const DRY_CLEARANCE=.01
const RECIPE=[["village_cottage_a",.18],["village_barn",.15],["village_cottage_b",.13]]
static func key(hex: Array) -> String:return "%d,%d"%[int(hex[0]),int(hex[1])]
static func hex_(cell: String) -> Array:
	var parts=cell.split(",");return [int(parts[0]),int(parts[1])]
static func vector_row(v: Vector3) -> Array:return [v.x,v.y,v.z]
static func exact_coordinate_row(v: Vector3) -> Array:return [int(roundf(v.x*COORDINATE_SCALE)),int(roundf(v.y*COORDINATE_SCALE)),int(roundf(v.z*COORDINATE_SCALE))]
static func distances(graph: Dictionary,start: String) -> Dictionary:
	var result: Dictionary={};var queue: Array=[start];var cursor=0
	if not graph.has(start):return result
	result[start]=0
	while cursor<queue.size():
		var current: String=queue[cursor];cursor+=1
		for next in graph[current]:
			if result.has(next):continue
			result[next]=result[current]+1;queue.append(next)
	return result
static func identity(source: Dictionary,built: Dictionary,origin_hex: Array) -> Dictionary:
	return {"schema_version":ID,"profile_id":PROFILE,"source_hash":source.content_hash,"geometry_hash":built.geometry_hash,"renderer_profile":built.renderer_profile,"asset_catalog_hash":Assets.SHA,"river_reservation":"source_site_and_entry_cells/v1","origin_hex":origin_hex.duplicate()}
static func build(source: Dictionary,built: Dictionary,base_nav: RefCounted,origin_hex: Array) -> Dictionary:
	if not built.get("ok",false) or built.get("renderer_profile")!="structured_v1" or built.get("source_hash")!=source.get("content_hash") or base_nav.source_hash!=source.get("content_hash") or base_nav.geometry_hash!=built.get("geometry_hash"):
		return C.fail("PLACEMENT_IDENTITY","Placement requires the exact admitted structured v3 source, mesh and navigation.")
	if origin_hex.size()!=2 or not C.integer(origin_hex[0]) or not C.integer(origin_hex[1]) or not base_nav.supported.get(key(origin_hex),false):return C.fail("PLACEMENT_ORIGIN","The placement origin must be an admitted dry anchor.")
	var assets=Assets.read()
	if not assets.ok:return assets
	var surface=Surface.new();var checked=surface.build(built.ground_mesh,built.geometry_hash)
	if not checked.ok:return checked
	var start=key(origin_hex);var original=distances(base_nav.allowed,start);var candidates: Array=[]
	var context=identity(source,built,origin_hex);var context_hash=C.digest(context);var entity_namespace="v3:"+context_hash.substr(0,20)
	for cell in original:
		if int(original[cell])<2:continue
		candidates.append({"cell":cell,"ring":floori(float(original[cell])/3.0),"rank":(context_hash+"|"+cell).sha256_text()})
	candidates.sort_custom(func(a,b):return a.ring<b.ring if a.ring!=b.ring else a.rank<b.rank)
	var rejected: Dictionary={};var examined=0;var started=Time.get_ticks_usec()
	for candidate in candidates:
		examined+=1
		var attempt=_try_site(source,built,base_nav,surface,assets.data,context,context_hash,entity_namespace,candidate.cell,original)
		if not attempt.ok:
			var code=attempt.get("code","PLACEMENT_REJECTED");rejected[code]=rejected.get(code,0)+1;continue
		var manifest: Dictionary=C.normalized(attempt.manifest);manifest.placement_hash=C.digest(manifest)
		return {"ok":true,"manifest":manifest,"placement_hash":manifest.placement_hash,"surface":surface,"diagnostics":{"examined_cells":examined,"rejected":rejected,"build_ms":(Time.get_ticks_usec()-started)/1000.0,"source_preserved":true,"geometry_preserved":true,"biomes_preserved":true,"site_graph_distance":original[candidate.cell],"candidate_count":candidates.size()}}
	return {"ok":false,"code":"PLACEMENT_UNAVAILABLE","errors":["No eligible one-hex village fits this exact source and fixed physical profile; terrain and seed were not changed."],"diagnostics":{"examined_cells":examined,"rejected":rejected}}
static func _try_site(source: Dictionary,_built: Dictionary,nav: RefCounted,surface: RefCounted,assets: Dictionary,context: Dictionary,context_hash: String,entity_namespace: String,cell: String,component: Dictionary) -> Dictionary:
	if bool(source.cells[cell].get("river",false)):return C.fail("PLACEMENT_RIVER_RESERVED","Source river-marked cells are reserved from village placement; no physical river shape is assumed.")
	var center: Vector3=nav.cell_center(hex_(cell));var center2=Vector2(center.x,center.z)
	var site_id="settlement:"+entity_namespace+":village_0";var buildings: Array=[];var building_ids: Array=[]
	var phase=posmod(int(source.seed),6)*PI/3.0
	for i in RECIPE.size():
		var name: String=RECIPE[i][0];var radius: float=RECIPE[i][1];var asset: Dictionary=assets.assets[name]
		var theta=phase+i*TAU/3.0
		var offset=Vector2(cos(theta),sin(theta))*.65
		var position=Vector3(Surface.quantize(center.x+offset.x),0.0,Surface.quantize(center.z+offset.y))
		var yaw=Surface.quantize(atan2(offset.x,offset.y));var scale=Surface.quantize(radius*.95/float(asset.footprint_radius))
		var basis=Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale)
		var low: Array=asset.aabb_min_xyz;var high: Array=asset.aabb_max_xyz;var corners: Array=[]
		for local in [Vector3(low[0],0,low[2]),Vector3(high[0],0,low[2]),Vector3(high[0],0,high[2]),Vector3(low[0],0,high[2])]:corners.append(Surface.xz(position+basis*local))
		var footprint=Surface.quantized_enclosure(corners)
		# The complete conservative projected model remains in its one original hex.
		var hexagon: Array=[]
		for j in range(6):hexagon.append(center2+Vector2(cos(PI/6.0+j*TAU/6.0),sin(PI/6.0+j*TAU/6.0)))
		if absf(Surface.area(footprint)-Surface.area(Surface.clip(footprint,hexagon)))>0.000001:return C.fail("PLACEMENT_HEX_BOUNDS","Building leaves the original one-hex footprint.")
		var supported=surface.support(footprint,BUILDING_GRADIENT,BUILDING_SPREAD,DRY_CLEARANCE)
		if not supported.ok:return supported
		position.y=Surface.ceil_q(float(supported.max_height)+.003)
		var envelope=Surface.expanded(footprint,CLEARANCE)
		if Surface.segment_hits(center2,center2,envelope):return C.fail("PLACEMENT_PLAZA_BLOCKED","A building overlaps the traveler's plaza clearance.")
		for prior in buildings:
			if Surface.area(Surface.clip(footprint,Surface.as_points(prior.footprint)))>0.0000001:return C.fail("PLACEMENT_BUILDING_OVERLAP","Village buildings overlap.")
		var id_="building:"+entity_namespace+":village_0:"+str(i);building_ids.append(id_)
		buildings.append({"id":id_,"settlement_id":site_id,"asset_id":name,"asset_sha256":asset.sha256,"lod1_sha256":asset.lod1_sha256,"hex":hex_(cell),"position":vector_row(position),"yaw_radians":yaw,"scale":scale,"footprint":Surface.as_json(footprint),"clearance_envelope":Surface.as_json(envelope),"clearance_radius":CLEARANCE,"foundation_plane":[0.0,0.0,position.y],"support_limits":{"dry_clearance":DRY_CLEARANCE,"max_gradient":BUILDING_GRADIENT,"max_height_spread":BUILDING_SPREAD,"max_foundation_gap":BUILDING_SPREAD+.003+3.0/Surface.Q},"support":supported})
	var plaza_polygon=Surface.expanded([center2],CLEARANCE);var plaza=surface.support(plaza_polygon,.30,.20,DRY_CLEARANCE)
	if not plaza.ok:return plaza
	var graph: Dictionary=nav.allowed.duplicate(true);var blocked: Array=[];var cells=graph.keys();cells.sort()
	for a in cells:
		for b in graph[a].duplicate():
			if a>=b:continue
			var p: Vector3=nav.cell_center(hex_(a));var q: Vector3=nav.cell_center(hex_(b));var hit: Array=[]
			for building in buildings:
				if Surface.segment_hits(Vector2(p.x,p.z),Vector2(q.x,q.z),Surface.as_points(building.clearance_envelope)):hit.append(building.id)
			if hit.is_empty():continue
			graph[a].erase(b);graph[b].erase(a);blocked.append({"from":hex_(a),"to":hex_(b),"building_ids":hit,"reason":"building_clearance"})
	if blocked.is_empty():return C.fail("PLACEMENT_NO_OBSTRUCTION","The physical village must declare its actual route obstruction.")
	var reachable=distances(graph,key(context.origin_hex))
	if reachable.size()!=component.size():return C.fail("PLACEMENT_DISCONNECTED","Village would disconnect the origin's previously reachable dry component.")
	var roads: Array=[];var entry_hex: Array=[];var route_candidates: Array=graph[cell].duplicate()
	route_candidates.sort_custom(func(a,b):return (context_hash+"|road|"+a).sha256_text()<(context_hash+"|road|"+b).sha256_text())
	for next in route_candidates:
		if bool(source.cells[next].get("river",false)):continue
		var endpoint: Vector3=nav.cell_center(hex_(next));var road_centers=[center2,Vector2(endpoint.x,endpoint.z)];var corridor=Surface.expanded(road_centers,CLEARANCE)
		var road_support=surface.support(corridor,ROAD_GRADIENT,65536.0,DRY_CLEARANCE)
		if not road_support.ok:continue
		var intersects=false
		for building in buildings:
			if Surface.area(Surface.clip(corridor,Surface.as_points(building.footprint)))>0.0000001:intersects=true;break
		if intersects:continue
		var road_id="road:"+entity_namespace+":entry_0";var points: Array=[]
		for p: Vector3 in nav.route_points([hex_(cell),hex_(next)]):points.append(exact_coordinate_row(p))
		roads.append({"id":road_id,"settlement_id":site_id,"hex":hex_(cell),"route_hexes":[hex_(cell),hex_(next)],"centerline_q40":points,"centerline_scale":COORDINATE_SCALE,"width":.40,"clearance_radius":CLEARANCE,"footprint":Surface.as_json(Surface.expanded(road_centers,.20)),"clearance_envelope":Surface.as_json(corridor),"visual_lift":.012,"terrain_cost_modifier":1,"support_limits":{"dry_clearance":DRY_CLEARANCE,"max_gradient":ROAD_GRADIENT},"support":road_support})
		entry_hex=hex_(next);break
	if roads.is_empty():return C.fail("PLACEMENT_NO_ENTRY","No neighbor offers a full-width dry, clear entry road.")
	var entry_position: Vector3=nav.cell_center(entry_hex);var origin_component: Array=component.keys();origin_component.sort()
	var manifest: Dictionary=context.duplicate(true)
	manifest.merge({"context_hash":context_hash,"asset_clearance_contract":"full_asset_projected_aabb_plus_circumscribed_disk/v1","actor_sole_radius":.332,"actor_clearance_radius":CLEARANCE,"settlements":[{"id":site_id,"name":"旅途村落","kind":"village","center_hex":hex_(cell),"footprint_hexes":[hex_(cell)],"entry_hex":entry_hex,"building_ids":building_ids,"road_ids":[roads[0].id],"walled":false}],"buildings":buildings,"roads":roads,"plaza":{"footprint":Surface.as_json(plaza_polygon),"support_limits":{"dry_clearance":DRY_CLEARANCE,"max_gradient":.30,"max_height_spread":.20},"support":plaza},"entry_anchors":[{"role":"plaza","hex":hex_(cell),"position_q40":exact_coordinate_row(center),"position_scale":COORDINATE_SCALE},{"role":"entry","hex":entry_hex,"position_q40":exact_coordinate_row(entry_position),"position_scale":COORDINATE_SCALE}],"blocked_edges":blocked,"base_allowed_neighbors":nav.allowed.duplicate(true),"allowed_neighbors":graph,"origin_component":origin_component,"scope":{"one_hex_village":true,"gate":false,"river_geometry":false,"source_river_cells_reserved":true,"river_corridor_geometry_verified":false,"rooms":false,"npc_behavior":false,"road_cost_bonus":false}})
	return {"ok":true,"manifest":manifest}
static func validate(manifest: Variant,source: Dictionary,built: Dictionary,base_nav: RefCounted,origin_hex: Array) -> Dictionary:
	if not manifest is Dictionary or not C.safe(manifest) or manifest.get("schema_version")!=ID or manifest.get("profile_id")!=PROFILE:return C.fail("PLACEMENT_MANIFEST","Unsupported placement schema/profile.")
	var copied: Dictionary=manifest.duplicate(true);var supplied=copied.get("placement_hash","");copied.erase("placement_hash")
	if not supplied is String or supplied.length()!=64 or C.digest(copied)!=supplied:return C.fail("PLACEMENT_HASH","Placement manifest changed after admission.")
	var regenerated=build(source,built,base_nav,origin_hex)
	if not regenerated.ok:return regenerated
	if C.bytes(regenerated.manifest)!=C.bytes(manifest):return C.fail("PLACEMENT_REPRODUCE","Placement does not exactly match its source-bound deterministic profile.")
	return regenerated
