extends "res://tests/creative_actions/test_core.gd"
func run() -> void:
	base=Coast.world(true)
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/creative_actions_20261003/pending_expected.json"))
	for phase in ["awaiting_assessment","ready_roll","rolled","staged"]:
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/creative_actions_20261003/pending_"+phase+".json"))
		var e:=make(234);expect(e.load_data(data).ok,"fresh process exact load "+phase)
		var id: String=data.pending.keys()[0]
		if phase=="awaiting_assessment":
			var built:=Examples.assessment(e.model_request(id),PLANK,NORTH);expect(built.ok and e.prepare_assessment(built.assessment).ok,"fresh process assessment")
		if phase in ["awaiting_assessment","ready_roll"]:expect(e.roll_once(id).ok,"fresh program RNG")
		if phase!="staged":expect(e.stage(id).ok,"fresh stage")
		expect(e.commit(id,e.action_copy(id).stage_hash).ok,"fresh commit "+phase)
		expect(C.bytes(e.save_data())==C.bytes(expected),"same world, dice, receipt and retry history "+phase)
	print("CREATIVE_RELOAD ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
