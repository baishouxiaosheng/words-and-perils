extends "res://view/runtime_ai/scoped_engine.gd"
## View/transport boundary for an already bounded public profile. No new
## authority, projection, saved identity or second neighborhood selection.
const PROFILE := "generated_v3_village_equipment/v1"
const PROJECTION_ID := "generated_v3_village_equipment_context/v1"
const WORLD_PREFIX := "generated_v3_village_equipment_v1_"
const PROFILE_BUDGET := 65536
var configured_budget: Variant
func _init(source:RefCounted, guard:Callable, budget_bytes:Variant=PROFILE_BUDGET)->void:
	configured_budget=budget_bytes
	var checked:=Budget.validate(budget_bytes)
	# Invalid configuration is still invalid; a larger valid connection limit
	# never enlarges this immutable profile's existing admission limit.
	super(source,guard,mini(int(budget_bytes),PROFILE_BUDGET) if checked.ok else budget_bytes)
static func recognizes(state:Dictionary)->bool:
	return preload("res://view/generated_v3_equipment/projection.gd").active(state)
static func _identity_valid(state:Dictionary)->bool:
	return preload("res://view/generated_v3_equipment/projection.gd").matching_identity(state)
func _admitted()->bool:
	if not permitted.call():
		last_error=C.fail("STALE_CONTEXT","当前冒险已改变，未发送或应用回复。");return false
	if not _identity_valid(engine.state_copy()):
		last_error=C.fail("RUNTIME_PROFILE","当前冒险的公开资料身份无效，未发送请求。");return false
	return true
func model_request(id:String)->Dictionary:
	if not _admitted():return {}
	var full:Dictionary=engine.model_request(id)
	if full.is_empty():return {}
	var context:Variant=full.get("context",{})
	if not context is Dictionary:
		last_error=C.fail("RUNTIME_PROFILE","公开请求格式无效，未发送。");return {}
	var facts:Variant=context.get("facts",{})
	var metadata:Variant=facts.get("generated_source",{}) if facts is Dictionary else {}
	if not C.safe(full) or full.get("schema_version")!="ai_gm_rebuilt/v1" or full.get("phase")!="assessment" or full.get("action_id")!=id or not metadata is Dictionary or metadata.get("profile")!=PROFILE or metadata.get("equipment_profile")!=PROFILE or metadata.get("projection_id")!=PROJECTION_ID or metadata.get("source_contract")!="generated_v3_source/v1" or full.get("context_hash")!=C.digest(full.get("context",{})):
		last_error=C.fail("RUNTIME_PROFILE","公开请求不是完整的当前村庄冒险资料，未发送。");return {}
	return _budget(full,full,id)
func narration_request(id:String)->Dictionary:
	if not _admitted():return {}
	return super.narration_request(id)
func _budget(full:Dictionary,scoped:Dictionary,key:String)->Dictionary:
	var result:Dictionary=super._budget(full,scoped,key)
	last_metrics["configured_budget_bytes"]=configured_budget
	last_metrics["profile_budget_bytes"]=PROFILE_BUDGET
	if result.is_empty() and last_error.get("code")=="CONTEXT_BUDGET" and Budget.validate(configured_budget).ok and int(configured_budget)>=PROFILE_BUDGET:
		last_error.errors=["村庄冒险的公开资料超过固定64 KiB上限；未发送、未裁剪。请缩短意图或取消，连接上限不能扩大此存档版本的范围。"]
	return result
func prepare_assessment(reply:Variant)->Dictionary:
	if not _admitted():return last_error.duplicate(true)
	if not C.safe(reply) or not valid_transport_strings(reply) or C.bytes(reply).to_utf8_buffer().size()>PROFILE_BUDGET:return C.fail("V3_REPLY_BUDGET","评估资料过长或格式无效，未应用。")
	if reply is Dictionary and reply.get("narration") is String and (reply.narration.to_utf8_buffer().size()>8192 or not valid_display_text(reply.narration)):return C.fail("NARRATION_TEXT","评估文字超出此版本范围，未应用。")
	return super.prepare_assessment(reply)
func validate_narration_reply(reply:Variant)->Dictionary:
	if not _admitted():return last_error.duplicate(true)
	var result:Dictionary=super.validate_narration_reply(reply)
	if result.ok and (str(result.get("narration","")).to_utf8_buffer().size()>8192 or not valid_display_text(str(result.get("narration","")))):return C.fail("NARRATION_TEXT","叙述包含无法保存的控制字符，未显示或记录。")
	return result
static func valid_display_text(value:String)->bool:
	for i in value.length():
		var code=value.unicode_at(i)
		if code<32 and code not in [9,10,13]:return false
	return true

static func valid_transport_strings(value:Variant)->bool:
	if value is String:return valid_display_text(value)
	if value is Array:
		for child in value:
			if not valid_transport_strings(child):return false
	elif value is Dictionary:
		for key in value:
			if not key is String or not valid_display_text(key) or not valid_transport_strings(value[key]):return false
	return true
