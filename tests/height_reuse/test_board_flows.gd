extends SceneTree
const Contract=preload("res://core/world_generation_contract.gd")
const Inventory=preload("res://view/generated_inventory/adapter.gd")
const GeneratedBoard=preload("res://view/generated_adventure/board.gd")
const LegacyBoard=preload("res://view/hex_board.gd")
const Game=preload("res://core/game_state.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:Array=[]
var failures:=0
var rows:Array=[]
var radius:=4
var out:=""
var release_expected:=false
func _initialize()->void:
	out=OS.get_environment("FOGBANK_PERF_OUT")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--radius="):radius=int(arg.trim_prefix("--radius="))
		if arg=="--release":release_expected=true
	run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks.append({"name":label_,"passed":ok})
	if not ok:failures+=1;printerr("CACHE_RELEASE_FAIL ",label_)
func frames(count:=3)->void:
	for _i in range(count):await process_frame
func mesh_hash(mesh:Mesh)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	for surface in range(mesh.get_surface_count()):context.update(var_to_bytes(mesh.surface_get_arrays(surface)))
	return context.finish().hex_encode()
func material_signature(material:Material)->Dictionary:
	if material==null:return {}
	var row:Dictionary={"class":material.get_class()}
	if material is BaseMaterial3D:
		row.merge({"albedo":str(material.albedo_color),"roughness":material.roughness,"metallic":material.metallic,"unshaded":material.shading_mode,"cull":material.cull_mode})
	if material is ShaderMaterial and material.shader!=null:
		row["shader_code_sha"]=material.shader.code.sha256_text()
	return row
func terrain_snapshot(board:Node)->Dictionary:
	var meshes:Array=[]
	for node in board.terrain_root.find_children("*","MeshInstance3D",true,false):
		if node.is_queued_for_deletion() or node.mesh==null:continue
		meshes.append({"name":str(node.name),"geometry_sha":mesh_hash(node.mesh),"transform":str(node.transform),"bounds":str(node.mesh.get_aabb()),"material":material_signature(node.material_override),"visible":node.visible})
	var whole:Dictionary={}
	for layer in board.whole_terrain_layers:whole[str(layer.name)]=mesh_hash(layer.mesh)
	var samples:Array=[]
	for h in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-2,1),Vector2i(3,-1)]:
		var point:Vector3=board.hex_pos(h)+Vector3(.083,0,.017)
		samples.append([board.terrain_field.surface_height(point),board.terrain_field.water_height(point),board.terrain_field.support_height(h)])
	return {"meshes":meshes,"whole":whole,"samples":samples,"triangle_count":board.terrain_field.triangle_count,"query_entries":board.terrain_field.query_cache.size(),"landscape_entries":board.terrain_field.landscape_cache.size()}
func run()->void:
	root.size=Vector2i(1280,720)
	var preset:="coast_exploration" if radius==12 else "compact_coast"
	var envelope:Dictionary=Contract.generate("726381",preset,radius)
	check(envelope.ok,"source generated normally")
	var adapter:=Inventory.new();check(adapter.start_seeded(envelope).ok,"same pipeline source admitted")
	var exact:=C.digest(adapter.save_data());var state:Dictionary=adapter.state_copy()
	var board:=GeneratedBoard.new(adapter.source);root.add_child(board);board.set_world(state);await frames()
	check(board.load_error.is_empty(),"admitted generated board ready")
	check(board.terrain_field.height_field.get_script()==preload("res://core/world_generator.gd"),"original height field restored before live queries")
	check(board.terrain_field.vertex_cache.is_empty()==release_expected,"expected build-only cache lifetime")
	var initial:=terrain_snapshot(board);rows.append({"label":"initial","snapshot":initial})
	board.set_world(state);await frames()
	check(terrain_snapshot(board)==initial,"unchanged refresh preserves exact mesh, bounds, materials and height samples")
	check(C.digest(adapter.save_data())==exact,"render and sampled queries leave source/save authority exact")
	var copy:=Inventory.new();check(copy.load_data(adapter.save_data()).ok and C.digest(copy.save_data())==exact,"unchanged pipeline preserves exact inventory save reload")
	if radius==4:
		var changed:Dictionary=state.duplicate(true);changed.actors.actor_player.health.current-=1
		board.set_world(changed);await frames()
		check(terrain_snapshot(board)==initial,"actor-only presentation update leaves terrain unchanged")
		var rebuilt:Dictionary=board.terrain_field.build_meshes()
		for key in initial.whole:check(mesh_hash(rebuilt[key])==initial.whole[key],"repeat raw mesh build identical "+key)
		rebuilt.clear()
		board.terrain_chunk_size=5;board.set_world(state);await frames()
		check(board.terrain_field.vertex_cache.is_empty()==release_expected,"forced render-policy rebuild keeps intended cache lifetime")
		check(board.terrain_field.height_field.get_script()==preload("res://core/world_generator.gd"),"policy rebuild restores original height field")
		rows.append({"label":"forced_policy_rebuild","snapshot":terrain_snapshot(board)})
		var replacement:Dictionary=Contract.generate("雪岸-缓存","compact_coast",4)
		var next:=Inventory.new();check(next.start_seeded(replacement).ok,"replacement source independently admitted")
		board.admitted_source=next.source;board.set_world(next.state_copy());await frames()
		check(board.load_error.is_empty() and board.terrain_field.vertex_cache.is_empty()==release_expected,"generated-world replacement rebuild remains valid")
		check(board.terrain_field.height_field.get_script()==preload("res://core/world_generator.gd"),"world replacement restores original height field")
		rows.append({"label":"replacement","snapshot":terrain_snapshot(board)})
	board.queue_free();await frames()
	var legacy:=LegacyBoard.new();legacy.set_meta("diagnosis_skip_startup_sky",true);root.add_child(legacy)
	var game:=Game.new();game.new_world();legacy.set_world(game.state);await frames()
	check(not legacy.terrain_field.generated and not legacy.terrain_field.vertex_cache.is_empty(),"later original preview retains prior cache behavior")
	legacy.queue_free();await frames()
	var file:=FileAccess.open(out+"/cache_r%d.json"%radius,FileAccess.WRITE)
	file.store_string(JSON.stringify({"radius":radius,"release_expected":release_expected,"checks":checks,"failures":failures,"rows":rows,"pipeline_digest":preload("res://view/generated_adventure/source.gd").pipeline_digest(),"source_hash":envelope.source.content_hash},"\t"));file.close()
	print("CACHE_RELEASE_COMPLETE r",radius," failures=",failures);quit(0 if failures==0 else 1)
