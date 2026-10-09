extends "res://tests/generated_v3_npc/test_adapter.gd"
const OUT="res://artifacts/generated_v3_npc/requests_after/"
var sizes:Array=[]
func max_goal(token:String)->String:
	var prefix="向守路村民确认入口道路。"
	return prefix+token.repeat(4096-prefix.to_utf8_buffer().size()).substr(0,4096-prefix.to_utf8_buffer().size())
func retain(a:RefCounted,label:String):
	var request:Dictionary=a.request();var bytes=C.bytes(request).to_utf8_buffer().size()
	check(not request.is_empty() and bytes<=65536,label+" real request64KiB "+str(bytes))
	if request.is_empty():return
	check(request.context.goal.to_utf8_buffer().size()==4096,label+" full goal retained")
	FileAccess.open(OUT+label+".json",FileAccess.WRITE).store_string(C.bytes(request))
	sizes.append({"label":label,"bytes":bytes,"phase":request.phase,"headroom":65536-bytes})
func authored_manual(a:RefCounted)->Dictionary:
	# Transport-budget test: an explicitly offline assessed conversation, with
	# unchanged real request binding and exact public target witnesses.
	var compatible:Dictionary=a.request().duplicate(true);compatible.context.goal=a.sample_goal("talk")
	var built:Dictionary=Examples.build(compatible)
	if not built.ok:return built
	built.assessment.provenance={"provider":"offline_budget_test","live":false,"kind":"model_reply"}
	return a.import_reply(built.assessment)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for recipe in ["coastal_range","plateau_hinterland"]:
		var generated:Dictionary=Generator.generate(726381,12,recipe)
		var a=Adapter.new();a.feature_options={"vegetation":true}
		if not check(a.start_source(generated.source).ok,recipe+" source"):continue
		if not check(walk_to_npc(a),recipe+" legitimate travel"):continue
		if a.state_copy().actors.actor_player.stamina.current<1:check(execute(a,"rest"),recipe+" rest before talk")
		if not check(execute(a,"talk",a.npc_reference()),recipe+" initial learned fact"):continue
		var learned=C.bytes(a.state_copy().npc_state.learned_facts)
		var rows:Array=[a.npc_reference(),a.item_reference()]
		for id in a.source.identity.static_entity_catalog.entries:
			for hex in a.source.identity.static_entity_catalog.entries[id].supported_hexes:rows.append(a.static_reference(id,hex))
		var far_id="";var far_distance=-1
		for plant_id in a.source.identity.vegetation_entity_catalog.entries:
			var h:Array=a.source.identity.vegetation_entity_catalog.entries[plant_id].hex
			var player_hex:Array=a.state_copy().actors.actor_player.hex
			var q:int=h[0]-player_hex[0];var r:int=h[1]-player_hex[1];var distance=maxi(absi(q),maxi(absi(r),absi(q+r)))
			if distance>far_distance:far_id=plant_id;far_distance=distance
		check(not far_id.is_empty() and far_distance>4,recipe+" actual outer-radius plant after learning")
		if not far_id.is_empty():rows.append(a.vegetation_reference(far_id))
		var index=0
		for reference in rows:
			for token in ["x","\"","\\"]:
				var before=C.bytes(a.state_copy());var goal_=max_goal(token)
				if check(a.begin_intent(goal_,reference).ok,recipe+" learned max intent"):
					retain(a,recipe+"_learned_"+str(index));index+=1
					check(a.cancel().ok and C.bytes(a.state_copy())==before,recipe+" canceled max request no gameplay mutation")
		var road:String=a.source.placement_result.manifest.roads[0].id
		for token in ["x","\\"]:
			if a.state_copy().actors.actor_player.stamina.current<1:check(execute(a,"rest"),recipe+" rest repeat")
			check(a.begin_intent(max_goal(token),a.static_reference(road)).ok,recipe+" assessed repeat max goal")
			retain(a,recipe+"_repeat_assessment_"+str(index))
			if not check(authored_manual(a).ok,recipe+" explicit offline assessment"):break
			check(a.roll_once().ok and a.stage().ok,recipe+" stage assessed repeat")
			retain(a,recipe+"_repeat_staged_"+str(index))
			check(a.request().context.provisional_until_commit,recipe+" narration staged flag")
			check(a.commit().ok,recipe+" repeat commit")
			retain(a,recipe+"_repeat_committed_"+str(index));index+=1
			check(not a.request().context.provisional_until_commit and C.bytes(a.state_copy().npc_state.learned_facts)==learned,recipe+" repeated first proof preserved")
		# Unsupported C0 controls are a separate text-admission case, not a
		# fictional six-byte JSON expansion. Standard quote/backslash maxima
		# above are retained verbatim and independently parseable.
		var before=C.bytes(a.save_data());var result:Dictionary=a.begin_intent(max_goal(String.chr(1)),a.static_reference(road))
		check(not result.ok and result.get("code")=="NPC_INTENT_TEXT" and a.phase()=="idle",recipe+" unsupported control rejected before action")
		check(C.bytes(a.save_data())==before,recipe+" invalid text no authority/RNG/counter mutation")
		check(a.begin_intent("普通文字\n\t\r保持原样",a.npc_reference()).ok,recipe+" ordinary newline tab CR admitted")
		var bad=a.save_data();bad.engine.pending[a.active_action].goal+=String.chr(1)
		check(not Adapter.new().load_data(bad).ok,recipe+" pending unsupported control save rejected")
		check(a.cancel().ok,recipe+" normal control-text request canceled")
		bad=a.save_data();var receipt_id=bad.engine.receipts.keys()[0];bad.engine.receipts[receipt_id].goal+=String.chr(1)
		check(not Adapter.new().load_data(bad).ok,recipe+" historical unsupported control save rejected")
		roundtrip(a,recipe+" learned max-goal history")
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"sizes":sizes,"ok":failures.is_empty()},"\t"))
	print("NPC_CONTEXT_AFTER ",checks," ",failures);quit(0 if failures.is_empty() else 1)
