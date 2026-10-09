extends SceneTree
const WaterQueries = preload("river_water_queries.gd")
var failure := false
func check(ok: bool, label: String) -> void:
	if not ok:
		failure = true
		push_error(label)
func v(value: Array) -> Vector2: return Vector2(value[0],value[1])
func _initialize() -> void:
	var data_dir := ProjectSettings.globalize_path("res://../../artifacts/river_overlay_portfix_20261002")
	var helper := WaterQueries.new()
	check(helper.load_file(data_dir.path_join("optimized_same_footprint/new_water_query.json")),"load bound query")
	if not helper.ready:
		quit(1)
		return
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("water_query_cases.json")))
	var outputs: Dictionary = {}
	for name in ["cross_river","same_bank","zero_wet","zero_dry","far_away"]:
		var pair: Array = cases[name]
		var hit := helper.segment_intersects_water(v(pair[0]),v(pair[1]))
		outputs[name] = hit
		check(hit["ok"],name+" query failed")
		check(hit["intersects"] == (name in ["cross_river","zero_wet"]),name+" unexpected water contact")
		check(not hit["movement_result_decided"],name+" must not decide movement")
	var cross: Dictionary = outputs["cross_river"]
	check(not cross["start_in_new_water"] and not cross["end_in_new_water"],"cross endpoints must remain dry")
	check(cross["contact_length_world"]>.10 and cross["contact_length_world"]<.14,"actual narrow water width contact")
	check(cross["water_bodies"]["source"]=="lake:28127" and cross["water_bodies"]["receiver"]=="lake:31","actual lake IDs")
	check(not cross["original_faces"].is_empty(),"original face metadata lost")
	var reverse := helper.segment_intersects_water(v(cases["cross_river"][1]),v(cases["cross_river"][0]))
	check(absf(reverse["contact_length_world"]-cross["contact_length_world"])<1e-7,"reversed segment differs")
	var wet := helper.water_endpoint_context(v(cases["wet_endpoint"]))
	var dry := helper.water_endpoint_context(v(cases["dry_endpoint"]))
	check(wet["is_new_river_water"] and not dry["is_new_river_water"],"wet/dry endpoints")
	check(not helper.water_endpoint_context(v(cases["old_source_lake_center"]))["is_new_river_water"],"old source lake must be excluded")
	check(not helper.water_endpoint_context(v(cases["old_receiver_lake_center"]))["is_new_river_water"],"old receiver lake must be excluded")
	var candidates: Array = [cases["wet_endpoint"],cases["dry_endpoint"],[100,100]]
	var nearest := helper.nearest_dry_candidate(v(cases["wet_endpoint"]),candidates)
	check(nearest["found"] and nearest["candidate_index"]==1,"nearest supplied dry candidate")
	var empty := helper.nearest_dry_candidate(v(cases["wet_endpoint"]),[cases["wet_endpoint"]])
	check(not empty["found"],"must not invent dry anchor")
	var boundary: Array = helper.polygons[100]["polygon_xz"][0]
	check(helper.water_endpoint_context(v(boundary))["is_new_river_water"],"exact boundary contact within f32 tolerance")
	var bad := WaterQueries.new()
	check(not bad.load_file(data_dir.path_join("optimized_same_footprint/new_water_query.json"),"wrong-sha"),"corrupt binding accepted")
	var report := {"status":"FAIL_WATER_QUERY_CASES" if failure else "PASS_WATER_QUERY_CASES","scope":"READ_ONLY_NEW_RIVER_NO_MOVEMENT_RESULT","candidate_sha256":WaterQueries.CANDIDATE_SHA,"query_sha256":WaterQueries.QUERY_SHA,"new_water_polygons":helper.polygons.size(),"cases":outputs,"nearest_supplied_dry_candidate":nearest,"boundary_contact_included":true,"reverse_invariant":true,"bad_sha_rejected":true}
	var out := FileAccess.open(data_dir.path_join("water_query_headless.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"status":report["status"],"polygons":helper.polygons.size(),"cross_contact_length":cross["contact_length_world"],"cross_original_faces":cross["original_faces"],"same_bank_intersects":outputs["same_bank"]["intersects"],"nearest_dry_index":nearest["candidate_index"]}))
	quit(1 if failure else 0)
