extends SceneTree
const Adapter=preload("res://view/generated_v3_npc/adapter.gd")
const Session=preload("res://view/runtime_ai/village_session.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures=[]
func _initialize():run.call_deferred()
func check(value:bool,label:String):
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func run():
	var path="user://runtime_npc_sidecar.json"
	var raw=FileAccess.get_file_as_string(path);var data=JSON.parse_string(raw)
	check(data is Dictionary,"prior process core exists")
	var a=Adapter.new();var result=a.load_file(path)
	if result.ok:
		check(C.bytes(a.save_data())==C.bytes(data),"fresh process exact authority and RNG")
		var before=C.bytes(a.save_data());var session=Session.new(a);var loaded=session.load_sidecar(path)
		check(loaded.status=="loaded" and session.narration_entries().size()==1,"fresh process matching prose sidecar")
		check(session.has_recorded_narration(a.last_action),"fresh process idempotency binds receipt")
		check(a.narration.contains("MOCK_DISPLAY_ONLY"),"fresh process restores visible prose")
		check(not C.bytes(a.request()).contains("MOCK_DISPLAY_ONLY") and not raw.contains("MOCK_DISPLAY_ONLY"),"prose absent from core and model facts")
		check(C.bytes(a.save_data())==before,"sidecar load changes no authority")
		check(session.record_narration(a.last_action,"new text","manual").already_recorded and session.narration_entries().size()==1,"manual duplicate after restart remains idempotent")
	else:check(false,"core readmission: "+str(result))
	FileAccess.open("res://artifacts/runtime_npc/restart_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"fresh_process":true},"\t"))
	print("RUNTIME_NPC_RESTART ",checks," ",failures);quit(0 if failures.is_empty() else 1)
