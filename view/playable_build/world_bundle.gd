extends RefCounted
## Sole active playable source authority. Hash failures never fall back to old caches.
const PATH := "res://artifacts/world_bundle_20261002/manifest.json"
const SCHEMA := "fogbank-active-world-bundle/v1"
static var cache: Dictionary = {}
static var accepted_manifest_sha := ""
static var last_error := ""
static var documents: Dictionary = {}
static func reset() -> void:
	cache.clear(); documents.clear(); accepted_manifest_sha=""; last_error=""
static func _reject(message:String)->bool:
	reset(); last_error=message; return false
static func load_bundle(path:String=PATH)->bool:
	reset()
	if not FileAccess.file_exists(path):return _reject("Active world bundle is missing")
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("schema")!=SCHEMA or data.get("source_family")!="natural-shared-terrain-shore-v03":return _reject("Unknown world bundle/schema")
	if not str(data.get("bundle_id","")).begins_with("natural-shore-v03-"):return _reject("Unknown source bundle identity")
	if not data.get("runtime") is Dictionary or not data.get("source_identity") is Dictionary:return _reject("Incomplete source bundle")
	for required in ["render_manifest","source_topology","catalog","navigation","physical_water","retained_river_query","retained_river_manifest","mountain_manifest","dependency_closure"]:
		if not data.runtime.has(required):return _reject("Missing bundle contract: "+required)
	for name_ in data.runtime:
		var entry:Dictionary=data.runtime.get(name_,{})
		if not str(entry.get("path","")).begins_with("res://artifacts/") or str(entry.get("path","")).contains("..") or not FileAccess.file_exists(str(entry.get("path",""))):return _reject("Bundle member missing: "+name_)
		if FileAccess.get_sha256(entry.path)!=entry.get("sha256",""):return _reject("Bundle member SHA mismatch: "+name_)
		if name_ in ["render_manifest","catalog","navigation","physical_water","mountain_manifest","dependency_closure"]:
			var item:Variant=JSON.parse_string(FileAccess.get_file_as_string(entry.path))
			if not item is Dictionary:return _reject("Invalid bundle member JSON: "+name_)
			documents[name_]=item
	var source:Dictionary=data.source_identity
	var render:Dictionary=documents.render_manifest
	if render.get("source_mesh_sha256")!=source.get("mesh_sha256") or render.get("source_drainage_sha256")!=source.get("drainage_sha256") or render.get("dry_support_sha256")!=source.get("dry_support_sha256"):return _reject("Render/source identity mismatch")
	if data.runtime.render_manifest.sha256!=source.get("render_manifest_sha256") or data.runtime.retained_river_query.sha256!=source.get("retained_river_query_sha256"):return _reject("Render/river dependency mismatch")
	if render.get("files",{}).get("source_topology_v03.json.gz",{}).get("sha256")!=data.runtime.source_topology.sha256:return _reject("Source topology mismatch")
	for name_ in ["catalog","navigation","physical_water"]:
		var item:Dictionary=documents[name_]
		if item.get("bundle_id")!=data.bundle_id or item.get("source_identity")!=source:return _reject("Mixed source bundle: "+name_)
	if documents.catalog.get("schema")!="active-world-playable-catalog/v2" or documents.navigation.get("schema")!="active-world-dry-anchor-navigation/v2" or documents.physical_water.get("schema")!="active-world-physical-water/v1":return _reject("Unknown derived cache schema")
	if documents.navigation.get("catalog_sha256")!=data.runtime.catalog.sha256 or documents.navigation.get("physical_water_sha256")!=data.runtime.physical_water.sha256:return _reject("Navigation dependency mismatch")
	var mountain:Dictionary=documents.mountain_manifest
	if mountain.get("new_source_mesh_sha256")!=source.mesh_sha256 or mountain.get("new_source_drainage_sha256")!=source.drainage_sha256 or mountain.get("new_source_dry_support_sha256")!=source.dry_support_sha256:return _reject("Mountain source mismatch")
	var closure:Dictionary=documents.dependency_closure
	if closure.get("schema")!="fogbank-runtime-dependency-closure/v1":return _reject("Unknown runtime dependency closure")
	for entry in closure.get("files",[]):
		if not entry.get("runtime_required",true):continue
		var member_path:String=str(entry.get("path",""))
		if not member_path.begins_with("res://artifacts/") or member_path.contains("..") or not FileAccess.file_exists(member_path):return _reject("Missing/invalid runtime dependency: "+member_path)
		if FileAccess.get_sha256(member_path)!=entry.get("sha256",""):return _reject("Runtime dependency SHA mismatch: "+member_path)
	cache=data; accepted_manifest_sha=FileAccess.get_sha256(path)
	return true
static func ready()->bool:
	if cache.is_empty():return load_bundle()
	if FileAccess.get_sha256(PATH)!=accepted_manifest_sha:return _reject("Active world changed after load; restart required")
	return true
static func manifest()->Dictionary:
	return cache if ready() else {}
static func document(name_:String)->Dictionary:
	return documents.get(name_,{}) if ready() else {}
static func bundle_id()->String:
	return str(cache.get("bundle_id","")) if ready() else ""
static func catalog_sha256()->String:
	return str(cache.runtime.catalog.sha256) if ready() else ""
static func source_matches(mesh_sha:String,drainage_sha:String,render_sha:String)->bool:
	if not ready():return false
	return cache.source_identity.mesh_sha256==mesh_sha and cache.source_identity.drainage_sha256==drainage_sha and cache.source_identity.render_manifest_sha256==render_sha
