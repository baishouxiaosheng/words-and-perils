extends SceneTree
## Actual production Coast Main, real picked references, GUI windows and installed Tween.
## Deterministic Tween sampling is not OS mouse input or rendered visual acceptance.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle=preload("res://view/playable_build/world_bundle.gd")
const Catalog=preload("res://view/attention_catalog.gd")
const MAIN_SHA="d759e33bbe942f9935a72cbf0d99495296259311bc0f221cb642b3a8ea85939a"
const MODULE_SHA="60835b0672a4426faf747c57e6a21617ebbf87e08c68b8cb3244175f813448e7"
var checks:=0
var failures:Array=[]
var samples:Array=[]
var captures:Array=[]
var scene:Control
var motion:Node
var before_authority:=""
var signal_events:=0
var eligibility:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->bool:
	checks+=1
	if not ok:failures.append(label_);printerr("SELECTION_MAIN_FAIL ",label_)
	return ok
func frames(count:int=3)->void:
	for _i in range(count):await process_frame
func tick()->void:motion.call("_process",0.0)
func dispatch(candidate:Dictionary)->void:
	# Candidate is obtained from the actual board's ray/mesh picker. A single
	# selected result exercises the same connected production signal and avoids
	# deliberately opening the overlap chooser over the animation being tested.
	scene.board.focus_candidates.emit([candidate],Vector2.ZERO);signal_events+=1;tick()
func clear_selection()->void:
	scene.clear_target_button.pressed.emit();signal_events+=1;tick()
func pick_subject(kind:String,id:String,node:Node3D)->Dictionary:
	for child in node.find_children("*","MeshInstance3D",true,false):
		if not child.is_visible_in_tree() or child.mesh==null or child.name=="SelectedEdgeGlow":continue
		var box:AABB=child.mesh.get_aabb()
		for offset in [Vector3.ZERO,Vector3(0.0,0.25,0.0),Vector3(0.25,0.0,0.0),Vector3(-0.25,0.0,0.0)]:
			var world:Vector3=child.global_transform*(box.get_center()+box.size*offset)
			var point:Vector2=scene.board.camera.unproject_position(world)
			for row in scene.board.pick_focus(point):
				if row.get("reference",{}).get("kind")==kind and row.reference.get("id")==id:return row
	return {}
func geometry(root_node:Node3D)->Dictionary:
	var result:Dictionary={}
	for child in root_node.find_children("*","MeshInstance3D",true,false):
		if child.name=="SelectedEdgeGlow":continue
		result[str(root_node.get_path_to(child))]={"transform":child.transform,"mesh_id":child.mesh.get_instance_id() if child.mesh!=null else 0}
	return result
func sample(label_:String,root_node:Node3D,body:MeshInstance3D)->void:
	samples.append({"label":label_,"root_transform":str(root_node.transform),"mesh_transform":str(body.transform),"mesh_world_position":[body.global_position.x,body.global_position.y,body.global_position.z],"world_version":scene.playtest.state_copy().state_version,"selected_focus":scene.selected_focus.duplicate(true)})
func capture(label_:String)->void:
	var directory:=OS.get_environment("FOGBANK_SELECTION_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name()=="headless" or not (label_.begins_with("actor_") or label_.begins_with("item_")):return
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var path:=directory.path_join(label_+".png")
	if not check(not FileAccess.file_exists(path),"optional capture output is new "+label_):return
	if not check(image!=null and not image.is_empty() and image.save_png(path)==OK,"optional actual viewport capture "+label_):return
	captures.append({"path":path.get_file(),"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height()})
func start_peak(candidate:Dictionary,root_node:Node3D,label_:String,height:float)->Dictionary:
	dispatch(candidate)
	if not check(motion._motion_root==root_node and not motion._parts.is_empty() and motion._motion_tween!=null,label_+": actual picked signal starts installed motion on actual visual children"):return {}
	var body:MeshInstance3D=motion._parts[0].node
	var baseline:Transform3D=motion._parts[0].base
	var root_baseline:Transform3D=root_node.transform
	var tween:Tween=motion._motion_tween;tween.pause()
	sample(label_+"_t0",root_node,body)
	await capture(label_+"_t0")
	# Existing selected-actor lift and carried-item following may legally run
	# between render captures; compare only this SelectionMotion step.
	root_baseline=root_node.transform
	var position_before:Vector3=body.global_position
	tween.custom_step(motion.HOP_DURATION*0.5)
	sample(label_+"_peak",root_node,body)
	check(body.transform!=baseline and absf((body.global_position-position_before).y-height)<0.012,label_+": production Tween reaches bounded visible peak")
	check(root_node.transform==root_baseline,label_+": gameplay/display root is not translated or scaled")
	await capture(label_+"_peak")
	return {"node":body,"baseline":baseline,"root_baseline":root_baseline,"tween":tween}
func complete_motion(row:Dictionary,root_node:Node3D,label_:String)->void:
	var root_before:Transform3D=root_node.transform
	var tween:Tween=row.tween;tween.custom_step(motion.HOP_DURATION*0.5+0.001)
	check(row.node.transform==row.baseline and motion._motion_tween==null and motion._parts.is_empty(),label_+": actual Tween callback restores exact baseline and releases animation")
	check(root_node.transform==root_before,label_+": final animation step leaves current root exact")
	sample(label_+"_end",root_node,row.node)
	await capture(label_+"_end")
func catalog_capture(reference:Dictionary,node:Node3D)->Dictionary:
	# Coast's picker uses immutable mesh BVHs and reads current transforms, not
	# AttentionCatalog. This additional capture uses the unchanged production
	# AttentionCatalog on the real scene mesh to check the refresh seam's result;
	# it is not a claim that a V3/legacy capture path ran in this Coast test.
	var catalog:=Catalog.new();catalog.capture(reference,"actual selected mesh",node,true)
	var row:Dictionary=catalog.subjects.get(str(reference.kind)+":"+str(reference.id),{})
	return {"parts":row.get("parts",[]),"local_bounds":row.get("local_bounds",AABB())}
func same_catalog(actual:Dictionary,expected:Dictionary)->bool:
	if actual.parts.is_empty() or actual.parts.size()!=expected.parts.size():return false
	if not actual.local_bounds.is_equal_approx(expected.local_bounds):return false
	for index in range(actual.parts.size()):
		var a:Dictionary=actual.parts[index];var b:Dictionary=expected.parts[index]
		if a.prototype!=b.prototype or not a.transform.is_equal_approx(b.transform) or not a.inverse.is_equal_approx(b.inverse) or not a.bounds.is_equal_approx(b.bounds):return false
	return true
func run()->void:
	var expected:=OS.get_environment("FOGBANK_SELECTION_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/")!=expected:
		printerr("SELECTION_MAIN_REFUSED isolated user directory mismatch");quit(2);return
	if FileAccess.file_exists("user://r24_coast_adventure_save.json") or FileAccess.file_exists("user://r24_coast_adventure_save.json.narration.json"):
		printerr("SELECTION_MAIN_REFUSED fresh test user directory required");quit(2);return
	if not check(FileAccess.get_sha256("res://main.gd")==MAIN_SHA and FileAccess.get_sha256("res://view/tabletop_interaction/selection_motion.gd")==MODULE_SHA,"exact combined API/P1 WASD selection Main and module"):
		quit(2);return
	root.gui_embed_subwindows=true;root.size=Vector2i(1280,720)
	scene=Main.instantiate();root.add_child(scene);current_scene=scene;await frames(6)
	if not check(scene.coast_mode and scene.playtest!=null and Bundle.ready(),"actual Main admits production Coast bundle"):
		finish();return
	var state:Dictionary=scene.playtest.state_copy();var world:Dictionary=Bundle.document("catalog")
	check(state.hexes.size()==1801 and state.world_id==world.world_id and state.actors.actor_player.scene_id=="scene_coast" and scene.playtest.engine.rule_id()=="coast_release/v1","actual 1801-cell bundle identity and production Coast rules")
	motion=scene.get_node_or_null("SelectionMotion")
	if not check(motion!=null and motion.get_script().resource_path=="res://view/tabletop_interaction/selection_motion.gd" and scene.get_node_or_null("WASDCameraPan")!=null,"both actual presentation modules installed by combined Main"):
		finish();return
	# Only automatic observation is paused; installed production _process reads
	# actual Main selection/window state. Real created Tweens are sampled through
	# their native custom_step, not a manual call to an animation formula.
	motion.set_process(false);scene.goal.release_focus();root.gui_release_focus();scene.board.focus_player();await frames();tick()
	eligibility={"host_visible":scene.is_visible_in_tree(),"host_can_process":scene.can_process(),"board_visible":scene.board.is_visible_in_tree(),"board_input_enabled":scene.board.is_processing_input(),"root_focused":root.has_focus(),"windows":motion._windows.size()}
	if not check(motion.call("_allowed"),"actual Main windows/input state permit selection feedback"):
		finish();return
	before_authority=C.bytes(scene.playtest.engine.save_data())
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured(),"fresh Main offline with no keys or role configuration")
	var actor:Node3D=scene.board.token_nodes.actor_player
	var actor_hit:=pick_subject("actor","actor_player",actor)
	if not check(not actor_hit.is_empty(),"actual Coast mesh picker finds actor_player"):
		finish();return
	var actor_row:Dictionary=await start_peak(actor_hit,actor,"actor",motion.ACTOR_HOP)
	if actor_row.is_empty():finish();return
	var peak:Transform3D=actor_row.node.transform
	dispatch(actor_hit)
	check(motion._motion_tween==actor_row.tween and actor_row.node.transform==peak,"repeated actual selection signal neither stacks nor restarts")
	await complete_motion(actor_row,actor,"actor")
	clear_selection();check(scene.selected_focus.is_empty(),"real Clear target button clears Main selection")
	# Select an actual independently rendered source-bound item, with its own mesh.
	var item:Node3D;var item_hit:Dictionary={};var item_id:=""
	for id in scene.board.creative_view.item_nodes:
		var candidate:Node3D=scene.board.creative_view.item_nodes[id].node
		if not candidate.is_visible_in_tree():continue
		var hit:=pick_subject("item",str(id),candidate)
		if not hit.is_empty():item=candidate;item_hit=hit;item_id=str(id);break
	if not check(item!=null and not item_hit.is_empty() and state.items.has(item_id),"actual independent item mesh and source-bound pick reference exist"):
		finish();return
	var item_before:=geometry(item)
	var item_row:Dictionary=await start_peak(item_hit,item,"item",motion.ITEM_HOP)
	if item_row.is_empty():finish();return
	var scale_ratio:float=item_row.node.transform.basis.get_scale().length()/item_row.baseline.basis.get_scale().length()
	check(scale_ratio>1.039 and scale_ratio<1.041,"actual item mesh receives only the specified four-percent swell")
	await complete_motion(item_row,item,"item")
	check(geometry(item)==item_before,"all real item meshes and shared mesh identities restore exactly")
	clear_selection()
	actor_row=await start_peak(actor_hit,actor,"cancel",motion.ACTOR_HOP)
	if actor_row.is_empty():finish();return
	clear_selection();check(actor_row.node.transform==actor_row.baseline and motion._parts.is_empty(),"real Clear target event cancels and restores current hop")
	actor_row=await start_peak(actor_hit,actor,"menu",motion.ACTOR_HOP)
	if actor_row.is_empty():finish();return
	scene.tools_menu.get_popup().popup(Rect2i(20,20,300,300))
	check(actor_row.node.transform==actor_row.baseline and motion._parts.is_empty(),"actual PopupMenu visibility synchronously cancels hop")
	tick();check(not motion.call("_allowed"),"actual open menu blocks selection animation")
	scene.close_tool_menus();await frames();tick()
	check(motion._motion_tween==null,"menu close does not replay consumed selection")
	# Warm selected glow before baseline so newly created selection shells are not
	# mistaken for a cache mismatch. Compare same selected state on both sides.
	scene.refresh_world(false);tick()
	var catalog_before:=catalog_capture(scene.selected_focus,actor)
	var geometry_before:=geometry(actor)
	clear_selection();actor_row=await start_peak(actor_hit,actor,"refresh",motion.ACTOR_HOP)
	if actor_row.is_empty():finish();return
	var pick_cache:Dictionary=scene.board.entity_selection.mesh_bounds.duplicate(true)
	scene.refresh_world(false)
	check(actor_row.node.transform==actor_row.baseline and motion._parts.is_empty(),"actual Main refresh seam restores mesh synchronously before renderer refresh")
	check(geometry(actor)==geometry_before,"refresh does not freeze visual offset into actual actor geometry")
	check(same_catalog(catalog_capture(scene.selected_focus,actor),catalog_before),"production AttentionCatalog recapture of real selected mesh preserves parts and local bounds")
	check(scene.board.entity_selection.mesh_bounds==pick_cache,"actual Coast immutable mesh-bound cache unchanged by refresh")
	tick();check(motion._motion_tween==null,"same-world refresh does not replay old selection")
	clear_selection()
	var origin:Array=state.actors.actor_player.hex;var destination:Array=[]
	for offset in [[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]:
		var next:Array=[int(origin[0])+offset[0],int(origin[1])+offset[1]]
		var preview:Dictionary=scene.playtest.movement_preview(next)
		if preview.get("ok",false) and preview.get("route",[]).size()>1:destination=next;break
	if not check(destination.size()==2,"production movement preview supplies a legal adjacent destination"):
		finish();return
	scene.on_hex_selected(Vector2i(destination[0],destination[1]));signal_events+=1;tick()
	check(scene.selected_focus.get("kind")=="tile" and scene.movement_preview.get("ok",false) and scene.movement_preview.route.size()>1,"real tile selection populates existing authoritative read-only route preview")
	if not check(not motion._route_nodes.is_empty() and motion._route_nodes.size()<=motion.MAX_ROUTE_PULSES and motion._route_tween!=null,"installed motion adds bounded markers over existing route segments"):
		finish();return
	var route_geometry:=geometry(scene.board.route_preview)
	var route_tween:Tween=motion._route_tween;route_tween.pause();route_tween.custom_step(0.2)
	check(geometry(scene.board.route_preview)==route_geometry,"route feedback leaves actual preview geometry untouched")
	clear_selection();check(motion._route_nodes.is_empty() and motion._route_tween==null,"real clear event cancels route markers")
	check(C.bytes(scene.playtest.engine.save_data())==before_authority,"all selection/Tween/menu/refresh/preview events leave complete Engine position resources RNG turn history byte-exact")
	check(not scene.runtime_ai.connection_enabled and not scene.runtime_ai.client.any_role_configured() and not scene.runtime_ai.busy(),"selection route never configured keys or began API work")
	finish()
func finish()->void:
	var report:Dictionary={"schema":"selection_motion_real_main_events/v1","ok":failures.is_empty(),"checks":checks,"failures":failures,"pid":OS.get_process_id(),"display_backend":DisplayServer.get_name(),"main_sha256":FileAccess.get_sha256("res://main.gd"),"module_sha256":FileAccess.get_sha256("res://view/tabletop_interaction/selection_motion.gd"),"initial_eligibility":eligibility,"production_signal_events":signal_events,"samples":samples,"captures":captures,"network_calls":0,"network_claim_basis":"fresh runtime remains disabled and no role configured; test issues no action or HTTP request, not packet capture","scope":"actual1801 Coast Main, picked actor/item references, installed native Tween, actual menu and refresh; controlled observation/Tween clock, no OS mouse or visual acceptance","attention_cache_scope":"Coast native mesh bounds unchanged; production AttentionCatalog additionally recaptures actual selected scene mesh after Main refresh, no V3 or legacy-world claim"}
	var path:=OS.get_environment("FOGBANK_SELECTION_TEST_REPORT")
	if path.is_empty():path="user://selection_motion_main_events.json"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f==null:printerr("SELECTION_MAIN_REPORT_WRITE_FAILED");quit(2);return
	f.store_string(JSON.stringify(report,"\t"));f.close()
	if is_instance_valid(scene):scene.free()
	print("SELECTION_MAIN_EVENTS_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
