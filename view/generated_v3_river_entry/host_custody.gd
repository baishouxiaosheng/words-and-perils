extends RefCounted
## Read-only custody for the two existing adapter save capabilities.
## Never calls save_file/load_file or serializes a Node/provider/credential.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const COAST_ADAPTER="res://view/playable_build/adapter.gd"

static func _method_returns(object: Object, method_name: String, return_type: int)->bool:
	if object==null:return false
	for method in object.get_method_list():
		if method.name==method_name:
			return method.get("args",[]).is_empty() and method.get("return",{}).get("type",TYPE_NIL)==return_type
	return false

static func _is_coast_adapter(host: RefCounted)->bool:
	var script: Script=host.get_script()
	while script!=null:
		if script.resource_path==COAST_ADAPTER:return true
		script=script.get_base_script()
	return false

static func capture(host: RefCounted)->Dictionary:
	if host==null or not _method_returns(host,"phase",TYPE_STRING) or not _method_returns(host,"state_copy",TYPE_DICTIONARY):
		return C.fail("RIVER_HOST_CAPABILITY","原旅程缺少明确的只读状态接口，未打开实验。")
	var kind: String
	var saved: Variant
	var presentation: Dictionary={"phase":host.phase()}
	if _is_coast_adapter(host):
		# Coast's existing save_file delegates to this exact engine payload,
		# with its narration records written separately by NarrationLog.
		var authority: Variant=host.get("engine")
		if not authority is RefCounted or not _method_returns(authority,"save_data",TYPE_DICTIONARY):
			return C.fail("RIVER_HOST_CAPABILITY","海岸权威保存接口不可验证，未打开实验。")
		kind="coast_engine_and_narration/v1"
		saved=authority.save_data()
		for field in ["active_action","last_action","narration","last_feedback","narration_log_status"]:
			var value: Variant=host.get(field)
			if not value is String:return C.fail("RIVER_HOST_CAPABILITY","海岸显示状态类型不能验证，未打开实验。")
			presentation[field]=value
		for field in ["_narration_records","_provisional_narration"]:
			var value: Variant=host.get(field)
			if not value is Dictionary:return C.fail("RIVER_HOST_CAPABILITY","海岸叙事记录类型不能验证，未打开实验。")
			presentation[field]=value.duplicate(true)
	else:
		if not _method_returns(host,"save_data",TYPE_DICTIONARY):
			return C.fail("RIVER_HOST_CAPABILITY","当前旅程没有受支持的完整保存读取接口，未打开实验。")
		kind="adapter_save_data/v1"
		saved=host.save_data()
	if not saved is Dictionary or saved.is_empty() or not C.safe(saved) or not C.safe(presentation):
		return C.fail("RIVER_HOST_SAVE","原旅程完整保存不能验证，未打开实验。")
	return {"ok":true,"kind":kind,"snapshot":{"capability":kind,"saved":saved,"presentation":presentation}}
