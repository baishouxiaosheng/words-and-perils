extends RefCounted
## Explicit opt-in save envelope, leaving historical raw coast saves untouched.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content=preload("res://core/status_gameplay/content.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const SCHEMA:="coast_status_gameplay_save/v1"
const PATH:="user://coast_status_gameplay_v1.json"
const REQUEST_PATH:="user://coast_status_gameplay_request_v1.json"
const MAX_SAVE_BYTES:=32*1024*1024
static func make_envelope(engine:RefCounted) -> Dictionary:
 var data:Dictionary=engine.save_data()
 return {"schema_version":SCHEMA,"catalog_hash":Foundation.runtime().catalog_hash,"engine":data}
static func unwrap(value:Variant) -> Dictionary:
 if not C.safe(value) or not C.exact_fields(value,["schema_version","catalog_hash","engine"]) or not value.schema_version is String or value.schema_version!=SCHEMA or not value.catalog_hash is String or value.catalog_hash!=Foundation.runtime().catalog_hash or not value.engine is Dictionary or not value.engine.get("state") is Dictionary:return C.fail("STATUS_SAVE_VERSION","This is not a compatible explicit status-gameplay save; legacy saves are not reinterpreted")
 if not value.engine.get("rule_id") is String or not value.engine.rule_id in ["coast_release/v1","ai_gm_test_coast_release/v1"]:return C.fail("STATUS_SAVE_RULE","Status gameplay requires its fixed release calculation policy")
 if not Content.active(value.engine.state):return C.fail("STATUS_SAVE_VERSION","Versioned status save must retain its trusted ruleset")
 var checked:Dictionary=Content.validate(value.engine.state)
 if not checked.ok:return checked
 return {"ok":true,"engine":value.engine.duplicate(true)}
static func save_file(engine:RefCounted,path:String) -> Dictionary:
 if not Content.active(engine.state_copy()):return C.fail("STATUS_SAVE_VERSION","Only explicit status worlds use this save envelope")
 if FileAccess.file_exists(path):
  var prior:=FileAccess.open(path,FileAccess.READ)
  if prior==null:return C.fail("STATUS_SAVE_IO","Cannot inspect existing save")
  var prior_length:int=prior.get_length();prior.close()
  if prior_length>MAX_SAVE_BYTES:return C.fail("STATUS_SAVE_BUDGET","Existing file exceeds the declared read budget")
  var existing:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
  if not existing is Dictionary or not existing.get("schema_version") is String or existing.schema_version!=SCHEMA:return C.fail("STATUS_SAVE_PROTECTED","Existing legacy or unrelated file will not be overwritten")
 var bytes:String=C.bytes(make_envelope(engine))
 if bytes.to_utf8_buffer().size()>MAX_SAVE_BYTES:return C.fail("STATUS_SAVE_BUDGET","Status save exceeds its declared storage budget")
 var temp:=path+".tmp"
 var file:=FileAccess.open(temp,FileAccess.WRITE)
 if file==null:return C.fail("STATUS_SAVE_IO","Cannot open temporary save")
 file.store_string(bytes);file.flush()
 var write_error:Error=file.get_error()
 file.close()
 if write_error!=OK:return C.fail("STATUS_SAVE_IO","Temporary save write failed; original save was preserved")
 if DirAccess.rename_absolute(temp,path)!=OK:return C.fail("STATUS_SAVE_IO","Atomic save rename failed")
 return {"ok":true,"schema_version":SCHEMA,"path":path}
