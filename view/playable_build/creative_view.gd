extends Node3D
## Native visual truth for authored passages and the same three conserved items.
## No colliders, speculative relocation or gameplay writes. The canonical effects
## own ground edge restrictions; this node only projects committed state.
const Content = preload("res://view/playable_build/creative_content.gd")
const UNIT := Content.WORLD_UNITS_PER_MM
const STONE := Color("b4b3a1")
const SHADOW_STONE := Color("858b81")
const CONTACT := Color("456b6d")
var board: Node3D
var passage_nodes: Dictionary = {}
var item_nodes: Dictionary = {}
var labels: Array = []
var _last_signature := ""
var _enabled := false
var _selected_id := ""
var diagnostics := {"passages": 0, "items": 0, "ground_items": 0, "carried_items": 0, "braced_items": 0, "loose_items": 0, "physics_nodes": 0, "source_bound": true}

func configure(owner_board: Node3D) -> void:
	board = owner_board
	process_priority = 20 # After actor motion; before the shared label-density pass.
	for child in get_children():
		remove_child(child); child.queue_free()
	passage_nodes.clear(); item_nodes.clear(); labels.clear(); _last_signature = ""
	var manifest := Content.manifest()
	if manifest.is_empty(): return
	for target in manifest.passage_targets.values(): _build_passage(target, manifest.geometry[target.id])
	for id in Content.ITEM_IDS: _build_item(id, manifest.item_profiles[manifest.items[id].profile_id])
	hide()

func _box(parent: Node3D, size_: Vector3, position_: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size_; node.mesh = mesh
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 0.95
	node.material_override = material; node.position = position_; parent.add_child(node)
	return node

func _label(parent: Node3D, text_: String, at: Vector3) -> Label3D:
	var label := Label3D.new(); label.text = text_; label.position = at
	label.set_meta("label_anchor_local", at)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.font_size = 30; label.pixel_size = 0.003
	label.outline_size = 0; label.modulate = Color.WHITE; label.no_depth_test = false
	parent.add_child(label); labels.append(label); label.hide()
	return label

func _build_passage(target: Dictionary, geometry: Dictionary) -> void:
	var root := Node3D.new(); root.name = "AuthoredNarrowPassage_" + str(passage_nodes.size()); add_child(root)
	var pose := Content.pose(target.id, "braced")
	# One shared orientation and opening width are used for the physical contact
	# frame, stone aperture and all three deployed source meshes.
	root.transform = Transform3D(pose.basis, Vector3(pose.origin.x, 0, pose.origin.z))
	var opening := float(target.width_mm) * UNIT
	var span := float(geometry.cheek_span_mm) * UNIT
	var depth := float(geometry.cheek_depth_mm) * UNIT
	var height := float(geometry.cheek_height_mm) * UNIT
	for index in range(2):
		var sign_ := -1.0 if index == 0 else 1.0
		var base_y := float(geometry.cheek_ground[index].position[1])
		var x := sign_ * (opening * 0.5 + span * 0.5)
		# Low masonry cheeks make this a genuine narrow aperture, with a plainly
		# visible gap. These do not borrow settlement gate or wall identities.
		# The top is a real open-ended U-shaped channel, not a solid block
		# intersecting the beam. The same 0.14-wide throat accommodates the
		# maximum authored 0.11 section and each item's narrower visible section.
		var channel_floor := pose.origin.y - 0.024
		var lower_height := channel_floor - base_y + 0.012
		_box(root, Vector3(span, lower_height, depth), Vector3(x, base_y - 0.012 + lower_height * 0.5, 0), STONE)
		var lip_height := base_y + height - channel_floor
		for side in [-1.0, 1.0]:
			_box(root, Vector3(span, lip_height, 0.04), Vector3(x, channel_floor + lip_height * 0.5, side * 0.09), STONE)
			_box(root, Vector3(span + 0.016, 0.024, 0.048), Vector3(x, base_y + height + 0.012, side * 0.09), SHADOW_STONE)
		# Authored teal saddle contacts visibly explain the compatible bearing.
		var contact_x := sign_ * (opening * 0.5 + 0.036)
		_box(root, Vector3(0.072, 0.025, 0.14), Vector3(contact_x, pose.origin.y - 0.0235, 0), CONTACT)
		_box(root, Vector3(0.028, 0.12, 0.02), Vector3(contact_x, pose.origin.y + 0.020, -0.073), CONTACT)
		_box(root, Vector3(0.028, 0.12, 0.02), Vector3(contact_x, pose.origin.y + 0.020, 0.073), CONTACT)
	var center_ground := float(geometry.center.position[1])
	var title := _label(root, target.name + " · 窄口", Vector3(0, center_ground + height + 0.20, 0))
	passage_nodes[target.id] = {"id": target.id, "kind": "passage_edge", "node": root, "hex": target.support_hex.duplicate(), "title": title}
	diagnostics.passages = passage_nodes.size()

func _build_item(id: String, profile: Dictionary) -> void:
	var root := Node3D.new(); root.name = id; add_child(root)
	var traits: Dictionary = profile.physical_traits; var art: Dictionary = profile.presentation
	var length_ := float(traits.length_mm) * UNIT; var width := float(traits.section_mm) * UNIT
	var thickness := float(art.thickness_mm) * UNIT; var color := Color(str(art.color))
	var center_y := thickness * 0.5 - 22.5 * UNIT
	if art.form == "shaft_and_blade":
		# The joined shaft/blade covers precisely the declared length; the blade
		# is the widest section. This visual branch grants no executor capability.
		var blade_length := length_ * 0.24
		_box(root, Vector3(length_ - blade_length, thickness, thickness), Vector3(-blade_length * 0.5, center_y, 0), color)
		_box(root, Vector3(blade_length, thickness, width), Vector3((length_ - blade_length) * 0.5, center_y, 0), color.lightened(0.11))
	else:
		_box(root, Vector3(length_, thickness, width), Vector3(0, center_y, 0), color)
		if art.form == "rectangular_timber":
			# Shallow grain strips stay within the declared solid envelope.
			for offset in [-0.22, 0.22]: _box(root, Vector3(length_ * 0.92, 0.001, width * 0.045), Vector3(0, center_y + thickness * 0.5 - 0.0005, width * offset), color.darkened(0.18))
	var label_root := Node3D.new(); label_root.name = "ItemName"; add_child(label_root)
	var title := _label(label_root, Content.items()[id].name, Vector3.ZERO)
	item_nodes[id] = {"id": id, "kind": "item", "node": root, "hex": [], "title": title, "label_root": label_root, "owner_id": "", "carry_offset": Vector3.ZERO, "carry_label_height": 0.0}
	diagnostics.items = item_nodes.size()

func sync_state(state: Dictionary) -> void:
	_enabled = Content.active(state)
	visible = _enabled
	if not _enabled: return
	var signature := JSON.stringify({"world": state.world_id, "items": state.items, "actors": state.actors, "relations": state.creative_relations, "placements": state.creative_placements}, "", true, true)
	if signature == _last_signature: return
	_last_signature = signature
	diagnostics.ground_items = 0; diagnostics.carried_items = 0; diagnostics.braced_items = 0; diagnostics.loose_items = 0
	for id in passage_nodes:
		var blocked: bool = Content.entity_state(state, id).ground_blocking
		passage_nodes[id].title.text = state.passage_targets[id].name + (" · 已架挡" if blocked else " · 窄口")
	for index in range(Content.ITEM_IDS.size()):
		var id: String = Content.ITEM_IDS[index]; var row: Dictionary = item_nodes[id]; var item: Dictionary = state.items[id]
		var scene := Content.item_scene(id, state); var hex := Content.item_hex(id, state)
		row.hex = hex; row.node.visible = scene == Content.SCENE and hex.size() == 2
		row.label_root.visible = row.node.visible
		if not row.node.visible: continue
		var owner: String = str(item.get("owner_actor_id", ""))
		row.owner_id = owner
		var placement: Dictionary = state.creative_placements.get(id, {})
		var posture := "carried" if not owner.is_empty() else str(placement.get("posture", "ground"))
		if not placement.is_empty():
			row.node.transform = Content.pose(placement.target_id, posture)
			diagnostics["braced_items" if posture == "braced" else "loose_items"] += 1
		elif not owner.is_empty():
			# Carried models have their real authored dimensions; no duplicate
			# ground token or fake item is added. Position follows the owner only.
			var p: Vector3 = board._position(hex)
			var side := Vector3(0.30 + index * 0.095, 0.49, 0.08 + index * 0.055)
			row.carry_offset = side; row.carry_label_height = 0.54 + index * 0.12
			row.node.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), p + side)
			diagnostics.carried_items += 1
		else:
			var p: Vector3 = board._position(hex)
			row.node.transform = Transform3D(Basis(Vector3.UP, 0.20 * index), p + Vector3(0, 0.052, 0.20 + index * 0.13))
			diagnostics.ground_items += 1
		row.title.text = item.name + {"carried": " · 携带", "braced": " · 架挡", "loose": " · 松放", "ground": " · 落地"}.get(posture, "")
		row.label_root.position = row.node.position + Vector3(0, 0.18 if owner.is_empty() else 0.54 + index * 0.12, 0)
	_follow_carried_motion()
	for label in labels:
		if is_instance_valid(board.name_style): board.name_style.attach(label)
	_update_label_visibility()

func selection_nodes() -> Array:
	var result: Array = []
	if not _enabled: return result
	for row in passage_nodes.values(): result.append(row)
	for row in item_nodes.values():
		if row.node.visible: result.append(row)
	return result

func select(id: String) -> bool:
	_selected_id = id
	_update_label_visibility()
	var row: Dictionary = item_nodes.get(id, passage_nodes.get(id, {}))
	if row.is_empty() or not _enabled or not row.node.visible: return false
	board.attention_glow.select_actor(id, {id: row.node})
	return true

func clear_selection() -> void:
	_selected_id = ""
	_update_label_visibility()

func _update_label_visibility() -> void:
	for label in labels: label.hide()
	var row: Dictionary = item_nodes.get(_selected_id, passage_nodes.get(_selected_id, {}))
	if _enabled and not row.is_empty() and row.node.visible: row.title.show()

func report() -> Dictionary:
	var result := diagnostics.duplicate(true)
	result["label_policy"] = "selected_subject_only"
	result["selected_id"] = _selected_id
	result["visible_subject_labels"] = labels.filter(func(label): return label.visible).size()
	return result

func _process(_delta: float) -> void:
	if not _enabled or not is_instance_valid(board) or not is_instance_valid(board.camera): return
	_follow_carried_motion()
	var screen_height := maxf(1.0, board.get_viewport().get_visible_rect().size.y)
	for label in labels:
		label.pixel_size = 13.0 * board.camera.size / (float(label.font_size) * screen_height)
		var shadow: Sprite3D = label.get_node_or_null("SoftNameShadow")
		if shadow != null: shadow.pixel_size = label.pixel_size


func _follow_carried_motion() -> void:
	# Only the displayed origin follows the actual animated token. Keeping the
	# source under this unscaled parent avoids inheriting token scale/rotation and
	# preserves every authored object dimension and all canonical custody facts.
	for row in item_nodes.values():
		var owner: String = row.owner_id
		if owner.is_empty() or not row.node.visible or not board.token_nodes.has(owner): continue
		var token: Node3D = board.token_nodes[owner]
		if not is_instance_valid(token): continue
		row.node.position = to_local(token.global_position) + row.carry_offset
		row.label_root.position = row.node.position + Vector3(0, row.carry_label_height, 0)
