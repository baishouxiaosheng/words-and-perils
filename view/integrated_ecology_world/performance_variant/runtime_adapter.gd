extends RefCounted
## Shipping-only cache reader: hashes the frozen derived cache and receipt.
## Full scientific sources are required by the authoring adapter, not this runtime.
const ROOT:="res://artifacts/integrated_ecology_world_20261002/cache/"
const BASELINE_SHA:="8616eb10c32f38899120b89417546e9befe675a4b3e2f6dde2b088755024e325"
const Receipt:=preload("res://view/integrated_ecology_world/performance_variant/source_receipt.gd")
static func load_cache()->Dictionary:
	var path:=ROOT+"manifest.json"
	if FileAccess.get_sha256(path)!=BASELINE_SHA:return {"ok":false,"error":"冻结runtime manifest改变"}
	var p:=JSON.new()
	if p.parse(FileAccess.get_file_as_string(path))!=OK or not p.data is Dictionary:return {"ok":false,"error":"runtime manifest无效"}
	var m:Dictionary=p.data
	var receipt:=Receipt.load_receipt(m)
	if not receipt.get("verified",false):return {"ok":false,"error":"有限源receipt未验证："+str(receipt.get("reason",""))}
	for name in m.files:
		if name.is_empty() or name.contains("/") or name.contains(".."):return {"ok":false,"error":"非本地缓存路径"}
		if FileAccess.get_sha256(ROOT+name)!=str(m.files[name].sha256):return {"ok":false,"error":"runtime缓存sha不匹配："+name}
	return {"ok":true,"manifest":m,"manifest_sha256":BASELINE_SHA,"source_validation_mode":"FROZEN_DERIVED_CACHE_AND_PREEXISTING_LIMITED_RECEIPT","source_scientific_files_reloaded_at_runtime":false,"source_receipt":receipt}
