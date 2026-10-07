extends RefCounted
## NEW reconstruction, 2026-10-07. Not restored bytes of missing module d8f1e4c.
## New explicit-size/role-pin runtime fork. Source only: never engine parsed/run.
## Original frozen local_mask_pass.gd bytes remain unchanged.
## stage is read-only; activate owns its entire render branch; sync_frame is explicit.
const MAX_PIXELS := 1280 * 960
const OWNED_GROUND_COLOUR_SHA := "659e8bb23e6b90a92b149513dc26701ad4228f4cf404cca38b0e4c166b7f286f"
const OWNED_COLOUR_INCLUDE_SHA := "266905b4fcd43131cb5510c0062d423dddca163993e25c052ab5c285cdd1ee91"
var _size := Vector2i.ZERO
var _source_viewport: Viewport
var _source_shader_kinds: Dictionary = {}
var _registered_opaque_casters: Dictionary = {}
var _owned_ground_material_ids: Dictionary = {}
var _owned_ground_colour: Shader
var _owned_ground_colour_code := ""
const RECEIVER := 1 << 18
const CASTER := 1 << 19
const DATA_SHADERS := {"ground": "a030587df23167d4b200dd09e0d3ea1c4e99f2655a0a7b4e3df378055c55c673", "water": "433768bf4f108ce328a241ab4a603b7ff4efd928b6a7b532368d12a5ec5bffea"}
const DATA_INCLUDE_SHA := "07873ef9852ba0d8d171cc7dd716b3b520497d6754278769ba1de6d3bd7c779b"
const PRIVATE_PARAMETERS := ["mask_render", "mask_domain", "mask_neighbour_ring", "mask_depth_span", "palette_union_mask", "shadow_debug"]
const CAMERA_PROPERTIES := ["projection", "keep_aspect", "size", "fov", "near", "far", "h_offset", "v_offset", "frustum_offset"]
const SUN_PROPERTIES := ["light_color", "light_energy", "light_indirect_energy", "light_specular", "light_negative", "light_angular_distance", "shadow_enabled", "shadow_opacity", "shadow_bias", "shadow_normal_bias", "shadow_reverse_cull_face", "shadow_transmittance_bias", "directional_shadow_mode", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_blend_splits", "directional_shadow_fade_start", "directional_shadow_max_distance", "directional_shadow_pancake_size", "sky_mode"]
# Caller-reviewed exact SHA→role admission; no frozen93/Main alias assumptions.
var last_error := ""
var _view: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _source_world: World3D
var _rows: Array = []
var _skipped_off: Array = []
var _shaders: Dictionary = {}
var _viewport: SubViewport
var _world: World3D
var _own_camera: Camera3D
var _own_sun: DirectionalLight3D
var _sync_ok := false

func _error(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message}

func stage(source_view: Node3D, camera: Camera3D, receivers: Array, casters: Array, sun: DirectionalLight3D, shader_map: Dictionary, source_viewport: Viewport, raster_size: Vector2i, registered_source_shader_pins: Dictionary, registered_opaque_casters: Dictionary = {}) -> Dictionary:
	if is_instance_valid(_viewport): return _error("Uninstall the active private pass before restaging")
	if not is_instance_valid(source_view) or not source_view.is_inside_tree(): return _error("Source fixture must be in a SceneTree")
	if not is_instance_valid(camera) or not is_instance_valid(sun) or not camera.is_inside_tree() or not sun.is_inside_tree(): return _error("Explicit source Camera3D/Sun must be in the source tree")
	if not is_instance_valid(source_viewport) or camera.get_viewport() != source_viewport or source_view.get_viewport() != source_viewport: return _error("Explicit source viewport identity mismatch")
	if source_viewport.get_camera_3d() != camera: return _error("Explicit source camera must be the current camera of the actual source viewport")
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL: return _error("Only orthographic camera is admitted")
	if raster_size.x <= 0 or raster_size.y <= 0 or raster_size.x * raster_size.y > MAX_PIXELS: return _error("Explicit positive raster exceeds 1280x960 pixel cap")
	if Vector2i(source_viewport.get_texture().get_size()) != raster_size: return _error("Explicit size must match actual source viewport texture raster")
	if source_viewport.scaling_3d_scale != 1.0 or source_viewport.use_taa or source_viewport.msaa_3d != Viewport.MSAA_DISABLED or source_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED: return _error("Source AA/upscaling raster is not admitted")
	_source_shader_kinds.clear()
	for key: Variant in registered_source_shader_pins:
		var sha: String = str(key)
		var role: String = str(registered_source_shader_pins[key])
		if sha.length() != 64 or sha != sha.to_lower() or role not in ["ground", "water", "caster"]: return _error("Registration requires lowercase exact SHA256→ground|water|caster")
		for digit in sha:
			if not "0123456789abcdef".contains(str(digit)): return _error("Registration SHA256 contains a nonhex character")
		_source_shader_kinds[sha] = role
	if _source_shader_kinds.is_empty(): return _error("Explicit caller-reviewed source shader pins are required")
	_registered_opaque_casters.clear()
	for key: Variant in registered_opaque_casters:
		var admission: String = str(registered_opaque_casters[key])
		if not key is int or admission not in ["null_shadow_proxy", "opaque_standard"]: return _error("Opaque admission requires exact nodeID→null_shadow_proxy|opaque_standard")
		_registered_opaque_casters[key] = admission
	_source_viewport = source_viewport; _size = raster_size
	if camera.get_world_3d() != source_view.get_world_3d() or sun.get_world_3d() != source_view.get_world_3d(): return _error("Camera/Sun must belong to the selected source World3D")
	if not sun.shadow_enabled or not sun.is_visible_in_tree(): return _error("Frozen source Sun must be visible with shadows enabled")
	for kind in ["ground", "water"]:
		var shader: Variant = shader_map.get(kind)
		if not shader is Shader or shader.get_mode() != Shader.MODE_SPATIAL: return _error("Explicit spatial shader missing for " + kind)
		var domain := "1.0" if kind == "ground" else "2.0"
		if shader.code.sha256_text() != DATA_SHADERS[kind] or not shader.code.contains("#define WP_MASK_DATA_PASS") or not shader.code.contains("#define WP_MASK_DOMAIN " + domain): return _error("Unregistered reconstructed data shader role/bytes: " + kind)
		if FileAccess.get_sha256(shader.resource_path.get_base_dir().path_join("mask_data_interface.gdshaderinc")) != DATA_INCLUDE_SHA: return _error("Pinned mask data include changed")
	var plans: Array = []
	var seen: Dictionary = {}
	var counts := {"ground": 0, "water": 0}
	for entry: Variant in receivers:
		if not entry is Dictionary or not entry.get("source") is GeometryInstance3D or not is_instance_valid(entry.get("source")): return _error("Receiver requires {source: GeometryInstance3D, kind: ground|water}")
		var kind: String = str(entry.get("kind", ""))
		if not counts.has(kind): return _error("Unknown receiver kind")
		var node: GeometryInstance3D = entry.source
		if seen.has(node.get_instance_id()): return _error("Duplicate receiver")
		var reason := _geometry_error(node, source_view, true, kind)
		if not reason.is_empty(): return _error(reason)
		var material := _active_material(node, 0) as ShaderMaterial
		if material == null or _shader_role(material) != kind: return _error("Receiver source shader/kind is outside exact caller pins")
		plans.append({"source": node, "kind": kind, "material": material})
		seen[node.get_instance_id()] = true
		counts[kind] += 1
	if counts.ground == 0 or counts.water == 0: return _error("Explicit Ground and Water receivers are both required")
	# Keep receiver identities admitted so a source cannot also be a caster.
	var skipped: Array = []
	for value: Variant in casters:
		if not value is GeometryInstance3D or not is_instance_valid(value): return _error("Caster must be a live explicit GeometryInstance3D")
		var node: GeometryInstance3D = value
		if node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			skipped.append(node.get_instance_id())
			continue
		if seen.has(node.get_instance_id()): return _error("Duplicate caster")
		var reason := _geometry_error(node, source_view, false, "caster")
		if not reason.is_empty(): return _error(reason)
		plans.append({"source": node, "kind": "caster"})
		seen[node.get_instance_id()] = true
	for row: Dictionary in plans:
		var slots: Array = []
		var source: GeometryInstance3D = row.source
		for surface in range(_mesh(source).get_surface_count()):
			var material: Material = _active_material(source, surface)
			var slot: Dictionary = {"material": material}
			if material is ShaderMaterial:
				slot["kind"] = "shader"; slot["shader"] = material.shader; slot["code"] = material.shader.code
			elif material is StandardMaterial3D:
				slot["kind"] = "standard"; slot["opacity"] = _standard_opacity_fields(material)
			else: slot["kind"] = "null"
			slots.append(slot)
		row["slots"] = slots
		row["mesh"] = _mesh(source)
		row["multimesh"] = source.multimesh if source is MultiMeshInstance3D else null
	_view = source_view; _camera = camera; _sun = sun; _source_world = source_view.get_world_3d()
	_rows = plans; _skipped_off = skipped; _shaders = shader_map.duplicate()
	_sync_ok = false
	last_error = ""
	return {"ok": true, "viewport_allocated": false, "receivers": counts, "casters": plans.size() - counts.ground - counts.water, "excluded_cast_off": skipped}

func _mesh(node: GeometryInstance3D) -> Mesh:
	if node is MeshInstance3D: return node.mesh
	if node is MultiMeshInstance3D and node.multimesh != null: return node.multimesh.mesh
	return null

func _active_material(node: GeometryInstance3D, surface: int) -> Material:
	if node.material_override != null: return node.material_override
	if node is MeshInstance3D and node.get_surface_override_material(surface) != null: return node.get_surface_override_material(surface)
	return _mesh(node).surface_get_material(surface)

func _geometry_error(node: GeometryInstance3D, root: Node3D, receiver: bool, role: String) -> String:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d() != root.get_world_3d(): return "Explicit geometry is outside source World3D"
	if node != root and not root.is_ancestor_of(node): return "Explicit geometry is outside selected source branch"
	var mesh := _mesh(node)
	if mesh == null or mesh.get_surface_count() == 0: return "Only original Mesh/MultiMesh refs are admitted"
	if receiver and mesh.get_surface_count() != 1: return "Ground/Water requires one opaque surface"
	if (mesh is ArrayMesh and mesh.get_blend_shape_count() != 0) or (node is MeshInstance3D and node.skin != null): return "Skin/blendshape requires an adapter and is rejected"
	if node is MultiMeshInstance3D and node.multimesh.transform_format != MultiMesh.TRANSFORM_3D: return "Only 3D MultiMesh refs are admitted"
	if node.material_overlay != null or node.transparency != 0.0 or node.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED: return "Overlay/transparency/visibility fading is rejected"
	if not node.global_transform.is_finite(): return "Nonfinite source pose"
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] != null and not arrays[Mesh.ARRAY_BONES].is_empty(): return "Skinned vertex streams are rejected"
		var material := _active_material(node, surface)
		if material == null:
			if receiver or _registered_opaque_casters.get(node.get_instance_id(), "") != "null_shadow_proxy" or not _is_null_shadow_proxy(node): return "Missing material requires exact caller admission of strict original null shadow proxy"
			continue
		if material.next_pass != null: return "next_pass is rejected"
		if material is StandardMaterial3D:
			if receiver or _registered_opaque_casters.get(node.get_instance_id(), "") != "opaque_standard" or not _standard_is_opaque(material): return "Standard caster requires exact node admission and original strict opaque semantics"
		elif not material is ShaderMaterial or _shader_role(material) != role: return "Actual source shader SHA/role is outside explicit caller-reviewed pins"

	return ""

func activate() -> Dictionary:
	if is_instance_valid(_viewport): return _error("Private mask already active")
	if _rows.is_empty() or not is_instance_valid(_view) or not is_instance_valid(_camera) or not is_instance_valid(_sun): return _error("Stage the explicit live frozen fixture first")
	_viewport = SubViewport.new(); _viewport.name = "PrivateGroundWaterMaskRebuilt"
	_viewport.size = _size; _viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED; _viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false; _viewport.use_debanding = false; _viewport.scaling_3d_scale = 1.0
	_world = World3D.new(); _viewport.world_3d = _world
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED; environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR; environment.tonemap_exposure = 1.0
	environment.fog_enabled = false; environment.volumetric_fog_enabled = false
	environment.glow_enabled = false; environment.ssao_enabled = false; environment.ssil_enabled = false; environment.ssr_enabled = false; environment.sdfgi_enabled = false; environment.adjustment_enabled = false
	_world.environment = environment
	# A new private branch on the existing root; no original nodes are duplicated.
	_view.get_tree().root.add_child(_viewport)
	var branch := Node3D.new(); branch.name = "OwnedMaskGeometry"; branch.process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.add_child(branch)
	_own_camera = Camera3D.new(); _own_camera.set_disable_scale(false); branch.add_child(_own_camera)
	_own_camera.environment = environment; _own_camera.attributes = null; _own_camera.cull_mask = RECEIVER | CASTER
	_own_camera.current = true
	_own_sun = DirectionalLight3D.new()
	# Light3D defaults disable_scale=true, which orthonormalizes a second time.
	# Preserve the source's already orthonormalized matrix exactly on our Sun only.
	_own_sun.set_disable_scale(false); branch.add_child(_own_sun)
	_own_sun.layers = RECEIVER
	_own_sun.light_cull_mask = RECEIVER | CASTER; _own_sun.shadow_caster_mask = CASTER
	assert((_own_sun.layers & _own_camera.cull_mask) != 0, "Private Sun must survive camera-layer culling")
	for row: Dictionary in _rows:
		var source: GeometryInstance3D = row.source
		var clone: GeometryInstance3D
		if source is MeshInstance3D:
			var mesh_clone := MeshInstance3D.new(); mesh_clone.mesh = source.mesh
			for surface in range(source.mesh.get_surface_count()): mesh_clone.set_surface_override_material(surface, source.get_surface_override_material(surface))
			clone = mesh_clone
		else:
			var mm_clone := MultiMeshInstance3D.new(); mm_clone.multimesh = source.multimesh
			clone = mm_clone
		clone.name = "Mask_" + str(source.get_instance_id()); branch.add_child(clone)
		clone.set_disable_scale(false); clone.material_override = source.material_override
		clone.layers = CASTER if row.kind == "caster" else RECEIVER
		clone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if row.kind == "caster" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clone.extra_cull_margin = source.extra_cull_margin; clone.custom_aabb = source.custom_aabb
		for property in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin", "ignore_occlusion_culling", "lod_bias"]: clone.set(property, source.get(property))
		if row.kind != "caster":
			var material := ShaderMaterial.new(); material.shader = _shaders[row.kind]
			clone.material_override = material; row["owned_material"] = material
		row["clone"] = clone
	# Disable only the new World's private physics space, after entering the tree.
	PhysicsServer3D.space_set_active(_world.space, false)
	var result := sync_frame()
	if not result.ok:
		var message: String = str(result.get("error", "Private activation changed source state"))
		uninstall()
		return _error(message)
	return {"ok": true, "runtime_source_receipt_measured": false, "sun_visible_layer_intersection": _own_sun.layers & _own_camera.cull_mask}

func sync_frame() -> Dictionary:
	if not is_instance_valid(_viewport): return _error("Private mask is inactive")
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sync_ok = false
	if not is_instance_valid(_view) or not is_instance_valid(_camera) or not is_instance_valid(_sun) or _view.get_world_3d() != _source_world: return _error("Frozen source identities/world changed")
	if _camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_instance_valid(_source_viewport) or _camera.get_viewport() != _source_viewport or _view.get_viewport() != _source_viewport or Vector2i(_source_viewport.get_texture().get_size()) != _size: return _error("Source viewport identity/raster/projection changed; explicit size or restage is required")
	if not _sun.shadow_enabled or not _sun.is_visible_in_tree(): return _error("Frozen source Sun visibility/shadow setting changed")
	var current: Dictionary = check_source_current()
	if not current.get("ok", false): return current
	for property in CAMERA_PROPERTIES: _own_camera.set(property, _camera.get(property))
	_own_camera.global_transform = _camera.global_transform
	for property in SUN_PROPERTIES: _own_sun.set(property, _sun.get(property))
	_own_sun.global_transform = _sun.global_transform; _own_sun.visible = _sun.is_visible_in_tree()
	for row: Dictionary in _rows:
		var source: GeometryInstance3D = row.source
		if not is_instance_valid(source): return _error("Explicit source geometry was freed")
		var reason := _sync_source_error(row)
		if not reason.is_empty(): return _error(reason)
		if row.kind == "caster" and source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return _error("Admitted caster became cast OFF; restage explicit inputs")
		var clone: GeometryInstance3D = row.clone
		if _mesh(clone) != _mesh(source) or (source is MultiMeshInstance3D and (clone as MultiMeshInstance3D).multimesh != source.multimesh): return _error("Frozen original mesh/MultiMesh identity changed; restage")
		if row.kind == "caster":
			if clone.material_override != source.material_override: return _error("Frozen caster material override changed; restage")
			if source is MeshInstance3D:
				for surface in range(source.mesh.get_surface_count()):
					if (clone as MeshInstance3D).get_surface_override_material(surface) != source.get_surface_override_material(surface): return _error("Frozen caster surface override changed; restage")
		clone.global_transform = source.global_transform; clone.visible = source.is_visible_in_tree()
		clone.extra_cull_margin = source.extra_cull_margin; clone.custom_aabb = source.custom_aabb
		for property in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin", "visibility_range_end_margin", "ignore_occlusion_culling", "lod_bias"]: clone.set(property, source.get(property))
		if row.kind == "caster":
			_copy_instance_parameters(source, clone)
		else:
			var material := _active_material(source, 0) as ShaderMaterial
			if material != row.material: return _error("Frozen receiver material identity changed; restage")
			_copy_parameters(material, row.owned_material)
	assert((_own_sun.layers & _own_camera.cull_mask) != 0)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sync_ok = true
	last_error = ""
	return {"ok": true, "runtime_source_receipt_measured": false, "explicit_frame_requested": true}

func _copy_parameters(source: ShaderMaterial, target: ShaderMaterial) -> void:
	var target_names: Array = []
	for uniform: Dictionary in target.shader.get_shader_uniform_list(): target_names.append(str(uniform.name))
	# Source shader is already SHA-pinned; copy only its same-name data parameters.
	for uniform: Dictionary in source.shader.get_shader_uniform_list():
		var name_: String = str(uniform.name)
		if PRIVATE_PARAMETERS.has(name_) or not target_names.has(name_): continue
		var value: Variant = source.get_shader_parameter(name_)
		# Type guard FIRST. Never compare bool/scalar Variants against Texture objects.
		if value is ViewportTexture: continue
		target.set_shader_parameter(name_, value)
	# Role/domain/data-only selection are compile-time constants in pinned shaders.

func _copy_instance_parameters(source: GeometryInstance3D, target: GeometryInstance3D) -> void:
	for property: Dictionary in source.get_property_list():
		var name_: String = str(property.name)
		if not name_.begins_with("instance_shader_parameters/"): continue
		var value: Variant = source.get(name_)
		if value is ViewportTexture: continue
		target.set_instance_shader_parameter(name_.trim_prefix("instance_shader_parameters/"), value)

func get_mask_texture() -> ViewportTexture:
	return _viewport.get_texture() if is_instance_valid(_viewport) else null

func uninstall() -> Dictionary:
	var had_viewport := is_instance_valid(_viewport)
	if had_viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		PhysicsServer3D.space_set_active(_world.space, false)
		_viewport.free() # Only our new nodes/materials/world are owned; source refs survive.
	_viewport = null; _world = null; _own_camera = null; _own_sun = null
	_sync_ok = false
	_rows.clear(); _skipped_off.clear(); _shaders.clear()
	_view = null; _camera = null; _sun = null; _source_world = null
	_source_viewport = null; _size = Vector2i.ZERO; _source_shader_kinds.clear(); _registered_opaque_casters.clear()
	_owned_ground_material_ids.clear(); _owned_ground_colour = null; _owned_ground_colour_code = ""
	return {"ok": true, "freed_owned_branch": had_viewport, "already_inactive": not had_viewport}

func _shader_role(material: ShaderMaterial) -> String:
	if material.shader == null: return ""
	if _owned_ground_material_ids.has(material.get_instance_id()) and material.shader == _owned_ground_colour:
		return "ground"
	return str(_source_shader_kinds.get(material.shader.code.sha256_text(), ""))

func register_owned_ground_colour(shader: Shader, materials: Array) -> Dictionary:
	if shader == null or shader.code.sha256_text() != OWNED_GROUND_COLOUR_SHA: return _error("Owned Ground colour adapter SHA changed")
	if FileAccess.get_sha256(shader.resource_path.get_base_dir().path_join("receiver_ring_interface.gdshaderinc")) != OWNED_COLOUR_INCLUDE_SHA: return _error("Owned Ground colour include SHA changed")
	var staged: Dictionary = {}
	for row: Dictionary in _rows:
		if row.kind == "ground": staged[row.material.get_instance_id()] = true
	var admitted: Dictionary = {}
	for value: Variant in materials:
		if not value is ShaderMaterial or not staged.has(value.get_instance_id()): return _error("Owned colour registration requires staged Ground material identity")
		admitted[value.get_instance_id()] = true
	if admitted.size() != staged.size(): return _error("All staged Ground materials must be installed/restored together")
	_owned_ground_colour = shader; _owned_ground_colour_code = shader.code; _owned_ground_material_ids = admitted
	return {"ok": true}

func set_size(raster_size: Vector2i) -> Dictionary:
	if raster_size.x <= 0 or raster_size.y <= 0 or raster_size.x * raster_size.y > MAX_PIXELS: return _error("Explicit positive raster exceeds pixel cap")
	if not is_instance_valid(_source_viewport) or Vector2i(_source_viewport.get_texture().get_size()) != raster_size: return _error("Size must match actual source viewport texture raster")
	_size = raster_size
	if is_instance_valid(_viewport): _viewport.size = raster_size; _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sync_ok = false
	return {"ok": true}

func _sync_source_error(row: Dictionary) -> String:
	var source: GeometryInstance3D = row.source
	if row.kind == "caster" and source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return "Admitted caster became cast OFF; restage explicit inputs"
	if not source.is_inside_tree() or source.get_world_3d() != _source_world or (source != _view and not _view.is_ancestor_of(source)): return "Source geometry moved outside staged branch/world; restage"
	if source.material_overlay != null or source.transparency != 0.0 or source.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED or not source.global_transform.is_finite(): return "Source opacity/pose changed outside admitted semantics; restage"
	var mesh := _mesh(source)
	if mesh != row.mesh or (source is MultiMeshInstance3D and source.multimesh != row.multimesh): return "Source mesh/MultiMesh identity changed; restage"
	if mesh == null or mesh.get_surface_count() != row.slots.size(): return "Source mesh topology/slot count changed; restage"
	if (mesh is ArrayMesh and mesh.get_blend_shape_count() != 0) or (source is MeshInstance3D and source.skin != null) or (source is MultiMeshInstance3D and source.multimesh.transform_format != MultiMesh.TRANSFORM_3D): return "Source skin/blendshape/MultiMesh format changed outside admitted semantics; restage"
	for surface in range(row.slots.size()):
		var slot: Dictionary = row.slots[surface]
		var material: Material = _active_material(source, surface)
		if material != slot.material: return "Source material identity changed; restage"
		if slot.kind == "null":
			if _registered_opaque_casters.get(source.get_instance_id(), "") != "null_shadow_proxy" or not _is_null_shadow_proxy(source): return "Admitted null shadow proxy semantics changed; restage"
			continue
		if material == null or material.next_pass != null: return "Source material/pass changed; restage"
		if slot.kind == "standard":
			if not material is StandardMaterial3D or not _standard_is_opaque(material) or _standard_opacity_fields(material) != slot.opacity: return "Admitted Standard caster opacity fields changed; restage"
			continue
		if not material is ShaderMaterial: return "Source shader material type changed; restage"
		if row.kind == "ground" and _owned_ground_material_ids.has(material.get_instance_id()) and material.shader == _owned_ground_colour:
			if material.shader.code != _owned_ground_colour_code: return "Owned Ground colour shader code changed; restage"
		elif material.shader != slot.shader or material.shader.code != slot.code:
			return "Source shader identity/code changed; restage with reviewed exact pins"
	return ""

func pause_updates() -> void:
	if is_instance_valid(_viewport): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func check_source_current() -> Dictionary:
	if not is_instance_valid(_view) or not is_instance_valid(_camera) or not is_instance_valid(_sun) or not is_instance_valid(_source_viewport): return _error("Staged source identity was freed; restage")
	if _view.get_world_3d() != _source_world or _camera.get_world_3d() != _source_world or _sun.get_world_3d() != _source_world or _camera.get_viewport() != _source_viewport or _view.get_viewport() != _source_viewport: return _error("Staged source World/viewport identities changed; restage")
	if _source_viewport.get_camera_3d() != _camera: return _error("Current source camera changed; restage")
	if _source_viewport.scaling_3d_scale != 1.0 or _source_viewport.use_taa or _source_viewport.msaa_3d != Viewport.MSAA_DISABLED or _source_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED: return _error("Source AA/upscaling setting changed; restage")
	var pose_current := true
	for row: Dictionary in _rows:
		if not is_instance_valid(row.source): return _error("Staged source geometry was freed; restage")
		var reason := _sync_source_error(row)
		if not reason.is_empty(): return _error(reason)
		if row.has("clone") and is_instance_valid(row.clone):
			pose_current = pose_current and row.clone.global_transform == row.source.global_transform and row.clone.visible == row.source.is_visible_in_tree()
	return {"ok": true, "pose_current": pose_current}

func _is_null_shadow_proxy(node: GeometryInstance3D) -> bool:
	var mesh := _mesh(node)
	return node is MeshInstance3D and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and mesh is ArrayMesh and mesh.get_surface_count() == 1 and node.material_override == null and node.material_overlay == null and node.get_surface_override_material(0) == null and mesh.surface_get_material(0) == null and node.skin == null

func _standard_is_opaque(material: StandardMaterial3D) -> bool:
	return material.next_pass == null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a >= 1.0 and material.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED and not material.proximity_fade_enabled

func _standard_opacity_fields(material: StandardMaterial3D) -> Array:
	return [material.transparency, material.albedo_color, material.distance_fade_mode, material.proximity_fade_enabled, material.next_pass]
