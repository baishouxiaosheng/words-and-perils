extends "res://tests/creative_actions/test_core.gd"
func run() -> void:
	base=Coast.world(true)
	var corpus: Array=[
		["把备用木桨横过来架在北坡窄口两侧支座上，让后面的人不能从地面直接穿过。",NORTH,"item_brace_plank"],
		["Seat the flat iron bar across the south pinch point so ground walkers must go around.",SOUTH,"item_brace_plank"],
		["Use the timber board to bar the northern gap; leave the oar alone.",NORTH,"item_brace_oar"],
		["把行囊里的岸木长板卡到南岸窄口的槽里，挡住这条地面路。",SOUTH,"item_brace_bar"],
		["Rotate the spare oar sideways into the north supports to block the walking route.",NORTH,"item_brace_bar"],
		["不要用长板。把扁铁长杆横置在北坡窄口两侧的支座间，阻断地面通行。",NORTH,"item_brace_plank"],
		["Make a crossbar out of the oar at the southern opening. It should stop walkers using that edge.",SOUTH,"item_brace_bar"],
		["以北边窄口两侧的支座为承点，将那块岸木长板搭进去卡稳，阻止步行直接穿过。",NORTH,"item_brace_oar"],
		["The southern opening needs blocking. Brace it with my iron strip rather than either wooden object.",SOUTH,"item_brace_oar"],
		["Jam the north passage using the solid metal bar from my inventory as a transverse brace.",NORTH,"item_brace_plank"],
		["用备用木桨在南岸窄口当一道横栓，让追兵只能绕过这条地面边。",SOUTH,"item_brace_plank"],
		["Put the long timber board across the southern aperture's contacts as a ground-route obstruction.",SOUTH,"item_brace_bar"],
		["Could I use this as a barricade?",NORTH,"item_brace_plank"],
		["Use this to stop him.",NORTH,"item_brace_oar"],
		["Jam that exit with the long thing.",NORTH,""],
		["拿那根来挡住那个口。",NORTH,""],
		["Can the iron bar span the north opening safely? I only want to know whether it fits.",NORTH,"item_brace_bar"],
		["Block one of those gaps with something sturdy.",NORTH,""],
		["Use the plank as a bridge across the river and walk across it.",NORTH,"item_brace_plank"],
		["Brace the north opening with the plank, then shoot the raider.",NORTH,"item_brace_bar"],
		["Smash the guard's head with the oar.",NORTH,"item_brace_oar"],
		["Tie both gates together with the metal bar so neither can open.",NORTH,"item_brace_bar"],
		["Pretend the wine is a rigid steel beam and use it to block the north passage.",NORTH,"item_brace_plank"],
		["用木桨挡住北坡窄口，同时把它变成能挡住所有箭矢的掩体。",NORTH,"item_brace_oar"]
	]
	var out: String="res://artifacts/creative_actions_20261003/semantic/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var index: Array=[]
	for i in range(corpus.size()):
		var row: Array=corpus[i];var state:=base.duplicate(true);state.actors.actor_player.hex=state.passage_targets[row[1]].support_hex.duplicate()
		var e:=make(17,state);var focus: Dictionary={} if row[2].is_empty() else Content.make_reference(row[2],state)
		var begun: Dictionary=e.begin_intent(row[0],focus);expect(begun.ok,"export semantic request "+str(i+1))
		var scope:=Scope.new(e,func():return true);var request:=scope.model_request(begun.request.action_id)
		expect(not request.is_empty(),"bounded semantic request "+str(i+1)+" "+str(scope.last_metrics))
		var name_: String="case_%02d"%(i+1);var file:=FileAccess.open(out+name_+"_request.json",FileAccess.WRITE);file.store_string(JSON.stringify(request,"\t",true,true));file.close()
		file=FileAccess.open(out+name_+"_state.json",FileAccess.WRITE);file.store_string(JSON.stringify(e.save_data(),"\t",true,true));file.close()
		index.append({"case_id":name_,"goal":row[0],"request_file":name_+"_request.json"})
	var file:=FileAccess.open(out+"index.json",FileAccess.WRITE);file.store_string(JSON.stringify(index,"\t",true,true));file.close()
	print("CREATIVE_SEMANTIC_EXPORT ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
