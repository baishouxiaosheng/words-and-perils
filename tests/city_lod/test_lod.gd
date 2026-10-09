extends "res://tests/city_lod/profile.gd"
var entries:Array=[]
func gather(view:Node3D)->void:
	entries.append_array(view._lod_entries)
	for extra in view._additional_views:gather(extra)
func run()->void:
	if out.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(out);OS.set_environment("FOGBANK_QA_WINDOWED","1")
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	app=load("res://main.tscn").instantiate();root.add_child(app);await frames(24)
	var view=app.board.settlement_view
	gather(view);var source_before:=C.digest(app.playtest.engine.save_data())
	check(entries.size()==21,"all21 existing authored models have one active mesh LOD pair")
	check(view.lod_report().asset_failures.is_empty(),"all existing LOD1 hashes load correctly")
	var initial_ids:Array=[]
	for subject in view.selection_nodes():initial_ids.append(subject.id)
	var transforms:Array=[]
	for entry in entries:transforms.append(entry.node.global_transform)
	camera(4.0);await frames(4)
	var focal:Dictionary=entries[0]
	check(not focal.low,"closest manor keeps complete roof and trim")
	var scale_constant:float=focal.pixels*4.0
	camera(scale_constant/36.0);await frames(3);check(not focal.low,"full detail stays full in32-44px hysteresis band")
	camera(scale_constant/27.0);await frames(3);check(focal.low,"below32px switches to authored simplified mesh")
	camera(scale_constant/36.0);await frames(3);check(focal.low,"simplified detail stays simplified in hysteresis band")
	camera(scale_constant/48.0);await frames(3);check(not focal.low,"above44px restores exact original mesh")
	var switches:int=view.lod_report().switches
	await frames(20);check(view.lod_report().switches==switches,"unchanged camera does not repeat swaps")
	# A selected district's existing shells must follow a mesh change in either direction.
	var subject:Dictionary={}
	for candidate in view.selection_nodes():
		if candidate.node.is_ancestor_of(focal.node): subject=candidate;break
	check(not subject.is_empty(), "focal model belongs to a selectable district")
	app.board.attention_glow.select_actor(subject.id,{subject.id:subject.node})
	check(focal.node.get_node_or_null("SelectedEdgeGlow")!=null,"selected district creates a real model outline")
	for target_size in [100.0,4.0,100.0,4.0]:
		camera(target_size);await frames(4)
		for entry in entries:
			var shell=entry.node.get_node_or_null("SelectedEdgeGlow")
			if shell!=null:check(shell.mesh==entry.node.mesh,"selected city shell follows displayed mesh")
	app.board.attention_glow.clear()
	camera(100.0);await frames(3)
	check(view.lod_report().simplified_models==21,"all distant modules keep silhouettes in simplified representation")
	for entry in entries:
		check(entry.node.mesh==entry.far,"one active MeshInstance uses actual LOD1 mesh")
		var faces:PackedVector3Array=entry.node.mesh.get_faces()
		var a:Vector3=entry.node.global_transform*faces[0];var b:Vector3=entry.node.global_transform*faces[1];var c:Vector3=entry.node.global_transform*faces[2]
		var normal:Vector3=(b-a).cross(c-a).normalized();var center:Vector3=(a+b+c)/3.0
		var hit:Dictionary=app.board.entity_selection.hit_node(entry.node,center+normal*.2,-normal)
		check(not hit.is_empty(),"current LOD mesh stays ray-pickable without physics")
	camera(4.0);await frames(4)
	for i in range(entries.size()):check(entries[i].node.global_transform.is_equal_approx(transforms[i]),"LOD never refits or recenters authored module")
	var final_ids:Array=[]
	for current in view.selection_nodes():final_ids.append(current.id)
	check(initial_ids==final_ids,"all site district gate selection identities unchanged")
	var r:Dictionary=view.report()
	for site in r.sites:check(site.lod.tracked_models==site.authored_models,"per-site LOD diagnostics do not double-count other settlements")
	# Synthetic missing/hash-bad descriptor tests never mutate actual assets.
	var test_view=load("res://view/playable_build/settlement_view.gd").new()
	var model:=Node3D.new();var high:=MeshInstance3D.new();model.add_child(high);high.mesh=BoxMesh.new()
	var fake:="res://assets/city_districts/models/synthetic_missing.glb"
	test_view._asset_rows[fake]={"lod1_glb":"lod1/not_present.glb","lod1_sha256":"bad"}
	check(test_view._load_lod_mesh(fake,model,high)==null,"missing LOD refuses replacement and retains original")
	check(test_view._lod_asset_failures.size()==1,"missing LOD emits one explicit failure")
	check(test_view._load_lod_mesh(fake,model,high)==null and test_view._lod_asset_failures.size()==1,"failed LOD is cached with no repeated load attempts")
	var bad:="res://assets/city_districts/models/synthetic_hash.glb"
	test_view._asset_rows[bad]={"lod1_glb":"lod1/rich_manor_lod1.glb","lod1_sha256":"wrong"}
	check(test_view._load_lod_mesh(bad,model,high)==null,"wrong LOD hash cannot replace model")
	model.free();test_view.free()
	check(C.digest(app.playtest.engine.save_data())==source_before,"zoom selection and failure probes preserve complete authority bytes")
	report["lod"]=view.lod_report();save();app.queue_free();await frames(4)
	print("CITY_LOD_TEST_COMPLETE checks=",report.checks.size()," failures=",failures);quit(0 if failures==0 else 1)
