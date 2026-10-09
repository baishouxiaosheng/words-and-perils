extends RefCounted
## One native build is shared by rendering, picking and navigation.
## Explicit experimental physical profile. Original source/pipelines are never rewritten.
const ID="natural_coast_native_geometry_bundle/experimental2"
const PROFILE="natural_coast_shared_chain/experimental2"
const WATER_CLIP_PROFILE="exact_zero_endpoints_area_1e-12/v1"
const LegacySource=preload("res://view/generated_v3_adventure/source.gd")
const VERIFIED_SOURCES=["ddbfb153ea7278c355092f7b3d5daba4d42c4363f126fdcdaba8b59263cc8009","a7609ba12b6266f04d0417ce6916eb2b287a869a9e0106d10d8f4bac4c93e875"]
const Builder=preload("res://view/generated_v3_natural_coast/builder.gd")
const Appearance=preload("res://view/generated_v3_runtime/appearance.gd")
const Ground=preload("res://view/generated_v3_runtime/ground.gdshader")
const Water=preload("res://view/generated_v3_runtime/water.gdshader")
const Chunks=preload("res://view/mesh_chunks.gd")
static func build(source: Dictionary,profile: String=PROFILE) -> Dictionary:
	if profile!=PROFILE:return {"ok":false,"code":"V3_RENDER_PROFILE","errors":["This detached candidate only accepts its explicit experimental2 profile."]}
	if source.get("schema_version")!="coastal_source_v3/prototype1" or source.get("recipe_version")!="coastal_recipes/v2_tiny_remnant_cleanup" or source.get("board_radius") not in [4,12]:
		return {"ok":false,"code":"V3_RENDER_SOURCE","errors":["Expected the explicit verified v3 cleanup source, radius4 or12."]}
	var checked=LegacySource.validate_source(source)
	if not checked.get("ok",false):return checked
	if source.board_radius!=4 or source.content_hash not in VERIFIED_SOURCES:return {"ok":false,"code":"COAST_SOURCE_NOT_VERIFIED","errors":["Detached native stage currently admits only the two exact verified r4 inputs."]}
	var started=Time.get_ticks_usec()
	var built=Builder.build(source)
	if not built.ok:return {"ok":false,"code":built.get("error_code","V3_MESH"),"errors":[built.get("message","Native mesh construction failed.")]}
	var arrays=built.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors=PackedColorArray();var uv2=PackedVector2Array()
	var appearance=Appearance.new(source)
	for p in vertices:
		var sample=appearance.sample(p)
		if not sample.valid:return {"ok":false,"code":"V3_APPEARANCE_SAMPLE","errors":["A native mesh vertex has no source climate sample."]}
		colors.append(sample.color);uv2.append(sample.weights)
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var ground=ArrayMesh.new();ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var actual=ground.surface_get_arrays(0)
	if actual[Mesh.ARRAY_VERTEX].to_byte_array()!=vertices.to_byte_array() or actual[Mesh.ARRAY_INDEX].to_byte_array()!=arrays[Mesh.ARRAY_INDEX].to_byte_array():
		return {"ok":false,"code":"V3_PALETTE_GEOMETRY","errors":["Adding appearance attributes changed native geometry."]}
	var water=make_water(ground)
	var checked_water=validate_shared_sea(ground,water)
	if not checked_water.ok:return checked_water
	var ground_material=ShaderMaterial.new();ground_material.shader=Ground;ground_material.set_shader_parameter("surface_kind",0)
	var water_material=ShaderMaterial.new();water_material.shader=Water
	return {"ok":true,"source_hash":source.content_hash,"renderer_profile":profile,"geometry_hash":built.data.canonical_geometry_hash,"water_hash":water_hash(water),"water_clipper_profile":WATER_CLIP_PROFILE,"ground_mesh":ground,"water_mesh":water,"ground_material":ground_material,"water_material":water_material,"geometry":built.data,"bounds":built.data.bounds,"camera_focus":built.data.camera_focus,"metrics":{"builder_ms":built.data.construction.build_ms,"bundle_ms":(Time.get_ticks_usec()-started)/1000.0,"vertices":vertices.size(),"triangles":built.data.construction.triangles,"appearance_id":Appearance.ID,"source_climate_interpolation":"cell-center barycentric, normalized boundary samples","vertex_positions_unchanged":false,"physical_geometry_changed":true,"experimental_only":true,"water_level":0.0,"rivers_rendered":false,"settlements_rendered":false}}
static func clip_water(triangle: Array) -> Array:
	var result: Array=[];var previous: Vector3=triangle[-1]
	for point: Vector3 in triangle:
		if (previous.y<=0.0)!=(point.y<=0.0):
			# A zero endpoint already belongs to the exact shared ground/water edge.
			# Vector3.lerp at t=1 can shift it by one float32 ULP and emit slivers.
			if previous.y==0.0:result.append(previous)
			elif point.y==0.0:result.append(point)
			else:result.append(previous.lerp(point,-previous.y/(point.y-previous.y)))
		if point.y<=0.0:result.append(point)
		previous=point
	return result
static func make_water(mesh: ArrayMesh) -> ArrayMesh:
	var arrays=mesh.surface_get_arrays(0);var vs: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);var count=0
	for i in range(0,ids.size(),3):
		var polygon=clip_water([vs[ids[i]],vs[ids[i+1]],vs[ids[i+2]]])
		for j in range(1,polygon.size()-1):
			var a: Vector3=polygon[0];var b: Vector3=polygon[j];var c: Vector3=polygon[j+1]
			if absf((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))<0.000000000002:continue
			for p: Vector3 in [a,b,c]:
				surface.set_normal(Vector3.UP);surface.set_color(Color("557cba").srgb_to_linear());surface.add_vertex(Vector3(p.x,0.0,p.z));count+=1
	return surface.commit() if count>0 else null
static func create_view(built: Dictionary,use_chunks: bool=false) -> Node3D:
	var root=Node3D.new();root.name="NativeV3Terrain"
	for layer in ["ground","water"]:
		var mesh=built[layer+"_mesh"]
		if mesh==null:continue
		var material=built[layer+"_material"]
		if use_chunks:
			var parts=Chunks.split(mesh,6)
			for key in parts:
				var instance=MeshInstance3D.new();instance.name=layer+"_"+key;instance.mesh=parts[key];instance.material_override=material;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(instance)
		else:
			var instance=MeshInstance3D.new();instance.name=layer;instance.mesh=mesh;instance.material_override=material;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(instance)
	return root
static func install_lighting(parent: Node3D) -> Dictionary:
	var environment=WorldEnvironment.new();environment.name="V3ProductionEnvironment"
	var settings=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("bddfe4")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("c7def2");settings.ambient_light_energy=0.28
	environment.environment=settings;parent.add_child(environment)
	var light=DirectionalLight3D.new();light.name="V3ProductionSun";light.light_color=Color("fff4dd");light.light_energy=1.0;light.shadow_enabled=false;light.rotation_degrees=Vector3(-60,-34,0);parent.add_child(light)
	return {"environment":environment,"light":light,"ground_lighting":"exact existing generated matte shader; averaged mesh normals","shadow_enabled":false}

static func water_hash(mesh: ArrayMesh) -> String:
	var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	if mesh!=null:
		var arrays=mesh.surface_get_arrays(0);hash_.update(arrays[Mesh.ARRAY_VERTEX].to_byte_array())
	return hash_.finish().hex_encode()

static func water_triangle_key(points: Array) -> String:
	points.sort_custom(func(a,b):return a.x<b.x if a.x!=b.x else a.z<b.z)
	return PackedVector3Array(points).to_byte_array().hex_encode()
static func validate_shared_sea(ground: ArrayMesh,water: ArrayMesh) -> Dictionary:
	# This builder splits every shore at zero: sea is exactly the projection of
	# nonpositive ground faces, with no new shoreline intersection coordinates.
	var ga=ground.surface_get_arrays(0);var vs: PackedVector3Array=ga[Mesh.ARRAY_VERTEX];var ids: PackedInt32Array=ga[Mesh.ARRAY_INDEX];var expected={};var count=0
	for i in range(0,ids.size(),3):
		var a=vs[ids[i]];var b=vs[ids[i+1]];var c=vs[ids[i+2]]
		if minf(a.y,minf(b.y,c.y))<0 and maxf(a.y,maxf(b.y,c.y))>0:return {"ok":false,"code":"COAST_UNSPLIT_SEA","errors":["Ground has an unsplit zero crossing."]}
		if maxf(a.y,maxf(b.y,c.y))>0:continue
		var key_=water_triangle_key([Vector3(a.x,0,a.z),Vector3(b.x,0,b.z),Vector3(c.x,0,c.z)])
		expected[key_]=expected.get(key_,0)+1;count+=1
	if water==null:return {"ok":count==0,"code":"COAST_WATER_MISSING","expected_triangles":count}
	var wa=water.surface_get_arrays(0);var actual: PackedVector3Array=wa[Mesh.ARRAY_VERTEX];var wi=wa[Mesh.ARRAY_INDEX]
	if wi is PackedInt32Array and not wi.is_empty():return {"ok":false,"code":"COAST_WATER_INDEX_CONTRACT","errors":["Unexpected indexed sea emission."]}
	if actual.size()!=count*3:return {"ok":false,"code":"COAST_WATER_COUNT","expected_triangles":count,"actual_vertices":actual.size()}
	var minimum_area=INF
	for i in range(0,actual.size(),3):
		var a=actual[i];var b=actual[i+1];var c=actual[i+2]
		var cross_=(float(b.x)-a.x)*(float(c.z)-a.z)-(float(b.z)-a.z)*(float(c.x)-a.x)
		if a.y!=0 or b.y!=0 or c.y!=0 or cross_<=0:return {"ok":false,"code":"COAST_WATER_FACE","errors":["Nonzero, reversed or degenerate sea face."]}
		minimum_area=minf(minimum_area,cross_*0.5)
		var key_=water_triangle_key([a,b,c])
		if expected.get(key_,0)<=0:return {"ok":false,"code":"COAST_WATER_OFF_GROUND","errors":["A sea triangle is not the exact source face projection."]}
		expected[key_]-=1
	for remaining in expected.values():
		if remaining!=0:return {"ok":false,"code":"COAST_WATER_COVERAGE","errors":["A ground water face is missing."]}
	return {"ok":true,"exact_ground_partition":true,"triangles":count,"minimum_triangle_area":minimum_area,"water_clipper_profile":WATER_CLIP_PROFILE}
