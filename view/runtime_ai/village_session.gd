extends RefCounted
## Display-only facade around the unchanged V19 adapter. Neither records nor
## sidecar files enter core save data, ModelView, rules or Source admission.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const NarrationLog=preload("res://view/runtime_ai/narration_log.gd")
const BoundedScope=preload("res://view/runtime_ai/bounded_profile_engine.gd")
var adapter:RefCounted
var _records:Dictionary={}
var _provisional:Dictionary={}
var log_status:="empty"
var engine:RefCounted:
	get:return adapter.engine if adapter!=null else null
var active_action:String:
	get:return adapter.active_action if adapter!=null else ""
var last_action:String:
	get:return adapter.last_action if adapter!=null else ""
var narration:String:
	get:return adapter.narration if adapter!=null else ""
	set(value):
		if adapter!=null:adapter.narration=value
func _init(value:RefCounted)->void:adapter=value
func phase()->String:return adapter.phase()
func record_narration(action_id:String,text:String,source:="provider")->Dictionary:
	if not BoundedScope.valid_display_text(text):return C.fail("NARRATION_TEXT","叙述包含无法保存的控制字符，未记录。")
	var result:Dictionary=NarrationLog.record(_records,engine,action_id,text,source)
	if result.ok and phase()=="idle" and action_id==last_action:narration=result.narration
	return result
func has_recorded_narration(action_id:String)->bool:
	return _records.has(action_id) and not engine.committed_receipt_hash(action_id).is_empty() and _records[action_id].receipt_hash==engine.committed_receipt_hash(action_id) and _records[action_id].world_id==engine.state_copy().world_id
func narration_entries()->Array:
	var data:Dictionary=engine.save_data();var valid:Dictionary={}
	for id in _records:
		if NarrationLog._valid(_records[id],data):valid[id]=_records[id]
	return NarrationLog.ordered(valid)
func import_narration(reply:Dictionary)->Dictionary:
	if not BoundedScope.valid_transport_strings(reply):return C.fail("NARRATION_TEXT","叙述包含无法保存的控制字符，未记录。")
	var text:String=str(reply.get("narration",""))
	if not BoundedScope.valid_display_text(text):return C.fail("NARRATION_TEXT","叙述包含无法保存的控制字符，未记录。")
	var result:Dictionary=adapter.import_reply(reply)
	if not result.ok:return result
	if phase()=="staged":
		_provisional={"action_id":active_action,"stage_hash":adapter.action_copy().stage_hash,"narration":result.narration}
		result["provisional_until_commit"]=true;return result
	var recorded:=record_narration(str(reply.action_id),str(result.narration),"manual")
	if not recorded.ok:return recorded
	result["narration"]=recorded.narration;result["already_recorded"]=recorded.already_recorded
	return result
func committed()->Dictionary:
	var result:Dictionary={"ok":true,"recorded":false}
	if not _provisional.is_empty() and phase()=="idle" and last_action==_provisional.action_id:
		var receipt:Dictionary=engine.save_data().receipts.get(last_action,{})
		if receipt.get("stage_hash")==_provisional.stage_hash:
			result=record_narration(last_action,_provisional.narration,"manual");result["recorded"]=result.ok
	_provisional.clear();return result
func save_sidecar(path:String)->Dictionary:return NarrationLog.save(path,_records,engine)
func load_sidecar(path:String)->Dictionary:
	var loaded:Dictionary=NarrationLog.load(path,engine)
	_records=loaded.records
	var unsafe:Array=[]
	for id in _records:
		if not BoundedScope.valid_transport_strings(_records[id]):unsafe.append(id)
	for id in unsafe:_records.erase(id)
	if not unsafe.is_empty():
		loaded["status"]="partially_ignored";loaded["ignored"]=int(loaded.get("ignored",0))+unsafe.size();loaded["warning"]="部分可选叙事含无效文字，已忽略；核心进度正常恢复。"
	_provisional.clear();log_status=loaded.status
	if phase()=="idle" and has_recorded_narration(last_action):narration=_records[last_action].narration
	return loaded
