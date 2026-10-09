extends SceneTree
## Static-prepared test. Run only in a new integration candidate after the UI
## owner releases the serial native slot. It is not a full Main integration gate.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const EntrySession = preload("res://view/generated_natural_coast_entry/session.gd")
const Custody = preload("res://view/generated_v3_river_entry/host_custody.gd")
class HostProbe extends RefCounted:
	var current_phase := "idle"
	var authority := {"world_id":"probe_existing_host","turn":7,"rng":{"counter":11},"receipts":["previous_real_action"]}
	var writes := 0
	func phase() -> String: return current_phase
	func save_data() -> Dictionary: return authority.duplicate(true)
	func state_copy() -> Dictionary: return authority.duplicate(true)
	func load_data(_value: Variant) -> Dictionary: writes+=1;return {"ok":false}
	func commit() -> Dictionary: writes+=1;return {"ok":false}
	func save_file(_path: String="") -> Dictionary: writes+=1;return {"ok":false}
class WrongReturnProbe extends RefCounted:
	func phase() -> String: return "idle"
	func state_copy() -> Dictionary: return {"world_id":"wrong_return_probe"}
	func save_data() -> Array: return ["not a complete save"]
class EmptySaveProbe extends HostProbe:
	func save_data() -> Dictionary: return {}
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> bool:
	checks+=1
	if not value: failures.append(label);printerr("ENTRY_FAIL ",label)
	return value
func idle_status() -> Dictionary:
	return {"world_build_busy":false,"generated_start_busy":false,"end_turn_busy":false,"runtime_busy":false,"active_action":""}
func run() -> void:
	var host := HostProbe.new();var original := C.bytes(host.save_data());var session := EntrySession.new()
	check(not Custody.capture(RefCounted.new()).ok,"missing explicit host capability fails closed")
	check(not Custody.capture(WrongReturnProbe.new()).ok,"wrong save return signature fails closed")
	check(not Custody.capture(EmptySaveProbe.new()).ok,"empty save cannot substitute for real authority")
	var capture:Dictionary=Custody.capture(host)
	check(capture.ok and capture.kind=="adapter_save_data/v1" and C.bytes(capture.snapshot.saved)==original,"generated capability reads complete typed save without writes")
	check(not EntrySession.descriptor().get("default",true),"entry is never default")
	check(EntrySession.descriptor().radius==4 and EntrySession.descriptor().seed==726381,"only fixed admitted seed/radius described")
	check(not session.enter(host,idle_status(),"default").ok and session.coast==null,"wrong choice cannot build river")
	for field in ["world_build_busy","generated_start_busy","end_turn_busy","runtime_busy"]:
		var busy := idle_status();busy[field]=true
		check(not session.enter(host,busy,EntrySession.ENTRY_ID).ok and session.coast==null,"busy host denied: "+field)
	var missing := idle_status();missing.erase("runtime_busy")
	check(not session.enter(host,missing,EntrySession.ENTRY_ID).ok,"missing busy flag fails closed")
	var pending := idle_status();pending.active_action="host_action"
	check(not session.enter(host,pending,EntrySession.ENTRY_ID).ok,"active host action denied")
	host.current_phase="ready_roll"
	check(not session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok,"pending host phase denied")
	host.current_phase="idle"
	check(C.bytes(host.save_data())==original and host.writes==0,"all entry rejections preserve host")
	var opened: Dictionary=session.enter(host,idle_status(),EntrySession.ENTRY_ID)
	if not check(opened.get("ok",false),"explicit fixed river session opens"): finish();return
	var coast: RefCounted=session.coast
	check(session.is_open() and C.bytes(host.save_data())==original,"opened host remains exact")
	check(not session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok and session.coast==coast,"duplicate open never creates second session")
	for filename in ["generated_v3_village_equipment_v1.json","generated_v3_village_equipment_request_v1.json","GENERATED_V3_VILLAGE_EQUIPMENT_V1.JSON"]:
		check(not coast._check_destination("user://"+filename).ok,"equipment namespace protected: "+filename)
	check(coast.default_save_path()=="user://natural_coast_basic_v1_coastal_range.json","river keeps its isolated save path")
	var state: Dictionary=coast.state_copy();var at: Array=state.actors.actor_player.hex
	var neighbor: String=coast.source.navigation.allowed["%d,%d"%at][0]
	var cell: Dictionary=coast.source.data.cells[neighbor];var focus: Dictionary=coast.tile_reference([cell.q,cell.r])
	check(coast.begin_intent(coast.sample_goal("move",focus),focus).ok and coast.prepare_fixture().ok,"river pending action prepared normally")
	check(not session.leave().ok and session.is_open() and coast.phase()=="ready_roll","return never silently cancels or commits pending action")
	check(C.bytes(host.save_data())==original and host.writes==0,"river assessment never touches host authority")
	check(coast.cancel().ok,"explicit river cancel remains available")
	var retained := C.bytes(coast.save_data())
	check(session.leave().ok and not session.is_open() and session.coast==null,"idle return retains only JSON, not guest resources")
	coast=null
	check(session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok and session.coast!=null and C.bytes(session.coast.save_data())==retained,"reentry reconstructs exact independent session without reroll")
	host.authority.turn=8
	check(not session.leave().ok and session.is_open(),"host drift fails closed")
	check(host.authority.turn==8 and host.writes==0,"host drift never triggers snapshot rollback or overwrite")
	host.authority.turn=7
	check(session.leave().ok,"exact restored host can return without rollback")
	var retained_coastal: Dictionary = session._parked_coast_saves.coastal_range.duplicate(true)
	check(session.enter(host,idle_status(),EntrySession.ENTRY_ID,"plateau_hinterland").ok and session.coast.source.data.recipe.id == "plateau_hinterland","second recipe enters only when explicitly selected")
	check(session.leave().ok and C.bytes(session._parked_coast_saves.coastal_range) == C.bytes(retained_coastal),"recipe sessions park independent JSON progress")
	check(session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok and C.bytes(session.coast.save_data()) == C.bytes(retained_coastal),"return to first recipe restores exact previous progress")
	check(session.leave().ok,"final session leaves cleanly")
	finish()
func finish() -> void:
	var output := OS.get_environment("COAST_PLAY_OUTPUT")
	var result := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"suite":get_script().resource_path,"recipe":OS.get_environment("COAST_PLAY_RECIPE"),"run_id":OS.get_environment("COAST_PLAY_RUN_ID"),"owned_pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path)}
	if not output.is_empty():
		var encoded := JSON.stringify(result,"\t",true,true)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(encoded)
		FileAccess.open(output.path_join("completed.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":result.run_id,"owned_pid":result.owned_pid,"checks":checks,"result_sha256":encoded.sha256_text(),"script_sha256":result.script_sha256}))
	print("NATURAL_COAST_BASIC ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
