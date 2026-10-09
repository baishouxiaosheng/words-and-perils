extends Node3D
## Physicsless exact renderer picking. Shared mesh BVHs + spatial MultiMesh buckets.
## One selected silhouette/glyph, zero physics nodes per tree.
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Creative = preload("res://view/playable_build/creative_content.gd")
var board: Node3D
var observed_world_view: Node3D
var buckets: Array = []
var rows: Dictionary = {}
var mesh_queries: Dictionary = {}
var mesh_bounds: Dictionary = {}
var selected_reference: Dictionary = {}
var outline: MeshInstance3D
var glyph: Label3D
var outline_material: ShaderMaterial
var ready_catalog := false
var last_state_version := -1
var last_world_id := ""
var last_entity_signature := "unconfigured"
var contact_restore: Dictionary = {}
var original_contact_strength := -1.0
var diagnostics := {"tested_groups": 0, "tested_instances": 0, "triangle_queries": 0, "physics_nodes": 0}

func _ready() -> void:
	outline_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_front, shadows_disabled; uniform float edge_width=0.035; void vertex(){VERTEX+=NORMAL*edge_width;} void fragment(){ALBEDO=vec3(1.0,0.84,0.36); EMISSION=ALBEDO*0.3;}"
	outline_material.shader = shader
	outline = MeshInstance3D.new(); outline.name = "SelectedEnvironmentalEdge"; outline.material_override = outline_material; outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(outline); outline.hide()
	glyph = Label3D.new(); glyph.name = "SelectedEnvironmentalGlyph"; glyph.text = "◆"; glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED; glyph.font_size = 24; glyph.outline_size = 0; glyph.pixel_size = 0.001; glyph.modulate = Color("ffdf94"); add_child(glyph); glyph.hide()

func configure(owner_board: Node3D) -> bool:
	_restore_contact_field()
	board = owner_board
	if not is_instance_valid(observed_world_view) or observed_world_view != board.world_view:
		if is_instance_valid(observed_world_view):
			observed_world_view.whole_canopies_changed.disconnect(_canopy_renderer_changed)
			observed_world_view.canopy_support_changed.disconnect(_canopy_renderer_changed)
		observed_world_view = board.world_view
		observed_world_view.whole_canopies_changed.connect(_canopy_renderer_changed)
		observed_world_view.canopy_support_changed.connect(_canopy_renderer_changed)
	# Clear before validation: a failed configure must never expose retired nodes.
	ready_catalog = false
	buckets.clear(); rows.clear(); mesh_queries.clear(); mesh_bounds.clear()
	outline.hide(); outline.mesh = null; glyph.hide()
	if not Catalog.ready() or not is_instance_valid(board.world_view.whole_canopies) or not is_instance_valid(board.world_view.natural_shorelines): return false
	for source_group in board.world_view.whole_canopies.groups:
		var entries: Array = []
		var bounds := AABB(); var first := true
		for k in range(source_group.rows.size()):
			var row: int = source_group.rows[k]; var id := Catalog.tree_id(row)
			if id.is_empty(): continue
			var transform_: Transform3D = Catalog.instance_transform(row)
			if not board.world_view.natural_shorelines.visible:
				# The immutable catalog remains v03; fallback height comes from
				# the verified raw source row, never an already-posed display node.
				# Reconfiguration must not accumulate the fallen pose's +0.025.
				transform_.origin.y = board.world_view.whole_canopies.instance_rows[row*10+1]
			if absf(transform_.basis.determinant()) < 0.000000000001: continue
			var entry := {"id": id, "row": row, "index": k, "near": source_group.near, "far": source_group.far, "base": transform_, "current": transform_}
			rows[id] = entry; entries.append(entry)
			var box: AABB = source_group.near.global_transform * transform_ * _bounds(source_group.near.multimesh.mesh)
			bounds = box if first else bounds.merge(box); first = false
		if not entries.is_empty(): buckets.append({"source": source_group, "entries": entries, "bounds": bounds.grow(1.2)})
	# Mountain source mapping uses this same visible CPU face list. Keep its
	# broad-phase box deterministic even when a headless renderer has no GPU AABB.
	if is_instance_valid(board.world_view.faceted_mountains):
		for group in board.world_view.faceted_mountains.pick_groups:
			var vertices: PackedVector3Array = group.vertices
			if vertices.is_empty(): continue
			var bounds := AABB(vertices[0],Vector3.ZERO)
			for vertex in vertices: bounds=bounds.expand(vertex)
			group.bounds=bounds
	ready_catalog = true; last_state_version = -1; last_entity_signature = "unconfigured"
	sync_state(board.world_state)
	return true

func _canopy_renderer_changed() -> void:
	if is_instance_valid(board): configure(board)

func _restore_contact_field() -> void:
	for stored in contact_restore.values(): stored.material.set_shader_parameter("canopy_contact_strength", stored.value)
	contact_restore.clear()
	if original_contact_strength >= 0 and is_instance_valid(board) and is_instance_valid(board.world_view) and is_instance_valid(board.world_view.clear_daylight_profile):
		board.world_view.clear_daylight_profile.contact_strength = original_contact_strength
	original_contact_strength = -1.0

func _query(mesh: Mesh) -> TriangleMesh:
	var id := mesh.get_instance_id()
	if not mesh_queries.has(id):
		var query := TriangleMesh.new(); query.create_from_faces(mesh.get_faces()); mesh_queries[id] = query
	return mesh_queries[id]

func _mesh_hit(mesh: Mesh, transform_: Transform3D, origin: Vector3, direction: Vector3) -> Dictionary:
	if mesh == null or absf(transform_.basis.determinant()) < 0.000000000001: return {}
	var box: AABB = transform_ * _bounds(mesh)
	if box.grow(0.0001).intersects_ray(origin, direction) == null: return {}
	var inverse := transform_.affine_inverse()
	var hit := _query(mesh).intersect_ray(inverse * origin, (inverse.basis * direction).normalized())
	diagnostics.triangle_queries += 1
	if hit.is_empty(): return {}
	var position_: Vector3 = transform_ * hit.position
	return {"position": position_, "distance": origin.distance_to(position_), "face_index": hit.face_index}

func hit_node(node: Node, origin: Vector3, direction: Vector3) -> Dictionary:
	var best: Dictionary = {}
	if node is Node3D and not node.is_visible_in_tree(): return best
	if node is MeshInstance3D and node.mesh != null and node.name != "SelectedEdgeGlow": best = _mesh_hit(node.mesh, node.global_transform, origin, direction)
	for child in node.get_children():
		if child.name == "SelectedEdgeGlow": continue
		var hit := hit_node(child, origin, direction)
		if not hit.is_empty() and (best.is_empty() or hit.distance < best.distance): best = hit
	return best

func pick(point: Vector2, max_distance: float = INF) -> Array:
	var found: Array = []
	if not ready_catalog: return found
	var origin: Vector3 = board.camera.project_ray_origin(point); var direction: Vector3 = board.camera.project_ray_normal(point)
	diagnostics = {"tested_groups": 0, "tested_instances": 0, "triangle_queries": 0, "physics_nodes": 0}
	for bucket in buckets:
		var source: Dictionary = bucket.source
		var node: MultiMeshInstance3D = source.near if source.near.is_visible_in_tree() else source.far
		if not node.is_visible_in_tree() or bucket.bounds.intersects_ray(origin, direction) == null: continue
		diagnostics.tested_groups += 1
		for entry in bucket.entries:
			diagnostics.tested_instances += 1
			var transform_: Transform3D = node.global_transform * entry.current
			var hit := _mesh_hit(node.multimesh.mesh, transform_, origin, direction)
			if hit.is_empty() or hit.distance > max_distance+0.01: continue
			var reference := Catalog.make_reference(entry.id, board.world_state)
			if reference.is_empty(): continue
			found.append({"reference": reference, "label": Catalog.descriptor(entry.id).name+" · 树木", "distance": hit.distance, "hit_position": hit.position, "render_instance_row": entry.row})
	if is_instance_valid(board.settlement_view):
		for subject in board.settlement_view.selection_nodes():
			var hit := hit_node(subject.node,origin,direction)
			if not hit.is_empty() and hit.distance<=max_distance+0.01:
				var reference := Catalog.make_reference(subject.id,board.world_state,subject.hex)
				if not reference.is_empty():
					var descriptor_:Dictionary=Catalog.descriptor(subject.id)
					var category:String="分区" if descriptor_.kind=="district" else {"village":"村庄","city_state":"城邦","large_city":"城市","lift_gate":"城门","hinged_gate":"城门"}.get(descriptor_.public_facts.visible_form,"聚落")
					found.append({"reference":reference,"label":descriptor_.name+" · "+category,"distance":hit.distance,"hit_position":hit.position})
	if is_instance_valid(board.creative_view):
		for subject in board.creative_view.selection_nodes():
			var hit := hit_node(subject.node, origin, direction)
			if hit.is_empty() or hit.distance > max_distance + 0.01: continue
			var reference := Creative.make_reference(subject.id, board.world_state)
			if not reference.is_empty():
				var label: String = subject.title.text
				found.append({"reference": reference, "label": label, "distance": hit.distance, "hit_position": hit.position})
	if is_instance_valid(board.lighthouse):
		var hit := hit_node(board.lighthouse, origin, direction)
		if not hit.is_empty() and hit.distance <= max_distance+0.01:
			var reference := Catalog.make_reference(Catalog.lamp_id(), board.world_state)
			if not reference.is_empty(): found.append({"reference": reference, "label": "旧灯 · 物件", "distance": hit.distance, "hit_position": hit.position})
	found.sort_custom(func(a,b): return a.distance < b.distance)
	# Only foremost visible environmental surface is directly selected. Ground is
	# appended separately as a deliberate alternate, never an inferred action.
	if found.size() > 1: found.resize(1)
	return found

func sync_state(state: Dictionary) -> void:
	if not ready_catalog or state.is_empty(): return
	var signature := JSON.stringify({"environment":state.get("environment_entities", {}),"settlement":state.get("settlement_state",{}),"creative_relations":state.get("creative_relations",{}),"creative_placements":state.get("creative_placements",{}),"physical_items":state.get("items",{})}, "", true, true)
	if last_entity_signature == signature and last_world_id == str(state.world_id): return
	last_state_version = int(state.state_version); last_world_id = str(state.world_id); last_entity_signature = signature
	for id in rows:
		var entry: Dictionary = rows[id]; var transform_: Transform3D = entry.base
		if state.get("environment_entities", {}).has(id) and Catalog.state_for(id,state).get("posture") == "fallen":
			# Pose this instance around its existing root. Its source geography and
			# immutable support descriptor remain untouched; collision is core state.
			transform_.basis = Basis(Vector3.FORWARD, -PI*0.48) * transform_.basis
			transform_.origin.y += 0.025
		entry.current = transform_
		for node in [entry.near,entry.far]: node.multimesh.set_instance_transform(entry.index, transform_)
	if not state.get("environment_entities", {}).is_empty():
		if is_instance_valid(board.world_view.clear_daylight_profile):
			if original_contact_strength < 0: original_contact_strength = board.world_view.clear_daylight_profile.contact_strength
			board.world_view.clear_daylight_profile.contact_strength = 0.0
		_disable_stale_contact_field(board.world_view)
	else:
		_restore_contact_field()
	select(selected_reference)

func _disable_stale_contact_field(node: Node) -> void:
	if node is GeometryInstance3D and node.material_override is ShaderMaterial:
		var material: ShaderMaterial = node.material_override
		for parameter in material.shader.get_shader_uniform_list():
			if parameter.name == "canopy_contact_strength":
				if not contact_restore.has(material.get_instance_id()): contact_restore[material.get_instance_id()] = {"material": material, "value": material.get_shader_parameter("canopy_contact_strength")}
				material.set_shader_parameter("canopy_contact_strength", 0.0)
	for child in node.get_children(): _disable_stale_contact_field(child)

func select(reference: Dictionary) -> void:
	selected_reference = reference.duplicate(true)
	outline.hide(); glyph.hide()
	if is_instance_valid(board) and is_instance_valid(board.creative_view): board.creative_view.clear_selection()
	if reference.is_empty() or not ready_catalog: return
	if reference.get("catalog_version") == Creative.FOCUS_VERSION:
		if is_instance_valid(board.creative_view): board.creative_view.select(str(reference.get("id", "")))
		return
	var value := Catalog.entity(str(reference.get("id", "")), board.world_state)
	if value.is_empty(): return
	if value.kind == "tree" and rows.has(value.id):
		var entry: Dictionary = rows[value.id]
		var node: MultiMeshInstance3D = entry.near if entry.near.is_visible_in_tree() else entry.far
		outline.mesh = node.multimesh.mesh; outline.global_transform = node.global_transform * entry.current
		outline.show(); glyph.global_position = _glyph_position(); glyph.show()
	elif value.kind == "mountain" and is_instance_valid(board.world_view.faceted_mountains):
		for node in board.world_view.faceted_mountains.get_children():
			if node is MeshInstance3D and node.get_meta("source_region", "") == value.source.source_region:
				outline.mesh = node.mesh; outline.global_transform = node.global_transform; outline.show()
				var box: AABB = _bounds(node.mesh); glyph.global_position = node.global_transform * (box.position+box.size*Vector3(0.5,1.0,0.5)); glyph.show(); break
	elif value.kind in ["settlement","district"] and is_instance_valid(board.settlement_view):
		for subject in board.settlement_view.selection_nodes():
			if subject.id==value.id:
				board.attention_glow.select_actor(value.id,{value.id:subject.node})
				# City/district outlines and the existing title are sufficient; a tall
				# generic tree glyph would float far above these compact rooftops.
				break
	elif value.kind == "prop":
		board.attention_glow.select_actor(value.id, {value.id: board.lighthouse})
		glyph.global_position = board.lighthouse.global_position+Vector3(0,1.6,0); glyph.show()

func clear() -> void: select({})
func report() -> Dictionary:
	var result := Catalog.coverage(board.world_state); result["indexed_visible_instances"] = rows.size(); result["spatial_buckets"] = buckets.size(); result["shared_mesh_bvhs"] = mesh_queries.size(); result["physics_nodes"] = 0; result["static_contact_field_disabled_after_change"] = original_contact_strength >= 0; result["last_pick"] = diagnostics.duplicate(); return result

func _process(_delta: float) -> void:
	if is_instance_valid(board) and is_instance_valid(board.camera):
		glyph.pixel_size = 16.0 * board.camera.size / (float(glyph.font_size) * maxf(1.0, board.get_viewport().get_visible_rect().size.y))
	# LOD changes swap the selected shell to the same displayed mesh identity.
	if not ready_catalog or selected_reference.get("kind") != "tree" or not rows.has(selected_reference.get("id")): return
	var entry: Dictionary = rows[selected_reference.id]
	var node: MultiMeshInstance3D = entry.near if entry.near.is_visible_in_tree() else entry.far
	outline.visible = node.is_visible_in_tree(); glyph.visible = outline.visible
	if not outline.visible: return
	outline.mesh = node.multimesh.mesh
	outline.global_transform = node.global_transform * entry.current
	glyph.global_position = _glyph_position()

func _glyph_position() -> Vector3:
	var box: AABB = outline.global_transform * _bounds(outline.mesh)
	return box.position+box.size*Vector3(0.5,1.0,0.5)+Vector3(0,0.12,0)

func _bounds(mesh: Mesh) -> AABB:
	var id := mesh.get_instance_id()
	if not mesh_bounds.has(id):
		var faces := mesh.get_faces()
		var box := AABB(faces[0],Vector3.ZERO) if not faces.is_empty() else AABB()
		for vertex in faces: box=box.expand(vertex)
		mesh_bounds[id]=box
	return mesh_bounds[id]
