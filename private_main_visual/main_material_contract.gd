extends RefCounted
## Exact original Main factory/instance registration, never a StandardMaterial wildcard.
const CREATIVE_SHA="a204eba8c91e88225bfa6822cbf5f7c210d0eb5f80f6f4c764915a2185e5d310"
const LAMP_SHA="ec260b7e8eb95a7656da2b1d4dcb83aa08626c53b343cf8bc004a5a93bc1f488"
const BOARD_SHA="99c56230b6bafd301f7cd6124153dd445d5c42b8add6bda663f9457ed8df0a80"
const VIEW_SHA="f000559f9cad74531ab2a2976a36dbc0196676d6ddf3e84d70de0ff827e13355"
const GRID_SHA="86ce9d2ddba7f69c15f3580c3ba9a9d07f1513d4de2eca51e7080089ce3d28e5"
static func original_ui_features(mat:StandardMaterial3D)->bool:
	if mat==null:return false
	for slot in range(BaseMaterial3D.TEXTURE_MAX):
		if mat.get_texture(slot)!=null:return false
	if mat.vertex_color_use_as_albedo or mat.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or mat.no_depth_test or mat.grow or mat.proximity_fade_enabled or mat.distance_fade_mode!=BaseMaterial3D.DISTANCE_FADE_DISABLED or mat.cull_mode!=BaseMaterial3D.CULL_BACK:return false
	for feature in ["normal_enabled","emission_enabled","refraction_enabled","clearcoat_enabled","rim_enabled","ao_enabled","heightmap_enabled"]:
		if bool(mat.get(feature)):return false
	return true
static func exclusions(board:Node3D)->Dictionary:
	if FileAccess.get_sha256("res://view/integrated_ecology_world/natural_shorelines/shore_layer.gd")!="77037a2762f592c8cb526a2b9851faaae313e9a7288eb12ccffc6c3e1f2bdafe" or FileAccess.get_sha256("res://view/integrated_ecology_world/performance_variant/whole_canopies.gd")!="3426c4617148977022d23226ff858684c5b0a329bf72a24fb8129b106f48a86f":
		return {"ok":false,"error":"Original shoreline/exclusion recipe changed"}
	var layer=board.world_view.whole_canopies;var shore=board.world_view.natural_shorelines
	if not is_instance_valid(layer) or not is_instance_valid(shore):return {"ok":false,"error":"Original canopy exclusion owners missing"}
	var proof:Dictionary=shore.prepare_canopy_bindings(layer)
	if not proof.ok:return {"ok":false,"error":str(proof.error)}
	# prepare_canopy_bindings verified this exact immutable file/source identity.
	var support:Variant=JSON.parse_string(shore._bytes("canopy_support_v03.json.gz").get_string_from_utf8())
	if not support is Dictionary or not support.get("updates") is Array:return {"ok":false,"error":"Verified exclusion support payload missing"}
	var expected:Dictionary={}
	for row:Dictionary in shore.canopy_adjustments:
		if not expected.has(row.mi.get_instance_id()):expected[row.mi.get_instance_id()]={}
		expected[row.mi.get_instance_id()][row.index]=row.current if shore.visible else row.original
	var slots:Dictionary={};var source_rows:Dictionary={};var verified:=0
	for group:Dictionary in layer.groups:
		for node:MultiMeshInstance3D in [group.near,group.far]:
			if node.multimesh.instance_count!=group.rows.size():return {"ok":false,"error":"Original source row/MM slot mapping changed"}
			var allowed:Dictionary={}
			for index in range(group.rows.size()):
				var transform_:Transform3D=node.multimesh.get_instance_transform(index)
				var zero:bool=transform_.basis.x==Vector3.ZERO and transform_.basis.y==Vector3.ZERO and transform_.basis.z==Vector3.ZERO
				if not zero:continue
				var original:Variant=expected.get(node.get_instance_id(),{}).get(index)
				if not original is Transform3D or original!=transform_ or not transform_.is_finite():return {"ok":false,"error":"Unproven all-zero source slot: "+str(node.name)+":"+str(index)}
				var source:int=group.rows[index]
				var hide:Dictionary=support.updates[source]
				if hide.get("row")!=source or not hide.get("hide") is bool:return {"ok":false,"error":"Original source exclusion row identity changed"}
				if not layer.river_excluded.has(source) and not (shore.visible and hide.hide):return {"ok":false,"error":"Source slot has no active river/shore exclusion"}
				allowed[index]=true;source_rows[source]=true;verified+=1
			slots[node.get_instance_id()]=allowed
	return {"ok":true,"slots":slots,"verified_zero_slots":verified,"unique_source_rows":source_rows.size(),"source_manifest_sha256":layer.manifest_sha256}
static func register(board:Node3D,main:Node=null)->Dictionary:
	var files={"res://view/playable_build/creative_view.gd":CREATIVE_SHA,"res://view/playable_build/lighthouse_marker.gd":LAMP_SHA,"res://view/playable_build/board.gd":BOARD_SHA,"res://view/integrated_ecology_world/world_view.gd":VIEW_SHA}
	for path:String in files:
		if FileAccess.get_sha256(path)!=files[path]:return {"ok":false,"error":"Original Main factory changed: "+path}
	if not is_instance_valid(board.get("creative_view")) or not is_instance_valid(board.get("lighthouse")) or not is_instance_valid(board.get("marker")):
		return {"ok":false,"error":"This board lacks the explicit Coast render participant contract"}
	var entries:Dictionary={};var creative=board.creative_view
	if creative.get_script().resource_path!="res://view/playable_build/creative_view.gd":return {"ok":false,"error":"Creative factory instance changed"}
	var roots:Array=[]
	for row:Dictionary in creative.passage_nodes.values():roots.append(row.node)
	for row:Dictionary in creative.item_nodes.values():roots.append(row.node)
	var count:=0
	for root:Node3D in roots:
		if root.get_parent()!=creative:return {"ok":false,"error":"Creative live root ownership changed"}
		for node:Node in root.get_children():
			if not node is MeshInstance3D:continue
			if not node.mesh is BoxMesh:return {"ok":false,"error":"Creative original box factory changed"}
			entries[node.get_instance_id()]={"node":node,"material":node.material_override,"kind":"main_solid","factory":"creative_box"};count+=1
	if count!=38:return {"ok":false,"error":"Original 38 creative box participant count changed"}
	var lamp=board.lighthouse
	if lamp.get_script().resource_path!="res://view/playable_build/lighthouse_marker.gd":return {"ok":false,"error":"Lighthouse factory instance changed"}
	for name_:String in ["StoneFoot","LampColumn","LanternBase","LanternRoof"]:
		var node:MeshInstance3D=lamp.get_node_or_null(name_)
		if node==null or not node.mesh is CylinderMesh or node.mesh.radial_segments!=6:return {"ok":false,"error":"Original lighthouse cylinder participant changed: "+name_}
		entries[node.get_instance_id()]={"node":node,"material":node.material_override,"kind":"main_solid","factory":"lighthouse_cylinder"}
	if lamp.lantern==null or lamp.lantern.material_override!=lamp.lens_material:return {"ok":false,"error":"Live dynamic lens material identity changed"}
	entries[lamp.lantern.get_instance_id()]={"node":lamp.lantern,"material":lamp.lens_material,"kind":"preserve","factory":"dynamic_story_lantern"}
	var marker:MeshInstance3D=board.marker
	if not marker.mesh is TorusMesh or marker.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:return {"ok":false,"error":"Original focus UI marker changed"}
	entries[marker.get_instance_id()]={"node":marker,"material":marker.material_override,"kind":"preserve","factory":"focus_ui"}
	var view=board.world_view
	if view.grid_root.get_child_count()!=1:return {"ok":false,"error":"Original full grid participant count changed"}
	var grid:MeshInstance3D=view.grid_root.get_child(0)
	if grid.material_override!=view.grid_material or grid.material_override.shader.code.sha256_text()!=GRID_SHA or grid.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return {"ok":false,"error":"Original full grid shader/live material identity changed"}
	entries[grid.get_instance_id()]={"node":grid,"material":grid.material_override,"kind":"preserve","factory":"unshaded_full_grid"}
	var preserved:=3
	# Exact original UI owners remain live and keep their animation/materials.
	# These are not palette receivers/casters and may retire their own nodes.
	if is_instance_valid(board.route_preview):
		var route:Node3D=board.route_preview
		if FileAccess.get_sha256("res://view/playable_build/route_preview.gd")!="1da2ed3a86f06830f837752f4733317aa33009b3f8048453b90a3bb453a617ba" or route.get_script().resource_path!="res://view/playable_build/route_preview.gd" or route.get_parent()!=view.content_root:return {"ok":false,"error":"Original route UI owner changed"}
		for node:MeshInstance3D in route.get_children():
			var mat:StandardMaterial3D=node.material_override as StandardMaterial3D
			var primitive_ok:bool=(node.mesh is CylinderMesh and is_equal_approx(node.mesh.top_radius,.028) and is_equal_approx(node.mesh.bottom_radius,.028) and node.mesh.radial_segments==6) or (node.mesh is TorusMesh and is_equal_approx(node.mesh.inner_radius,.17) and is_equal_approx(node.mesh.outer_radius,.22) and node.mesh.rings==16 and node.mesh.ring_segments==4)
			if not primitive_ok or not original_ui_features(mat) or mat.albedo_color!=Color("e5c98c") or mat.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED or mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:return {"ok":false,"error":"Original route UI material/primitive changed"}
			entries[node.get_instance_id()]={"node":node,"material":mat,"kind":"preserve","factory":"read_only_route_ui"};preserved+=1
	if is_instance_valid(main):
		var motion:Node=main.get_node_or_null("SelectionMotion")
		if motion==null or FileAccess.get_sha256("res://view/tabletop_interaction/selection_motion.gd")!="60835b0672a4426faf747c57e6a21617ebbf87e08c68b8cb3244175f813448e7" or motion.get_script().resource_path!="res://view/tabletop_interaction/selection_motion.gd" or motion._host!=main:return {"ok":false,"error":"Original selection UI owner changed"}
		var pulses:Array=motion._pulse_nodes.duplicate();pulses.append_array(motion._route_nodes)
		for node:MeshInstance3D in pulses:
			if not is_instance_valid(node):continue
			var mat:StandardMaterial3D=node.material_override as StandardMaterial3D;var expected:=Color("f5d994")
			if node.get_parent()!=board or motion._board!=board or not node.mesh is TorusMesh or node.mesh.rings!=24 or node.mesh.ring_segments!=4 or not is_equal_approx(node.mesh.outer_radius-node.mesh.inner_radius,.025) or not original_ui_features(mat) or mat.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED or mat.transparency!=BaseMaterial3D.TRANSPARENCY_ALPHA or not Vector3(mat.albedo_color.r,mat.albedo_color.g,mat.albedo_color.b).is_equal_approx(Vector3(expected.r,expected.g,expected.b)) or mat.albedo_color.a<0 or mat.albedo_color.a>1 or node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:return {"ok":false,"error":"Original owned selection pulse changed"}
			entries[node.get_instance_id()]={"node":node,"material":mat,"kind":"preserve","factory":"owned_selection_feedback_ui"};preserved+=1
	return {"ok":true,"entries":entries,"styled_opaque_count":42,"preserved_count":preserved}
