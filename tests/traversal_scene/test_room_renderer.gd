extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Board = preload("res://view/playable_build/scene_test_board.gd")
const Coast = preload("res://view/playable_build/world.gd")
const Fixture = preload("res://view/playable_build/scene_framework_fixture.gd")
var failures: Array=[]
var checks:=0
func check(v: bool,label: String) -> void:
	checks+=1
	if not v:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var state:=Coast.world();Fixture.install(state)
	# Display-only fixture. Gameplay commit/save transitions are in test_framework.
	state.actors.actor_player.scene_id=Fixture.ROOM;state.actors.actor_player.hex=[0,0]
	var board:=Board.new();root.add_child(board);await process_frame
	board.set_world(state,false);await process_frame
	check(board.load_error.is_empty(),"registered room renderer loads")
	check(board.world_state.hexes.size()==7 and board.tiles.size()==7,"only seven authored floor cells rendered")
	check(board.world_state.actors.size()==1 and board.token_nodes.has("actor_player"),"outer coast actors not rendered")
	check(board.world_state.generated_world.is_empty() and board.world_state.board_radius==1,"outer source generator not reused")
	board.focus_player();board.set_route_preview([[0,0],[1,0]])
	await process_frame
	check(board.camera!=null and not board.world_view.overview,"room focus camera interface works")
	check(board.route_preview.get_child_count()>0,"room route preview renders local coordinates")
	var facts_before:=C.bytes(board.world_state)
	for cycle in range(3):
		board.reset_camera();await process_frame
		check(board.world_view.overview and board.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"room enters true orthographic overview "+str(cycle))
		check(board.camera.size>0 and is_finite(board.camera.size) and board.camera.position.y>board.view_focus.y,"room overview is fitted above local cells "+str(cycle))
		board._resize_overview()
		check(board.world_view.overview,"resize preserves room overview "+str(cycle))
		# Same branch selection used by main.toggle_overview().
		if board.world_view.overview:board.focus_player()
		else:board.reset_camera()
		check(not board.world_view.overview and board.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"room overview toggles back to focused camera "+str(cycle))
	check(C.bytes(board.world_state)==facts_before,"repeated camera toggles do not mutate scene facts")
	board.clear_actor_selection();board.set_route_preview([]);board.queue_free();await process_frame
	print("ROOM RENDERER ",checks-failures.size(),"/",checks," ",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
