extends "res://view/integrated_ecology_world/performance_variant/world_view66.gd"
## Real canopy lifecycle and source files, without building terrain/topology/UI.
var candidate_builds:=0
var mountain_refreshes:=0
func _ready()->void:
	clear_daylight_enabled=false
	content_root=Node3D.new();add_child(content_root)
	ground_root=Node3D.new();content_root.add_child(ground_root)
	water_root=Node3D.new();content_root.add_child(water_root)
	grid_root=Node3D.new();content_root.add_child(grid_root)
	vegetation_root=Node3D.new();content_root.add_child(vegetation_root)
	compact_root=Node3D.new();content_root.add_child(compact_root)
	camera=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6;camera.current=true
	camera.position=Vector3(0,12,10);camera.look_at(Vector3.ZERO)
	ground_material=ShaderMaterial.new();ground_material.shader=preload("res://view/integrated_ecology_world/performance_variant/ground_shore66.gdshader")
	water_material=ShaderMaterial.new();water_material.shader=preload("res://view/integrated_ecology_world/water.gdshader")
	grid_material=ShaderMaterial.new();grid_material.shader=preload("res://view/integrated_ecology_world/grid.gdshader")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/integrated_ecology_world_20261002/performance_variant/world_canopies_v2/manifest.json"))
	manifest={"source_identity":{"mesh":{"sha256":source.source_mesh_sha256},"ecology_pending":{"sha256":source.source_ecology_sha256}}}
	for i in range(2):
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=BoxMesh.new();mm.instance_count=4
		var mi:=MultiMeshInstance3D.new();mi.multimesh=mm;vegetation_root.add_child(mi)
		var material:=ShaderMaterial.new();material.shader=preload("res://view/ecology_preview/vegetation_surface.gdshader");mi.material_override=material
		tree_groups.append({"instance":mi,"count":4,"center":Vector3(i,0,0)});total_instances+=4
func _new_world_canopies()->Node3D:
	candidate_builds+=1
	return preload("res://tests/vegetation_lifecycle/fixture_canopies.gd").new()
func apply_faceted_mountains()->void:
	mountain_refreshes+=1
