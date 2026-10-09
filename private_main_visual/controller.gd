extends Node
## Private actual-Main bridge: complete registration and preflight precede writes.
const Audit=preload("material_audit.gd")
const Transaction=preload("transaction.gd")
const MainMaterials=preload("main_material_contract.gd")
const RidgeProxy=preload("ridge_shadow_proxy.gd")
var requested:=false
var desired_enabled:=false
var source_revision:=0
var resume_pending:=false
var waiting_for_source_ready:=false
var bounds_dirty:=false
var bound_entries:Array=[]
var bound_view:Node3D
func _ready()->void:process_priority=50
var transaction:RefCounted
var last_report:Dictionary={}
var last_error:=""
var host
var camera_snapshot:Dictionary={}
var registered_lights:Array=[]
var registered_contacts:Array=[]
var registered_roots:Array=[]
var suspended_profile:Node
func toggle(main:Node)->bool:
	host=main
	if desired_enabled:
		desired_enabled=false;waiting_for_source_ready=false;source_revision+=1;uninstall();requested=false;last_error="";return true
	var accepted:bool=enable(main)
	desired_enabled=accepted
	return accepted
func _exit_tree()->void:uninstall()
## Startup: the coast profile and canopies attach a few frames after Main is
## ready, so retry briefly instead of failing on the first, still-empty board.
func enable_by_default(main:Node,attempts:int=40)->void:
	host=main
	if desired_enabled or attempts<=0 or not is_inside_tree():return
	if not main.world_build_busy and not main.generated_start_busy and is_instance_valid(main.board) and main.board.is_inside_tree():
		var view=main.board.get("world_view")
		if is_instance_valid(view) and is_instance_valid(view.get("clear_daylight_profile")):
			if toggle(main):
				if is_instance_valid(main.display_menu):main.display_menu.set_item_checked(main.display_menu.get_item_index(main.PRIVATE_VISUAL_MENU_ID),true)
				return
			print("PALETTE_SHADOW startup not ready: ",last_error)
	get_tree().create_timer(.1).timeout.connect(enable_by_default.bind(main,attempts-1))
func before_world_change()->void:
	source_revision+=1;uninstall();requested=false
	if is_instance_valid(host) and is_instance_valid(host.display_menu):
		var index:int=host.display_menu.get_item_index(host.PRIVATE_VISUAL_MENU_ID)
		if index>=0:host.display_menu.set_item_checked(index,false)
func after_world_change()->void:
	if not desired_enabled or resume_pending:return
	resume_pending=true;_resume_after_source_change.call_deferred(source_revision)
func _resume_after_source_change(revision:int)->void:
	resume_pending=false
	if revision!=source_revision:after_world_change();return
	if not desired_enabled or not is_instance_valid(host) or not host.is_inside_tree():return
	if host.world_build_busy or host.generated_start_busy:
		waiting_for_source_ready=true;return
	waiting_for_source_ready=false
	var accepted:bool=enable(host)
	if is_instance_valid(host.display_menu):host.display_menu.set_item_checked(host.display_menu.get_item_index(host.PRIVATE_VISUAL_MENU_ID),accepted)
	if not accepted:
		desired_enabled=false
		host.set_status("本次场景表现重新登记未通过，实验显示已关闭；可从菜单重新启用。")
func _mark_bounds_dirty()->void:
	if requested:bounds_dirty=true
func _process(_delta:float)->void:
	# Observe only the two existing readiness flags while waiting. No repeated
	# material/proxy work is queued during an asynchronous build.
	if waiting_for_source_ready and desired_enabled and is_instance_valid(host) and not host.world_build_busy and not host.generated_start_busy:
		waiting_for_source_ready=false;after_world_change()
	if not requested or not bounds_dirty:return
	bounds_dirty=false
	var next:Dictionary=_cached_active_bounds()
	if not next.ok or float(next.far)>float(camera_snapshot.far):
		last_error=str(next.get("error","Active camera depth exceeds registered original clip range"))
		desired_enabled=false;before_world_change()
		if is_instance_valid(host):host.set_status("镜头已超出本次表现登记范围，实验显示已关闭。")
		return
	camera_snapshot.camera.far=next.far;last_report["active_camera_bounds"]=next
func uninstall()->void:
	if is_instance_valid(bound_view) and bound_view.private_visual_bounds_dirty.is_connected(_mark_bounds_dirty):bound_view.private_visual_bounds_dirty.disconnect(_mark_bounds_dirty)
	bound_view=null;bound_entries.clear();bounds_dirty=false
	if transaction!=null:transaction.uninstall()
	if not camera_snapshot.is_empty() and is_instance_valid(camera_snapshot.camera):
		camera_snapshot.camera.near=camera_snapshot.near;camera_snapshot.camera.far=camera_snapshot.far
		camera_snapshot.camera.cull_mask=camera_snapshot.cull_mask
	camera_snapshot.clear();transaction=null
	if is_instance_valid(suspended_profile):suspended_profile.resume_ownership()
	suspended_profile=null
func _authority(main:Node)->String:
	return JSON.stringify(main.playtest.engine.save_data(),"",true,true).sha256_text() if main.playtest_mode and main.playtest!=null else JSON.stringify(main.game.state,"",true,true).sha256_text()
func enable(main:Node)->bool:
	host=main;uninstall();requested=false;last_error=""
	var before:=_authority(main)
	var board:Node3D=main.board
	if not is_instance_valid(board) or not board.is_inside_tree():last_error="Current Main board is unavailable";return false
	registered_roots=[board]
	if is_instance_valid(board.get("world_view")):registered_roots.append(board.world_view)
	if is_instance_valid(board.get("settlement_view")):registered_roots.append(board.settlement_view)
	for pawn:Node in board.get("token_nodes").values():registered_roots.append(pawn)
	registered_contacts=[]
	if board.get("contact_shadows") is Dictionary:
		for contact:Node in board.contact_shadows.values():registered_contacts.append(contact);registered_roots.append(contact)
	# get_world_3d reads the optional custom property. Main uses own_world_3d;
	# find_world_3d resolves that actual private world without changing it.
	var world_:World3D=main.viewport.find_world_3d()
	registered_lights=[]
	if world_==null or board.get_world_3d()!=world_:
		last_error="Selected Main board has no matching resolved World3D"
		last_report={"registration":{"world_valid":false},"authority_unchanged":_authority(main)==before}
		return false
	for light:Light3D in main.get_tree().root.find_children("*","Light3D",true,false):
		if light.get_world_3d()==world_:registered_lights.append(light)
	var materials:Dictionary=MainMaterials.register(board,main)
	if not materials.ok:last_error=str(materials.error);return false
	var excluded:Dictionary=MainMaterials.exclusions(board)
	if not excluded.ok:last_error=str(excluded.error);return false
	var inspected:Dictionary=Audit.inspect(board,registered_contacts,materials.entries,excluded.slots)
	last_report=Audit.serializable(inspected)
	last_report["verified_original_exclusions"]={"zero_slots":excluded.verified_zero_slots,"unique_source_rows":excluded.unique_source_rows,"source_manifest_sha256":excluded.source_manifest_sha256,"scope":"Only original strict river/shore hide registry rows; MM buffers and group.rows/index remain unchanged; guarded shader custom inverse is skipped"}
	last_report["registration"]={"board_id":board.get_instance_id(),"viewport_world_id":world_.get_instance_id(),"participant_roots":registered_roots.size(),"registered_contacts":registered_contacts.size(),"registered_shared_lights":registered_lights.size(),"scope":"Entire selected actual Main board; every same-World3D light explicitly registered; no93-surface extract claim"}
	var view=board.get("world_view")
	last_report["authority_unchanged"]=_authority(main)==before
	if not last_report.authority_unchanged:last_error="Read-only preflight changed authority";return false
	if not inspected.ready_for_atomic_install:
		last_error="Unknown/unsupported actual Main surfaces: "+str(inspected.blocked_surfaces)+"; original presentation retained";return false
	var profile:Node=view.get("clear_daylight_profile")
	if not is_instance_valid(profile) or not profile.has_method("suspend_ownership"):
		last_error="Selected Main profile has no explicit reversible ownership handoff";return false
	var proxies:Dictionary=_mountain_proxies(inspected.plans)
	if not proxies.ok:last_error=str(proxies.error);return false
	if not profile.suspend_ownership():last_error="Main profile ownership is already suspended";return false
	suspended_profile=profile
	var camera:Camera3D=board.camera
	camera_snapshot={"camera":camera,"near":camera.near,"far":camera.far,"cull_mask":camera.cull_mask}
	transaction=Transaction.new()
	var required_ids:Array=[]
	for site:Dictionary in preload("res://view/playable_build/settlement_content.gd").all_settlements():required_ids.append(str(site.id))
	if not transaction.install(board,proxies.meshes,["ground","tree","building","piece","water"],registered_contacts,-1,{"shared_lights":registered_lights,"originals":materials.entries,"exclusions":excluded.slots,"required_content_ids":required_ids}):
		last_error=transaction.last_error;uninstall();return false
	var geometry:Array=[]
	for plan:Dictionary in inspected.plans:
		if plan.classification.kind!="preserve":geometry.append(plan.node)
	var bounds:Dictionary=camera_bounds(camera,geometry,transaction.proxies,excluded.slots)
	if not bounds.ok:last_error=str(bounds.error);uninstall();return false
	camera.cull_mask|=Transaction.RECEIVER|Transaction.CASTER
	camera.far=bounds.far
	_cache_local_bounds(geometry,transaction.proxies,excluded.slots)
	bound_view=view
	view.private_visual_bounds_dirty.connect(_mark_bounds_dirty)
	last_report["active_camera_bounds"]=bounds
	last_report["mountain_proxies"]=proxies.reports
	last_report["main_original_material_contract"]={"styled_opaque":materials.styled_opaque_count,"preserved":materials.preserved_count}
	if _authority(main)!=before:last_error="Presentation transaction changed authority";uninstall();return false
	requested=true;last_error="";return true
func _cache_local_bounds(geometry:Array,proxies:Array,exclusions:Dictionary)->void:
	bound_entries.clear();var nodes:Array=geometry.duplicate();nodes.append_array(proxies)
	for node:GeometryInstance3D in nodes:
		var mesh:Mesh=Audit.mesh_of(node)
		if mesh==null:continue
		var local:AABB=mesh.get_aabb()
		if node is MultiMeshInstance3D:
			var mm:MultiMesh=node.multimesh;var found:=false;var combined:AABB
			for index in range(mm.instance_count):
				var transform_:Transform3D=mm.get_instance_transform(index)
				if exclusions.get(node.get_instance_id(),{}).has(index):continue
				var box:AABB=transform_*local
				combined=combined.merge(box) if found else box;found=true
			if not found:continue
			local=combined
		bound_entries.append({"node":node,"local_box":local})
func _cached_active_bounds()->Dictionary:
	if camera_snapshot.is_empty() or not is_instance_valid(camera_snapshot.camera):return {"ok":false,"error":"Registered camera disappeared"}
	var camera:Camera3D=camera_snapshot.camera;var inverse:Transform3D=camera.global_transform.affine_inverse()
	var low:=INF;var high:float=-INF;var corners:=0
	for entry:Dictionary in bound_entries:
		var node:GeometryInstance3D=entry.node
		if not is_instance_valid(node) or not node.is_inside_tree():return {"ok":false,"error":"Registered bounds participant changed"}
		if not node.is_visible_in_tree():continue
		if not node.global_transform.is_finite():return {"ok":false,"error":"Nonfinite current participant pose"}
		var transform_:Transform3D=inverse*node.global_transform;var box:AABB=entry.local_box
		for k in range(8):
			var point:Vector3=transform_*(box.position+Vector3(box.size.x if (k&1)!=0 else 0.0,box.size.y if (k&2)!=0 else 0.0,box.size.z if (k&4)!=0 else 0.0))
			if not point.is_finite():return {"ok":false,"error":"Nonfinite cached active depth"}
			low=minf(low,-point.z);high=maxf(high,-point.z);corners+=1
	if high<=0:return {"ok":false,"error":"No active positive camera depth"}
	var margin:float=2.0+.10*maxf(0.0,high-low)
	return {"ok":true,"near":camera.near,"far":ceilf(high+margin),"corners":corners,"margin_world":margin,"scope":"Current visible admitted nodes with cached conservative local MM bounds; no proxy rebuild during pan/zoom"}
func _mountain_proxies(plans:Array)->Dictionary:
	var grounds:Array=[];var meshes:Dictionary={};var reports:Array=[]
	for plan:Dictionary in plans:
		if plan.classification.kind=="ground" and plan.node.is_visible_in_tree():
			grounds.append({"node":plan.node,"faces":plan.node.mesh.get_faces(),"box":plan.node.mesh.get_aabb()})
	for plan:Dictionary in plans:
		if plan.classification.kind!="mountain":continue
		var node:MeshInstance3D=plan.node
		var local_inverse:Transform3D=node.global_transform.affine_inverse()
		var ground:PackedVector3Array=[]
		var box:AABB=node.mesh.get_aabb().grow(.01)
		for receiver:Dictionary in grounds:
			var transform_:Transform3D=local_inverse*receiver.node.global_transform
			var receiver_box:AABB=transform_*receiver.box
			if receiver_box.end.x<box.position.x or receiver_box.position.x>box.end.x or receiver_box.end.z<box.position.z or receiver_box.position.z>box.end.z:continue
			var faces:PackedVector3Array=transform_*receiver.faces
			for i in range(0,faces.size(),3):
				var a:Vector3=faces[i];var b:Vector3=faces[i+1];var c:Vector3=faces[i+2]
				if maxf(a.x,maxf(b.x,c.x))<box.position.x or minf(a.x,minf(b.x,c.x))>box.end.x or maxf(a.z,maxf(b.z,c.z))<box.position.z or minf(a.z,minf(b.z,c.z))>box.end.z:continue
				ground.append_array(PackedVector3Array([a,b,c]))
		print("MAIN_PROXY_STAGE ",str(node.name)," ground_triangles ",ground.size()/3)
		var arrays:Array=node.mesh.surface_get_arrays(0)
		var built:Dictionary=RidgeProxy.build(arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_COLOR],ground)
		if not built.ok:return {"ok":false,"error":str(built.error)+" at "+str(node.name)}
		meshes[node.get_instance_id()]=built.mesh;reports.append({"node":str(node.name),"report":built.report})
		print("MAIN_PROXY_DONE ",str(node.name)," source_triangles ",built.report.source_triangles)
	return {"ok":true,"meshes":meshes,"reports":reports}
func camera_bounds(camera:Camera3D,geometry:Array,proxies:Array=[],excluded_source_slots:Dictionary={})->Dictionary:
	var inverse:Transform3D=camera.global_transform.affine_inverse()
	var lo:=Vector3(INF,INF,INF);var hi:=Vector3(-INF,-INF,-INF);var maximum:float=-INF;var corners:=0
	var participants:Array=geometry.duplicate();participants.append_array(proxies)
	for node:GeometryInstance3D in participants:
		if not node.is_visible_in_tree():continue
		var mesh:Mesh=Audit.mesh_of(node)
		if mesh==null:continue
		var transforms:Array=[]
		if node is MultiMeshInstance3D:
			var mm:MultiMesh=node.multimesh;var limit:int=mm.instance_count if mm.visible_instance_count<0 else mini(mm.visible_instance_count,mm.instance_count)
			for index in range(limit):
				var t:Transform3D=mm.get_instance_transform(index)
				var zero:bool=t.basis.x==Vector3.ZERO and t.basis.y==Vector3.ZERO and t.basis.z==Vector3.ZERO
				if zero and t.is_finite() and excluded_source_slots.get(node.get_instance_id(),{}).has(index):continue
				if not t.is_finite() or absf(t.basis.determinant())<1e-8:return {"ok":false,"error":"Invalid active MM transform; original exclusion registry needs explicit admission"}
				transforms.append(node.global_transform*t)
		else:transforms.append(node.global_transform)
		var box:AABB=mesh.get_aabb()
		for t:Transform3D in transforms:
			for k in range(8):
				var point:Vector3=inverse*(t*(box.position+Vector3(box.size.x if (k&1)!=0 else 0.0,box.size.y if (k&2)!=0 else 0.0,box.size.z if (k&4)!=0 else 0.0)))
				if not point.is_finite():return {"ok":false,"error":"Nonfinite active bounds"}
				var p:=Vector3(point.x,point.y,-point.z);lo=lo.min(p);hi=hi.max(p);corners+=1
				if p.z>0:maximum=maxf(maximum,p.z)
	if maximum==-INF:return {"ok":false,"error":"No active positive camera depth"}
	var margin:float=2.0+.10*maxf(0.0,hi.z-lo.z)
	return {"ok":true,"near":camera.near,"far":ceilf(maximum+margin),"corners":corners,"margin_world":margin,"scope":"Only all explicitly supplied active Main geometry/proxies, never fixed28"}
