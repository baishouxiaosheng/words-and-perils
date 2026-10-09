extends "res://tests/creative_actions/test_core.gd"
## Replies were produced by an independent offline model using public requests only.
func run()->void:
	base=Coast.world(true)
	var folder:="res://artifacts/creative_actions_20261003/semantic/"
	var sources:Array=["item_brace_oar","item_brace_bar",PLANK,PLANK,"item_brace_oar","item_brace_bar","item_brace_oar",PLANK,"item_brace_bar","item_brace_bar","item_brace_oar",PLANK]
	var targets:Array=[NORTH,SOUTH,NORTH,SOUTH,NORTH,NORTH,SOUTH,NORTH,SOUTH,NORTH,SOUTH,SOUTH]
	var results:Array=[];var accepted_count:=0;var feedback_count:=0
	for i in range(24):
		var name_:String="case_%02d"%(i+1)
		var raw_text:=FileAccess.get_file_as_string(folder+name_+"_reply.json")
		var raw:Variant=JSON.parse_string(raw_text)
		expect(raw is Dictionary,"offline model returned exact JSON "+name_)
		if not raw is Dictionary:continue
		var request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+name_+"_request.json"))
		var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+name_+"_state.json"))
		var e:=make(999);expect(e.load_data(saved).ok,"same frozen engine context loads "+name_)
		var scope:=Scope.new(e,func():return true);scope.model_request(raw.action_id)
		var before:Dictionary=e.save_data();var checked:Dictionary=scope.prepare_assessment(raw)
		var score:Dictionary={"case_id":name_,"player_goal":request.context.goal,"raw_reply_sha256":raw_text.sha256_text(),"schema":raw.schema_version,"accepted":checked.ok,"diagnostic":checked.get("code","")}
		if i<12:
			accepted_count+=1 if checked.ok else 0
			expect(checked.ok,"supported novel wording accepted "+name_+" "+str(checked))
			if not checked.ok:results.append(score);continue
			expect(raw.bindings.source.id==sources[i] and raw.bindings.target.id==targets[i] and raw.bindings.operation=="place_obstruction" and raw.bindings.intended_effect=="restrict_ground_traversal","source/target/consequence fidelity "+name_)
			var numeric:=true
			for component in raw.components:
				if component.parameters.A!=2 or component.parameters.P!=0 or component.parameters.D!=(3 if sources[i]=="item_brace_bar" else 2):numeric=false
			expect(numeric,"public rubric consistent, no invented skill "+name_)
			expect(e.roll_once(raw.action_id).ok and e.stage(raw.action_id).ok,"fixed program adjudication "+name_)
			var stage:Dictionary=e.action_copy(raw.action_id);var committed:Dictionary=e.commit(raw.action_id,stage.stage_hash)
			expect(committed.ok and World.validate(e.state_copy()).ok and e.state_copy().items.size()==before.state.items.size() and e.state_copy().turn==1,"grounded commit and conservation "+name_)
			score["source_fidelity"]=raw.bindings.source.id==sources[i];score["target_fidelity"]=raw.bindings.target.id==targets[i];score["numeric_consistency"]=numeric;score["receipt"]=committed.get("receipt",{})
		else:
			var allowed:Array=["NEEDS_CLARIFICATION"] if i<18 else ["INFEASIBLE","NO_SUPPORTED_MECHANISM","NEEDS_CLARIFICATION"]
			var appropriate:bool=not checked.ok and checked.get("code") in allowed
			feedback_count+=1 if appropriate else 0
			expect(appropriate,"questions/ambiguous/unsupported full intent remains unexecuted "+name_+" "+str(checked))
			expect(C.bytes(before)==C.bytes(e.save_data()),"feedback has zero state/RNG/turn/cost "+name_)
			score["nonexecuting_feedback"]=appropriate
		results.append(score)
	# Actual main adapter's manual-import route, using unchanged independent reply.
	var a:=Adapter.new(17,true)
	var request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"case_01_request.json"))
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"case_01_reply.json"))
	var focus:=Content.make_reference(request.context.attention_focus.id,a.state_copy())
	expect(a.begin_intent(request.context.goal,focus).ok and a.request().context_hash==request.context_hash,"independent first case reproduces exact actual-main public context")
	var imported:Dictionary=a.import_reply(raw)
	expect(imported.ok and a.action_copy().assessment.provenance.provider=="manual_offline_assessment","actual manual-import path accepts independent model reply honestly")
	expect(imported.ok and a.roll_once().ok and a.stage().ok and a.commit().ok,"actual manual-import program adjudication commits")
	var report:Dictionary={"evaluation":"independent_offline_model_public_requests_only","live_provider":false,"fixture_or_keyword_router":false,"supported_accepted":accepted_count,"supported_total":12,"appropriate_nonexecuting":feedback_count,"nonexecuting_total":12,"checks":checks,"failures":failures,"cases":results}
	write_json("semantic_report.json",report)
	print("CREATIVE_SEMANTIC ",checks-failures.size(),"/",checks," supported=",accepted_count,"/12 feedback=",feedback_count,"/12");quit(0 if failures.is_empty() else 1)
