extends RefCounted
const ROOT:="res://artifacts/integrated_ecology_world_20261002/performance_variant/compact66_cache/"
const BASELINE_ROOT:="res://artifacts/integrated_ecology_world_20261002/cache/"
const BASELINE_SHA:="8616eb10c32f38899120b89417546e9befe675a4b3e2f6dde2b088755024e325"
const MANIFEST_SHA:="0d36b4646ad91d4b0fd494c7f8f377cd54fc45e37810eb56220f82608afa53d4"
static func load_compact()->Dictionary:
	var path:=ROOT+"manifest.json"
	if FileAccess.get_sha256(path)!=MANIFEST_SHA:return {"ok":false,"error":"compact66 manifest字节改变"}
	if not FileAccess.file_exists(path):return {"ok":false,"error":"compact缓存尚未完成"}
	if FileAccess.get_sha256(BASELINE_ROOT+"manifest.json")!=BASELINE_SHA:return {"ok":false,"error":"冻结checkpoint01改变"}
	var p:=JSON.new();if p.parse(FileAccess.get_file_as_string(path))!=OK or not p.data is Dictionary:return {"ok":false,"error":"compact manifest格式"}
	var m:Dictionary=p.data
	if not m.has("chunks") or not m.has("files"):return {"ok":false,"error":"compact chunks/files缺失"}
	for name in m.files:
		if name.contains("/") or name.contains("..") or name.is_empty():return {"ok":false,"error":"非本地缓存名"}
		var row:Dictionary=m.files[name];var root_:String=BASELINE_ROOT if row.get("storage","")=="baseline_cache" else ROOT
		if FileAccess.get_sha256(root_+name)!=row.sha256:return {"ok":false,"error":"compact缓存字节改变 "+name}
	return {"ok":true,"manifest":m,"manifest_sha256":FileAccess.get_sha256(path)}
static func bytes(m:Dictionary,name:String)->PackedByteArray:
	if not m.files.has(name):return PackedByteArray()
	var row:Dictionary=m.files[name];var root_:String=BASELINE_ROOT if row.get("storage","")=="baseline_cache" else ROOT;var f:=FileAccess.open(root_+name,FileAccess.READ)
	if f==null:return PackedByteArray()
	var raw:=f.get_buffer(f.get_length());f.close();return raw.decompress(int(row.decoded_bytes),FileAccess.COMPRESSION_GZIP) if name.ends_with(".gz") else raw
