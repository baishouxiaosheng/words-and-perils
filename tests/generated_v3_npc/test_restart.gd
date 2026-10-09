extends "res://tests/generated_v3_npc/test_adapter.gd"
const OUT="res://artifacts/generated_v3_npc_restart/"
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	var args=OS.get_cmdline_user_args();var mode:String=args[0] if args.size()>0 else "create";var phase_:String=args[1] if args.size()>1 else "pending"
	var a=Adapter.new();var path=OUT+phase_+".json"
	if mode=="create":
		var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
		check(a.start_source(generated.source).ok,"fresh creation")
		if not a.ready().ok:finish_restart(mode,phase_);return
		check(walk_to_npc(a),"real travel before saved conversation")
		if phase_!="idle":
			check(a.begin_intent(a.sample_goal("talk"),a.npc_reference()).ok,"start conversation")
			if phase_ in ["ready","locked","staged","committed","repeat"]:check(a.prepare_fixture().ok,"assessed")
			if phase_ in ["locked","staged","committed","repeat"]:check(a.roll_once().ok,"locked")
			if phase_ in ["staged","committed","repeat"]:check(a.stage().ok,"staged")
			if phase_ in ["committed","repeat"]:check(a.commit().ok,"committed")
			if phase_=="repeat":
				if a.state_copy().actors.actor_player.stamina.current<1:check(execute(a,"rest"),"rest")
				check(execute(a,"talk",a.npc_reference()),"second conversation")
		check(a.save_file(path).ok,"write independent phase save")
		FileAccess.open(OUT+phase_+"_request.json",FileAccess.WRITE).store_string(C.bytes(a.request()))
	else:
		var exact=FileAccess.get_file_as_string(path);var loaded:Dictionary=a.load_file(path)
		if not check(loaded.ok,"fresh process admits "+phase_+str(loaded)):finish_restart(mode,phase_);return
		check(C.bytes(a.save_data())==C.bytes(JSON.parse_string(exact)),"fresh process byte exact authority")
		check(C.bytes(a.request())==FileAccess.get_file_as_string(OUT+phase_+"_request.json"),"fresh process same frozen request")
		if phase_ in ["pending","ready"]:
			var before=C.bytes(a.state_copy());check(a.cancel().ok and C.bytes(a.state_copy())==before,"recovered pending cancel no knowledge")
		elif phase_ in ["locked","staged"]:
			var before=C.bytes(a.save_data());check(not a.cancel().ok and C.bytes(a.save_data())==before,"recovered lock cannot cancel")
			if phase_=="locked":check(a.stage().ok,"recovered stage")
			check(a.commit().ok and a.state_copy().npc_state.contacts[a.source.npc_id].conversation_count==1,"recovered commit learns exactly once")
		else:check(a.source.validate_history(a.engine.save_data()).ok,"recovered committed history")
	finish_restart(mode,phase_)
func finish_restart(mode:String,phase_:String):
	FileAccess.open(OUT+mode+"_"+phase_+"_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty()},"\t"))
	print("NPC_RESTART ",mode," ",phase_," ",checks," ",failures);quit(0 if failures.is_empty() else 1)
