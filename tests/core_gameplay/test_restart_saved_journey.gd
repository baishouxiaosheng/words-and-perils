extends SceneTree
## New OS process + unseeded ordinary Main; imports an actual prior native save
## into this test's isolated user:// directory. No invented state or outcome.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var scene
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("RESTART_FAIL ",label)
func _initialize()->void:call_deferred("run")
func frames(n:=8)->void:
	for i in range(n):await process_frame
func run()->void:
	var prefix:=OS.get_environment("FOGBANK_RESTART_FIXTURE")
	var expected_path:=prefix+"_expected.json"
	check(not prefix.is_empty() and FileAccess.file_exists(expected_path),"prior actual-main fixture is explicitly supplied")
	if not failures.is_empty():finish({});return
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(expected_path))
	check(FileAccess.get_sha256(prefix+".json")==expected.save_sha256,"prior save hash matches recorded native evidence")
	check(expected.display=="X11","restart fixture came from rendered native self-play")
	scene=Main.instantiate();root.add_child(scene);await frames(12)
	check(scene.coast_mode and scene.board.load_error.is_empty(),"fresh ordinary main opens without cached user progress")
	check(scene.playtest.engine.rule_id()=="coast_release/v1","fresh main defaults to production rule before loading labelled test save")
	check(DirAccess.copy_absolute(prefix+".json",scene.playtest.COAST_SAVE)==OK,"copy actual save into isolated test user directory")
	check(DirAccess.copy_absolute(prefix+".json.narration.json",scene.playtest.COAST_SAVE+".narration.json")==OK,"copy exact bound prose sidecar")
	scene.load_game();await frames()
	check(scene.last_load_result.get("ok",false),"new process actually accepts the saved adventure "+str(scene.last_load_result))
	check(C.bytes(scene.playtest.state_copy()).sha256_text()==expected.state_sha256,"new process restores exact world consequences inventory positions and status")
	check(scene.playtest.phase()==expected.phase and C.bytes(scene.playtest.action_copy()).sha256_text()==expected.action_sha256,"new process restores exact phase and frozen action")
	check(C.bytes(scene.playtest.journal_entries())==C.bytes(expected.history),"all authoritative historical wording replays exactly")
	check(C.bytes(scene.playtest.narration_entries())==C.bytes(expected.prose),"bound optional prose survives actual process restart")
	for row in expected.prose:
		check(scene.journal.get_parsed_text().count(row.narration)==1,"optional prose is displayed once after restart")
	var state:Dictionary=scene.playtest.state_copy()
	check(state.environment_entities[expected.tree_id].state.posture=="fallen" and state.hexes["-1,13"].ground_blocked,"restarted real tree and supporting ground remain blocked")
	check(scene.hero_subtitle.text.contains("飞行") and state.actors.actor_player.statuses.condition_flight.remaining_turns==3,"restarted ongoing status is visible and unticked")
	check(scene.board.committed_feedback.accepted_receipts==0 and scene.board.committed_feedback.active_count()==0 and scene.board.committed_feedback.pending.is_empty(),"load never replays past committed presentation")
	if expected.phase=="rolled":
		scene.end_turn()
		check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().state_version==state.state_version+1,"restored locked turn finishes once through primary UI")
		check(scene.playtest.state_copy().actors.actor_player.statuses.condition_flight.remaining_turns==2,"restored locked turn ticks condition once")
		var committed:=C.bytes(scene.playtest.state_copy());scene.complete_requested_turn()
		check(C.bytes(scene.playtest.state_copy())==committed,"repeated completion after restart remains idempotent")
	finish(expected)
func finish(expected:Dictionary)->void:
	var output:=OS.get_environment("FOGBANK_RESTART_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"stage":expected.get("stage",""),"prior_save_sha256":expected.get("save_sha256",""),"actual_new_process":true,"display":DisplayServer.get_name()},"\t"));file.close()
	print("ACTUAL_MAIN_RESTART ",checks-failures.size(),"/",checks)
	if is_instance_valid(scene):scene.queue_free()
	quit(0 if failures.is_empty() else 1)
