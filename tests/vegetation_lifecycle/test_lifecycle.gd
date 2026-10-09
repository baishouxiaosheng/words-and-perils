extends SceneTree
## Requires the patched scripts over a v23 project. Does NOT launch main/UI.
## Actual natural_v2 assets/catalog/shore support; fixture-only same-source swaps.
const View=preload("res://tests/vegetation_lifecycle/fixture_view.gd")
const Board=preload("res://tests/vegetation_lifecycle/fixture_board.gd")
const Shore=preload("res://view/integrated_ecology_world/natural_shorelines/shore_layer.gd")
const Profile=preload("res://view/integrated_ecology_world/tabs_style/profile.gd")
const Selection=preload("res://view/playable_build/entity_selection.gd")
const Catalog=preload("res://view/playable_build/entity_catalog.gd")
const Canonical=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:Array=[]
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->void:
	checks.append({"name":label_,"passed":value})
	if not value:failures+=1;printerr("VEGETATION_FAIL ",label_)
func frames(count:int=2)->void:
	for i in range(count):await process_frame
func fallback_counts(view:Node3D)->Array:
	var result:Array=[]
	for group in view.tree_groups:result.append(group.instance.multimesh.visible_instance_count)
	return result
func live_bindings(view:Node3D,selection:Node3D)->bool:
	for row in view.natural_shorelines.canopy_adjustments:
		if not is_instance_valid(row.mi) or row.mi.get_parent()!=view.whole_canopies:return false
	for row in view.natural_shorelines.canopy_group_counts:
		if row.group not in view.whole_canopies.groups:return false
	for entry in selection.rows.values():
		if not is_instance_valid(entry.near) or not is_instance_valid(entry.far) or entry.near.get_parent()!=view.whole_canopies or entry.far.get_parent()!=view.whole_canopies:return false
	return true
func selected_transform(selection:Node3D,id:String)->Transform3D:
	var row:Dictionary=selection.rows[id]
	return row.near.multimesh.get_instance_transform(row.index)
func geometry_digest(crowns:Node3D)->String:
	var bytes:=PackedByteArray()
	for group in crowns.groups:
		for node in [group.near,group.far]:bytes.append_array(node.multimesh.mesh.get_faces().to_byte_array())
	return bytes.hex_encode().sha256_text()
func pick_selected(view:Node3D,selection:Node3D,id:String)->bool:
	var entry:Dictionary=selection.rows[id]
	view.overview=false;view.target=entry.current.origin+Vector3(0,.2,0)
	view.pitch=1.2;view.yaw=.2;view.distance=8;view.camera.size=2;view._update_camera()
	var transform_:Transform3D=entry.near.global_transform*entry.current
	var faces:PackedVector3Array=entry.near.multimesh.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var screen:Vector2=view.camera.unproject_position(transform_*((faces[i]+faces[i+1]+faces[i+2])/3.0))
		var hits:Array=selection.pick(screen)
		if not hits.is_empty() and hits[0].reference.id==id:return true
	return false
func install_shore(view:Node3D)->Node3D:
	var shore:=Shore.new();view.content_root.add_child(shore);shore.source_view=view
	shore.manifest=JSON.parse_string(FileAccess.get_file_as_string(Shore.ROOT+"manifest.json"))
	# Selection/source-array sentinels only. Real terrain/topology/pixel parity is
	# a separate actual-main gate; this fixture does not claim to build terrain.
	shore.old_picks=[{"source":"legacy-fixture"}];shore.new_picks=[{"source":"v03-fixture"}]
	var prepared:Dictionary=shore.prepare_canopy_bindings(view.whole_canopies)
	check(prepared.get("ok",false),"actual shoreline support accepts actual natural_v2 identity")
	if not prepared.get("ok",false):return null
	view.natural_shorelines=shore;shore.commit_canopy_bindings(prepared);shore.set_active(true)
	return shore
func run()->void:
	root.size=Vector2i(1280,720)
	var guard:=Timer.new();guard.one_shot=true;guard.wait_time=120;root.add_child(guard)
	guard.timeout.connect(func():printerr("VEGETATION_TIMEOUT");quit(2));guard.start()
	var board:=Board.new();root.add_child(board)
	var view:=View.new();board.add_child(view);board.world_view=view;board.camera=view.camera
	view.budget=1;view._update_budget()
	check(view.visible_instances==1,"original fallback budget is active before canopy success")
	var original_counts:=fallback_counts(view);var original_children:=view.content_root.get_child_count()
	check(not view.enable_world_canopies("v1"),"shipped absent v1 fails initial load (no invented success)")
	check(not is_instance_valid(view.whole_canopies) and view.vegetation_root.visible and view.total_instances==8 and view.content_root.get_child_count()==original_children,"failed initial load preserves fallback and attaches no candidate")
	check(view.enable_world_canopies("natural_v2"),"actual shipped natural_v2 loads")
	check(view.tree_groups.size()==2 and view.vegetation_root.get_child_count()==2,"original fallback nodes/data are intentionally retained")
	check(fallback_counts(view)==original_counts,"active whole canopy skips hidden fallback writes")
	var current=view.whole_canopies;var builds:int=view.candidate_builds
	check(view.enable_world_canopies("natural_v2") and view.whole_canopies==current and view.candidate_builds==builds,"same variant is allocation-free no-op")
	var shore:=install_shore(view)
	if shore==null:quit(1);return
	var profile:Node=Profile.attach_to(view);view.clear_daylight_profile=profile
	check(profile.last_error.is_empty() and profile.enabled,"actual contact profile initializes with verified natural_v2 field")
	check(Catalog.ready(),"actual immutable source catalog accepts shipped bundle")
	if not Catalog.ready():quit(1);return
	var tree_id:=Catalog.tree_id(1148)
	if tree_id.is_empty():
		for i in range(view.whole_canopies.total_count):
			tree_id=Catalog.tree_id(i)
			if not tree_id.is_empty():break
	var descriptor:Dictionary=Catalog.descriptor(tree_id)
	board.world_state={"world_id":"fixture-canopy-lifecycle","state_version":0,"generated_world":{"bundle_id":descriptor.bundle_id},"hexes":{"%d,%d"%descriptor.hex:{}},"environment_entities":{}}
	var selection:=Selection.new();board.add_child(selection)
	check(selection.configure(board),"real selection consumer configures on actual records")
	var reference:=Catalog.make_reference(tree_id,board.world_state);selection.select(reference)
	check(not reference.is_empty() and selection.selected_reference==reference,"real catalog identity is selected without a turn")
	var source_save:=Canonical.bytes(board.world_state)
	var source_picks:=Canonical.bytes(view.picks)
	var natural_geometry:=geometry_digest(view.whole_canopies)
	var rows_before:PackedFloat32Array=view.whole_canopies.instance_rows
	var selected_before:=selected_transform(selection,tree_id)
	check(pick_selected(view,selection,tree_id),"actual near-mesh ray selection resolves source tree before replacement")
	current=view.whole_canopies
	for invalid_variant in ["v1","unknown_variant","fixture_load_failure","fixture_wrong_instance_source","fixture_wrong_anchor_source"]:
		var count_before:=view.content_root.get_child_count()
		check(not view.enable_world_canopies(invalid_variant),"reject "+invalid_variant)
		check(view.whole_canopies==current and view.content_root.get_child_count()==count_before and selection.selected_reference==reference and selected_transform(selection,tree_id)==selected_before and Canonical.bytes(view.picks)==source_picks and live_bindings(view,selection),"failed later replacement preserves canopy/source/selection: "+invalid_variant)
	check(view.enable_world_canopies("natural_v2") and view.whole_canopy_error.is_empty(),"successful no-op clears obsolete load error")
	# Deliberately invalidate one retained group's center. A hidden base sort or
	# range loop would fail; the active whole layer must never touch this sentinel.
	view.tree_groups[0].center="HIDDEN_FALLBACK_MUST_NOT_BE_SORTED"
	for cycle in range(2):
		var old_root=weakref(view.whole_canopies)
		var old_material:ShaderMaterial=view.whole_canopies.groups[0].near.material_override
		var old_material_ref=weakref(old_material)
		check(view.enable_world_canopies("fixture_same_source_"+str(cycle)),"fixture-only same-source replacement commits cycle "+str(cycle))
		check(live_bindings(view,selection) and selection.selected_reference==reference and selected_transform(selection,tree_id)==selected_before,"all node consumers synchronously rebind cycle "+str(cycle))
		check(pick_selected(view,selection,tree_id),"actual near-mesh ray selection survives replacement cycle "+str(cycle))
		check(not profile.tree_shaders.has(old_material),"profile drops retired material key cycle "+str(cycle))
		check(view.whole_canopies.instance_rows==rows_before and geometry_digest(view.whole_canopies)==natural_geometry,"exact instance records and near/far mesh vertices preserved cycle "+str(cycle))
		old_material=null;current=null
		await frames()
		check(old_root.get_ref()==null and old_material_ref.get_ref()==null,"retired whole root/material actually released cycle "+str(cycle))
		for enabled in [false,true]:
			view.set_trees(enabled);view.budget=cycle;view.camera.size=28 if enabled else 5;view.target=Vector3(cycle*5,0,0);view._update_budget()
			check(view.whole_canopies.visible==enabled and not view.vegetation_root.visible and fallback_counts(view)==original_counts,"tree/budget/camera updates never reactivate or mutate hidden fallback")
		shore.set_active(false)
		check(view.picks==shore.old_picks and view.compact_root.visible and live_bindings(view,selection),"coastline fallback keeps live replacement bindings")
		shore.set_active(true)
		check(Canonical.bytes(view.picks)==source_picks and selected_transform(selection,tree_id)==selected_before,"coastline reactivation restores exact support and selected transform")
	check(Canonical.bytes(board.world_state)==source_save,"all presentation operations preserve complete fixture state bytes")
	# Sparse gameplay pose remains applied after a renderer or support replacement.
	board.world_state.environment_entities[tree_id]={"id":tree_id,"state":{"posture":"fallen","revision":1,"ground_blocking":true}}
	board.world_state.state_version=1;selection.sync_state(board.world_state)
	reference=Catalog.make_reference(tree_id,board.world_state);selection.select(reference)
	var fallen_transform:=selected_transform(selection,tree_id);source_save=Canonical.bytes(board.world_state)
	check(view.enable_world_canopies("natural_v2"),"return from fixture alias to actual natural_v2")
	check(selected_transform(selection,tree_id)==fallen_transform and selection.selected_reference==reference and profile.contact_strength==0.0,"replacement restores sparse fallen pose/selection and disabled stale contact field")
	shore.set_active(false)
	var fallback_fallen:=selected_transform(selection,tree_id)
	var source_row:int=selection.rows[tree_id].row
	check(selection.rows[tree_id].base.origin.y==view.whole_canopies.instance_rows[source_row*10+1],"fallback base height comes from immutable source row")
	for repeat in range(3):
		check(selection.configure(board) and selected_transform(selection,tree_id)==fallback_fallen and selection.selected_reference==reference and Canonical.bytes(board.world_state)==source_save,"fallen fallback configure is pose/reference/state-idempotent repeat "+str(repeat))
	# The same picker may be configured for another owner; old subscriptions must
	# be released, and reconfiguration there must use that view's immutable row.
	var other_board:=Board.new();root.add_child(other_board)
	var other_view:=View.new();other_board.add_child(other_view);other_board.world_view=other_view;other_board.camera=other_view.camera
	check(other_view.enable_world_canopies("natural_v2"),"second independent view loads actual natural_v2")
	var other_shore:=install_shore(other_view)
	if other_shore==null:quit(1);return
	other_board.world_state=board.world_state.duplicate(true);other_shore.set_active(false)
	check(selection.configure(other_board) and live_bindings(other_view,selection) and selected_transform(selection,tree_id)==fallback_fallen,"picker reconfigures to second view with exact fallen fallback pose")
	var callback:=Callable(selection,"_canopy_renderer_changed")
	check(not view.whole_canopies_changed.is_connected(callback) and not view.canopy_support_changed.is_connected(callback) and other_view.whole_canopies_changed.is_connected(callback) and other_view.canopy_support_changed.is_connected(callback),"reconfigure disconnects both old subscriptions and owns both new subscriptions")
	for repeat in range(2):
		check(selection.configure(other_board) and selected_transform(selection,tree_id)==fallback_fallen and selection.selected_reference==reference and Canonical.bytes(other_board.world_state)==source_save,"second-view fallback configure remains pose/reference/state-idempotent repeat "+str(repeat))
	shore.set_active(true)
	check(selection.observed_world_view==other_view and live_bindings(other_view,selection),"old-view support events cannot steal the reconfigured picker")
	check(selection.configure(board) and live_bindings(view,selection) and selected_transform(selection,tree_id)==fallen_transform and selection.selected_reference==reference,"picker returns to original active shoreline and exact fallen pose")
	check(Canonical.bytes(board.world_state)==source_save and Canonical.bytes(other_board.world_state)==source_save,"cross-view configure preserves both authoritative fixture-state byte strings")
	other_board.queue_free();await frames()
	shore.set_active(false);shore.set_active(true)
	check(selected_transform(selection,tree_id)==fallen_transform and Canonical.bytes(board.world_state)==source_save,"coastline roundtrip preserves fallen pose and exact state bytes")
	# Known separate gap: profile off/on can restore the static contact field while
	# an unchanged-state sync is skipped. Do not force last_entity_signature here
	# or label that artificial resync a natural profile-toggle regression pass.
	var view_ref=weakref(view);var selection_ref=weakref(selection);var profile_ref=weakref(profile)
	board.queue_free();await frames(3)
	check(view_ref.get_ref()==null and selection_ref.get_ref()==null and profile_ref.get_ref()==null,"scene exit releases renderer and every observer")
	var reentered:=View.new();root.add_child(reentered)
	check(reentered.enable_world_canopies("natural_v2") and reentered.whole_canopies.total_count==rows_before.size()/10,"scene reentry builds unchanged complete canopy records")
	reentered.queue_free();await frames()
	guard.stop()
	print("VEGETATION_LIFECYCLE ",checks.size()-failures,"/",checks.size()," fixture-only successful replacement; shipped v1 absent")
	print(JSON.stringify({"checks":checks,"failures":failures,"actual_main":false,"geometry_source":"complete shipped natural_v2","v1_success_tested":false,"known_out_of_scope_gap":"Profile off/on stale-contact suppression is not validated; no forced signature reset"}))
	quit(0 if failures==0 else 1)
