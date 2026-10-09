extends SceneTree
## Dirty/local rendering updates must preserve exact advisory paths and world facts.
const Board=preload("res://view/hex_board.gd")
const Before=preload("res://tests/fixtures/accepted_art_renderer/hex_board.gd")
const Game=preload("res://core/game_state.gd")
const Generator=preload("res://core/world_generator.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func child_id(board,path:String)->int:
	var node=board.overlays.get_node_or_null(path)
	return node.get_instance_id() if node!=null else -1
func compare_paths(board,before,label:String,all_cells:bool)->void:
	var builds:int=board.preview_tree_builds
	var keys=board.tiles.keys()
	for i in range(keys.size()):
		if not all_cells and i%maxi(1,keys.size()/16)!=0:continue
		var h:Vector2i=board.tiles[keys[i]].hex
		var got:Dictionary=board.preview_to(h);var expected:Dictionary=before.preview_to(h)
		check(got==expected,label+" exact path/cost/distances retained for "+keys[i])
	check(board.preview_tree_builds==builds,label+" target changes reuse one advisory distance tree")
	var detached:Dictionary=board.preview_to(Vector2i.ZERO)
	detached.distances[board.tile_key(board.focus_hex)]=-999
	check(board.preview_to(Vector2i.ZERO).distances[board.tile_key(board.focus_hex)]==0.0,label+" caller cannot mutate the cached advisory tree")
func run()->void:
	var viewport=SubViewport.new();viewport.size=Vector2i(1128,642);viewport.own_world_3d=true;root.add_child(viewport)
	var board=Board.new();var before=Before.new();viewport.add_child(board);viewport.add_child(before);await process_frame
	var game=Game.new();var original:Dictionary=game.state.duplicate(true)
	board.set_world(game.state);before.set_world(game.state);await process_frame
	compare_paths(board,before,"original61",true)
	var terrain_id=board.terrain_root.get_instance_id();var scenery_id=board.static_root.get_instance_id()
	var range_id=child_id(board,"AdvisoryRangeFill");var border_id=child_id(board,"AdvisoryRangePerimeter")
	var revision:int=board.terrain_revision;var range_builds:int=board.range_rebuilds;var overlay_builds:int=board.overlay_rebuilds
	board.set_world(game.state)
	check(board.terrain_root.get_instance_id()==terrain_id and board.static_root.get_instance_id()==scenery_id,"Unchanged refresh retains exact terrain/scenery objects")
	check(board.terrain_revision==revision and board.range_rebuilds==range_builds and board.overlay_rebuilds==overlay_builds,"Unchanged refresh does no terrain/range/target geometry work")
	check(child_id(board,"AdvisoryRangeFill")==range_id and child_id(board,"AdvisoryRangePerimeter")==border_id,"Unchanged refresh keeps exact advisory fill/border meshes")
	var health_only:Dictionary=game.state.duplicate(true);health_only.actors.actor_player.health.current=19
	board.set_world(health_only,true)
	check(board.terrain_revision==revision and board.range_rebuilds==range_builds and board.overlay_rebuilds==overlay_builds,"Health-only refresh updates actors without terrain/range/target rebuild")
	check(board.token_nodes.actor_player.get_node("Nameplate").text.contains("19/20"),"Actor label still updates to the new health fact")
	board.hover_hex=Vector2i.ZERO;board.draw_overlay();await process_frame
	check(child_id(board,"AdvisoryRangeFill")==range_id and child_id(board,"AdvisoryRangePerimeter")==border_id,"Hover rebuilds only target/path, retaining static range")
	check(board.range_rebuilds==range_builds and board.preview_tree_builds==1,"Hover keeps range and distance-tree caches")
	var target=board.target_overlays;var meshes=target.get_children().filter(func(node):return node is MeshInstance3D)
	check(not meshes.is_empty() and meshes.all(func(node):return node.name.begins_with("Batched_")),"Dynamic route and target meshes are batched without losing world geometry")
	var moved:Dictionary=health_only.duplicate(true);moved.actors.actor_player.hex=[-1,1]
	board.set_world(moved,false);await process_frame
	check(board.terrain_revision==revision and board.terrain_root.get_instance_id()==terrain_id,"Actor move retains the full terrain field")
	check(board.range_rebuilds==range_builds+1 and board.preview_tree_builds==2,"New actor focus invalidates range and advisory tree exactly once")
	var old_revision:int=board.terrain_revision
	# Deliberate in-place fixture mutation catches a cache-alias bug. This is a
	# detached test world, never a GM event or the user's persistent state.
	moved.hexes["-3,0"].terrain="forest";board.set_world(moved)
	check(board.terrain_revision==old_revision+1 and board.terrain_root.get_instance_id()!=terrain_id,"In-place canonical terrain edit cannot alias/evade detached dirty detection")
	check(game.state==original,"All cache tests leave the original model unchanged")
	var world:Dictionary=Generator.generate(726381,7)
	var generated:Dictionary=original.duplicate(true);generated.hexes=world.hexes.duplicate(true);generated.generated_world=world.duplicate(true);generated.board_radius=7
	for id in generated.actors:generated.actors[id].hex=world.actor_spawn_hexes[id].duplicate()
	board.set_world(generated);before.set_world(generated);await process_frame
	compare_paths(board,before,"v1radius7",false)
	check(board.terrain_field.landscape_cache.size()>0 and board.terrain_field.landscape_cache_hits>0,"Generated macro/fill samples are reused at shared coordinates")
	var exact:Dictionary=generated.duplicate(true);board.set_world(generated)
	check(generated==exact,"Generated refresh caches preserve complete canonical graph/climate/site/road facts")
	viewport.queue_free();await process_frame
	if failures.is_empty():print("RENDER CACHES PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
