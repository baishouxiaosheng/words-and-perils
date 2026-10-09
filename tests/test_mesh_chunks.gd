extends SceneTree
const Chunks=preload("res://view/mesh_chunks.gd")
const Field=preload("res://view/terrain_field.gd")
const Board=preload("res://view/hex_board.gd")
const Generator=preload("res://core/world_generator.gd")
const Game=preload("res://core/game_state.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func triangle_key(arrays:Array,start:int)->String:
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var packed=PackedFloat32Array()
	for i in range(3):
		var point=points[start+i];packed.append(point.x);packed.append(point.y);packed.append(point.z)
	return packed.to_byte_array().hex_encode()
func triangles(mesh:ArrayMesh)->Dictionary:
	var result={}
	if mesh==null:return result
	var arrays=mesh.surface_get_arrays(0)
	for i in range(0,arrays[Mesh.ARRAY_VERTEX].size(),3):
		var key_=triangle_key(arrays,i)
		if not result.has(key_):result[key_]=[]
		result[key_].append(i)
	return result
func run()->void:
	var world:Dictionary=Generator.generate(726381,7,{"generator_version":"macro_hex_biomes_v2"})
	var source={}
	for key_ in world.hexes:
		var c:Dictionary=world.hexes[key_];source[key_]={"hex":Vector2i(c.q,c.r),"terrain":c.terrain,"raw":c}
	var field=Field.new();check(field.configure(source,world),"V2 canonical sampler is valid")
	var meshes=field.build_meshes();var total=0;var groups=0;var max_normal=0.0
	for layer in meshes:
		var whole:ArrayMesh=meshes[layer]
		if whole==null:continue
		var expected=triangles(whole);var original=whole.surface_get_arrays(0);var chunks:Dictionary=Chunks.split(whole,4);groups+=chunks.size()
		for chunk in chunks.values():
			var arrays=chunk.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_VERTEX].size()%3==0,"Chunk has complete faces: "+layer)
			for i in range(0,arrays[Mesh.ARRAY_VERTEX].size(),3):
				var key_=triangle_key(arrays,i);check(expected.has(key_) and not expected[key_].is_empty(),"Exact source triangle retained once: "+layer)
				if not expected.has(key_) or expected[key_].is_empty():continue
				var start:int=expected[key_].pop_back();total+=1
				for j in range(3):
					max_normal=maxf(max_normal,original[Mesh.ARRAY_NORMAL][start+j].distance_to(arrays[Mesh.ARRAY_NORMAL][i+j]))
					if original[Mesh.ARRAY_TEX_UV2]!=null:check(original[Mesh.ARRAY_TEX_UV2][start+j].is_equal_approx(arrays[Mesh.ARRAY_TEX_UV2][i+j]),"Biome UV2 weights remain unchanged")
					if original[Mesh.ARRAY_COLOR]!=null:check(original[Mesh.ARRAY_COLOR][start+j].is_equal_approx(arrays[Mesh.ARRAY_COLOR][i+j]),"Palette/bank/water colors remain unchanged")
		for key_ in expected:check(expected[key_].is_empty(),"No source face omitted/added, including only original outer skirts: "+layer)
	check(max_normal<0.00015,"Global original normals are copied before partition, no boundary relighting; max=%s"%max_normal)
	var viewport=SubViewport.new();viewport.size=Vector2i(1128,642);viewport.own_world_3d=true;root.add_child(viewport)
	var board=Board.new();viewport.add_child(board);await process_frame
	var game=Game.new();var v2:Dictionary=Generator.generate(726381,10,{"generator_version":"macro_hex_biomes_v2"})
	game.state.hexes=v2.hexes.duplicate(true);game.state.generated_world=v2.duplicate(true);game.state.board_radius=10
	for id in game.state.actors:game.state.actors[id].hex=v2.actor_spawn_hexes[id].duplicate()
	var before=game.state.duplicate(true);board.set_world(game.state);board.focus_player();await process_frame
	check(board.chunk_mode and board.terrain_chunks.visible and board.whole_terrain_layers.all(func(node):return not node.visible),"Near camera selects exact spatial chunks for frustum culling")
	board.reset_camera();await process_frame
	check(not board.chunk_mode and not board.terrain_chunks.visible and board.whole_terrain_layers.all(func(node):return node.visible),"Overview uses original whole meshes to avoid extra submission cost")
	check(game.state==before,"Chunk visibility never deletes or changes full world/actor/GM facts")
	viewport.queue_free();await process_frame
	print("MESH CHUNK METRICS triangles=",total," groups=",groups," maximum_normal_delta=",max_normal)
	if failures.is_empty():print("MESH CHUNKS PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
