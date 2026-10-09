extends RefCounted
## Optional display-only sidecar. Never supplied to engine.load_data, ModelView,
## calculators, resolvers, patches, receipts, RNG, or the assessment provider.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const SCHEMA := "display_narration_log/v1"
const MAX_ENTRIES := 64
const MAX_TEXT_BYTES := 8192
const MAX_FILE_BYTES := 600000
const FIELDS := ["action_id","receipt_hash","world_id","bundle_id","turn","source","narration","text_sha256","non_authoritative"]
static func _bundle(data: Dictionary) -> String: return String(data.state.get("generated_world",{}).get("bundle_id",""))
static func _valid(row: Variant, data: Dictionary) -> bool:
	if not C.exact_fields(row,FIELDS) or not C.safe(row): return false
	if not row.action_id is String or not data.receipts.has(row.action_id) or not row.narration is String: return false
	if row.narration.strip_edges().is_empty() or row.narration.to_utf8_buffer().size()>MAX_TEXT_BYTES: return false
	var receipt: Dictionary=data.receipts[row.action_id]
	return row.non_authoritative==true and row.world_id==data.state.world_id and row.bundle_id==_bundle(data) and row.receipt_hash==receipt.receipt_hash and C.integer(row.turn) and row.turn==receipt.turn and row.source in ["provider","manual"] and row.text_sha256==row.narration.sha256_text()
static func ordered(records: Dictionary) -> Array:
	var rows:Array=records.values().duplicate(true)
	rows.sort_custom(func(a,b): return String(a.action_id)<String(b.action_id) if int(a.turn)==int(b.turn) else int(a.turn)<int(b.turn))
	return rows
static func record(records: Dictionary, engine: RefCounted, action_id: String, text: String, source: String) -> Dictionary:
	if not source in ["provider","manual"] or text.strip_edges().is_empty() or text.to_utf8_buffer().size()>MAX_TEXT_BYTES: return C.fail("NARRATION_LOG_TEXT","可选叙事为空、来源无效或超过8 KiB；未写入历史。")
	var data:Dictionary=engine.save_data()
	if not data.receipts.has(action_id): return C.fail("NARRATION_NOT_COMMITTED","只有已提交回执的可选叙事可进入历史。")
	if records.has(action_id) and _valid(records[action_id],data):
		return {"ok":true,"already_recorded":true,"narration":records[action_id].narration}
	var receipt:Dictionary=data.receipts[action_id]
	var row:Dictionary={"action_id":action_id,"receipt_hash":receipt.receipt_hash,"world_id":data.state.world_id,"bundle_id":_bundle(data),"turn":receipt.turn,"source":source,"narration":text,"text_sha256":text.sha256_text(),"non_authoritative":true}
	records[action_id]=row
	var rows:=ordered(records)
	while rows.size()>MAX_ENTRIES:
		records.erase(rows.pop_front().action_id)
	return {"ok":true,"already_recorded":false,"narration":text}
static func save(core_path: String, records: Dictionary, engine: RefCounted) -> Dictionary:
	var data:Dictionary=engine.save_data();var rows:Array=[]
	for row in ordered(records):
		if _valid(row,data): rows.append(row)
	while rows.size()>MAX_ENTRIES: rows.pop_front()
	var envelope:Dictionary={"schema_version":SCHEMA,"core_save_sha256":FileAccess.get_file_as_string(core_path).sha256_text(),"world_id":data.state.world_id,"bundle_id":_bundle(data),"records":rows}
	var content:=C.bytes(envelope)
	if content.to_utf8_buffer().size()>MAX_FILE_BYTES: return C.fail("NARRATION_LOG_SIZE","可选叙事历史过大；核心进度已保存。")
	var path:=core_path+".narration.json";var temp:=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return C.fail("NARRATION_LOG_WRITE","无法写入可选叙事历史；核心进度已保存。")
	file.store_string(content);file.flush();file.close()
	if DirAccess.rename_absolute(temp,path)!=OK:return C.fail("NARRATION_LOG_WRITE","可选叙事历史原子替换失败；核心进度已保存。")
	return {"ok":true,"entries":rows.size()}
static func load(core_path: String, engine: RefCounted) -> Dictionary:
	var path:=core_path+".narration.json"
	if not FileAccess.file_exists(path):return {"ok":true,"records":{},"status":"missing"}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return _ignored("unreadable")
	if file.get_length()>MAX_FILE_BYTES:file.close();return _ignored("oversize")
	var content:=file.get_as_text();file.close()
	var parser:=JSON.new()
	if parser.parse(content)!=OK:return _ignored("malformed")
	var value:Variant=parser.data
	var data:Dictionary=engine.save_data()
	if not C.exact_fields(value,["schema_version","core_save_sha256","world_id","bundle_id","records"]) or not C.safe(value):return _ignored("malformed")
	if value.schema_version!=SCHEMA or value.core_save_sha256!=FileAccess.get_file_as_string(core_path).sha256_text() or value.world_id!=data.state.world_id or value.bundle_id!=_bundle(data) or not value.records is Array or value.records.size()>MAX_ENTRIES:return _ignored("binding_or_size")
	var records:Dictionary={};var ignored:=0
	for row in value.records:
		if not _valid(row,data) or records.has(row.action_id):ignored+=1;continue
		records[row.action_id]=row.duplicate(true)
	return {"ok":true,"records":records,"status":"loaded" if ignored==0 else "partially_ignored","ignored":ignored,"warning":"部分可选叙事历史无效，已忽略；核心进度正常恢复。" if ignored>0 else ""}
static func _ignored(reason: String) -> Dictionary:
	return {"ok":true,"records":{},"status":"ignored_"+reason,"warning":"可选叙事历史无效，已忽略；已验证的核心进度正常恢复。"}
