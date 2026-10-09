extends "res://tests/generated_v3_npc/test_adapter.gd"
# Synthetic wire-padding oracle only. The real source, selected focus, engine,
# pending lifecycle and64KiB adapter cap are unchanged. Padding is NOT public
# gameplay data and is never assessed, committed, saved or used by production.
class BudgetEngine:
	extends "res://core/ai_gm_rebuilt/engine.gd"
	var desired_bytes=65536
	var measured=0
	func model_request(action_id:String)->Dictionary:
		var result:Dictionary=super.model_request(action_id)
		if result.is_empty():return result
		result["synthetic_transport_padding"]=""
		var overhead=C.bytes(result).to_utf8_buffer().size()
		result.synthetic_transport_padding="x".repeat(maxi(0,desired_bytes-overhead))
		measured=C.bytes(result).to_utf8_buffer().size()
		return result
func run():
	var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
	var a=Adapter.new();check(a.start_source(generated.source).ok,"real source admitted")
	var original=a.engine
	a.engine=BudgetEngine.new(a.source.world,original._calculator,original._resolvers,original._policy)
	var rows=[]
	for target in [65536,65537]:
		a.engine.desired_bytes=target
		var before=C.bytes(a.state_copy());var rng=C.bytes(a.engine.save_data().rng)
		var result:Dictionary=a.begin_intent("\"".repeat(4096),a.npc_reference())
		check(a.engine.measured==target,"exact synthetic wire boundary "+str(target))
		if target==65536:
			check(result.ok and a.phase()=="awaiting_assessment","64KiB request admitted")
			check(a.cancel().ok,"under-limit fixture canceled without assessment")
		else:check(not result.ok and str(result.get("code","")).ends_with("REQUEST_BUDGET") and a.phase()=="idle","64KiB+1 safely rejected and canceled")
		check(before==C.bytes(a.state_copy()) and rng==C.bytes(a.engine.save_data().rng),"boundary preserves gameplay and RNG")
		rows.append({"synthetic_padding":true,"goal_bytes":4096,"measured_request_bytes":a.engine.measured,"result_ok":result.ok,"code":result.get("code",""),"phase_after_cancel":a.phase(),"gameplay_unchanged":before==C.bytes(a.state_copy()),"rng_unchanged":rng==C.bytes(a.engine.save_data().rng)})
	FileAccess.open("res://artifacts/generated_v3_npc/transport_boundary_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"synthetic padding of an actual engine request; separate from real maximum source-backed requests","rows":rows},"\t"))
	print("NPC_TRANSPORT_BOUNDARY ",checks," ",failures);quit(0 if failures.is_empty() else 1)
