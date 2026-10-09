extends SceneTree
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Geometry=preload("res://view/generated_v3_runtime/geometry.gd")
const Navigation=preload("res://view/generated_v3_runtime/navigation.gd")
const Appearance=preload("res://view/generated_v3_runtime/appearance.gd")
var checks=0
var failures: Array=[]
var rows: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for radius in [4,12]:
		for recipe in G.RECIPES:
			var name="726381_r%d_%s"%[radius,recipe]
			var generated=G.generate(726381,radius,recipe)
			check(generated.ok,name+" generation")
			if not generated.ok:continue
			var source: Dictionary=generated.source;var original=C.bytes(source)
			var built=Geometry.build(source)
			check(built.ok,name+" geometry appearance bundle "+str(built.get("errors",[])))
			if not built.ok:continue
			var nav=Navigation.new();var admitted=nav.build(source,built)
			check(admitted.ok,name+" actual native navigation "+str(admitted.get("errors",[])))
			if not admitted.ok:continue
			check(C.bytes(source)==original,name+" immutable source")
			var arrays=built.ground_mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_COLOR].size()==arrays[Mesh.ARRAY_VERTEX].size(),name+" complete palette colors")
			check(arrays[Mesh.ARRAY_TEX_UV2].size()==arrays[Mesh.ARRAY_VERTEX].size(),name+" complete biome weights")
			var colors: Dictionary={};var soils=0;var greens=0
			for i in range(arrays[Mesh.ARRAY_COLOR].size()):
				colors[arrays[Mesh.ARRAY_COLOR][i].to_html()]=true
				if arrays[Mesh.ARRAY_TEX_UV2][i].x>0.75:soils+=1
				else:greens+=1
			check(colors.size()>4 and soils>0 and greens>0,name+" actual source-aware palette varies")
			var spawn: Array=[];var edge_count=0
			for key in nav.allowed:
				edge_count+=nav.allowed[key].size()
				if spawn.is_empty() and nav.allowed[key].size()>0:spawn=[source.cells[key].q,source.cells[key].r]
			check(not spawn.is_empty() and edge_count>0,name+" connected dry spawn available")
			var consistent=true;var route_samples=0
			for key in nav.allowed:
				var c: Dictionary=source.cells[key]
				for next in nav.allowed[key]:
					if key>=next:continue
					var n: Dictionary=source.cells[next]
					var points=nav.route_points([[c.q,c.r],[n.q,n.r]])
					consistent=consistent and points.size()>=2
					for i in range(points.size()):
						var hit=nav.height_at_xz(Vector2(points[i].x,points[i].z));route_samples+=1
						consistent=consistent and hit.ok and float(hit.get("height",-1))>Navigation.CLEARANCE and absf(float(hit.get("height",-1))-points[i].y)<0.00001
						if i>0:
							var mid: Vector3=points[i-1].lerp(points[i],0.5);var sample=nav.height_at_xz(Vector2(mid.x,mid.z));route_samples+=1
							consistent=consistent and sample.ok and absf(float(sample.get("height",-1))-mid.y)<0.00002
			check(consistent,name+" complete path polyline follows actual triangles")
			check(not nav.plan({"generated_world":{"content_hash":source.content_hash,"geometry_hash":"wrong"}},[0,0],4).ok,name+" wrong mesh rejected")
			var water_arrays=built.water_mesh.surface_get_arrays(0);var water_ok=true
			for p in water_arrays[Mesh.ARRAY_VERTEX]:water_ok=water_ok and p.y==0.0
			check(water_ok,name+" visible water exactly sea datum")
			if radius==12 and recipe=="coastal_range":
				var appearance=Appearance.new(source)
				for key in ["-1,-2","-5,5","-6,6"]:
					var c: Dictionary=source.cells[key];var point=Navigation.raw_center([c.q,c.r]);point.y=c.elevation
					var sample=appearance.sample(point)
					check(c.biome=="temperate_forest" and sample.color.g<Color("749b50").srgb_to_linear().g,name+" cool humid forest remains forest-colored "+key)
			write_json("artifacts/generated_v3_runtime/source_"+name+".json",source)
			write_json("artifacts/generated_v3_runtime/mesh_"+name+".json",built.geometry)
			write_json("artifacts/generated_v3_runtime/nav_"+name+".json",nav.export_data(spawn))
			rows.append({"case":name,"source_hash":source.content_hash,"geometry_hash":built.geometry_hash,"nav":nav.diagnostics,"render":built.metrics,"distinct_palette_colors":colors.size(),"soil_vertices":soils,"other_vertices":greens,"route_samples":route_samples,"spawn":spawn})
			print("V3 RUNTIME ",name," colors=",colors.size()," edges=",edge_count/2," samples=",route_samples," nav_ms=",nav.diagnostics.build_ms)
	write_json("artifacts/generated_v3_runtime/runtime_report.json",{"checks":checks,"failures":failures,"cases":rows,"engine":Engine.get_version_info().string})
	for failure in failures:printerr("FAIL ",failure)
	print("V3 RUNTIME ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
func write_json(path: String,value: Variant) -> void:
	var file=FileAccess.open("res://"+path,FileAccess.WRITE);file.store_string(C.bytes(value));file.close()
