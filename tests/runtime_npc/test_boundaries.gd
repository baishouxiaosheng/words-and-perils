extends "res://tests/runtime_npc/test_controller.gd"
class RequestFixture:
	extends RefCounted
	var state:Dictionary={}
	var request:Dictionary={}
	func state_copy()->Dictionary:return state.duplicate(true)
	func model_request(_id:String)->Dictionary:return request.duplicate(true)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
	var a=Adapter.new(generated.source)
	if not check(a.ready().ok and walk_to_npc(a) and a.begin_intent("想问问进村的路。",a.npc_reference()).ok,"boundary source and pending intent"):finish_boundaries();return
	var exact=a.request();var frozen=C.bytes(a.save_data())
	var full=Full.new(a.engine,func():return true,98304)
	check(C.bytes(full.model_request(a.active_action))==C.bytes(exact),"valid96KiB configuration still sends existing request unchanged")
	var bad_capacity=Full.new(a.engine,func():return true,0)
	check(bad_capacity.model_request(a.active_action).is_empty() and bad_capacity.last_error.code=="INVALID_REQUEST_BUDGET","invalid capacity does not clamp into validity")
	var small=Full.new(a.engine,func():return true,100)
	check(small.model_request(a.active_action).is_empty() and small.last_error.code=="CONTEXT_BUDGET","explicit smaller capacity remains enforced")
	var stopped=Full.new(a.engine,func():return false)
	check(stopped.model_request(a.active_action).is_empty(),"invalidated scope sends nothing")
	for mutation in ["missing_profile","wrong_profile","wrong_projection","scalar_metadata","missing_npc_state"]:
		var fixture=RequestFixture.new();fixture.state=a.state_copy();fixture.request=exact
		match mutation:
			"missing_profile":fixture.state.generated_world.erase("profile")
			"wrong_profile":fixture.state.generated_world.profile="unregistered"
			"wrong_projection":fixture.state.generated_world.projection_id="unregistered"
			"scalar_metadata":fixture.state.generated_world=17
			"missing_npc_state":fixture.state.erase("npc_state")
		check(Full.recognizes(fixture.state),mutation+" remains recognizable for fail-closed dispatch")
		var scope=Full.new(fixture,func():return true)
		check(scope.model_request(a.active_action).is_empty() and scope.last_error.code=="RUNTIME_PROFILE",mutation+" rejected without coast fallback")
	var boundary_rows=[]
	for target in [65536,65537]:
		var fixture=RequestFixture.new();fixture.state=a.state_copy();fixture.request=exact.duplicate(true);fixture.request["synthetic_wire_padding"]=""
		var overhead=C.bytes(fixture.request).to_utf8_buffer().size();fixture.request.synthetic_wire_padding="x".repeat(target-overhead)
		var scope=Full.new(fixture,func():return true,98304);var wire:Dictionary=scope.model_request(a.active_action)
		check(C.bytes(fixture.request).to_utf8_buffer().size()==target,"synthetic boundary measured exactly")
		check((not wire.is_empty())==(target==65536),"existing64KiB profile cap at "+str(target))
		if target==65537:check(scope.last_error.code=="CONTEXT_BUDGET" and str(scope.last_error.errors).contains("固定64"),"larger generic setting does not imply profile expansion")
		boundary_rows.append({"synthetic_padding":true,"bytes":target,"sent":not wire.is_empty(),"configured_capacity":98304,"effective_capacity":scope.last_metrics.budget_bytes})
	check(C.bytes(a.save_data())==frozen,"all scope probes leave authority exact")
	# Real client/codec path rejects all unsupported text and size shapes before
	# the original engine can freeze an assessment. Incoming controls are valid
	# JSON escapes; no shared canonical serialization is modified.
	var trio=configured(a);var runtime:Node=trio[0];var mock:Node=trio[1]
	for attack in ["narration_control","interpretation_control","ref_id_control","key_control","oversize_reply","oversize_narration","off_scope_fact","wrong_binding","raw_patch"]:
		var started:Dictionary=runtime.request_assessment();var request=outgoing(mock);var reply=answer(request)
		match attack:
			"narration_control":reply.narration+=String.chr(1)
			"interpretation_control":reply.interpretation+=String.chr(31)
			"ref_id_control":reply.fact_refs[0].id+=String.chr(1);reply.components[0].fact_ref_ids[0]=reply.fact_refs[0].id
			"key_control":reply[String.chr(1)]="unknown"
			"oversize_reply":reply.interpretation="x".repeat(65536)
			"oversize_narration":reply.narration="x".repeat(8193)
			"off_scope_fact":reply.fact_refs[0].path="/untransmitted_private_fact"
			"wrong_binding":reply.context_hash="wrong"
			"raw_patch":reply.patches=[{"type":"flag_set","flag_id":"invented","value":true}]
		mock.respond(started.request_id,envelope(reply))
		check(not runtime.last_result.ok and a.phase()=="awaiting_assessment" and C.bytes(a.save_data())==frozen,attack+" rejects without authority mutation")
	# Synchronous cancellation response is not permitted to prepare a plan.
	var started:Dictionary=runtime.request_assessment();var request=outgoing(mock)
	mock.cancellation_response=envelope(answer(request));runtime.cancel()
	check(not runtime.busy() and a.phase()=="awaiting_assessment" and C.bytes(a.save_data())==frozen,"synchronous cancel reply ignored")
	mock.cancellation_response=""
	var delivered=[0];runtime.assessment_validated.connect(func(_id):delivered[0]+=1)
	mock.synchronous_response=envelope(answer(a.request()))
	started=runtime.request_assessment()
	check(started.ok and delivered[0]==1 and a.phase()=="ready_roll" and not runtime.busy(),"synchronous send completion has armed token and one notification")
	var locked_before=C.bytes(a.state_copy());check(a.roll_once().ok,"original lock once")
	var count=mock.sent.size();check(not runtime.request_assessment().ok and mock.sent.size()==count,"locked plan cannot request reassessment")
	check(a.stage().ok and a.commit().ok,"original staged result commits after synchronous response")
	var session:RefCounted=trio[2];session.committed();mock.synchronous_response=""
	check(a.state_copy().turn==JSON.parse_string(locked_before).turn+1,"one committed turn only")
	# Committed prose has the same transport-safe text boundary and sidecar
	# idempotency; staged/manual prose remains optional display-only data.
	for bad_text in ["bad"+String.chr(1),"x".repeat(8193)]:
		started=runtime.request_narration();request=outgoing(mock);var before=C.bytes(a.save_data())
		mock.respond(started.request_id,envelope(prose(request,bad_text)))
		check(not runtime.last_result.ok and C.bytes(a.save_data())==before and session.narration_entries().is_empty(),"invalid optional prose rejected before display/history")
	var manual:Dictionary=prose(a.request(),"首次手工文字，后续不能改写。")
	check(session.import_narration(manual).ok and session.narration_entries().size()==1,"manual committed narration uses same sidecar")
	manual.narration="重复文字不能覆盖首次记录。"
	check(session.import_narration(manual).already_recorded and session.narration_entries()[0].narration=="首次手工文字，后续不能改写。","manual duplicate does not rewrite first prose")
	var path="user://runtime_boundary_sidecar.json";check(a.save_file(path).ok and session.save_sidecar(path).ok,"sidecar fixture saved")
	var original=FileAccess.get_file_as_string(path+".narration.json");var core=C.bytes(a.save_data())
	for attack in ["wrong_core","wrong_receipt","wrong_world","control_text"]:
		var doc:Dictionary=JSON.parse_string(original)
		match attack:
			"wrong_core":doc.core_save_sha256="wrong"
			"wrong_receipt":doc.records[0].receipt_hash="wrong"
			"wrong_world":doc.world_id="wrong"
			"control_text":doc.records[0].narration+=String.chr(1);doc.records[0].text_sha256=doc.records[0].narration.sha256_text()
		FileAccess.open(path+".narration.json",FileAccess.WRITE).store_string(C.bytes(doc))
		var loaded:Dictionary=session.load_sidecar(path)
		check(session.narration_entries().is_empty() and not str(loaded.get("warning","")).is_empty() and C.bytes(a.save_data())==core,attack+" optional sidecar ignored without authority loss")
	runtime.free()
	FileAccess.open(OUT+"boundary_rows.json",FileAccess.WRITE).store_string(JSON.stringify(boundary_rows,"\t"));finish_boundaries()
func finish_boundaries():
	FileAccess.open(OUT+"boundaries_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"live":false,"synthetic_padding_boundary_separate":true},"\t"))
	print("RUNTIME_NPC_BOUNDARIES ",checks," ",failures);quit(0 if failures.is_empty() else 1)
