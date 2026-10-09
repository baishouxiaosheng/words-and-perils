extends SceneTree
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Controller=preload("res://view/generated_v3_river_entry/controller.gd")
func _initialize()->void:
	var host:=Node.new();var viewport:=SubViewport.new();var adapter:=RefCounted.new();var controller:=Controller.new()
	var bad_ui={"board_instance":host.get_instance_id(),"playtest_instance":adapter.get_instance_id()}
	var good_ui={"board_instance":str(host.get_instance_id()),"playtest_instance":str(adapter.get_instance_id())}
	var denied:Dictionary=controller.open(host,adapter,{},viewport,func()->Dictionary:return bad_ui)
	var report={"refcounted_id_exact":str(adapter.get_instance_id()),"node_id_exact":str(host.get_instance_id()),"numeric_snapshot_safe":C.safe(bad_ui),"numeric_snapshot_bytes_empty":C.bytes(bad_ui).is_empty(),"string_snapshot_safe":C.safe(good_ui),"string_snapshot_bytes_nonempty":not C.bytes(good_ui).is_empty(),"actual_controller_rejection":denied,"session_built":controller.session.is_open()}
	var passed:bool=not report.numeric_snapshot_safe and report.numeric_snapshot_bytes_empty and report.string_snapshot_safe and report.string_snapshot_bytes_nonempty and denied.get("code")=="RIVER_HOST_UI" and not report.session_built
	report["ok"]=passed
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_river_entry")
	FileAccess.open("res://artifacts/generated_v3_river_entry/identity_diagnosis.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
	print("RIVER_IDENTITY_DIAGNOSIS ",JSON.stringify(report))
	controller.free();viewport.free();host.free();quit(0 if passed else 1)
