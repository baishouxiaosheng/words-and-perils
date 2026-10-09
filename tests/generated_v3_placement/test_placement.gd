extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const Geometry=preload("res://view/generated_v3_runtime/geometry.gd")
const Nav=preload("res://view/generated_v3_runtime/navigation.gd")
const Source=preload("res://view/generated_v3_adventure/source.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Overlay=preload("res://core/generated_v3_placement/navigation_overlay.gd")
const View=preload("res://view/generated_v3_settlement/settlement_view.gd")
var checks=0
var failures: Array=[]
var results: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func _initialize() -> void:call_deferred("run")
func write_json(name: String,value: Variant) -> void:
	var file=FileAccess.open("res://artifacts/generated_v3_placement/"+name,FileAccess.WRITE);file.store_string(C.bytes(value));file.close()
func run() -> void:
	fixtures()
	for seed in [726381,0,20261005]:
		for radius in [4,12]:
			for recipe in G.RECIPES:
				var label="%s_r%d_%s"%[seed,radius,recipe];var generated=G.generate(seed,radius,recipe)
				check(generated.ok,label+" generated")
				if not generated.ok:continue
				var original=C.bytes(generated.source);var built=Geometry.build(generated.source)
				check(built.ok,label+" built")
				if not built.ok:continue
				var arrays=built.ground_mesh.surface_get_arrays(0);var original_vertices=arrays[Mesh.ARRAY_VERTEX].to_byte_array();var original_indices=arrays[Mesh.ARRAY_INDEX].to_byte_array()
				var nav=Nav.new();check(nav.build(generated.source,built).ok,label+" base nav")
				var spawn=Source.choose_spawn(generated.source,nav);check(spawn.ok,label+" deterministic source spawn")
				if not spawn.ok:continue
				var original_graph=C.bytes(nav.allowed);var placement=Planner.build(generated.source,built,nav,spawn.hex)
				check(placement.ok,label+" fixed village eligibility")
				if not placement.ok:results.append({"case":label,"failure":placement});continue
				var manifest: Dictionary=placement.manifest;var again=Planner.build(generated.source,built,nav,spawn.hex)
				check(again.ok and C.bytes(again.manifest)==C.bytes(manifest),label+" deterministic repeat")
				var roundtrip=JSON.parse_string(C.bytes(manifest));check(C.bytes(roundtrip)==C.bytes(manifest),label+" exact JSON round trip")
				if C.bytes(roundtrip)!=C.bytes(manifest):write_json("roundtrip_"+label+".json",roundtrip)
				check(manifest.buildings.size()==3 and manifest.settlements.size()==1 and manifest.settlements[0].footprint_hexes.size()==1,label+" one hex three buildings")
				check(manifest.blocked_edges.size()>0 and manifest.roads.size()==1,label+" physical obstruction and road")
				check(not generated.source.cells[Planner.key(manifest.settlements[0].center_hex)].river and not generated.source.cells[Planner.key(manifest.settlements[0].entry_hex)].river,label+" source river cell and entry reserved")
				check(C.bytes(generated.source)==original and C.bytes(nav.allowed)==original_graph,label+" source biomes and base graph unchanged")
				check(built.ground_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()==original_vertices and built.ground_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].to_byte_array()==original_indices,label+" exact native geometry unchanged")
				var overlay=Overlay.new();check(overlay.build(nav,manifest).ok,label+" overlay admission")
				check(Planner.distances(overlay.allowed,Planner.key(spawn.hex)).size()==spawn.component.size(),label+" origin component preserved")
				for blocked in manifest.blocked_edges:
					check(nav.step(blocked.from,blocked.to).ok and not overlay.step(blocked.from,blocked.to).ok,label+" real building blocks prior route")
					check(not overlay.step(blocked.to,blocked.from).ok and overlay.route_points([blocked.from,blocked.to]).is_empty(),label+" symmetric route obstruction")
				var route=manifest.roads[0].route_hexes;check(overlay.step(route[0],route[1]).ok and overlay.route_points(route).size()>=2,label+" reachable clear road")
				check(not overlay.plan({},route[0],99).ok,label+" mismatched world rejected")
				for building in manifest.buildings:
					var support=placement.surface.support(building.footprint,.18,.06,.01);check(support.ok,label+" full building footprint dry support")
					var gaps=placement.surface.plane_gaps(building.footprint,building.foundation_plane);check(gaps.ok and gaps.min_gap>=.0029 and gaps.max_gap<=building.support_limits.max_foundation_gap+.00005,label+" exact full foundation residual")
				if seed==726381:
					check(Planner.validate(roundtrip,generated.source,built,nav,spawn.hex).ok,label+" roundtrip readmission")
					var tampered=manifest.duplicate(true);tampered.buildings[0].position[0]+=.25;tampered.erase("placement_hash");tampered.placement_hash=C.digest(tampered)
					check(not Planner.validate(tampered,generated.source,built,nav,spawn.hex).ok,label+" rehashed geometry tamper rejected")
				if seed==726381 and radius==4 and recipe=="coastal_range":
					# Synthetic semantic mask fixture, never admitted as a generated map.
					# Height/mesh stay unchanged; every logical river cell is reserved.
					var all_river: Dictionary=generated.source.duplicate(true)
					for cell in all_river.cells:all_river.cells[cell].river=true
					all_river.erase("content_hash");all_river.content_hash=C.digest(all_river)
					var synthetic_built: Dictionary=built.duplicate();synthetic_built.source_hash=all_river.content_hash
					var synthetic_nav=Nav.new();check(synthetic_nav.build(all_river,synthetic_built).ok,"all-river synthetic geometry retained")
					var unavailable=Planner.build(all_river,synthetic_built,synthetic_nav,spawn.hex)
					check(not unavailable.ok and unavailable.code=="PLACEMENT_UNAVAILABLE","all-river mask fails closed without terrain or seed fallback")
					check(unavailable.diagnostics.rejected.get("PLACEMENT_RIVER_RESERVED",0)==unavailable.diagnostics.examined_cells and unavailable.diagnostics.examined_cells>0,"all-river no eligible candidate rejection is explicit")
					check(C.bytes(generated.source)==original and C.bytes(nav.allowed)==original_graph,"negative fixture preserves real source and navigation")
				var row={"case":label,"source_hash":generated.source.content_hash,"geometry_hash":built.geometry_hash,"placement_hash":manifest.placement_hash,"spawn":spawn.hex,"site":manifest.settlements[0].center_hex,"entry":manifest.settlements[0].entry_hex,"blocked_edges":manifest.blocked_edges.size(),"diagnostics":placement.diagnostics};results.append(row)
				write_json("source_"+label+".json",generated.source);write_json("mesh_"+label+".json",built.geometry);write_json("placement_"+label+".json",manifest);write_json("nav_"+label+".json",overlay.export_data(spawn.hex))
	write_json("placement_report.json",{"checks":checks,"failures":failures,"cases":results});print("V3 PLACEMENT ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
func quad(x0: float,x1: float,z0: float,z1: float,height_callable: Callable) -> Array:
	var p: Array=[]
	for v in [[x0,z0],[x1,z0],[x1,z1],[x0,z1]]:p.append(Vector3(v[0],height_callable.call(v[0],v[1]),v[1]))
	return [[p[0],p[1],p[2]],[p[0],p[2],p[3]]]
func fixture_surface(triangles: Array) -> RefCounted:
	var vertices=PackedVector3Array();var indices=PackedInt32Array()
	for triangle in triangles:
		for p in triangle:indices.append(vertices.size());vertices.append(p)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(vertices.to_byte_array());var id_=hash.finish().hex_encode()
	var surface=Surface.new();check(surface.build(mesh,id_).ok,"synthetic surface identity");return surface
func fixtures() -> void:
	var target=[[-.8,-.8],[.8,-.8],[.8,.8],[-.8,.8]]
	var flat=fixture_surface(quad(-1,1,-1,1,func(_x,_z):return 1.0))
	check(flat.support(target,.01,.01).ok,"full interior flat support")
	check(not flat.support([[0,0],[1,1],[0,1],[1,0]],1,1).ok,"self crossing footprint rejected")
	check(not flat.support([[0,0],[2,0],[2,2],[0,2]],1,1).ok,"missing coverage rejected")
	var duplicate=quad(-1,0,-1,1,func(_x,_z):return 1.0);duplicate.append_array(duplicate.duplicate(true))
	var masked_hole=fixture_surface(duplicate);check(not masked_hole.support(target,1,1).ok,"duplicate overlap cannot hide uncovered half")
	var wet_tris: Array=[];var coords=[-1.0,-.15,.15,1.0]
	for x in range(3):
		for z in range(3):wet_tris.append_array(quad(coords[x],coords[x+1],coords[z],coords[z+1],func(a,b):return -.1 if absf(a)<=.151 and absf(b)<=.151 else 1.0))
	var wet=fixture_surface(wet_tris);check(not wet.support(target,99,99).ok,"dry perimeter cannot hide wet interior")
	var sloped=fixture_surface(quad(-1,1,-1,1,func(x,_z):return 2.0+x));check(not sloped.support(target,.18,99).ok,"interior slope limit")
	var tilted=fixture_surface(quad(-1,1,-1,1,func(x,_z):return 2.0+x*.1));check(not tilted.support(target,.18,.06).ok,"foundation spread limit")
	var disk=Surface.expanded([Vector2.ZERO],.35)
	for i in disk.size():check(absf(Surface.cross2(disk[(i+1)%disk.size()]-disk[i],-disk[i]))/(disk[(i+1)%disk.size()]-disk[i]).length()>=.35-.000001,"circumscribed actor clearance")
	check(flat.plane_gaps(target,[0,0,1.01]).ok,"full polygon support plane residual")
