extends RefCounted
## Explicit, bounded material transaction for the actual scene inventory.
## The audit happens for all mesh surfaces before any scene-state write.
const Audit:=preload("material_audit.gd")
const RECEIVER:=1<<18
const CASTER:=1<<19
const SHADERS:={
	"ground":preload("ground.gdshader"),"vegetation":preload("vegetation.gdshader"),
	"mountain":preload("mountain.gdshader"),"water":preload("water.gdshader"),
	"rigid":preload("rigid.gdshader"),"rigid_back":preload("rigid_back.gdshader")
}
var snapshots:Array=[]
var light_snapshots:Array=[]
var proxies:Array=[]
var sun:DirectionalLight3D
var installed:=false
var last_error:=""
var last_audit:Dictionary={}

func settlement_provenance(plans:Array,required_content_ids:Array=[])->Dictionary:
	var seen:Dictionary={};var records:Array=[];var found_southwatch:=false
	for plan:Dictionary in plans:
		var site:Node=Audit.settlement_ancestor(plan.node)
		if site==null or seen.has(site.get_instance_id()):continue
		seen[site.get_instance_id()]=true
		if FileAccess.get_sha256("res://view/playable_build/settlement_view.gd")!=Audit.SETTLEMENT_SHA:
			return {"ok":false,"error":"Authored settlement source changed"}
		var proof:Dictionary=site.report()
		records.append(proof)
		if str(proof.get("content_id",""))=="settlement:natural-shore-v03-2f6a1a215a0d44a374f01c4a:south_watch_v1":
			if site.manifest.get("center_hex",[])!=[-3,17] or site.manifest.get("interior_hexes",[])!=[[-3,17],[-3,16],[-2,16]]:
				return {"ok":false,"error":"SouthWatch authored support hexes changed","records":records}
			found_southwatch=true
		if not proof.get("configured",false) or int(proof.get("authored_models",0))==0:
			return {"ok":false,"error":"Authored settlement not configured or no imported models","records":records}
		for key in ["missing_district_sites","asset_hash_failures","missing_asset_resources"]:
			if not proof.get(key,[]).is_empty():return {"ok":false,"error":"Authored settlement dependency failed: "+key,"records":records}
		if not proof.get("lod",{}).get("asset_failures",[]).is_empty():
			return {"ok":false,"error":"Authored city LOD dependency failed","records":records}
		if int(proof.get("wall_endpoint_mismatches",-1))!=0:
			return {"ok":false,"error":"Authored wall contour endpoint mismatch","records":records}
		for rows:Array in [proof.get("building_sites",[]),proof.get("prop_sites",[])]:
			for row:Dictionary in rows:
				if not row.get("authored_model",false):return {"ok":false,"error":"Constructor emitted fallback instead of authored model","records":records}
		if str(proof.get("source_mesh_sha256",""))!="68931983818b291b07022477029d4ad4761aceac0c670463fbe742b6a2ac986c":
			return {"ok":false,"error":"Settlement uses a different source terrain identity","records":records}
	for id:String in required_content_ids:
		if not records.any(func(row:Dictionary)->bool:return str(row.get("content_id",""))==id):return {"ok":false,"error":"Explicit authored content missing: "+id,"records":records}
	return {"ok":found_southwatch,"error":"SouthWatch authored content missing" if not found_southwatch else "","records":records}

func world_boundary_error(root:Node3D,registered_shared_lights:Array=[])->String:
	# Reject outside participants instead of muting or editing another scene.
	var world_:World3D=root.get_world_3d()
	for light:Light3D in registered_shared_lights:
		if not is_instance_valid(light) or light.get_world_3d()!=world_:return "Registered light is outside selected Main World3D"
	for light:Light3D in root.get_tree().root.find_children("*","Light3D",true,false):
		if light.get_world_3d()==world_ and not root.is_ancestor_of(light) and not light in registered_shared_lights:return "Unregistered light outside selected render boundary: "+str(light.get_path())
	for node:GeometryInstance3D in root.get_tree().root.find_children("*","GeometryInstance3D",true,false):
		if node.get_world_3d()==world_ and (node.layers&(RECEIVER|CASTER))!=0 and node!=root and not root.is_ancestor_of(node):
			return "Reserved-layer mesh outside owned extract: "+str(node.get_path())
	return ""

func cancel_install(reason:String)->bool:
	uninstall()
	last_error=reason if last_error.is_empty() else reason+"; "+last_error
	return false

func styled_material(plan:Dictionary)->ShaderMaterial:
	var source:Material=plan.material
	var kind:String=plan.classification.kind
	var result:=ShaderMaterial.new()
	if source is ShaderMaterial:result=source.duplicate() as ShaderMaterial
	if kind in ["ground","vegetation","mountain","water"]:
		result.shader=SHADERS[kind]
		if kind=="ground":result.set_shader_parameter("canopy_contact_strength",0.0)
		return result
	var back:bool=kind=="city" or (source is StandardMaterial3D and source.cull_mode==BaseMaterial3D.CULL_BACK)
	result.shader=SHADERS.rigid_back if back else SHADERS.rigid
	var color:=Color.WHITE
	if source is StandardMaterial3D:color=source.albedo_color
	elif kind=="prop":
		var value:Variant=source.get_shader_parameter("base_color")
		if value is Color:color=value
		elif value is Vector4:color=Color(value.x,value.y,value.z,value.w)
	result.set_shader_parameter("base_color",color)
	result.set_shader_parameter("vertex_rule",2 if kind=="city" else 1 if kind in ["settlement_solid","settlement_road"] else 0)
	result.set_shader_parameter("road_top_normal_up",kind=="settlement_road")
	result.set_shader_parameter("form_low",.34 if kind in ["city","settlement_solid","settlement_road"] else .20)
	result.set_shader_parameter("form_high",.44 if kind in ["city","settlement_solid","settlement_road"] else .30)
	return result

func install(root:Node3D,mountain_shadow_meshes:Dictionary={},required_roles:Array=["ground","tree","building","piece","water"],registered_contacts:Array=[],test_interrupt_after_steps:int=-1,main_contract:Dictionary={})->bool:
	if installed:last_error="Already installed";return false
	if test_interrupt_after_steps==0 or test_interrupt_after_steps< -1:
		last_error="Invalid test-only interruption boundary";return false
	if not is_instance_valid(root) or not root.is_inside_tree():last_error="Owned extract is not inside the scene tree";return false
	var registered_shared_lights:Array=main_contract.get("shared_lights",[])
	var boundary_error:=world_boundary_error(root,registered_shared_lights)
	if not boundary_error.is_empty():last_error=boundary_error;return false
	var inspected:Dictionary=Audit.inspect(root,registered_contacts,main_contract.get("originals",{}),main_contract.get("exclusions",{}))
	last_audit=Audit.serializable(inspected)
	if not inspected.ready_for_atomic_install:
		last_error="Unsupported actual surfaces; see complete audit ratios and rows";return false
	for role:String in required_roles:
		if not inspected.by_role.has(role) or int(inspected.by_role[role].visible_eligible)==0:
			last_error="Required actual scene role missing: "+role;return false
	if "tree" in required_roles and int(inspected.visible_active_tree_slots)==0:
		last_error="No visible nonsingular original tree slots in extract";return false
	if "building" in required_roles:
		var provenance:=settlement_provenance(inspected.plans,main_contract.get("required_content_ids",[]))
		last_audit["settlement_provenance"]=provenance
		if not provenance.ok:last_error=str(provenance.error);return false
	var pending:Array=[]
	for plan:Dictionary in inspected.plans:
		var node:GeometryInstance3D=plan.node
		var kind:String=plan.classification.kind
		if node.layers&(RECEIVER|CASTER):last_error="Reserved layer already used: "+str(node.name);return false
		if kind=="mountain":
			var supplied:Variant=mountain_shadow_meshes.get(node.get_instance_id())
			if not supplied is ArrayMesh or supplied.get_surface_count()!=1:
				last_error="Validated original-terrain mountain proxy required: "+str(node.name);return false
		pending.append({"node":node,"kind":kind,"original_override":node.material_override,
			"styled":null if kind in ["legacy_blob","preserve"] else styled_material(plan),
			"layers":node.layers,"cast":node.cast_shadow,"visible":node.visible})
	# Stage all nodes and all original snapshots before any scene-state write.
	snapshots=pending;light_snapshots.clear();proxies.clear()
	var all_lights:Array=root.find_children("*","Light3D",true,false)
	for light:Light3D in registered_shared_lights:
		if not light in all_lights:all_lights.append(light)
	for light:Light3D in all_lights:
		light_snapshots.append({"node":light,"mask":light.light_cull_mask,"caster_mask":light.shadow_caster_mask})
	for row:Dictionary in snapshots:
		if row.kind=="mountain":
			var proxy:=MeshInstance3D.new();proxy.mesh=mountain_shadow_meshes[row.node.get_instance_id()]
			proxy.layers=CASTER;proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			proxy.transform=root.global_transform.affine_inverse()*row.node.global_transform;proxies.append(proxy)
	sun=DirectionalLight3D.new();sun.name="SinglePaletteShadowSun"
	sun.light_cull_mask=RECEIVER;sun.shadow_caster_mask=CASTER
	sun.shadow_enabled=true;sun.shadow_bias=.1;sun.shadow_normal_bias=2.0
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1=.35;sun.directional_shadow_blend_splits=true
	# Recovery is available from the FIRST write, including test interruption.
	installed=true;last_error=""
	if test_interrupt_after_steps>light_snapshots.size()+snapshots.size()+proxies.size()+1:
		return cancel_install("Test-only interruption boundary exceeds staged transaction")
	# The test seam interrupts at participant-row/attachment boundaries; it does
	# not claim to inject a failure between every individual property assignment.
	var steps:=0
	for row:Dictionary in light_snapshots:
		row.node.light_cull_mask&=~(RECEIVER|CASTER);row.node.shadow_caster_mask&=~(RECEIVER|CASTER);steps+=1
		if steps==test_interrupt_after_steps:return cancel_install("Test-only interrupted commit; original snapshots restored")
	for row:Dictionary in snapshots:
		if row.kind=="preserve":continue
		if row.kind=="legacy_blob":
			row.node.visible=false;steps+=1
			if steps==test_interrupt_after_steps:return cancel_install("Test-only interrupted commit; original snapshots restored")
			continue
		row.node.material_override=row.styled
		var casts:bool=row.kind not in ["ground","water","mountain","settlement_road"]
		row.node.layers=RECEIVER|(CASTER if casts else 0)
		row.node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		steps+=1
		if steps==test_interrupt_after_steps:return cancel_install("Test-only interrupted commit; original snapshots restored")
	for proxy:MeshInstance3D in proxies:
		root.add_child(proxy);steps+=1
		if steps==test_interrupt_after_steps:return cancel_install("Test-only interrupted commit; original snapshots restored")
	root.add_child(sun);steps+=1
	if steps==test_interrupt_after_steps:return cancel_install("Test-only interrupted commit; original snapshots restored")
	sun.look_at(sun.global_position-Vector3(-.55,.74,.39).normalized(),Vector3.UP)
	last_error="";return true

func uninstall()->void:
	if not installed:return
	var missing:=0
	for row:Dictionary in snapshots:
		# Preserved source-owned UI was never written. Its live tween/retirement
		# must not be overwritten or mistaken for a missing styled participant.
		if row.kind=="preserve":continue
		if not is_instance_valid(row.node):missing+=1;continue
		row.node.material_override=row.original_override
		row.node.layers=row.layers;row.node.cast_shadow=row.cast;row.node.visible=row.visible
	for row:Dictionary in light_snapshots:
		if is_instance_valid(row.node):row.node.light_cull_mask=row.mask;row.node.shadow_caster_mask=row.caster_mask
		else:missing+=1
	for proxy:MeshInstance3D in proxies:
		if is_instance_valid(proxy):proxy.free()
	if is_instance_valid(sun):sun.free()
	snapshots.clear();light_snapshots.clear();proxies.clear();installed=false
	if missing>0:
		last_error="Original participants disappeared during transaction: "+str(missing)
		push_error(last_error)
