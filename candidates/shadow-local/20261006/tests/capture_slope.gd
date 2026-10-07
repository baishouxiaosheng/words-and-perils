extends SceneTree
const Profile:=preload("../source/profile.gd")
const Proxy:=preload("../source/ridge_shadow_proxy.gd")
const Trees:=preload("../fixture/vegetation_meshes.gd")
var world:Node3D
var camera:Camera3D
var nodes:Array=[]
var report:Dictionary={}
var captures:Dictionary={}
var output:=""
const SlopeDepth:=preload("../source/slope_depth.gdshader")

func _initialize()->void:call_deferred("run")
func fail(message:String)->void:
	push_error(message);quit(1)
func material(shader:Shader)->ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=shader;return m
func mesh_from(rows:Array, kind:String)->ArrayMesh:
	var a:=[];a.resize(Mesh.ARRAY_MAX)
	var vs:=PackedVector3Array();var ns:=PackedVector3Array();var cs:=PackedColorArray();var uv:=PackedVector2Array();var uv2:=PackedVector2Array()
	for row:Array in rows:
		vs.append(Vector3(row[0],row[1],row[2]));ns.append(Vector3(row[3],row[4],row[5]))
		cs.append(Color(row[6],row[7],row[8],row[9]) if kind=="ground" else Color(row[6],row[7],0,1))
		if kind=="ground":uv.append(Vector2(row[10],row[11]));uv2.append(Vector2(row[12],row[13]))
	a[Mesh.ARRAY_VERTEX]=vs;a[Mesh.ARRAY_NORMAL]=ns;a[Mesh.ARRAY_COLOR]=cs
	if kind=="ground":a[Mesh.ARRAY_TEX_UV]=uv;a[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);return mesh
func add_mesh(mesh:Mesh, mat:Material, kind:String)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat;node.name=kind
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.set_meta("shadow_kind",kind)
	world.add_child(node);nodes.append(node);return node
func geometry_digest()->String:
	var states:Array=[]
	for node:GeometryInstance3D in nodes:
		var mesh:Mesh=node.multimesh.mesh if node is MultiMeshInstance3D else node.mesh
		states.append([node.transform,mesh.surface_get_arrays(0),node.multimesh.buffer if node is MultiMeshInstance3D else null])
	states.append([camera.transform,camera.size,camera.near,camera.far])
	return bytes_digest(var_to_bytes(states))
func bytes_digest(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()
func capture(name_:String)->void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var im:=root.get_texture().get_image()
	if im.get_size()!=Vector2i(1280,960):fail("Unexpected capture viewport "+str(im.get_size()));return
	if im.save_png(output+"/"+name_+".png")!=OK:fail("PNG save failed "+name_);return
	captures[name_]=bytes_digest(im.get_data())
	print("SHADOW_CAPTURE ",name_," ",captures[name_])
func run()->void:
	var args:=OS.get_cmdline_user_args()
	output=args[0] if args.size()>0 else ProjectSettings.globalize_path("res://evidence/manual")
	DirAccess.make_dir_recursive_absolute(output)
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixture/ridge.json"))
	world=Node3D.new();root.add_child(world)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("bddfe4")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("c7def2");env.ambient_light_energy=.28
	var we:=WorldEnvironment.new();we.environment=env;world.add_child(we)
	for setup:Array in [[Color("fff4dd"),1.0,Vector3(-48,-35,0)],[Color("a8c9f4"),.12,Vector3(-25,130,0)],[Color("d3efff"),.12,Vector3(-26,-130,0)]]:
		var light:=DirectionalLight3D.new();light.light_color=setup[0];light.light_energy=setup[1];light.rotation_degrees=setup[2];world.add_child(light)
	camera=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7.3;camera.near=.2;camera.far=22.0;camera.position=Vector3(5.6,8.1,28.2);camera.look_at(Vector3(5.6,.8,20.4));camera.current=true
	var atlas:=Image.new();atlas.load_png_from_buffer(FileAccess.get_file_as_bytes("res://fixture/visual_weights_v03.png"))
	var weights:=ImageTexture.create_from_image(atlas)
	var ground_mat:=material(preload("../fixture/ground.gdshader"))
	ground_mat.set_shader_parameter("visual_blend",1.0)
	ground_mat.set_shader_parameter("world_min",Vector2(-44.167295593006365,-38.5))
	ground_mat.set_shader_parameter("world_extent",Vector2(88.33459118601273,77.0))
	ground_mat.set_shader_parameter("visual_weights",weights)
	var contact:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixture/contact_manifest.json"))
	var field_raw:=FileAccess.get_file_as_bytes("res://fixture/contact_"+str(contact.file)).decompress(int(contact.decoded_bytes),FileAccess.COMPRESSION_GZIP)
	var field:=Image.create_from_data(int(contact.width),int(contact.height),false,Image.FORMAT_R8,field_raw);field.generate_mipmaps()
	ground_mat.set_shader_parameter("canopy_contact_field",ImageTexture.create_from_image(field))
	ground_mat.set_shader_parameter("contact_field_min",Vector2(contact.world_min_xz[0],contact.world_min_xz[1]))
	ground_mat.set_shader_parameter("contact_field_extent",Vector2(contact.world_extent_xz[0],contact.world_extent_xz[1]))
	ground_mat.set_shader_parameter("canopy_contact_strength",1.15)
	var ground:=add_mesh(mesh_from(data.ground,"ground"),ground_mat,"ground")
	var mountain_mat:=material(preload("../fixture/mountains.gdshader"))
	mountain_mat.set_shader_parameter("visual_weights",weights)
	for key in ["world_min","world_extent"]:mountain_mat.set_shader_parameter(key,ground_mat.get_shader_parameter(key))
	var mountain:=add_mesh(mesh_from(data.mountains,"mountain"),mountain_mat,"mountain")
	var buckets:Dictionary={}
	for row:Dictionary in data.trees:
		if not buckets.has(row.kind):buckets[row.kind]=[]
		buckets[row.kind].append(row.values)
	for kind:String in buckets:
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=Trees.make(kind);mm.instance_count=buckets[kind].size()
		for i in range(mm.instance_count):
			var v:Array=buckets[kind][i]
			mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,-v[5]).scaled(Vector3(v[3],v[4],v[3])),Vector3(v[0],v[1],v[2])))
			mm.set_instance_color(i,Color(v[6],v[6],v[6],1))
		var node:=MultiMeshInstance3D.new();node.name="real_canopies_"+kind;node.multimesh=mm
		node.material_override=material(preload("../fixture/vegetation.gdshader"));node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("shadow_kind","vegetation");world.add_child(node);nodes.append(node)
	var ma:Array=mountain.mesh.surface_get_arrays(0);var ga:Array=ground.mesh.surface_get_arrays(0)
	var support:=PackedVector3Array()
	for p:Array in data.ground_support:support.append(Vector3(p[0],p[1],p[2]))
	var candidate:Dictionary=Proxy.build(ma[Mesh.ARRAY_VERTEX],ma[Mesh.ARRAY_COLOR],support)
	if not candidate.ok:fail(str(candidate));return
	report.proxy=candidate.report
	report.geometry_before=geometry_digest()
	report.canopy_instances=data.trees.size()
	report.camera={"position":str(camera.position),"basis":str(camera.basis),"size":camera.size,"near":camera.near,"far":camera.far,"projection":"orthographic","viewport":[1280,960]}
	report.renderer=RenderingServer.get_current_rendering_method()
	report.device=RenderingServer.get_video_adapter_name()
	var profile:=Profile.new()
	# Fail closed on an unknown shader before mutating an earlier valid receiver.
	var unknown:=ShaderMaterial.new();unknown.shader=Shader.new();unknown.shader.code="shader_type spatial;"
	var original:Material=mountain.material_override;mountain.material_override=unknown
	var rejected:=not profile.install(world,nodes,candidate.mesh)
	report.unknown_shader_atomic_rejection=rejected and ground.material_override==ground_mat and not profile.installed
	mountain.material_override=original
	if not report.unknown_shader_atomic_rejection:fail("Material preflight was not atomic");return
	if "--validate-only" in args:
		report.scope="CPU fixture/proxy checks only; no rendered visual acceptance"
	else:
		await capture("A_tabs")
		if not profile.install(world,nodes,mountain.mesh):fail(profile.last_error);return
		await capture("B_uncut")
		profile.proxy.mesh=candidate.mesh
		await capture("B_clipped")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",2)
		await capture("B_raw_attenuation")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",3)
		await capture("B_form_only")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",0)
		# Establish a shadow-depth route independent of receiver color shading.
		var depth_material:=material(SlopeDepth)
		profile.proxy.material_override=depth_material
		await capture("B_depth_route_identity")
		report.depth_identity_matches_default=captures.B_clipped==captures.B_depth_route_identity
		depth_material.set_shader_parameter("depth_route_probe",true)
		await capture("B_depth_route_far_probe")
		profile.proxy.visible=false
		await capture("B_hidden_mountain_proxy")
		profile.proxy.visible=true
		depth_material.set_shader_parameter("depth_route_probe",false)
		report.custom_shadow_depth_route_proven=captures.B_depth_route_far_probe==captures.B_hidden_mountain_proxy and captures.B_depth_route_far_probe!=captures.B_depth_route_identity
		if not (report.depth_identity_matches_default and report.custom_shadow_depth_route_proven):fail("Custom caster shadow-depth route was not proven");return
		depth_material.set_shader_parameter("slope_bias_enabled",true)
		await capture("C_slope_depth")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",2)
		await capture("C_raw_attenuation")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",3)
		await capture("C_form_only")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",1)
		await capture("C_masks_form_cast_max")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",0)
		report.form_mask_unchanged=captures.B_form_only==captures.C_form_only
		depth_material.set_shader_parameter("slope_bias_enabled",false)
		await capture("B_depth_route_restored")
		report.caster_toggle_reversible=captures.B_depth_route_restored==captures.B_depth_route_identity
		profile.proxy.material_override=null
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",1)
		await capture("B_masks_form_cast_max")
		for row:Dictionary in profile.snapshots:row.styled.set_shader_parameter("shadow_debug",0)
		report.geometry_during=geometry_digest()
		profile.sun.shadow_enabled=false
		await capture("B_no_cast")
		profile.sun.shadow_enabled=true
		# Deliberately remove just the receiver-normal fix for a same-pose regression image.
		var tree_rows:Array=[]
		for row:Dictionary in profile.snapshots:
			if row.kind!="vegetation":continue
			var broken:=Shader.new()
			broken.code=row.styled.shader.code.replace('#include "palette.gdshaderinc"','#include "res://source/palette.gdshaderinc"').replace("MODELVIEW_NORMAL_MATRIX=mat3(VIEW_MATRIX)*Nw;","")
			var broken_mat:ShaderMaterial=row.styled.duplicate();broken_mat.shader=broken
			row.node.material_override=broken_mat;tree_rows.append(row)
		await capture("B_receiver_normal_control")
		for row:Dictionary in tree_rows:row.node.material_override=row.styled
		profile.uninstall()
		await capture("A_restored")
		report.geometry_after=geometry_digest()
		report.pixel_exact_A_restore=captures.A_tabs==captures.A_restored
		report.geometry_pose_camera_unchanged=report.geometry_before==report.geometry_during and report.geometry_before==report.geometry_after
		report.material_identity_restored=ground.material_override==ground_mat and mountain.material_override==mountain_mat
		report.cast_changes_real_render=captures.B_clipped!=captures.B_no_cast
		report.proxy_changes_real_render=captures.B_clipped!=captures.B_uncut
		report.scope="Independent slope-depth candidate; actual visual acceptance requires pixel analysis"
		report.candidate_changes_real_cast=captures.C_slope_depth!=captures.B_clipped
		report.captures=captures
		if not (report.pixel_exact_A_restore and report.geometry_pose_camera_unchanged and report.material_identity_restored and report.cast_changes_real_render and report.proxy_changes_real_render and report.form_mask_unchanged and report.caster_toggle_reversible and report.candidate_changes_real_cast):fail("Render invariant failed");return
	var f:=FileAccess.open(output+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("SHADOW_LOCAL_PASS ",JSON.stringify(report))
	world.free();quit(0)
