extends RefCounted
## Read-only production inventory. No material, mesh, visibility or layer writes.
## Counts every MeshInstance/MultiMesh surface; unsupported core objects remain
## visible in the report and block installation rather than being filtered out.
const SHADER_KINDS := {
	"7b33e1a9669e7a982cf6eba043cc32c90434be75da4b23979bf8c6f69e009678":"ground",
	"1a0d7fc0381a450f9fffdea4ba9f03b45ed1204f79c47a6b0b4e6450414f7078":"vegetation",
	"2f0007fb52fb387fb914f4dd7d9a995941f0b05d80d39c0721442f00775343f7":"mountain",
	"30728f437eff7976defcd946cf325253be29763d727125fcd5b99b27b571ddf5":"city",
	"8aee5904521190e5a40feb674538f4386bc02c81d8a4140be00b7b6240e6845c":"prop",
	"96358bf047e6342de3483c29c62b538103525d667f0557e9384fd154e80384cc":"water",
	"1273e10881aadef81ccb48b04aede6facd65ec16aba220006b200db4ffbccb01":"legacy_blob"
}
const SETTLEMENT_SHA := "1ab97a8c1cfeff69a3a2e81fee7d659450f46f0d3b334684796def7e635c104d"
const TOKENS_SHA := "464b7f49981c01b85415654224f1067881f3b5b8925558fb98dfd92c09fa8043"
const MATERIALS_SHA := "31a2c4faf9c59f946cf3b6e6015e674bc9f2bc56f419eb9e86f9301691384a34"
const TokenFactory:=preload("res://view/chess_tokens.gd")

static func mesh_of(node:GeometryInstance3D)->Mesh:
	if node is MultiMeshInstance3D:return node.multimesh.mesh if node.multimesh!=null else null
	if node is MeshInstance3D:return node.mesh
	return null

static func piece_ancestor(node:Node)->Node:
	var current:=node
	while current!=null:
		if current.has_meta("chess_piece"):return current
		current=current.get_parent()
	return null

static func settlement_ancestor(node:Node)->Node:
	var current:=node
	while current!=null:
		var script:Script=current.get_script()
		if script!=null and script.resource_path=="res://view/playable_build/settlement_view.gd":return current
		current=current.get_parent()
	return null

static func textures(material:StandardMaterial3D)->Array:
	var result:Array=[]
	for slot in range(BaseMaterial3D.TEXTURE_MAX):
		var texture:Texture2D=material.get_texture(slot)
		if texture!=null:result.append({"slot":slot,"resource":texture.resource_path})
	return result

static func transform_inventory(node:GeometryInstance3D,proven_zero_slots:Dictionary={})->Dictionary:
	var result:={"global_finite":node.global_transform.is_finite(),"global_determinant":node.global_transform.basis.determinant(),
		"multimesh_slots":0,"visible_active_slots":0,"zero_basis_slots":0,"verified_source_excluded_slots":0,"singular_slots":0,"invalid_slots":[]}
	if node is MultiMeshInstance3D and node.multimesh!=null:
		var mm:MultiMesh=node.multimesh
		result.multimesh_slots=mm.instance_count
		if mm.transform_format!=MultiMesh.TRANSFORM_3D:
			result["reason"]="multimesh_requires_3d_transform";return result
		var limit:=mm.instance_count if mm.visible_instance_count<0 else mini(mm.visible_instance_count,mm.instance_count)
		for index in range(mm.instance_count):
			var transform_:Transform3D=mm.get_instance_transform(index)
			var determinant:float=transform_.basis.determinant()
			var combined:Transform3D=node.global_transform*transform_
			var combined_determinant:float=combined.basis.determinant()
			var zero:bool=transform_.basis.x==Vector3.ZERO and transform_.basis.y==Vector3.ZERO and transform_.basis.z==Vector3.ZERO
			if zero:
				result.zero_basis_slots+=1
				if proven_zero_slots.has(index) and transform_.is_finite() and combined.is_finite():
					result.verified_source_excluded_slots+=1;continue
			if not transform_.is_finite() or not is_finite(determinant) or absf(determinant)<1e-8 or not combined.is_finite() or not is_finite(combined_determinant) or absf(combined_determinant)<1e-8:
				result.singular_slots+=1
				if result.invalid_slots.size()<8:result.invalid_slots.append(index)
			elif index<limit and node.is_visible_in_tree():result.visible_active_slots+=1
		if result.singular_slots>0:
			# Original whole-canopy code can deliberately zero excluded trees. They
			# are recorded distinctly, but this inverse-matrix adapter never silently
			# accepts singular instance matrices. Extract only proven active source
			# rows, with exclusions retained in the extraction receipt.
			result["reason"]="singular_or_nonfinite_multimesh_instance"
	if not result.global_finite or not is_finite(float(result.global_determinant)) or absf(float(result.global_determinant))<1e-8:
		result["reason"]="singular_or_nonfinite_global_transform"
	return result

static func required_streams(kind:String)->Array:
	var streams:Array=[Mesh.ARRAY_NORMAL]
	if kind in ["ground","vegetation","mountain","water","city","settlement_solid","settlement_road"]:streams.append(Mesh.ARRAY_COLOR)
	if kind=="water":streams.append(Mesh.ARRAY_TEX_UV)
	if kind in ["ground","water"]:streams.append(Mesh.ARRAY_TEX_UV2)
	return streams

static func classify(node:GeometryInstance3D,material:Material,registered_contacts:Array,main_originals:Dictionary={})->Dictionary:
	if material==null:return {"kind":"unsupported","reason":"missing_material"}
	if material.next_pass!=null:return {"kind":"unsupported","reason":"next_pass"}
	var registered:Dictionary=main_originals.get(node.get_instance_id(),{})
	if not registered.is_empty() and (registered.node!=node or registered.material!=material):
		return {"kind":"unsupported","reason":"registered_original_live_identity_changed"}
	if registered.get("kind")=="preserve":return {"kind":"preserve","factory":registered.factory,"preservation":"Original material/layer/cast/visibility retained; included in total denominator"}
	if material is ShaderMaterial:
		if material.shader==null:return {"kind":"unsupported","reason":"missing_shader"}
		var sha:String=material.shader.code.sha256_text()
		if not SHADER_KINDS.has(sha):return {"kind":"unsupported","reason":"unknown_shader","shader_sha256":sha}
		if SHADER_KINDS[sha]=="legacy_blob" and (not node in registered_contacts or not str(node.name).begins_with("ContactShadow_")):
			return {"kind":"unsupported","reason":"legacy_blob_identity_not_registered","shader_sha256":sha}
		return {"kind":SHADER_KINDS[sha],"shader_sha256":sha}
	if not material is StandardMaterial3D:return {"kind":"unsupported","reason":"unknown_material_class","class":material.get_class()}
	if material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a<0.99999:
		return {"kind":"unsupported","reason":"transparent_standard"}
	if material.cull_mode not in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_DISABLED]:
		return {"kind":"unsupported","reason":"unregistered_standard_cull_mode"}
	if material.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or material.no_depth_test or material.grow or material.proximity_fade_enabled or material.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return {"kind":"unsupported","reason":"non_palette_standard_geometry_or_depth_setting"}
	var maps:=textures(material)
	if not maps.is_empty():return {"kind":"unsupported","reason":"textured_standard","textures":maps}
	for feature in ["normal_enabled","emission_enabled","refraction_enabled","clearcoat_enabled","rim_enabled","ao_enabled","heightmap_enabled"]:
		if bool(material.get(feature)):return {"kind":"unsupported","reason":"non_palette_standard_feature","feature":feature}
	if registered.get("kind")=="main_solid":
		if material.vertex_color_use_as_albedo or material.shading_mode!=BaseMaterial3D.SHADING_MODE_PER_PIXEL:
			return {"kind":"unsupported","reason":"registered_main_solid_material_rule_changed"}
		return {"kind":"main_solid","factory":registered.factory,"base_color":material.albedo_color,"vertex_rule":"none"}
	var settlement:=settlement_ancestor(node)
	if settlement!=null:
		if FileAccess.get_sha256("res://view/playable_build/settlement_view.gd")!=SETTLEMENT_SHA:
			return {"kind":"unsupported","reason":"settlement_source_changed"}
		if settlement.get("_material")!=material or not material.vertex_color_use_as_albedo:
			return {"kind":"unsupported","reason":"unregistered_settlement_standard"}
		if node is MeshInstance3D and str(node.name)=="WarmPackedEarthRibbon" and node.get_parent()==settlement.get("road_root"):
			if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				return {"kind":"unsupported","reason":"registered_road_original_cast_setting_changed"}
			return {"kind":"settlement_road","base_color":material.albedo_color,"vertex_rule":"authored_display_srgb","road_top_normal_up":true}
		return {"kind":"settlement_solid","base_color":material.albedo_color,"vertex_rule":"authored_display_srgb"}
	var piece:=piece_ancestor(node)
	if piece!=null:
		if FileAccess.get_sha256("res://view/chess_tokens.gd")!=TOKENS_SHA or FileAccess.get_sha256("res://view/miniature_materials.gd")!=MATERIALS_SHA:
			return {"kind":"unsupported","reason":"token_material_source_changed"}
		if material.vertex_color_use_as_albedo:return {"kind":"unsupported","reason":"unregistered_token_vertex_rule"}
		var faction:String=str(piece.get_meta("faction_style",""))
		var key:="ivory" if faction=="ivory_jade" else "slate" if faction=="slate_bronze" else ""
		var palette:Dictionary=TokenFactory._materials.get(key,{})
		if palette.is_empty() or not material in palette.values():return {"kind":"unsupported","reason":"token_solid_live_identity_not_registered"}
		return {"kind":"token_solid","base_color":material.albedo_color,"vertex_rule":"none"}
	return {"kind":"unsupported","reason":"unregistered_standard_origin"}

static func inspect(root:Node3D,registered_contacts:Array=[],main_originals:Dictionary={},main_exclusions:Dictionary={})->Dictionary:
	var nodes:Array=root.find_children("*","GeometryInstance3D",true,false)
	if root is GeometryInstance3D:nodes.push_front(root)
	var rows:Array=[];var by_kind:Dictionary={};var blocked_nodes:Dictionary={}
	var total_surfaces:=0;var eligible_surfaces:=0;var mesh_nodes:=0
	var multimesh_slots:=0;var visible_tree_slots:=0;var zero_basis_slots:=0
	var non_mesh_geometry:Array=[];var plans:Array=[];var by_role:Dictionary={}
	for node:GeometryInstance3D in nodes:
		var mesh:=mesh_of(node)
		if mesh==null:
			non_mesh_geometry.append({"path":str(root.get_path_to(node)),"class":node.get_class()});continue
		mesh_nodes+=1
		var transform_report:=transform_inventory(node,main_exclusions.get(node.get_instance_id(),{}))
		multimesh_slots+=int(transform_report.multimesh_slots)
		zero_basis_slots+=int(transform_report.zero_basis_slots)
		for surface in range(mesh.get_surface_count()):
			total_surfaces+=1
			var material:Material=node.material_override
			if material==null:
				material=node.get_surface_override_material(surface) if node is MeshInstance3D else null
				if material==null:material=mesh.surface_get_material(surface)
			var item:=classify(node,material,registered_contacts,main_originals)
			var original_kind:String=item.kind
			var missing:Array=[]
			if item.kind not in ["legacy_blob","unsupported"]:
				var arrays:Array=mesh.surface_get_arrays(surface)
				for stream:int in required_streams(item.kind):
					if arrays[stream]==null or arrays[stream].is_empty():missing.append(stream)
				if not missing.is_empty():item={"kind":"unsupported","reason":"required_authored_streams_missing","missing_streams":missing}
			if transform_report.has("reason") and item.kind!="legacy_blob":
				item={"kind":"unsupported","reason":transform_report.reason}
			if node.material_overlay!=null:item={"kind":"unsupported","reason":"material_overlay"}
			if mesh.get_surface_count()!=1:item={"kind":"unsupported","reason":"multisurface_requires_explicit_adapter","surfaces":mesh.get_surface_count()}
			if node is MeshInstance3D and node.get_surface_override_material(surface)!=null:
				item={"kind":"unsupported","reason":"surface_override_requires_explicit_adapter"}
			item["path"]=str(root.get_path_to(node));item["surface"]=surface
			item["original_kind"]=original_kind;item["visible_in_tree"]=node.is_visible_in_tree()
			item["transform_inventory"]=transform_report
			var role:="unknown"
			if piece_ancestor(node)!=null:role="piece"
			elif settlement_ancestor(node)!=null:role="building"
			elif original_kind=="ground":role="ground"
			elif original_kind=="vegetation":role="tree"
			elif original_kind=="water":role="water"
			elif original_kind=="legacy_blob":role="legacy_blob"
			elif original_kind=="mountain":role="mountain"
			if surface==0 and original_kind=="vegetation":visible_tree_slots+=int(transform_report.visible_active_slots)
			item["role"]=role
			if not by_role.has(role):by_role[role]={"total":0,"eligible":0,"blocked":0,"visible_eligible":0}
			by_role[role].total+=1
			by_role[role]["blocked" if item.kind=="unsupported" else "eligible"]+=1
			if item.kind!="unsupported" and node.is_visible_in_tree():by_role[role].visible_eligible+=1
			item["material_class"]=material.get_class() if material!=null else "null"
			rows.append(item)
			var kind:String=item.kind;by_kind[kind]=int(by_kind.get(kind,0))+1
			if kind=="unsupported":blocked_nodes[item.path]=true
			else:
				eligible_surfaces+=1;plans.append({"node":node,"material":material,"surface":surface,"classification":item})
	return {"scope":"Read-only actual scene material inventory; eligibility is not native rendering acceptance",
		"mesh_nodes":mesh_nodes,"material_surfaces":total_surfaces,"eligible_surfaces":eligible_surfaces,
		"blocked_surfaces":total_surfaces-eligible_surfaces,"blocked_mesh_nodes":blocked_nodes.size(),
		"blocked_surface_ratio":float(total_surfaces-eligible_surfaces)/maxi(total_surfaces,1),
		"blocked_mesh_node_ratio":float(blocked_nodes.size())/maxi(mesh_nodes,1),
		"by_kind":by_kind,"by_role":by_role,"multimesh_storage_slots":multimesh_slots,
		"visible_active_tree_slots":visible_tree_slots,"zero_basis_slots":zero_basis_slots,
		"tree_count_scope":"Visible active vegetation slots only; no frustum or unique-source-row count claimed",
		"rows":rows,"non_mesh_geometry_unchanged":non_mesh_geometry,
		"ready_for_atomic_install":blocked_nodes.is_empty() and total_surfaces>0,"plans":plans}

static func serializable(report:Dictionary)->Dictionary:
	var copy:=report.duplicate(true);copy.erase("plans");return copy
