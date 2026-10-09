extends SceneTree
const Probe = preload("res://tests/loading_startup/probe_main.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var app
var checks: Array=[]
var case_ := "default"
var failures:=0
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):case_=arg.trim_prefix("--case=")
	run.call_deferred()
func check(value:bool,label_:String)->void:
	checks.append({"passed":value,"name":label_})
	if not value:failures+=1;printerr("STARTUP_FAIL ",label_)
func has_sky(board:Node)->bool:
	for child in board.get_children():
		if child is WorldEnvironment and child.environment!=null and child.environment.sky!=null:return true
	return false
func run()->void:
	root.size=Vector2i(1280,720)
	app=load("res://main.tscn").instantiate();app.set_script(Probe);app.startup_legacy=case_=="property"
	if case_ in ["bundle","renderer"]:app.failure_kind=case_
	root.add_child(app)
	for _i in range(4):await process_frame
	var legacy:=case_ in ["property","environment","argument","bundle","renderer"]
	check(app.coast_mode==not legacy,"requested mode or preserved fallback")
	check(app.legacy_refreshes==(1 if legacy else 0),"initial legacy terrain built exactly when needed")
	if legacy:
		check(app.board.tiles.size()==app.game.state.hexes.size() and app.board.tiles.size()>0,"complete nonempty legacy map")
		check(is_instance_valid(app.board.terrain_root) and app.board.token_nodes.has("actor_player"),"fallback or legacy terrain and player exist")
		check(app.board.camera.current,"legacy camera focused and current")
		check(has_sky(app.board)==(case_ not in ["bundle","renderer"]),"Sky preserved for explicit entries; fallback remains prior skip behavior")
		if case_ in ["bundle","renderer"]:check(app.status_label.tooltip_text.contains("TEST_ONLY"),"fallback keeps exact load-error status")
	else:
		check(app.board.tiles.size()==1801 and app.board.load_error.is_empty(),"full coast rendered")
		check(not has_sky(app.board),"default coast Sky behavior unchanged")
		var state:=C.digest(app.playtest.engine.save_data())
		var journal:String=app.journal.text;app.set_player_intent("启动优化回归草稿")
		app.switch_playtest(false)
		for _i in range(4):await process_frame
		check(not app.playtest_mode and app.legacy_refreshes==1 and app.board.tiles.size()>0,"later preview builds map on demand once")
		check(has_sky(app.board) and not app.board.get_meta("diagnosis_skip_startup_sky",false),"later preview retains original Sky")
		check(C.digest(app.coast_adventure.engine.save_data())==state,"later preview does not change coast authority")
		check(app._mode_ui_snapshots.coast.goal=="启动优化回归草稿","coast draft snapshot preserved")
	var out:=OS.get_environment("FOGBANK_PERF_OUT")
	var f:=FileAccess.open(out+"/startup_"+case_+".json",FileAccess.WRITE);f.store_string(JSON.stringify({"case":case_,"checks":checks,"failures":failures},"\t"));f.close()
	app.queue_free()
	for _i in range(4):await process_frame
	print("STARTUP_CASE ",case_," failures=",failures);quit(0 if failures==0 else 1)
