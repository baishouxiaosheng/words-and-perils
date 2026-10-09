extends "res://tests/resource_lifecycle/profile_lifecycle.gd"
func measure(label_:String)->void:
	await super.measure(label_)
	if label_!="focus":return
	var view=app.board.world_view
	var facts:=C.digest(app.playtest.engine.save_data())
	for i in range(50):view._update_budget()
	var per_call_us:Array=[]
	for sample in range(5):
		var started:=Time.get_ticks_usec()
		for i in range(200):view._update_budget()
		per_call_us.append(float(Time.get_ticks_usec()-started)/200.0)
	per_call_us.sort()
	report["budget_refresh_microbenchmark"]={"calls":1000,"five_sorted_mean_usec_per_call":per_call_us,"median_usec_per_call":per_call_us[2],"retained_fallback_groups":view.tree_groups.size(),"active_whole_groups":view.whole_canopies.groups.size(),"unchanged_camera":true,"not_an_fps_measurement":true}
	check(C.digest(app.playtest.engine.save_data())==facts,"repeated visual budget refresh preserves authoritative save bytes")
	save()
