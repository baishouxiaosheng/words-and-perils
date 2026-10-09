extends SceneTree
const Coast=preload("res://view/playable_build/adapter.gd")
const Log=preload("res://view/runtime_ai/narration_log.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const PATH="user://runtime_narration_history_test.json"
const PROSE="NARRATION_ONLY_MARKER：雾沿旧灯散开，权威结果已经固定。"
var checks:=0
var failures:Array[String]=[]
class ReceiptArchive extends RefCounted:
	var data:Dictionary={"state":{"world_id":"unit_world","generated_world":{"bundle_id":"unit_bundle"}},"receipts":{}}
	func save_data()->Dictionary:return data.duplicate(true)
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL: "+label)
func _initialize()->void:run.call_deferred()
func assessment(req:Dictionary)->Dictionary:
	return {"schema_version":"ai_gm_assessment/v1","action_id":req.action_id,"state_version":req.state_version,"context_hash":req.context_hash,"narration":"准备观察海岸。","interpretation":"离线结构化评估用于历史持久化回归。","resolver_id":"coast_observe","bindings":{"actor_id":"actor_player"},"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["player","coast"]}],"fact_refs":[{"id":"player","path":"/actors/actor_player","expected":req.context.facts.actors.actor_player},{"id":"coast","path":"/story_anchors/anchor_coast","expected":req.context.facts.story_anchors.anchor_coast}],"provenance":{"provider":"manual_offline_assessment","live":false,"kind":"model_reply"}}
func committed_adapter()->RefCounted:
	var adapter:=Coast.new()
	check(adapter.begin_intent("观察海岸与旧灯附近的线索。").ok,"free intent created")
	check(adapter.import_reply(assessment(adapter.request())).ok,"manual typed assessment validated")
	check(adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok,"authoritative single commit")
	return adapter
func prose_reply(adapter:RefCounted,text:String)->Dictionary:
	var req:Dictionary=adapter.engine.narration_request(adapter.last_action)
	return {"schema_version":"ai_gm_narration/v1","action_id":req.action_id,"state_version":req.state_version,"context_hash":req.context_hash,"narration":text}
func write_text(path:String,text:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
func historical_count(adapter:RefCounted)->int:
	var n:=0
	for entry in adapter.journal_entries():
		if entry.get("non_authoritative",false):n+=1;check(String(entry.title).begins_with("叙事记录 · 第") and not String(entry.title).contains("非权威"),"replayed prose uses natural heading while metadata marks display-only text")
	return n
func run()->void:
	var adapter:=committed_adapter();var id:String=adapter.last_action
	var authority:=C.bytes(adapter.engine.save_data())
	check(not adapter.record_narration("not-committed",PROSE).ok,"uncommitted/unknown action cannot be recorded")
	check(not adapter.record_narration(id,"x".repeat(Log.MAX_TEXT_BYTES+1)).ok,"oversize prose rejected without truncation")
	check(not adapter.record_narration(id,PROSE,"invented_source").ok,"only whitelisted display sources")
	check(adapter.record_narration(id,PROSE,"provider").ok,"committed provider prose recorded")
	check(adapter.record_narration(id,PROSE,"provider").already_recorded,"same response idempotent")
	check(adapter.record_narration(id,"new text must not retcon saved prose","manual").already_recorded and adapter.narration==PROSE,"different duplicate cannot rewrite historical prose")
	check(adapter.narration_entries().size()==1 and historical_count(adapter)==1,"exactly one display record per receipt")
	check(C.bytes(adapter.engine.save_data())==authority,"prose recording never changes state/RNG/receipts")
	check(not C.bytes(adapter.request()).contains("NARRATION_ONLY_MARKER"),"display log never enters model/assessment context")
	check(adapter.save_file(PATH).ok,"core and optional sidecar save")
	check(not FileAccess.get_file_as_string(PATH).contains("NARRATION_ONLY_MARKER"),"core authority save excludes optional prose")
	var sidecar:=PATH+".narration.json"
	var original:String=FileAccess.get_file_as_string(sidecar)
	var envelope:Dictionary=JSON.parse_string(original)
	check(envelope.records.size()==1 and envelope.records[0].receipt_hash==adapter.engine.save_data().receipts[id].receipt_hash,"sidecar binds exact committed receipt")
	for forbidden in ['"api_key"','"endpoint"','"Authorization"','"config"','"rng"','"patches"','"assessment"']:
		check(not original.contains(forbidden),"sidecar excludes "+forbidden)
	var loaded:=Coast.new()
	check(loaded.load_file(PATH).ok and loaded.narration==PROSE,"valid core+sidecar restores optional prose")
	check(C.bytes(loaded.engine.save_data())==authority and historical_count(loaded)==1,"restoration retains exact authority and one historical prose entry")
	check(loaded.load_file(PATH).ok and historical_count(loaded)==1,"repeated load does not duplicate display history")
	for failure in ["malformed","oversize","wrong_core","wrong_world","wrong_receipt","wrong_action","wrong_turn","altered_text","extra_patch"]:
		var bad:Dictionary=envelope.duplicate(true)
		match failure:
			"malformed":write_text(sidecar,"broken JSON")
			"oversize":write_text(sidecar," ".repeat(Log.MAX_FILE_BYTES+1))
			"wrong_core":bad.core_save_sha256="wrong";write_text(sidecar,C.bytes(bad))
			"wrong_world":bad.world_id="other_world";write_text(sidecar,C.bytes(bad))
			"wrong_receipt":bad.records[0].receipt_hash="wrong";write_text(sidecar,C.bytes(bad))
			"wrong_action":bad.records[0].action_id="unknown";write_text(sidecar,C.bytes(bad))
			"wrong_turn":bad.records[0].turn=9999;write_text(sidecar,C.bytes(bad))
			"altered_text":bad.records[0].narration="changed without matching text digest";write_text(sidecar,C.bytes(bad))
			"extra_patch":bad.records[0]["patches"]=[{"type":"flag_set"}];write_text(sidecar,C.bytes(bad))
		check(loaded.load_file(PATH).ok,"invalid optional prose never invalidates valid core: "+failure)
		check(loaded.narration_entries().is_empty() and C.bytes(loaded.engine.save_data())==authority,"invalid prose ignored without authoritative mutation: "+failure)
	var duplicate:Dictionary=envelope.duplicate(true);duplicate.records.append(duplicate.records[0].duplicate(true));write_text(sidecar,C.bytes(duplicate))
	var duplicate_load:Dictionary=loaded.load_file(PATH)
	check(duplicate_load.ok and historical_count(loaded)==1,"duplicate sidecar rows replay once")
	check(not duplicate_load.get("narration_warning","").is_empty(),"ignored optional rows are disclosed without failing valid core")
	DirAccess.remove_absolute(sidecar)
	check(loaded.load_file(PATH).ok and loaded.narration_entries().is_empty(),"old/missing sidecar is backward compatible")
	var manual:=committed_adapter();var manual_authority:=C.bytes(manual.engine.save_data())
	check(manual.import_reply(prose_reply(manual,"MANUAL_PROSE_MARKER：仅为补充描述。")).ok,"manual committed narration uses same log")
	check(manual.narration_entries().size()==1 and manual.narration_entries()[0].source=="manual","manual source remains explicitly tagged")
	check(manual.import_reply(prose_reply(manual,"MANUAL_PROSE_MARKER：仅为补充描述。")).already_recorded,"manual duplicate suppressed")
	check(C.bytes(manual.engine.save_data())==manual_authority,"manual prose never changes authority")
	check(manual.save_file(PATH).ok and loaded.load_file(PATH).ok and loaded.narration.contains("MANUAL_PROSE_MARKER"),"manual narration survives validated save/load")
	check(historical_count(loaded)==1,"manual restored history remains nonauthoritative")
	check(loaded.start_scene_framework_test().ok and loaded.narration_entries().is_empty(),"explicit fresh scene session clears old prose bookkeeping")
	var staged:=Coast.new()
	check(staged.begin_intent("观察海岸旧灯。").ok and staged.import_reply(assessment(staged.request())).ok and staged.roll_once().ok and staged.stage().ok,"manual staged narration setup")
	var staged_request:Dictionary=staged.engine.narration_request(staged.active_action)
	var staged_reply:Dictionary={"schema_version":"ai_gm_narration/v1","action_id":staged_request.action_id,"state_version":staged_request.state_version,"context_hash":staged_request.context_hash,"narration":"已暂存观察结果的非权威描述。"}
	check(staged.import_reply(staged_reply).ok and staged.narration_entries().is_empty(),"provisional manual prose cannot enter committed log early")
	check(staged.commit().ok and staged.narration_entries().size()==1,"manual staged prose records only after matching successful atomic commit")
	# Test the bounded record container separately, with synthetic receipt metadata.
	var archive:=ReceiptArchive.new();var bounded:Dictionary={}
	for n in range(Log.MAX_ENTRIES+2):
		var aid:="action_"+str(n);archive.data.receipts[aid]={"receipt_hash":aid.sha256_text(),"turn":n}
		Log.record(bounded,archive,aid,"display text "+str(n),"manual")
	check(bounded.size()==Log.MAX_ENTRIES and not bounded.has("action_0") and bounded.has("action_65"),"history retains bounded latest64 entries without altering receipts")
	for path in [PATH,sidecar,sidecar+".tmp"]:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	var result:Dictionary={"checks":checks,"failures":failures,"scope":"production authoritative core + display-only provider/manual sidecar; no network","max_records":Log.MAX_ENTRIES,"max_text_bytes":Log.MAX_TEXT_BYTES}
	var report:=FileAccess.open("res://artifacts/runtime_ai_20261003/narration_history_results.json",FileAccess.WRITE);report.store_string(JSON.stringify(result,"\t"));report.close()
	print("NARRATION HISTORY ",checks-failures.size(),"/",checks,"; DISPLAY ONLY; NO NETWORK")
	quit(0 if failures.is_empty() else 1)
