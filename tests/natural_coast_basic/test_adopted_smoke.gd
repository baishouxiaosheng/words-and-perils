extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Main=preload("res://main.tscn")
const HostCustody=preload("res://view/generated_v3_river_entry/host_custody.gd")
const CHECK_SCHEMA := "natural_coast_editable_adoption_smoke/v1"
const EXPECTED_CHECK_IDS := ["adopt_commit_coastal_range", "adopt_commit_plateau_hinterland", "adopt_default_1801", "adopt_enter_coastal_range", "adopt_enter_plateau_hinterland", "adopt_exact_identity_coastal_range", "adopt_exact_identity_plateau_hinterland", "adopt_host_custody", "adopt_host_exact_coastal_range", "adopt_host_exact_plateau_hinterland", "adopt_prepare_coastal_range", "adopt_prepare_plateau_hinterland", "adopt_release_coastal_range", "adopt_release_plateau_hinterland", "adopt_return_coastal_range", "adopt_return_plateau_hinterland"]
var failures: Array=[]
var executed_check_ids: Array=[]
var checks:=0
func _initialize()->void: run.call_deferred()
func check(value:bool,label:String)->bool:
	checks+=1
	if label in executed_check_ids: failures.append("duplicate check ID: "+label)
	else: executed_check_ids.append(label)
	if not value: failures.append(label)
	return value
func frames(count:int=4)->void:
	for _i in range(count): await process_frame
func run()->void:
	var app:Control=Main.instantiate(); root.add_child(app); await frames(8)
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/natural_coast_basic/expected_identities.json"))
	check(app.coast_mode and app.playtest_mode and app.board.tiles.size()==1801 and app.playtest.state_copy().world_id=="natural_coast_shore_v03_adventure","adopt_default_1801")
	var custody:Dictionary=HostCustody.capture(app.playtest)
	if not check(custody.ok and not C.bytes(custody.snapshot).is_empty(),"adopt_host_custody"): finish(); return
	var host_bytes:=C.bytes(custody.snapshot); var ui_bytes:=C.bytes(app._river_entry_ui_snapshot())
	for recipe in ["coastal_range","plateau_hinterland"]:
		app.open_natural_coast_experiment(recipe); await frames(8)
		var entry:Node=app.natural_coast_entry_controller
		if not check(entry!=null and entry.session.is_open() and entry.view!=null,"adopt_enter_"+recipe): finish(); return
		check(C.bytes(entry.session.coast.source.identity)==C.bytes(expected[recipe]),"adopt_exact_identity_"+recipe)
		entry.view._select_neighbor(); entry.view._choose_example("move"); entry.view._assess()
		check(entry.session.coast.phase()=="ready_roll","adopt_prepare_"+recipe)
		entry.view._apply(); await frames()
		check(entry.session.coast.phase()=="idle" and entry.session.coast.state_copy().turn==1,"adopt_commit_"+recipe)
		check(entry.close().ok,"adopt_return_"+recipe); await frames(6)
		check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false),"adopt_release_"+recipe)
		check(C.bytes(HostCustody.capture(app.playtest).snapshot)==host_bytes and C.bytes(app._river_entry_ui_snapshot())==ui_bytes,"adopt_host_exact_"+recipe)
	app.queue_free(); await frames(); finish()
func finish()->void:
	executed_check_ids.sort()
	if executed_check_ids!=EXPECTED_CHECK_IDS: failures.append("missing or unexpected adoption check IDs")
	var result:Dictionary={"ok":failures.is_empty(),"failures":failures,"checks":checks,"check_schema":CHECK_SCHEMA,"expected_check_ids":EXPECTED_CHECK_IDS,"executed_check_ids":executed_check_ids,"run_id":OS.get_environment("COAST_PLAY_RUN_ID"),"owned_pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"independent editable adoption tree only: unchanged full1801 startup and both exact gameplay identities/actions/return"}
	var output:=OS.get_environment("COAST_PLAY_OUTPUT"); var encoded:=JSON.stringify(result,"\t",true,true)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(encoded)
	FileAccess.open(output.path_join("completed.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":result.run_id,"owned_pid":result.owned_pid,"checks":checks,"script_sha256":result.script_sha256,"result_sha256":encoded.sha256_text()}))
	print("NATURAL_COAST_ADOPTED_SMOKE ",JSON.stringify(result)); quit(0 if failures.is_empty() else 1)
