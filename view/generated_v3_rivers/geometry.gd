extends RefCounted
## One exact new ground/water bundle for rendering, picking and movement.
## Appearance repacking must leave both physical mesh identities unchanged.
const PROFILE = "structured_rivers_v1"
const ID = "generated_v3_physical_river_geometry/v1"
const Builder = preload("res://view/generated_v3_rivers/structured_builder.gd")
const Appearance = preload("res://view/generated_v3_runtime/appearance.gd")
const BaseGeometry = preload("res://view/generated_v3_runtime/geometry.gd")
const WaterQueries = preload("res://view/generated_v3_rivers/water_queries.gd")
const Ground = preload("res://view/generated_v3_rivers/ground.gdshader")
const Water = preload("res://view/generated_v3_runtime/water.gdshader")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")

static func mesh_hash(mesh: ArrayMesh) -> String:
	if mesh==null or mesh.get_surface_count()!=1:return ""
	var arrays: Array=mesh.surface_get_arrays(0)
	var vs: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var expanded:=PackedVector3Array()
	if ids.is_empty():expanded=vs
	else:
		for index in ids:
			if index<0 or index>=vs.size():return ""
			expanded.append(vs[index])
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(expanded.to_byte_array())
	return hashing.finish().hex_encode()

static func build(source: Dictionary, profile: String=PROFILE) -> Dictionary:
	if profile!=PROFILE:return C.fail("RIVER_RENDER_PROFILE","Only the explicit physical-river profile is admitted here.")
	var started: int=Time.get_ticks_usec()
	var result: Dictionary=Builder.build(source)
	if not result.get("ok",false):return C.fail(str(result.get("error_code","RIVER_MESH")),str(result.get("message","Physical river construction failed.")))
	if not result.get("ground_mesh") is ArrayMesh or not result.get("water_mesh") is ArrayMesh or not result.get("river_manifest") is Dictionary:
		return C.fail("RIVER_BUILD_BUNDLE","River builder did not return both physical meshes and the exact manifest.")
	if mesh_hash(result.ground_mesh)!=result.get("geometry_hash") or mesh_hash(result.water_mesh)!=result.get("water_hash"):
		return C.fail("RIVER_BUILD_HASH","Actual emitted ground or water differs from the builder identity.")
	var query:=WaterQueries.new();var checked: Dictionary=query.build(result.water_mesh,result.water_hash)
	if not checked.ok:return checked
	var arrays: Array=result.ground_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var bank_vertices: Dictionary={};var kinds: Array=result.data.get("face_kinds",[])
	for face in range(kinds.size()):
		if not str(kinds[face]).begins_with("river_bank"):continue
		for i in range(3):bank_vertices[indices[face*3+i]]=true
	var colors:=PackedColorArray();var uv2:=PackedVector2Array();var bank_uv:=PackedVector2Array();var appearance:=Appearance.new(source)
	for i in range(vertices.size()):
		var p: Vector3=vertices[i];var sample: Dictionary=appearance.sample(p)
		if not sample.get("valid",false):return C.fail("RIVER_APPEARANCE","A physical mesh vertex has no persisted source climate sample.")
		var color: Color=sample.color;var bank_mask: float=0.0
		if bank_vertices.has(i):
			var contact: Dictionary=query.point_contact(Vector2(p.x,p.z),0.0)
			if not contact.ok:return contact
			# Mark only the exact wet-side bank vertices. Outer bank vertices retain
			# a zero mask so the narrow physical fringe does not spread over dry fans.
			if contact.intersects:bank_mask=1.0
		colors.append(color);uv2.append(sample.weights);bank_uv.append(Vector2(bank_mask,0.0))
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_TEX_UV]=bank_uv
	var ground:=ArrayMesh.new();ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if mesh_hash(ground)!=result.geometry_hash:return C.fail("RIVER_PAINT_HASH","Adding terrain appearance changed its exact physical geometry.")
	var water_arrays: Array=result.water_mesh.surface_get_arrays(0)
	var water_vertices: PackedVector3Array=water_arrays[Mesh.ARRAY_VERTEX]
	var water_colors:=PackedColorArray()
	for _p in water_vertices:water_colors.append(Color("557cba").srgb_to_linear())
	water_arrays[Mesh.ARRAY_COLOR]=water_colors
	var water:=ArrayMesh.new();water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,water_arrays)
	if mesh_hash(water)!=result.water_hash:return C.fail("RIVER_PAINT_HASH","Adding water appearance changed its exact physical geometry.")
	var ground_material:=ShaderMaterial.new();ground_material.shader=Ground;ground_material.set_shader_parameter("surface_kind",0)
	var water_material:=ShaderMaterial.new();water_material.shader=Water
	var low: Vector3=vertices[0];var high: Vector3=vertices[0]
	for p in vertices:low=low.min(p);high=high.max(p)
	var manifest: Dictionary=result.river_manifest
	if str(manifest.get("layout_hash","")).length()!=64 or str(manifest.get("surface_profile_hash","")).length()!=64:
		return C.fail("RIVER_LAYOUT_HASH","The graph and solved river surface must have separate exact identities.")
	var metrics: Dictionary=result.metrics.duplicate(true)
	metrics["bundle_ms"]=(Time.get_ticks_usec()-started)/1000.0
	metrics["positions_and_indices_unchanged_by_appearance"]=true
	metrics["rivers_rendered"]=true;metrics["coastline_perturbation"]=false
	metrics["water_contact_policy"]=query.diagnostics.duplicate(true)
	return {"ok":true,"source_hash":source.content_hash,"renderer_profile":PROFILE,"river_profile":manifest.profile_id,"geometry_hash":result.geometry_hash,"water_hash":result.water_hash,"river_layout_hash":manifest.layout_hash,"river_surface_hash":manifest.surface_profile_hash,"river_manifest":manifest,"ground_mesh":ground,"water_mesh":water,"ground_material":ground_material,"water_material":water_material,"geometry":result.data,"data":result.data,"bounds":{"min":[low.x,low.y,low.z],"max":[high.x,high.y,high.z]},"camera_focus":[0.0,0.3,0.0],"metrics":metrics}

static func create_view(built: Dictionary, _use_chunks: bool=false) -> Node3D:
	var root:=Node3D.new();root.name="PhysicalRiverTerrain"
	for layer in ["ground","water"]:
		var instance:=MeshInstance3D.new();instance.name=layer;instance.mesh=built[layer+"_mesh"];instance.material_override=built[layer+"_material"];instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(instance)
	return root
static func install_lighting(parent: Node3D) -> Dictionary:return BaseGeometry.install_lighting(parent)
