extends SceneTree
const Main=preload("res://main.tscn")
const Generator=preload("res://core/world_generator.gd")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:call_deferred("run")
func run()->void:
	var scene=Main.instantiate();root.add_child(scene);await process_frame
	scene.world_build_requested=true;scene.world_build_seed=726381;scene.world_build_radius=7
	scene.build_selected_world()
	var world:Dictionary=scene.game.state.generated_world
	check(scene.game.state.hexes.size()==169,"Radius7 has169cells")
	check(scene.board.terrain_field.generated,"Renderer consumes generated macrofield")
	check(scene.board.terrain_field.channels.filter(func(segment):return not segment.get("outlet_extension",false)).size()==world.river_edges.size(),"Only directed drainage edges form rivers")
	for segment in scene.board.terrain_field.channels:
		if not segment.get("mouth",false):continue
		var direction=(segment.b-segment.a);direction.y=0;direction=direction.normalized()
		var continuation:Vector3=segment.b+direction*0.22
		check(scene.board.terrain_field.land_height(continuation)<scene.board.terrain_field.water_height(continuation),"River mouth continues underwater without terminal berm")
	check(scene.board.terrain_field.channels.any(func(segment):return segment.get("outlet_extension",false)),"Boundary outlets extend visually to cut edge")
	check(scene.board.get_node_or_null("BatchedScenery/SettlementsAndRoads")!=null,"Road and building geometry exists")
	var infra=scene.board.get_node("BatchedScenery/SettlementsAndRoads")
	for settlement in world.settlements:
		var village=infra.get_node_or_null(settlement.id)
		check(village!=null and int(village.get_meta("building_count",0))>=4,"Settlement has authored cluster, courtyard and label")
	var height=scene.board.terrain_field.land_height(Vector3.ZERO)
	check(is_finite(height),"Generated continuous height is finite")
	scene.goal.text="观察城镇周围的道路";scene.submit_action()
	check(scene.current_request.snapshot.generated_world.seed==726381,"GM receives exact generated world metadata")
	scene.save_game();scene.restart_game();scene.load_game()
	check(scene.game.state.generated_world.content_hash==world.content_hash,"Save restores same generated topology")
	check(scene.board.terrain_field.generated and not scene.active_action.is_empty(),"Renderer and pending action resume together")
	scene.cancel_pending();scene.restart_game()
	check(scene.game.state.hexes.size()==61 and not scene.board.terrain_field.generated,"Original recorded fixture remains available")
	check(scene.board.token_nodes.size()==2,"No stale generated token duplicates")
	scene.on_hex_selected(Vector2i(2,-1));scene.clear_target()
	check(scene.selected==Vector2i(99,99),"Clear target restores text-only action path")
	scene.goal.text="观察河岸";scene.submit_action();scene.show_import()
	scene.import_text.text="{broken JSON";scene.import_decision()
	check(scene.import_dialog.visible,"Invalid JSON stays open for correction")
	check(scene.game.state.state_version==0,"Invalid dialog does not mutate state")
	scene.queue_free();await process_frame
	if failures.is_empty():print("GENERATED RENDER WIRING PASSED: %d assertions"%checks);quit(0)
	else:
		for f in failures:printerr("FAIL: ",f)
		quit(1)
