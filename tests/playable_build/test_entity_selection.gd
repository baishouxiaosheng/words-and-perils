extends SceneTree
const Main = preload("res://main.tscn")
const Adapter = preload("res://view/playable_build/adapter.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Effects = preload("res://core/ai_gm_rebuilt/generic_effects.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
const Focus = preload("res://core/focus_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var passed := 0
var failed: Array = []
var guard: Timer
func check(value: bool, label_: String) -> void:
	if value: passed += 1
	else: failed.append(label_); printerr("FAIL: "+label_)
func _initialize() -> void:
	call_deferred("install_watchdog")
	call_deferred("run")
func install_watchdog() -> void:
	guard=Timer.new(); guard.one_shot=true; guard.wait_time=120; root.add_child(guard)
	guard.timeout.connect(_watchdog_expired); guard.start()
func _watchdog_expired() -> void:
	printerr("ENTITY_SELECTION_TIMEOUT"); quit(2)
func run() -> void:
	var adapter := Adapter.new(18); var state := adapter.state_copy()
	check(adapter.engine.ready().ok, "new world engine valid")
	check(Catalog.ready(), "bundle-bound entity catalog valid: "+Catalog.last_error)
	print("CATALOG ", Catalog.coverage())
	check(Catalog.coverage().mountain_groups==11, "all eleven rendered mountain groups registered")
	var small_mountain := Catalog.mountain_id("mountain:face:38676:component:2437")
	check(not small_mountain.is_empty() and not Catalog.descriptor(small_mountain).public_facts.support_hexes.is_empty(), "small visible mountain without a centre-cell label has exact support")
	var tree_id := Catalog.tree_id(0)
	# First row is halo; select an actual playable catalog entry deterministically.
	for i in range(7261):
		if not Catalog.tree_id(i).is_empty(): tree_id = Catalog.tree_id(i); break
	var reference := Catalog.make_reference(tree_id,state)
	var before := C.bytes(state)
	check(not reference.is_empty(), "real tree has stable source identity")
	var selected: Dictionary = adapter.engine.attention(reference)
	check(selected.ok and selected.focus.kind == "tree", "current rendered source tree focus resolves")
	check(C.bytes(adapter.state_copy()) == before, "selection alone does not mutate world/cost/turn")
	check(not adapter.begin_intent("", reference).ok, "selection cannot become a command")
	check(adapter.begin_intent("不要碰这棵树，我想观察旧灯。", reference).ok, "explicit different target remains natural text")
	var request := adapter.request()
	check(request.context.goal == "不要碰这棵树，我想观察旧灯。" and request.context.text_priority == "explicit_player_text", "text priority and exact intent preserved")
	check(request.context.attention_focus.id == tree_id and request.context.attention_focus.facts.entity.source.has("new_source_face_index"), "DecisionModel focus has actual source provenance")
	check(not C.bytes(request).contains("rng_before") and request.context.facts.environment_entities.is_empty(), "public context bounded sparse world and no RNG")
	check(adapter.save_file("user://entity_focus_pending.json").ok, "pending focus save")
	var restored := Adapter.new(19)
	check(restored.load_file("user://entity_focus_pending.json").ok and C.bytes(restored.request()) == C.bytes(request), "load preserves frozen public tree request")
	var bad := reference.duplicate(true); bad.hex = [999,999]
	check(not adapter.engine.attention(bad).ok, "out-of-world object reference rejected")
	bad = reference.duplicate(true); bad.id += ":missing"
	check(not adapter.engine.attention(bad).ok, "missing object ID rejected")
	bad = reference.duplicate(true); bad.entity_revision = 1
	check(not adapter.engine.attention(bad).ok, "stale object revision rejected")
	bad = reference.duplicate(true); bad.world_id = "old-world"
	check(not adapter.engine.attention(bad).ok, "wrong-world object rejected")
	check(Catalog.coverage().settlements == 0, "no city invented for absent scene asset")
	var changed := state.duplicate(true)
	var descriptor := Catalog.descriptor(tree_id)
	# Find a mutable source tree on an initially passable cell for state tests.
	for i in range(7261):
		var id := Catalog.tree_id(i)
		if id.is_empty(): continue
		var candidate := Catalog.descriptor(id)
		if not changed.hexes["%d,%d" % candidate.hex].ground_blocked: descriptor=candidate; break
	var focus_contract := Focus.new()
	var standing: Dictionary = focus_contract.resolve(Catalog.make_reference(descriptor.id, changed), changed).focus
	check(Effects.apply_fell(changed,{"type":"environment_fell","entity_id":descriptor.id,"expected_revision":0,"cell_id":changed.hexes["%d,%d"%descriptor.hex].id}).ok, "source tree effect creates sparse changed facts")
	var fallen: Dictionary = focus_contract.resolve(Catalog.make_reference(descriptor.id, changed), changed).focus
	check(fallen.facts.entity.public_facts.visible_form == "fallen_vegetation", "current fallen context never describes a standing tree")
	check(focus_contract.validate_historical(standing,changed).is_empty() and focus_contract.validate_historical(fallen,changed).is_empty(), "pre-fall and post-fall historical descriptors remain exact")
	var parsed_world: Dictionary = JSON.parse_string(C.bytes(changed))
	var parsed_focus: Dictionary = JSON.parse_string(C.bytes(fallen))
	check(Effects.validate_environment(parsed_world).ok and focus_contract.validate_historical(parsed_focus,parsed_world).is_empty(), "real JSON integral numbers preserve sparse fallen and historical focus contracts")
	var fractional: Dictionary = parsed_world.environment_entities[descriptor.id].duplicate(true); fractional.state.revision=1.25
	check(not Catalog.validate_record(descriptor.id,fractional) and not Catalog.same_hex([1,2.25],[1,2]), "fractional revisions and coordinates remain rejected")
	var projected := ModelView.facts(changed,{"npc_secret_allowlist":[],"public_flag_ids":[]})
	check(projected.environment_entities[descriptor.id].hex == descriptor.hex and projected.environment_entities[descriptor.id].public_facts.visible_form=="fallen_vegetation", "later public world context retains object consequence without selected focus")
	root.size=Vector2i(1920,1080)
	var scene = Main.instantiate(); root.add_child(scene)
	await process_frame; await process_frame
	var board = scene.board
	check(board.entity_selection.ready_catalog, "actual main installs renderer identity index")
	print("RENDER CATALOG ", board.entity_selection.report())
	var selected_id := Catalog.tree_id(1148)
	var screen := Vector2.ZERO
	var ids: Array = board.entity_selection.rows.keys()
	# Choose a real full-size tree, not a tiny ground shrub.
	for id in ([] if not selected_id.is_empty() else ids):
		var entity := Catalog.descriptor(id)
		if entity.public_facts.vegetation_type != "temperate": continue
		selected_id = id; break
	check(not selected_id.is_empty(), "actual main contains indexed forest tree")
	if not selected_id.is_empty():
		var entry: Dictionary = board.entity_selection.rows[selected_id]
		var node: MultiMeshInstance3D = entry.near
		var transform_: Transform3D = node.global_transform * entry.current
		board.world_view.overview = false; board.world_view.target = transform_.origin+Vector3(0,.2,0); board.world_view.pitch=1.2; board.world_view.yaw=.2; board.world_view.distance=8; board.camera.size=2.0; board.world_view._update_camera()
		await process_frame
		var faces := node.multimesh.mesh.get_faces()
		var found := false
		for i in range(0, faces.size(),3):
			screen = board.camera.unproject_position(transform_*((faces[i]+faces[i+1]+faces[i+2])/3.0))
			var hits: Array = board.entity_selection.pick(screen)
			if not hits.is_empty() and hits[0].reference.id == selected_id: found=true; break
		print("TREE_PICK_DEBUG ", selected_id, " ", node.is_visible_in_tree(), " ", board.entity_selection.diagnostics, " ", screen, " ", board.entity_selection.pick(screen))
		check(found, "ray intersects exact source MultiMesh forest triangles")
		if found:
			var candidates: Array = board.pick_focus(screen)
			check(not candidates.is_empty() and candidates[0].reference.id == selected_id, "default board selects visible tree before source tile")
			if not candidates.is_empty(): scene.on_focus_candidates(candidates,screen)
			check(scene.selected_focus.id == selected_id and board.entity_selection.outline.visible and board.entity_selection.glyph.visible, "actual main focus has edge and glyph without action")
			check(scene.active_action.is_empty() and scene.playtest.state_copy().turn==0, "actual renderer selection spends no turn")
			print("SELECTED_TREE ", selected_id, " ", screen)
	# Existing old-lamp prop selection is geometry-backed and separately identified.
	board.world_view.target=board.lighthouse.global_position+Vector3(0,.8,0);board.camera.size=3;board.world_view._update_camera()
	var lamp_screen: Vector2=board.camera.unproject_position(board.lighthouse.lantern.global_position)
	var lamp_hits: Array=board.pick_focus(lamp_screen)
	check(not lamp_hits.is_empty() and lamp_hits[0].reference.id==Catalog.lamp_id(), "old lamp actual mesh selectable as prop")
	# A highest actual visual face must resolve the same real mountain group and
	# clicked source cell, not the ground behind the mountain.
	var mountains = board.world_view.faceted_mountains
	var mountain_id := ""; var mountain_point := Vector3.ZERO
	for group in mountains.pick_groups:
		mountain_id=Catalog.mountain_id(str(group.source_region))
		if mountain_id.is_empty(): continue
		var vertices: PackedVector3Array=group.vertices; var top := -INF
		for i in range(0,vertices.size(),3):
			var center := (vertices[i]+vertices[i+1]+vertices[i+2])/3.0
			if center.y>top: top=center.y; mountain_point=mountains.to_global(center)
		break
	board.world_view.target=mountain_point;board.camera.size=6;board.world_view.pitch=1.4;board.world_view.distance=10;board.world_view._update_camera()
	await process_frame
	var mountain_hits: Array=board.pick_focus(board.camera.unproject_position(mountain_point))
	check(not mountain_hits.is_empty() and mountain_hits[0].reference.id==mountain_id and mountain_hits[0].reference.kind=="mountain", "actual highest mountain face resolves stable group before source tile")
	if not mountain_hits.is_empty() and mountain_hits[0].reference.kind=="mountain":
		scene._apply_focus(mountain_hits[0].reference)
		check(board.entity_selection.outline.visible and board.entity_selection.glyph.visible, "mountain selection has edge and glyph")
	print("ENTITY_SELECTION ", passed, "/", passed+failed.size())
	var report := {"passed":passed,"failed":failed,"coverage":Catalog.coverage(),"render":board.entity_selection.report(),"tree_id":selected_id,"live_model":false}
	var file:=FileAccess.open("res://tests/playable_build/entity_selection_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	scene.free(); guard.stop(); guard.free(); quit(0 if failed.is_empty() else 1)
