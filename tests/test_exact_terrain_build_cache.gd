extends SceneTree
const Board=preload("res://view/hex_board.gd")
const Before=preload("res://tests/fixtures/v7_renderer/hex_board.gd")
const Field=preload("res://view/terrain_field.gd")
const BeforeField=preload("res://tests/fixtures/v7_renderer/terrain_field.gd")
const Generator=preload("res://core/world_generator.gd")
const Game=preload("res://core/game_state.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:call_deferred("run")
func tiles(hexes:Dictionary)->Dictionary:
	var out={}
	for key_ in hexes:
		var c:Dictionary=hexes[key_];out[key_]={"hex":Vector2i(c.q,c.r),"terrain":c.terrain,"raw":c}
	return out
func mesh_equal(a:Mesh,b:Mesh,note:String)->void:
	check((a==null)==(b==null),note+" null status retained")
	if a==null or b==null:return
	check(a.get_surface_count()==b.get_surface_count(),note+" surface count")
	for j in range(a.get_surface_count()):
		var x=a.surface_get_arrays(j);var y=b.surface_get_arrays(j)
		for k in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_TANGENT,Mesh.ARRAY_INDEX]:check(x[k]==y[k],note+" exact attribute "+str(k))
func run_case(radius:int,version:String)->void:
	var game=Game.new();var metadata={}
	if version!="original61":metadata=Generator.generate(726381,radius,{"generator_version":version});game.state.hexes=metadata.hexes.duplicate(true)
	var exact=game.state.duplicate(true);var source=tiles(game.state.hexes)
	var field=Field.new();var before=BeforeField.new();check(field.configure(source,metadata) and before.configure(source,metadata),version+" configure")
	var expected=before.build_meshes();var got=field.build_meshes()
	for layer in expected:mesh_equal(expected[layer],got[layer],"%s/r%s/%s"%[version,radius,layer])
	check(field.triangle_count==before.triangle_count and field.shared_vertex_count==before.shared_vertex_count,"No tessellation/count reduction")
	check(game.state==exact,"Build caches do not change canonical state")
	for q in range(-5,6):
		for r in range(-5,6):
			var p=Vector3(q*0.731,0,r*0.619)
			check(field.water_height(p)==before.water_height(p) and field.surface_height(p)==before.surface_height(p),"Same water/surface curve beyond mesh samples")
	var board=Board.new();var ref=Before.new();root.add_child(board);root.add_child(ref);await process_frame
	board.terrain_field=field;ref.terrain_field=before
	for pair in [[Vector3(-3.4,0.3,2.7),Vector3(4.1,0.7,-3.2),10],[Vector3.ZERO,Vector3(1.7,1.1,0.4),12]]:
		var a=SurfaceTool.new();a.begin(Mesh.PRIMITIVE_TRIANGLES);var b=SurfaceTool.new();b.begin(Mesh.PRIMITIVE_TRIANGLES)
		ref._draped_strip(a,pair[0],pair[1],0.045,0.052,pair[2]);board._draped_strip(b,pair[0],pair[1],0.045,0.052,pair[2]);mesh_equal(a.commit(),b.commit(),"Exact strip data "+version)
	# Same instance must discard prior cached water after a terrain reconfigure.
	var previous_sample=field.vertex_cache.values()[0] if not field.vertex_cache.is_empty() else null
	field.configure(source,metadata);check(field.vertex_cache.is_empty(),"Configure invalidates shared vertex/water lifetime")
	var p=Vector3(0.23,0,0.27);check(field.water_height(p)==before.water_height(p),"Reconfigured water sample remains exact")
	board.queue_free();ref.queue_free();await process_frame;await process_frame
	print("EXACT BUILD CACHE CASE ",version," r",radius," checks=",checks)
func run()->void:
	await run_case(4,"original61")
	await run_case(7,Generator.VERSION)
	await run_case(7,Generator.BIOMES_VERSION)
	await run_case(12,Generator.BIOMES_VERSION)
	await run_case(24,Generator.BIOMES_VERSION)
	for f in failures:printerr("FAIL: ",f)
	print("EXACT TERRAIN BUILD CACHE: %d/%d passed"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
