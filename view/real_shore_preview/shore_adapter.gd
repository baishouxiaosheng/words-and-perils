extends RefCounted
## Independent, read-only visual cache admission. Source geometry is never rebuilt.
const Terrain := preload("res://view/recovered_terrain_loader.gd")
const Water := preload("res://view/recovered_terrain_water_loader.gd")
const MANIFEST := "res://artifacts/real_shore_preview_20261002/manifest.json"
const SCHEMA := "real-r24-shore-material-cache-0.1.0"
static func _read(path:String, maximum:int=4*1024*1024) -> Dictionary:
	if not FileAccess.file_exists(path):return Terrain.fail("Missing "+path)
	var f:=FileAccess.open(path,FileAccess.READ)
	if f==null or f.get_length()>maximum:return Terrain.fail("Read/byte budget "+path)
	var j:=JSON.new()
	if j.parse(f.get_as_text())!=OK:return Terrain.fail("JSON "+path)
	if not j.data is Dictionary:return Terrain.fail("Object expected "+path)
	return {"ok":true,"data":j.data}
static func _local(path:Variant) -> bool:
	return path is String and not path.contains("..") and not path.begins_with("/") and not path.contains(":")
static func load_scope(scope_name:String) -> Dictionary:
	var opened:=_read(MANIFEST)
	if not opened.ok:return opened
	var manifest:Dictionary=opened.data
	if manifest.get("schema")!=SCHEMA or not manifest.get("visual_only",false) or manifest.get("geometry_changed",true) or manifest.get("water_footprint_changed",true) or manifest.get("river_available",true) or manifest.get("zone_authority_loaded",true) or manifest.get("cover_generated",true):return Terrain.fail("Visual cache contract rejected")
	if not manifest.get("source") is Dictionary or not manifest.get("exporter") is Dictionary:return Terrain.fail("Cache identity missing")
	for key in ["mesh","water","receipt"]:
		var row:Variant=manifest.source.get(key,{})
		if not row is Dictionary or not _local(row.get("path")) or FileAccess.get_sha256("res://"+row.path)!=row.get("sha256"):return Terrain.fail("Source bytes rejected: "+key)
	if not _local(manifest.exporter.get("path")) or FileAccess.get_sha256("res://"+manifest.exporter.path)!=manifest.exporter.get("sha256"):return Terrain.fail("Exporter source mismatch")
	var accepted:=_read("res://"+manifest.source.receipt.path)
	if not accepted.ok:return accepted
	var receipt:Dictionary=accepted.data
	if receipt.get("status")!="PASS_FINAL_NEW_LAKE_PORTS_AUTHORITY" or not receipt.get("single_body_80_and_land_stage_dry_82_verified",false) or not receipt.get("finite_natural_spill_and_legal_root_flow_verified",false):return Terrain.fail("Frozen lake/port receipt not accepted")
	for key in ["mesh","water"]:
		var row:Dictionary=manifest.source[key]
		var entry:Variant=receipt.get("files",{}).get(row.path.get_file(),{})
		if not entry is Dictionary or entry.get("sha256")!=row.sha256 or entry.get("semantic_hash")!=manifest.source_semantic_hash.get(key):return Terrain.fail("Receipt binding rejected: "+key)
	var loaded:=Terrain.load_file("res://"+manifest.source.mesh.path)
	if not loaded.ok:return loaded
	if loaded.world.fixture or loaded.world.radius!=24 or loaded.world.seed!=12 or loaded.world.semantic_hash!=manifest.source_semantic_hash.mesh:return Terrain.fail("Scope requires actual frozen r24")
	var water_loaded:=Water.load_file("res://"+manifest.source.water.path,loaded.world)
	if not water_loaded.ok:return water_loaded
	if water_loaded.water.semantic_hash!=manifest.source_semantic_hash.water:return Terrain.fail("Water cache semantic binding rejected")
	var scope:Variant=manifest.get("scopes",{}).get(scope_name,{})
	if not scope is Dictionary or scope.is_empty():return Terrain.fail("Unknown shore scope")
	for key in ["texture","scope_data"]:
		if not scope.get(key) is Dictionary or not _local(scope[key].get("path")) or FileAccess.get_sha256("res://"+scope[key].path)!=scope[key].get("sha256"):return Terrain.fail("Scope bytes rejected "+key)
	var records:=_read("res://"+scope.scope_data.path,8*1024*1024)
	if not records.ok:return records
	var local:Dictionary=records.data
	if local.get("schema")!=SCHEMA or local.get("scope")!=scope_name or not local.get("source_faces") is Array or not local.get("source_footprint_indices") is Array:return Terrain.fail("Scope schema rejected")
	var seen:={}
	for row in local.source_faces:
		if not row is Dictionary or not Terrain.integer(row.get("index"),0,loaded.world.face_ids.size()-1):return Terrain.fail("Scope face index invalid")
		var fi:int=row.index
		if seen.has(fi) or row.get("id")!=loaded.world.face_ids[fi] or row.get("owner")!=loaded.world.face_owners[fi] or not row.get("vertices") is Array or row.vertices.size()!=3:return Terrain.fail("Original face identity/order lost")
		for j in range(3):
			if row.vertices[j]!=loaded.world.indices[fi*3+j]:return Terrain.fail("Original face vertex order changed")
		seen[fi]=true
	var bounds:Variant=scope.get("bounds_xz")
	if not bounds is Array or bounds.size()!=4:return Terrain.fail("Scope bounds missing")
	for v in bounds:
		if not Terrain.finite_number(v):return Terrain.fail("Scope bounds invalid")
	if bounds[2]<=bounds[0] or bounds[3]<=bounds[1]:return Terrain.fail("Scope bounds empty")
	for fi in range(loaded.world.face_ids.size()):
		var a:Vector3=loaded.world.positions[loaded.world.indices[fi*3]]
		var b:Vector3=loaded.world.positions[loaded.world.indices[fi*3+1]]
		var c:Vector3=loaded.world.positions[loaded.world.indices[fi*3+2]]
		var intersects:bool=minf(a.x,minf(b.x,c.x))<=bounds[2] and maxf(a.x,maxf(b.x,c.x))>=bounds[0] and minf(a.z,minf(b.z,c.z))<=bounds[3] and maxf(a.z,maxf(b.z,c.z))>=bounds[1]
		if intersects!=seen.has(fi):return Terrain.fail("Local original-face coverage incomplete or extra")
	var footprint_seen:={}
	for idx in local.source_footprint_indices:
		if not Terrain.integer(idx,0,water_loaded.water.footprints.size()-1) or not seen.has(water_loaded.water.footprints[int(idx)].face):return Terrain.fail("Footprint has no local original face")
		if footprint_seen.has(int(idx)):return Terrain.fail("Duplicate local footprint")
		footprint_seen[int(idx)]=true
	for idx in range(water_loaded.water.footprints.size()):
		var poly:PackedVector2Array=water_loaded.water.footprints[idx].polygon
		var mn:=poly[0];var mx:=poly[0]
		for p in poly:
			mn.x=minf(mn.x,p.x);mn.y=minf(mn.y,p.y);mx.x=maxf(mx.x,p.x);mx.y=maxf(mx.y,p.y)
		var intersects:bool=mn.x<=bounds[2] and mx.x>=bounds[0] and mn.y<=bounds[3] and mx.y>=bounds[1]
		if intersects!=footprint_seen.has(idx):return Terrain.fail("Source-footprint coverage incomplete or extra")
	return {"ok":true,"world":loaded.world,"water":water_loaded.water,"manifest":manifest,"scope":scope,"local":local,"manifest_sha256":FileAccess.get_sha256(MANIFEST)}
