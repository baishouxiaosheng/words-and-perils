extends SceneTree
const Main = preload("res://main.tscn")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var scene
var checks: Array = []
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks.append({"name":title,"passed":ok})
	if not ok:
		failures += 1
		printerr("LIFECYCLE_FAIL ",title)
func frames(n: int = 8) -> void:
	for i in range(n):
		await process_frame
func run() -> void:
	root.size = Vector2i(1920,1080)
	scene = Main.instantiate()
	root.add_child(scene)
	await frames(12)
	check(scene.coast_mode and scene.board.tiles.size()==1801 and scene.board.load_error.is_empty(), "actual complete default v22 coast")
	var original: String = C.bytes(scene.playtest.engine.save_data())
	var state: Dictionary = scene.playtest.state_copy()
	scene.on_hex_selected(Vector2i(-2,15))
	check(scene.selected_focus.kind=="tile" and scene.active_action.is_empty(), "actual main tile attention creates no action")
	var actor: Dictionary = state.actors.actor_player
	scene._apply_focus({"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":actor.hex})
	check(scene.selected_focus.id=="actor_player" and C.bytes(scene.playtest.engine.save_data())==original, "actor selection preserves authoritative save bytes")
	scene.save_game()
	check(scene.last_save_result.get("ok",false), "actual main JSON save succeeds")
	scene.load_game()
	await frames()
	check(scene.last_load_result.get("ok",false) and C.bytes(scene.playtest.engine.save_data())==original, "actual main JSON reload preserves complete state and RNG")
	var shore = scene.board.world_view.natural_shorelines
	var source_before: Dictionary = shore.source_context_at_xz(Vector2(10.240750399750986,20.4125))
	for cycle in range(2):
		shore.set_active(false)
		await frames(2)
		check(not shore.visible and scene.board.world_view.picks==shore.old_picks and scene.board.world_view.compact_root.visible, "source presentation fallback works cycle "+str(cycle))
		shore.set_active(true)
		await frames(2)
		check(shore.visible and scene.board.world_view.picks==shore.new_picks and C.bytes(shore.source_context_at_xz(Vector2(10.240750399750986,20.4125)))==C.bytes(source_before), "v03 reactivation preserves exact source payload cycle "+str(cycle))
	check(C.bytes(scene.playtest.engine.save_data())==original, "repeated source presentation changes preserve game save")
	var returned_static: Array = []
	for cycle in range(2):
		var old_board = weakref(scene.board)
		scene.switch_playtest(false)
		await frames()
		check(not scene.playtest_mode and scene.board.tiles.size()==61 and old_board.get_ref()==null, "old coast renderer actually freed on legacy entry cycle "+str(cycle))
		scene.switch_coast()
		await frames(12)
		check(scene.coast_mode and scene.board.tiles.size()==1801 and scene.board.load_error.is_empty(), "full coast reentry succeeds cycle "+str(cycle))
		check(C.bytes(scene.playtest.engine.save_data())==original, "coast mode roundtrip preserves exact authoritative save cycle "+str(cycle))
		var current_source: Dictionary = scene.board.world_view.natural_shorelines.source_context_at_xz(Vector2(10.240750399750986,20.4125))
		check(C.bytes(current_source)==C.bytes(source_before), "source trace survives scene reconstruction cycle "+str(cycle))
		returned_static.append(Performance.get_monitor(Performance.MEMORY_STATIC))
	var report := {"checks":checks,"failures":failures,"returned_static_bytes":returned_static,"live_provider_calls":false,"actual_main":true}
	var out := OS.get_environment("FOGBANK_PERF_OUT")
	var file := FileAccess.open(out+"/lifecycle.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	scene.queue_free()
	await frames(4)
	print("MAIN_RESOURCE_LIFECYCLE ",checks.size()-failures,"/",checks.size())
	quit(0 if failures==0 else 1)
