extends SceneTree
const Generator=preload("res://core/world_generation_v3/generator.gd")
const Adapter=preload("res://view/generated_v3_adventure/adapter.gd")
const Board=preload("res://view/generated_v3_adventure/board.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_ui/"
var checks:=0
var failures:Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures.append(label);printerr("V3_BOARD_FAIL ",label)
func brute(picker:RefCounted,origin:Vector3,direction:Vector3) -> Dictionary:
	var distance:=INF;var best:Dictionary={}
	for triangle in picker.triangles:
		var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,triangle.a,triangle.b,triangle.c)
		if hit is Vector3:
			var t:float=(hit-origin).dot(direction)
			if t>=0 and t<distance:distance=t;best={"distance":t,"point":hit,"surface":triangle.surface}
	return best
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var adapter:=Adapter.new(Generator.generate(726381,12,"coastal_range").source)
	check(adapter.ready().ok,"native r12 source admitted")
	if not adapter.ready().ok:finish({});return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
	var board:=Board.new(adapter.source);viewport.add_child(board);board.set_world(adapter.state_copy());board.focus_player()
	check(board.load_error.is_empty(),"standalone native board ready")
	var before:String=C.bytes(adapter.save_data())
	var times:Array=[];var cases:Array=[]
	for i in range(28):
		var x:float=-20+float((i*17)%41);var z:float=-18+float((i*13)%37)
		var origin:=Vector3(x,35,z);var direction:=Vector3(.13 if i%2 else 0,-1,.22 if i%3 else 0).normalized()
		var actual:Dictionary=board.picking.raycast(origin,direction);var expected:=brute(board.picking,origin,direction)
		check(actual.is_empty()==expected.is_empty(),"binned ray presence "+str(i))
		if not expected.is_empty():check(actual.point.distance_to(expected.point)<.0001 and actual.surface==expected.surface,"exact nearest triangle/surface "+str(i))
		cases.append({"origin":[x,35,z],"match":actual.is_empty()==expected.is_empty(),"stats":board.picking.last_query.duplicate()})
	for i in range(180):
		var point:=Vector2(220+(i*83)%830,70+(i*37)%500)
		var start:int=Time.get_ticks_usec();board.pick_focus(point);times.append(Time.get_ticks_usec()-start)
	times.sort()
	check(times[170]<20000,"r12 complete pointer-pick p95 below20ms")
	check(C.bytes(adapter.save_data())==before,"180 pointer queries do not alter authority")
	var pose:Dictionary=board.token_support_metrics.actor_player
	check(pose.unsupported_samples==0 and pose.lift<.10,"spawn sole has fully supported plane and bounded residual lift")
	check(board.token_nodes.actor_player.position==pose.position,"actual token uses verified support pose")
	var start_hex:Array=adapter.state_copy().actors.actor_player.hex;var key:String="%d,%d"%start_hex
	var next_key:String=adapter.source.navigation.allowed[key][0];var cell:Dictionary=adapter.state_copy().hexes[next_key]
	var focus:Dictionary=adapter.tile_reference([cell.q,cell.r]);var preview:Dictionary=adapter.movement_preview(focus.hex)
	board.set_route_preview(preview.route)
	check(not board.route_root.get_children().is_empty(),"route uses ground-conforming segments")
	check(adapter.begin_intent(adapter.sample_goal("move",focus),focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok,"real move commits")
	board.set_world(adapter.state_copy(),true,adapter.authoritative_result().public_effects)
	check(board.presentation.actors.actor_player.moving,"move animates committed route")
	var duration:float=board.presentation.actors.actor_player.duration
	check(duration<1.0,"one cell remains one paced traversal despite triangle seams")
	board.presentation._process(duration+1)
	check(not board.presentation.actors.actor_player.moving,"motion completes at support")
	check(board.token_nodes.actor_player.position==board.token_support_metrics.actor_player.position,"arrival lands on same actual support pose")
	var metrics:Dictionary={"picker_samples":180,"p50_usec":times[90],"p95_usec":times[170],"max_usec":times.back(),"triangle_count":board.picking.triangles.size(),"ray_cases":cases,"spawn":start_hex,"spawn_support":pose,"arrival_support":board.token_support_metrics.actor_player,"source_hash":adapter.source.identity.content_hash,"geometry_hash":adapter.source.identity.geometry_hash}
	board.queue_free();viewport.queue_free();finish(metrics)
func finish(metrics:Dictionary) -> void:
	var result:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"metrics":metrics}
	var file:=FileAccess.open(OUT+"board_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("V3_BOARD_RESULT ",checks," failures=",failures);quit(0 if failures.is_empty() else 1)
