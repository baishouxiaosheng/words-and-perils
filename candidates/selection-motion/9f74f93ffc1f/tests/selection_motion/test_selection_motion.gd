extends SceneTree
## Bounded fixture suite. Run only in an approved isolated Godot test project.
const Catalog = preload("res://view/attention_catalog.gd")
const Motion = preload("res://view/tabletop_interaction/selection_motion.gd")
class Presenter extends Node3D:
	var actors: Dictionary = {}
class Board extends Node3D:
	var token_nodes: Dictionary = {}
	var inventory_packs: Dictionary = {}
	var world_state := {"world_id": "fixture", "state_version": 0, "turn": 0, "rng": 37, "actors": {"a": {"health": {"current": 5}, "hex": [0, 0]}}, "items": {}}
	var presentation: Node3D
	var route_root: Node3D
class ItemView extends Node3D:
	var pack: Node3D
class Host extends Control:
	var board: Node3D
	var selected_focus: Dictionary = {}
	var movement_preview: Dictionary = {}
	var world_build_busy := false
	var generated_start_busy := false
var failures: Array[String] = []
var passed := 0
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var host := Host.new(); root.add_child(host)
	var board := Board.new(); host.add_child(board); host.board = board
	board.presentation = Presenter.new(); board.add_child(board.presentation)
	var token := Node3D.new(); token.scale = Vector3(0.62, 0.62, 0.62); board.add_child(token)
	board.token_nodes.a = token; board.presentation.actors.a = {"moving": false}
	var mesh := BoxMesh.new()
	var body := MeshInstance3D.new(); body.mesh = mesh; body.position = Vector3(0.1, 0.8, 0); token.add_child(body)
	var shell := MeshInstance3D.new(); shell.mesh = mesh; shell.name = "SelectedEdgeGlow"; body.add_child(shell)
	var sibling := MeshInstance3D.new(); sibling.mesh = mesh; board.add_child(sibling)
	var label := Label3D.new(); token.add_child(label)
	var batched := MultiMeshInstance3D.new(); token.add_child(batched)
	var motion := Motion.new(host); host.add_child(motion); motion.set_process(false); motion._board = board
	var base := body.transform; var root_base := token.transform; var sibling_base := sibling.transform
	var world_before := JSON.stringify(board.world_state)
	var focus := {"world_id": "fixture", "kind": "actor", "id": "a", "hex": [0, 0]}
	var baseline_catalog := Catalog.new(); baseline_catalog.capture(focus, "fixture actor", token, true)
	motion._observe({}, {}, "v0", true)
	motion._observe(focus, {}, "v0", true)
	check(motion._parts.size() == 1, "only mesh body, no label/MultiMesh/double shell")
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	check(is_equal_approx(body.global_position.y - token.to_global(base.origin).y, Motion.ACTOR_HOP), "global vertical hop respects scaled root")
	check(token.transform == root_base and shell.transform == Transform3D.IDENTITY, "root and nested shell transform unchanged")
	check(sibling.transform == sibling_base and body.mesh == sibling.mesh, "shared mesh and other instance untouched")
	var peak := body.transform
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	check(body.transform == peak, "sampling never accumulates")
	var tween = motion._motion_tween
	for i in range(30): motion._observe(focus, {}, "v0", true)
	check(motion._motion_tween == tween and body.transform == peak, "same selection does not stack or restart")
	motion._observe({}, {}, "v0", true)
	check(body.transform == base and motion._parts.is_empty(), "clear restores exact transform")
	motion._observe(focus, {}, "v0", true)
	motion._apply_motion(0.5, Motion.ITEM_HOP, 0.04)
	check(body.transform.basis.get_scale().x > base.basis.get_scale().x, "item pop bounded swell is applied")
	motion.cancel()
	check(body.transform == base, "cancel restores scale and offset")
	motion.cancel(); motion.cancel()
	check(body.transform == base and motion._motion_tween == null, "cancel is synchronous and idempotent")
	motion._begin_motion(token, "a", Motion.ACTOR_HOP, 0.0)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	var new_parent := Node3D.new(); board.add_child(new_parent)
	body.reparent(new_parent); body.position = Vector3(4, 5, 6)
	var adopted := body.transform
	motion._apply_motion(0.8, Motion.ACTOR_HOP, 0.0); motion.cancel()
	check(body.transform == adopted, "reparented mesh is no longer written or restored")
	body.reparent(token); body.transform = base; new_parent.free()
	motion._observe({}, {}, "v0", true); motion._observe(focus, {}, "v0", true)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	motion._observe(focus, {}, "v0", false)
	check(body.transform == base, "blocked modal restores immediately")
	motion._observe(focus, {}, "v0", true)
	check(motion._motion_tween == null, "close modal does not replay old selection")
	motion._observe({}, {}, "v0", true); motion._observe(focus, {}, "v0", true)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	board.presentation.actors.a.moving = true
	motion._observe(focus, {}, "v0", true)
	check(body.transform == base and motion._parts.is_empty(), "committed movement cancels selection hop")
	board.presentation.actors.a.moving = false
	motion._observe({}, {}, "v0", true); motion._observe(focus, {}, "v0", true)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	motion._observe(focus, {}, "v1", true)
	check(body.transform == base, "world version change cancels")
	motion._begin_motion(token, "a", Motion.ACTOR_HOP, 0.0)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	motion.cancel() # Main's required pre-refresh seam, before catalog.capture.
	var catalog := Catalog.new(); catalog.capture(focus, "fixture actor", token, true)
	check(catalog.subjects["actor:a"].parts == baseline_catalog.subjects["actor:a"].parts, "pre-refresh cancel prevents cached part-transform offset")
	check(catalog.subjects["actor:a"].local_bounds == baseline_catalog.subjects["actor:a"].local_bounds, "pre-refresh cancel preserves cached local bounds")
	motion._observe({}, {}, "v1", true); motion._observe(focus, {}, "v1", true)
	await create_timer(0.38).timeout
	check(body.transform == base and motion._motion_tween == null, "real finite Tween finishes at exact baseline")
	var view := ItemView.new(); board.add_child(view)
	view.pack = Node3D.new(); view.add_child(view.pack)
	var item_mesh := MeshInstance3D.new(); item_mesh.mesh = mesh; item_mesh.position.y = 0.2; view.pack.add_child(item_mesh)
	board.inventory_packs.bag = view
	var item_base := item_mesh.transform; var pack_base := view.pack.transform
	var item_focus := {"world_id": "fixture", "kind": "item", "id": "bag", "hex": [0, 0]}
	motion._observe(item_focus, {}, "v1", true)
	check(motion._motion_root == view.pack, "inventory lookup targets only selected pack")
	motion._apply_motion(0.5, Motion.ITEM_HOP, 0.04)
	check(view.pack.transform == pack_base and item_mesh.transform != item_base, "item root/custody unchanged while visual pops")
	motion._observe(focus, {}, "v1", true)
	check(item_mesh.transform == item_base, "switch item to actor restores previous mesh")
	board.world_state.actors.a.health.current = 0
	motion._observe({}, {}, "v1", true); motion._observe(focus, {}, "v1", true)
	check(motion._parts.is_empty() and motion._pulse_nodes.size() == 1, "downed actor only receives marker, no hop")
	board.world_state.actors.a.health.current = 5
	motion.cancel()
	var moved_focus := focus.duplicate(true); moved_focus.hex = [2, 1]
	check(Motion.focus_key(moved_focus) == Motion.focus_key(focus), "actor refresh is not a new selection")
	check(Motion.envelope(0.0) == 0.0 and Motion.envelope(1.0) == 0.0 and is_equal_approx(Motion.envelope(0.5), 1.0), "finite envelope endpoints and peak")
	board.route_root = Node3D.new(); board.add_child(board.route_root)
	for i in range(12):
		var segment := MeshInstance3D.new(); var cylinder := CylinderMesh.new(); cylinder.height = 1.0
		segment.mesh = cylinder; segment.position = Vector3(i, 0.08, 0); segment.rotation.z = -PI / 2; board.route_root.add_child(segment)
	var source_route_transform: Transform3D = board.route_root.get_child(0).transform
	motion._show_route()
	check(motion._route_nodes.size() == Motion.MAX_ROUTE_PULSES, "route pulses are bounded")
	motion._apply_route(0.5)
	check(board.route_root.get_child(0).transform == source_route_transform, "existing route geometry untouched")
	motion.cancel()
	check(motion._route_nodes.is_empty(), "route cancel removes owned feedback")
	motion._observe({}, {}, "v1", true); motion._observe(focus, {}, "v1", true)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	motion._observe(focus, {}, "v1", true, true)
	check(body.transform == base, "board replacement restores old visual transform")
	check(JSON.stringify(board.world_state) == world_before, "world turn/RNG/actor facts unchanged")
	var retired_board := Board.new(); host.add_child(retired_board)
	var retired_token := Node3D.new(); retired_board.add_child(retired_token)
	var retired_mesh := MeshInstance3D.new(); retired_mesh.mesh = mesh; retired_token.add_child(retired_mesh)
	motion._board = retired_board
	motion._begin_motion(retired_token, "", Motion.ACTOR_HOP, 0.0)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0); motion._show_pulse(Vector3.ZERO, 0.3)
	retired_board.free(); motion.cancel(); motion.cancel()
	check(motion._parts.is_empty() and motion._pulse_nodes.is_empty(), "real board.free before cancel handles stale mesh and marker references")
	motion._board = board
	motion._begin_motion(token, "a", Motion.ACTOR_HOP, 0.0)
	motion._apply_motion(0.5, Motion.ACTOR_HOP, 0.0)
	motion.free()
	check(body.transform == base, "module exit restores visual transform")
	print(JSON.stringify({"suite": "selection_motion", "passed": passed, "failures": failures, "live_Main_GUI_tested": false}))
	host.free()
	quit(0 if failures.is_empty() else 1)
