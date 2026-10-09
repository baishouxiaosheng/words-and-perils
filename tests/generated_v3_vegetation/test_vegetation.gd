extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator=preload("res://core/world_generation_v3/generator.gd")
const Source=preload("res://view/generated_v3_npc/source.gd")
const Assets=preload("res://core/generated_v3_vegetation/assets.gd")
const Planner=preload("res://core/generated_v3_vegetation/planner.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
var checks:int=0
var failures:Array=[]
var cases:Array=[]
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> bool:
	checks+=1
	if not value:failures.append(label);printerr("VEGETATION_FAIL ",label)
	return value
func save(name:String,value:Variant) -> void:
	var file=FileAccess.open("res://artifacts/generated_v3_vegetation/"+name,FileAccess.WRITE);file.store_string(C.bytes(value));file.close()
func vector_rows(vertices:PackedVector3Array) -> Array:
	var rows:Array=[]
	for v in vertices:rows.append([v.x,v.y,v.z])
	return rows
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/generated_v3_vegetation"))
	var assets:Dictionary=Assets.build()
	if not check(assets.ok,"unchanged original assets native build"):printerr(assets);quit(1);return
	var counts:Dictionary={"temperate":77,"tropical":91,"sapling":77,"shrub":63,"tuft":49,"reed":49};var buffers:Dictionary={}
	for kind in Assets.KINDS:
		check(int(assets.catalog.assets[kind].triangles)==counts[kind],kind+" exact native source recipe triangles")
		check(int(assets.catalog.assets[kind].far_triangles)==(counts[kind] if kind in ["tuft","reed"] else 7),kind+" declared native far triangles")
		check(assets.catalog.assets[kind].same_projected_footprint,kind+" full/far footprint preserved")
		buffers[kind]={"full":vector_rows(assets.measurements[kind].full_vertices),"far":vector_rows(assets.measurements[kind].far_vertices),"root":vector_rows(assets.measurements[kind].root_vertices),"solid":vector_rows(assets.measurements[kind].solid_vertices),"canopy":vector_rows(assets.measurements[kind].canopy_vertices)}
	save("native_assets.json",{"catalog":assets.catalog,"buffers":buffers})
	for radius in [4,12]:
		for recipe in Generator.RECIPES:
			var label:String="726381_r%d_%s"%[radius,recipe];var source=Source.new();var admitted:Dictionary=source.admit(Generator.generate(726381,radius,recipe).source)
			if not check(admitted.ok,label+" frozen village source admitted"):printerr(admitted);continue
			var source_bytes:String=C.bytes(source.data);var graph_bytes:String=C.bytes(source.navigation.allowed);var arrays:Array=source.renderer_bundle.ground_mesh.surface_get_arrays(0);var mesh_bytes:PackedByteArray=arrays[Mesh.ARRAY_VERTEX].to_byte_array();var indices:PackedByteArray=arrays[Mesh.ARRAY_INDEX].to_byte_array()
			var origin:Array=source.placement_result.manifest.origin_hex
			var result:Dictionary=Planner.build(source.data,source.renderer_bundle,source.navigation,source.placement_result,origin,source.npc_reservations)
			if not check(result.ok,label+" source-bound sparse profile builds"):printerr(result);continue
			var manifest:Dictionary=result.manifest
			check(manifest.plants.size()<=1024 and manifest.statistics.full_triangles<=80000,label+" hard instance and geometry budget")
			check(not manifest.plants.is_empty(),label+" usable sparse vegetation is emitted")
			check(result.surface==source.placement_result.surface,label+" shared exact native support index")
			check(C.bytes(source.data)==source_bytes and C.bytes(source.navigation.allowed)==graph_bytes,label+" source biome and movement graph unchanged")
			check(source.renderer_bundle.ground_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()==mesh_bytes and source.renderer_bundle.ground_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].to_byte_array()==indices,label+" exact terrain buffers unchanged")
			var wire:Variant=JSON.parse_string(C.bytes(manifest));check(C.bytes(wire)==C.bytes(manifest),label+" exact manifest JSON roundtrip")
			if C.bytes(wire)!=C.bytes(manifest):save("roundtrip_mismatch_"+label+".json",wire)
			var again:Dictionary=Planner.validate(wire,source.data,source.renderer_bundle,source.navigation,source.placement_result,origin,source.npc_reservations)
			check(again.ok,label+" deterministic source reproduction and readmission")
			if not again.ok:printerr(again)
			var node_budget:Dictionary={};var min_root_gap:float=INF
			for plant in manifest.plants:
				var row_copy:Dictionary=plant.duplicate(true);row_copy.erase("row_hash");check(C.digest(row_copy)==plant.row_hash,label+" exact row identity")
				check(plant.biome==source.data.cells[Planner.key(plant.hex)].biome,label+" declared root biome truthful")
				check(not source.data.cells[Planner.key(plant.hex)].river and not source.data.cells[Planner.key(plant.hex)].ocean,label+" river/ocean source root reserved")
				var p:Array=plant.position;var basis=Basis(Vector3.UP,plant.yaw).scaled(Vector3(plant.radius,plant.height,plant.radius));var position=Vector3(p[0],p[1],p[2]);var polygon:Array=Surface.as_points(plant.canopy_footprint);var root_polygon:Array=Surface.as_points(plant.root_footprint)
				var fits:bool=true
				for v in assets.measurements[plant.asset_id].full_vertices:
					if not Surface.segment_hits(Surface.xz(position+basis*v),Surface.xz(position+basis*v),polygon):fits=false;break
				check(fits,label+" every actual full vertex within admitted canopy envelope")
				fits=true
				for v in assets.measurements[plant.asset_id].far_vertices:
					if not Surface.segment_hits(Surface.xz(position+basis*v),Surface.xz(position+basis*v),polygon):fits=false;break
				check(fits,label+" every actual far vertex within same admitted envelope")
				check(result.surface.support(root_polygon,.55,.04,.01).ok,label+" full native root area dry and supported")
				var bucket:String="%s_%d_%d"%[plant.asset_id,floori((p[0]+24)/16),floori((p[2]+24)/16)];node_budget[bucket]=true
				min_root_gap=minf(min_root_gap,float(plant.canopy_ground_gap))
			check(node_budget.size()<=64,label+" hard active instance batch budget")
			if not manifest.plants.is_empty():
				var bad:Dictionary=manifest.duplicate(true);bad.plants[0].position[0]+=.02;bad.plants[0].erase("row_hash");bad.plants[0].row_hash=C.digest(bad.plants[0]);bad.erase("vegetation_hash");bad.vegetation_hash=C.digest(bad)
				check(not Planner.validate(bad,source.data,source.renderer_bundle,source.navigation,source.placement_result,origin,source.npc_reservations).ok,label+" rehashed moved plant rejected")
			var reservations:Array=[]
			for reserved in result.audit.reserved:reservations.append({"id":reserved.id,"kind":reserved.kind,"polygon":Surface.as_json(reserved.polygon)})
			var corridors:Array=[]
			for edge in result.audit.corridors:corridors.append({"from":edge.from,"to":edge.to,"a":[edge.a.x,edge.a.y],"b":[edge.b.x,edge.b.y],"radius":Planner.CLEARANCE})
			save("source_"+label+".json",source.data);save("mesh_"+label+".json",source.renderer_bundle.geometry);save("nav_"+label+".json",source.navigation.export_data(origin));save("village_"+label+".json",source.placement_result.manifest);save("vegetation_"+label+".json",manifest);save("exclusions_"+label+".json",{"reserved":reservations,"corridors":corridors,"npc_reservations":source.npc_reservations})
			cases.append({"case":label,"statistics":manifest.statistics,"vegetation_hash":manifest.vegetation_hash,"diagnostics":result.diagnostics,"active_batches":node_budget.size(),"minimum_declared_canopy_gap":min_root_gap if is_finite(min_root_gap) else null})
			print("VEGETATION_CASE ",label," ",manifest.statistics," ",result.diagnostics)
	save("placement_report.json",{"checks":checks,"failures":failures,"cases":cases});print("V3 VEGETATION ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
