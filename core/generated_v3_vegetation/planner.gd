extends RefCounted
## Deterministic sparse ecology on the exact admitted V3 surface. No graph edit.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Assets=preload("res://core/generated_v3_vegetation/assets.gd")
const ID="generated_v3_vegetation/v1"
const PROFILE="sparse_biomes/v1"
const MAX_PLANTS=1024
const MAX_TRIANGLES=80000
const MAX_MANIFEST_BYTES=4*1024*1024
const CLEARANCE=.38 # Measured full traveler plinth, not only the .332 sole.
const DRY=.01
# kind, candidate count, minimum crown radius, radius range, height, height range
const RECIPES={"temperate_forest":["temperate",6,.16,.055,.40,.18],"jungle":["tropical",6,.17,.055,.44,.16],"grassland":["sapling",2,.12,.035,.24,.12],"dry_steppe":["shrub",1,.065,.018,.09,.055],"desert":["shrub",1,.060,.018,.075,.045],"alpine":["tuft",2,.06,.018,.055,.035],"wetland":["reed",3,.06,.015,.14,.08]}
static func key(hex:Array) -> String:return "%d,%d"%hex
static func hex_(value:String) -> Array:
	var parts=value.split(",");return [int(parts[0]),int(parts[1])]
static func row(v:Vector3) -> Array:return [v.x,v.y,v.z]
static func unit(seed:String,slot:int) -> float:return float((seed+"/"+str(slot)).sha256_text().substr(0,7).hex_to_int())/268435455.0
static func hexagon(center:Vector2) -> Array:
	var result:Array=[]
	for i in range(6):result.append(center+Vector2(cos(PI/6+i*TAU/6),sin(PI/6+i*TAU/6)))
	return result
static func projected(vertices:PackedVector3Array,basis:Basis,position:Vector3) -> Array:
	var points:Array=[]
	for vertex in vertices:points.append(Surface.xz(position+basis*vertex))
	return Surface.quantized_enclosure(points)
static func bounds_(vertices:PackedVector3Array,basis:Basis,position:Vector3) -> Dictionary:
	var transformed=PackedVector3Array()
	for vertex in vertices:transformed.append(position+basis*vertex)
	return Assets.bounds(transformed)
static func bin_rows(rows:Array,polygon_field:String) -> Dictionary:
	var bins:Dictionary={}
	for i in rows.size():
		for bucket in Surface.bucket_keys(rows[i][polygon_field]):
			if not bins.has(bucket):bins[bucket]=[]
			bins[bucket].append(i)
	return bins
static func near_rows(poly:Array,bins:Dictionary) -> Array:
	var found:Dictionary={}
	for bucket in Surface.bucket_keys(poly):
		for id in bins.get(bucket,[]):found[id]=true
	return found.keys()
static func build(source:Dictionary,built:Dictionary,nav:RefCounted,placement_result:Dictionary,origin_hex:Array,npc_reservations:Array=[]) -> Dictionary:
	var started:int=Time.get_ticks_usec()
	if not built.get("ok",false) or built.get("source_hash")!=source.get("content_hash") or built.get("geometry_hash")!=nav.get("geometry_hash") or built.get("renderer_profile")!="structured_v1" or not placement_result.get("ok",false):return C.fail("VEGETATION_IDENTITY","Vegetation requires an admitted exact V3 source, mesh and village.")
	var placement:Dictionary=placement_result.get("manifest",{});var surface:Variant=placement_result.get("surface")
	if not surface is RefCounted or surface.get("geometry_hash")!=built.geometry_hash or nav.get("placement_hash")!=placement.get("placement_hash") or placement.get("source_hash")!=source.content_hash:return C.fail("VEGETATION_PLACEMENT","Vegetation and navigation do not share the same admitted village placement.")
	if origin_hex.size()!=2 or not nav.supported.get(key(origin_hex),false):return C.fail("VEGETATION_ORIGIN","Vegetation needs the original admitted dry spawn.")
	if npc_reservations.size()>16 or not C.safe(npc_reservations) or C.bytes(npc_reservations).to_utf8_buffer().size()>32768:return C.fail("VEGETATION_RESERVATIONS","NPC reservations exceed the fixed vegetation input bounds.")
	for reservation in npc_reservations:
		if not reservation is Dictionary or reservation.get("source_hash")!=source.content_hash or reservation.get("geometry_hash")!=built.geometry_hash or reservation.get("placement_hash")!=placement.placement_hash or not reservation.get("footprint") is Array or not Surface.valid_polygon(Surface.as_points(reservation.footprint)):return C.fail("VEGETATION_RESERVATIONS","An NPC reservation is not source-bound or has no valid complete footprint.")
	var assets:Dictionary=Assets.build()
	if not assets.ok:return assets
	var context:Dictionary={"schema_version":ID,"profile_id":PROFILE,"source_hash":source.content_hash,"geometry_hash":built.geometry_hash,"renderer_profile":built.renderer_profile,"placement_hash":placement.placement_hash,"navigation_hash":C.digest(nav.export_data(origin_hex)),"asset_catalog_hash":assets.catalog.catalog_hash,"reservation_hash":C.digest(npc_reservations),"origin_hex":origin_hex.duplicate(),"river_reservation":"full_source_river_cells/v1"}
	var context_hash:String=C.digest(context);var protected:Dictionary={key(origin_hex):"spawn"};var reserved:Array=[]
	for village in placement.settlements:protected[key(village.center_hex)]="village";protected[key(village.entry_hex)]="entry"
	for cell_key in source.cells:
		var cell:Dictionary=source.cells[cell_key]
		if cell.ocean:protected[cell_key]="source_ocean"
		elif cell.river:protected[cell_key]="source_river"
	for cell_key in protected:
		var center:Vector3=nav.cell_center(hex_(cell_key));reserved.append({"id":cell_key,"kind":protected[cell_key],"polygon":hexagon(Vector2(center.x,center.z))})
	for reservation in npc_reservations:reserved.append({"id":str(reservation.get("actor_id","npc")),"kind":"npc","polygon":Surface.as_points(reservation.footprint)})
	var reserved_bins:Dictionary=bin_rows(reserved,"polygon");var edges:Array=[];var cells:Array=nav.allowed.keys();cells.sort()
	for a in cells:
		for b in nav.allowed[a]:
			if a>=b:continue
			var p:Vector3=nav.cell_center(hex_(a));var q:Vector3=nav.cell_center(hex_(b))
			edges.append({"a":Vector2(p.x,p.z),"b":Vector2(q.x,q.z),"polygon":[Vector2(p.x,p.z),Vector2(q.x,q.z)],"from":hex_(a),"to":hex_(b)})
	var edge_bins:Dictionary=bin_rows(edges,"polygon");var candidates:Array=[]
	for cell_key in source.cells:
		var cell:Dictionary=source.cells[cell_key]
		if protected.has(cell_key) or not RECIPES.has(cell.biome):continue
		var recipe:Array=RECIPES[cell.biome];var slots:Array=[0,1,2,3,4,5]
		slots.sort_custom(func(a,b):return (context_hash+"/"+cell_key+"/"+str(a)).sha256_text()<(context_hash+"/"+cell_key+"/"+str(b)).sha256_text())
		for i in range(int(recipe[1])):candidates.append({"key":cell_key,"slot":slots[i],"rank":(context_hash+"/"+cell_key+"/"+str(slots[i])).sha256_text()})
	# A global deterministic ranking avoids clipping later lexical regions at cap.
	candidates.sort_custom(func(a,b):return a.rank<b.rank)
	var plants:Array=[];var rejected:Dictionary={};var triangles:int=0;var biome_counts:Dictionary={};var species_counts:Dictionary={};var solid_rows:Array=[];var solid_bins:Dictionary={}
	for candidate in candidates:
		var cell:Dictionary=source.cells[candidate.key];var recipe:Array=RECIPES[cell.biome];var kind:String=recipe[0];var record:Dictionary=assets.catalog.assets[kind]
		if plants.size()>=MAX_PLANTS or triangles+int(record.triangles)>MAX_TRIANGLES:rejected["budget"]=rejected.get("budget",0)+1;continue
		var attempt:Dictionary=_candidate(candidate,cell,recipe,nav,surface,assets,context_hash,reserved,reserved_bins,edges,edge_bins,solid_rows,solid_bins)
		if not attempt.ok:
			var reason:String=attempt.get("code","rejected");rejected[reason]=rejected.get(reason,0)+1;continue
		var plant:Dictionary=attempt.plant;plants.append(plant);triangles+=int(record.triangles)
		biome_counts[cell.biome]=biome_counts.get(cell.biome,0)+1;species_counts[kind]=species_counts.get(kind,0)+1
		var index:int=solid_rows.size();solid_rows.append(Surface.as_points(plant.solid_footprint))
		for bucket in Surface.bucket_keys(solid_rows[index]):
			if not solid_bins.has(bucket):solid_bins[bucket]=[]
			solid_bins[bucket].append(index)
	plants.sort_custom(func(a,b):return a.id<b.id)
	var manifest:Dictionary=context.duplicate(true)
	manifest.merge({"context_hash":context_hash,"plants":plants,"solid_clearance_radius":CLEARANCE,"limits":{"max_plants":MAX_PLANTS,"max_full_triangles":MAX_TRIANGLES,"max_active_batches":64,"dry_clearance":DRY,"root_max_gradient":.55,"root_max_spread":.04,"low_max_gradient":.30,"low_max_spread":.016,"root_embed":.003},"statistics":{"instances":plants.size(),"full_triangles":triangles,"biomes":biome_counts,"assets":species_counts},"scope":{"source_biomes_unchanged":true,"navigation_unchanged":true,"solid_policy":"stem_or_low_foliage_outside_existing_corridors/v1","canopy_is_navigation_wall":false,"cover_or_harvest_gameplay":false,"selection_is_action":false}})
	manifest=C.normalized(manifest);manifest["vegetation_hash"]=C.digest(manifest)
	return {"ok":true,"manifest":manifest,"assets":assets,"surface":surface,"diagnostics":{"candidate_count":candidates.size(),"rejected":rejected,"build_ms":(Time.get_ticks_usec()-started)/1000.0,"manifest_bytes":C.bytes(manifest).to_utf8_buffer().size(),"shared_surface":true},"audit":{"reserved":reserved,"corridors":edges,"npc_reservations":npc_reservations.duplicate(true)}}
static func _candidate(candidate:Dictionary,cell:Dictionary,recipe:Array,nav:RefCounted,surface:RefCounted,assets:Dictionary,context_hash:String,reserved:Array,reserved_bins:Dictionary,edges:Array,edge_bins:Dictionary,solids:Array,solid_bins:Dictionary) -> Dictionary:
	var kind:String=recipe[0];var seed:String=context_hash+"/plant/"+candidate.key+"/"+str(candidate.slot);var woody:bool=kind in ["temperate","tropical","sapling"]
	var radius:float=Surface.quantize(float(recipe[2])+float(recipe[3])*unit(seed,0));var height_:float=Surface.quantize(float(recipe[4])+float(recipe[5])*unit(seed,1));var yaw:float=Surface.quantize(unit(seed,2)*TAU)
	var theta:float=PI/6+int(candidate.slot)*TAU/6+(unit(seed,3)-.5)*.028
	var basis=Basis(Vector3.UP,yaw).scaled(Vector3(radius,height_,radius));var measurement:Dictionary=assets.measurements[kind]
	# A corner is between two radial walking spokes. Derive its fixed pocket
	# from the actual solid radius and conservative corridor expansion rather
	# than shrinking a plant or accepting a visible plinth overlap per seed.
	var solid_radius:float=0.0
	for vertex in measurement.solid_projection:solid_radius=maxf(solid_radius,Surface.xz(basis*vertex).length())
	var radial:float=2.0*(CLEARANCE/cos(PI/16.0)+solid_radius+.014)+.012*unit(seed,4)
	if radial>.978:return C.fail("corner_space","No fixed corner pocket fits this asset and the full traveler plinth.")
	var center:Vector3=nav.cell_center([cell.q,cell.r]);var position=Vector3(Surface.quantize(center.x+cos(theta)*radial),0,Surface.quantize(center.z+sin(theta)*radial))
	var root_poly:Array=projected(measurement.root_projection,basis,position);var solid_poly:Array=projected(measurement.solid_projection,basis,position);var canopy_poly:Array=projected(measurement.canopy_projection,basis,position)
	var source_hex:Array=hexagon(Vector2(center.x,center.z))
	if absf(Surface.area(root_poly)-Surface.area(Surface.clip(root_poly,source_hex)))>0.0000001:return C.fail("root_hex","Plant roots leave their declared source cell.")
	for id in near_rows(canopy_poly,reserved_bins):
		if Surface.area(Surface.clip(canopy_poly,reserved[id].polygon))>0.0000001:return C.fail("reserved_canopy","Plant canopy overlaps a reserved full cell or NPC footprint.")
	var envelope:Array=Surface.expanded(solid_poly,CLEARANCE)
	for id in near_rows(envelope,edge_bins):
		if Surface.segment_hits(edges[id].a,edges[id].b,envelope):return C.fail("corridor","Plant stem or low foliage infringes an existing actor corridor.")
	for id in near_rows(solid_poly,solid_bins):
		if Surface.area(Surface.clip(solid_poly,solids[id]))>0.0000001:return C.fail("solid_overlap","Plant solids overlap an earlier deterministic plant.")
	var root_support:Dictionary=surface.support(root_poly,.55,.04,DRY)
	if not root_support.ok:return C.fail("root_support","Plant root footprint has no complete dry support within fixed slope bounds.")
	var canopy_support:Dictionary=surface.support(canopy_poly,2.0,65536.0,DRY)
	if not canopy_support.ok:return C.fail("canopy_dry_coverage","Full projected canopy has a wet or unsupported interior.")
	if not woody:
		var low_support:Dictionary=surface.support(solid_poly,.30,.016,DRY)
		if not low_support.ok:return C.fail("low_support","Low foliage cannot fit the fixed ground slope/embed bounds.")
		root_support=low_support
	position.y=Surface.floor_q(float(root_support.min_height)-.003-float(measurement.minimum_y)*height_)
	var canopy_min:float=INF
	for vertex in measurement.canopy_vertices:canopy_min=minf(canopy_min,(position+basis*vertex).y)
	if woody and canopy_min<float(canopy_support.max_height)+.005:return C.fail("canopy_terrain","A woody canopy would intersect the local terrain envelope.")
	var plant:Dictionary={"id":"vegetation:v3:"+context_hash.substr(0,16)+":"+candidate.key.replace(",","_")+":"+str(candidate.slot),"hex":[cell.q,cell.r],"biome":cell.biome,"asset_id":kind,"position":row(position),"radius":radius,"height":height_,"yaw":yaw,"tint":Surface.quantize(.94+.10*unit(seed,5)),"root_footprint":Surface.as_json(root_poly),"solid_footprint":Surface.as_json(solid_poly),"canopy_footprint":Surface.as_json(canopy_poly),"solid_envelope":Surface.as_json(envelope),"support":root_support,"canopy_support":canopy_support,"solid_kind":"stem" if woody else "low_foliage","visual_bounds":bounds_(measurement.full_vertices,basis,position),"far_bounds":bounds_(measurement.far_vertices,basis,position),"root_bounds":bounds_(measurement.root_vertices,basis,position),"canopy_ground_gap":Surface.floor_q(canopy_min-float(canopy_support.max_height))}
	plant=C.normalized(plant);plant["row_hash"]=C.digest(plant);return {"ok":true,"plant":plant}
static func validate(manifest:Variant,source:Dictionary,built:Dictionary,nav:RefCounted,placement_result:Dictionary,origin_hex:Array,npc_reservations:Array=[]) -> Dictionary:
	if not manifest is Dictionary or not C.safe(manifest) or manifest.get("schema_version")!=ID or manifest.get("profile_id")!=PROFILE:return C.fail("VEGETATION_SCHEMA","Unsupported vegetation manifest/profile.")
	if not manifest.get("plants") is Array or manifest.plants.size()>MAX_PLANTS or C.bytes(manifest).to_utf8_buffer().size()>MAX_MANIFEST_BYTES:return C.fail("VEGETATION_BOUNDS","Vegetation manifest exceeds its fixed record or byte budget.")
	var copied:Dictionary=manifest.duplicate(true);var supplied:Variant=copied.get("vegetation_hash","");copied.erase("vegetation_hash")
	if not supplied is String or supplied.length()!=64 or C.digest(copied)!=supplied:return C.fail("VEGETATION_HASH","Vegetation changed after source admission.")
	var regenerated:Dictionary=build(source,built,nav,placement_result,origin_hex,npc_reservations)
	if not regenerated.ok:return regenerated
	if C.bytes(regenerated.manifest)!=C.bytes(manifest):return C.fail("VEGETATION_REPRODUCE","Vegetation cannot be reproduced exactly from its source and reservations.")
	return regenerated
