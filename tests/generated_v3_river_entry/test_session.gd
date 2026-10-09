extends SceneTree
## Static-prepared test. Run only in a new integration candidate after the UI
## owner releases the serial native slot. It is not a full Main integration gate.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const EntrySession = preload("res://view/generated_v3_river_entry/session.gd")
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
	check(not session.enter(host,idle_status(),"default").ok and session.river==null,"wrong choice cannot build river")
	for field in ["world_build_busy","generated_start_busy","end_turn_busy","runtime_busy"]:
		var busy := idle_status();busy[field]=true
		check(not session.enter(host,busy,EntrySession.ENTRY_ID).ok and session.river==null,"busy host denied: "+field)
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
	var river: RefCounted=session.river
	check(session.is_open() and C.bytes(host.save_data())==original,"opened host remains exact")
	check(not session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok and session.river==river,"duplicate open never creates second session")
	for filename in ["generated_v3_village_equipment_v1.json","generated_v3_village_equipment_request_v1.json","GENERATED_V3_VILLAGE_EQUIPMENT_V1.JSON"]:
		check(not river._check_destination("user://"+filename).ok,"equipment namespace protected: "+filename)
	check(river.default_save_path()=="user://generated_v3_rivers_v1.json","river keeps its isolated save path")
	var state: Dictionary=river.state_copy();var at: Array=state.actors.actor_player.hex
	var neighbor: String=river.source.navigation.allowed["%d,%d"%at][0]
	var cell: Dictionary=river.source.data.cells[neighbor];var focus: Dictionary=river.tile_reference([cell.q,cell.r])
	check(river.begin_intent(river.sample_goal("move",focus),focus).ok and river.prepare_fixture().ok,"river pending action prepared normally")
	check(not session.leave().ok and session.is_open() and river.phase()=="ready_roll","return never silently cancels or commits pending action")
	check(C.bytes(host.save_data())==original and host.writes==0,"river assessment never touches host authority")
	check(river.cancel().ok,"explicit river cancel remains available")
	var retained := C.bytes(river.save_data())
	check(session.leave().ok and not session.is_open() and session.river==null,"idle return retains only JSON, not guest resources")
	river=null
	check(session.enter(host,idle_status(),EntrySession.ENTRY_ID).ok and session.river!=null and C.bytes(session.river.save_data())==retained,"reentry reconstructs exact independent session without reroll")
	host.authority.turn=8
	check(not session.leave().ok and session.is_open(),"host drift fails closed")
	check(host.authority.turn==8 and host.writes==0,"host drift never triggers snapshot rollback or overwrite")
	finish()
func finish() -> void:
	print("EXPERIMENTAL_RIVER_ENTRY ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
