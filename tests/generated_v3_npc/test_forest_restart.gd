extends "res://tests/generated_v3_npc/test_adapter.gd"
func run():
	var path="res://artifacts/generated_v3_npc_ui/forest_committed.json"
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var a=Adapter.new();var result:Dictionary=a.load_file(path)
	if check(result.ok,"fresh process reads final native forest checkpoint"):
		check(C.bytes(a.save_data())==C.bytes(saved),"fresh forest authority byte exact")
		check(a.source.features.vegetation and a.source.identity.vegetation_entity_catalog.entries.size()>0,"explicit forest feature and catalog restored")
		check(a.source.validate_history(a.engine.save_data()).ok,"forest complete physical action history restored")
		check(a.attention(a.npc_reference()).ok and a.attention(a.item_reference()).ok,"NPC and pack current witnesses restored")
		var plant:String=a.source.identity.vegetation_entity_catalog.entries.keys()[0]
		var before=C.bytes(a.save_data())
		check(a.attention(a.vegetation_reference(plant)).ok and C.bytes(a.save_data())==before,"fresh plant inspection authority pure")
		check(a.source.identity.content_hash==saved.identity.content_hash and a.source.identity.geometry_hash==saved.identity.geometry_hash and a.source.identity.runtime_hash==saved.identity.runtime_hash,"fresh exact source geometry and composition identity")
	FileAccess.open("res://artifacts/generated_v3_npc_ui/forest_restart_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty()},"\t"))
	print("NPC_FOREST_RESTART ",checks," ",failures);quit(0 if failures.is_empty() else 1)
