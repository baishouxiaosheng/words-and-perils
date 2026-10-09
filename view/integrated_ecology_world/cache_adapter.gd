extends RefCounted
## New diagnostic adapter. Never calls or patches the old fixture allowlist.
const ROOT := "res://artifacts/integrated_ecology_world_20261002/cache/"
const SCHEMA := "integrated-real-ecology-render-cache-0.1.0"
static func load_cache() -> Dictionary:
	var path := ROOT + "manifest.json"
	if not FileAccess.file_exists(path): return {"ok":false,"error":"离线cache尚未生成"}
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:return {"ok":false,"error":"cache manifest格式无效"}
	var m:Dictionary=parser.data
	if not m.has("chunks") or not m.has("files"):return {"ok":false,"error":"缺少chunk/files"}
	if not str(m.get("status", "")).contains("DIAGNOSTIC"):return {"ok":false,"error":"仅允许显式DIAGNOSTIC缓存；科学终态不由视图升级"}
	# Minimum source identity: exact requested mesh/water and zone candidate bytes.
	# This is diagnostic binding, never scientific approval or a fixture whitelist.
	var source:Dictionary=m.get("source_identity",{})
	for role in ["mesh","drainage","ecology_pending"]:
		if not source.has(role):return {"ok":false,"error":"source绑定缺失："+role}
	for role in source:
		var input:Dictionary=source[role];var input_path:String=input.get("path","")
		if input_path.contains("..") or input_path.is_empty():return {"ok":false,"error":"source路径无效"}
		if not input_path.begins_with("/"):input_path="res://"+input_path
		if not FileAccess.file_exists(input_path) or FileAccess.get_sha256(input_path)!=input.get("sha256",""):return {"ok":false,"error":"source字节不匹配："+role}
	# Cache is a derived display. Verify its frozen small files once, not each frame.
	for name in m.files:
		if not safe_name(name):return {"ok":false,"error":"非cache本地文件"}
		var row:Dictionary=m.files[name]
		if not FileAccess.file_exists(ROOT+name) or FileAccess.get_sha256(ROOT+name)!=row.sha256:return {"ok":false,"error":"cache字节不匹配："+name}
	return {"ok":true,"manifest":m,"manifest_sha256":FileAccess.get_sha256(path)}
static func safe_name(name:String)->bool:return not name.contains("/") and not name.contains("..") and not name.is_empty()
static func bytes(m:Dictionary,name:String)->PackedByteArray:
	if not safe_name(name) or not m.files.has(name):return PackedByteArray()
	var row:Dictionary=m.files[name];var f:=FileAccess.open(ROOT+name,FileAccess.READ)
	if f==null:return PackedByteArray()
	var raw:=f.get_buffer(f.get_length());f.close()
	if name.ends_with(".gz"):return raw.decompress(int(row.decoded_bytes),FileAccess.COMPRESSION_GZIP)
	return raw
static func read_json(m:Dictionary,name:String)->Variant:
	var parser:=JSON.new()
	if parser.parse(bytes(m,name).get_string_from_utf8())!=OK:return null
	return parser.data
