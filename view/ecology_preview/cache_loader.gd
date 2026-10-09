extends RefCounted
const Terrain := preload("res://view/recovered_terrain_loader.gd")
const Receipts:=preload("res://view/ecology_preview/cache_receipts.gd")
const VERSION := "ecology-preview-render-cache-0.1.0"
static func load_file(path: String, world: Dictionary, water: Dictionary, zone_path: String) -> Dictionary:
	if world.is_empty() or water.is_empty():return Terrain.fail("Both terrain and water identity must load first")
	if not FileAccess.file_exists(path): return Terrain.fail("Render cache not found")
	var actual_sha:=FileAccess.get_sha256(path)
	if not Receipts.CACHE_RECEIPTS.has(actual_sha):return Terrain.fail("Unknown or modified immutable render snapshot; independent receipt required")
	var receipt:Dictionary=Receipts.CACHE_RECEIPTS[actual_sha]
	if receipt.mesh_sha256!=world.file_sha256 or receipt.water_sha256!=water.file_sha256 or receipt.zone_sha256!=FileAccess.get_sha256(zone_path):return Terrain.fail("Render snapshot receipt source mismatch")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 64 * 1024 * 1024: return Terrain.fail("Cache resource budget")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return Terrain.fail("Malformed cache")
	file.close()
	var data: Variant = json.data
	if not data is Dictionary or data.get("schema_version") != VERSION: return Terrain.fail("Cache schema mismatch")
	if data.get("fixture") != true or not world.fixture: return Terrain.fail("Whole zones are not independently released; fixture only")
	if data.get("mesh_semantic_hash") != world.semantic_hash or data.get("water_semantic_hash") != water.semantic_hash: return Terrain.fail("Semantic source mismatch")
	if data.get("identity", {}).get("mesh", {}).get("sha256") != world.file_sha256 or data.identity.get("drainage", {}).get("sha256") != water.file_sha256: return Terrain.fail("Stored mesh/water byte mismatch")
	if data.get("zone_sha256") != FileAccess.get_sha256(zone_path): return Terrain.fail("Stored zone byte mismatch")
	var required := ["mesh","drainage","climate","dry_support","classification","river_reserve"]
	if not data.get("identity") is Dictionary or data.identity.size()!=required.size():return Terrain.fail("Fixture identity requires six fixed source keys")
	for name in required:
		if not data.identity.has(name):return Terrain.fail("Missing fixed source: "+name)
	if not data.get("zone_schema") in ["terrain-zones-rebuilt-candidate-0.1.0","terrain-zones-rebuilt-candidate-0.1.1"] or data.get("actual_world_art_acceptance")!="NOT_RUN":return Terrain.fail("Unsupported zone/acceptance scope")
	if not data.get("config_canonical_json") is String or data.config_canonical_json.sha256_text()!=data.get("config_sha256"):return Terrain.fail("Config byte binding mismatch")
	var source_file:=FileAccess.open(zone_path,FileAccess.READ)
	if source_file==null or source_file.get_length()>8*1024*1024:return Terrain.fail("Zone file budget")
	var source_json:=JSON.new()
	if source_json.parse(source_file.get_as_text())!=OK:return Terrain.fail("Malformed source zone")
	source_file.close()
	var source:Variant=source_json.data
	if not source is Dictionary or source.get("schema_version")!=data.zone_schema or source.get("identity",{}).get("stage")!="SMALL_FIXTURE":return Terrain.fail("Source schema/stage mismatch")
	var cfg:Variant=JSON.parse_string(data.config_canonical_json)
	if not cfg is Dictionary or cfg!=source.get("config") or data.get("palette_linear_rgb")!=source.get("palette_linear_rgb"):return Terrain.fail("Cache config/palette differs from exact source zone")
	var dependency_paths := {"render_geometry.py":"res://tests/ecology_preview/dependencies/render_geometry.py","export_preview.py":"res://tests/ecology_preview/export_preview.py","v9_tree_recipe_hex_board.gd":"res://view/hex_board.gd"}
	if not data.get("source_dependencies") is Dictionary or data.source_dependencies.size()!=dependency_paths.size():return Terrain.fail("Source dependency identity missing")
	for name in dependency_paths:
		if data.source_dependencies.get(name)!=FileAccess.get_sha256(dependency_paths[name]):return Terrain.fail("Source dependency changed: "+name)
	for name in data.identity:
		var row: Variant = data.identity[name]
		if not row is Dictionary or not row.get("path") is String or not Terrain.hash_string(row.get("sha256")): return Terrain.fail("Malformed source identity")
		if not row.path.begins_with("res://artifacts/ecology_preview_20261002/") or row.path.contains("..") or not row.path.ends_with(".json"):return Terrain.fail("Fixture source path outside admitted preview artifacts")
		if source.get("identity",{}).get("files",{}).get(name,{}).get("sha256")!=row.sha256:return Terrain.fail("Identity differs from source zone: "+name)
		if not FileAccess.file_exists(row.path) or FileAccess.get_sha256(row.path) != row.sha256: return Terrain.fail("Source bytes changed: " + name)
	if not data.get("patches") is Array or data.patches.size() > 400000 or not data.get("canopies") is Array or data.canopies.size() > 100000: return Terrain.fail("Render budget exceeded")
	for p in data.patches:
		if not p is Dictionary or not Terrain.integer(p.get("face"), 0, world.face_ids.size() - 1) or not p.get("bary") is Array or p.bary.size() < 3 or p.bary.size() > 24: return Terrain.fail("Bad face/bary patch")
		if not p.get("detail") is Array or p.detail.size()!=2:return Terrain.fail("Bad local detail")
		for v in p.detail:
			if not Terrain.finite_number(v,1.0) or v<0:return Terrain.fail("Nonfinite local detail")
		if p.detail[0]+p.detail[1]>1.00001:return Terrain.fail("Local detail sum exceeded")
		if not p.get("linear_colors") is Array or p.linear_colors.size() != p.bary.size() or not p.get("detail") is Array or p.detail.size() != 2: return Terrain.fail("Bad color/detail patch")
		for bc in p.bary:
			if not bc is Array or bc.size() != 3: return Terrain.fail("Bad bary shape")
			var total := 0.0
			for n in bc:
				if not Terrain.finite_number(n, 1.00001) or n < -0.00001: return Terrain.fail("Bary outside sourceface")
				total += float(n)
			if absf(total - 1.0) > 0.00001: return Terrain.fail("Bary sum mismatch")
		for col in p.linear_colors:
			if not col is Array or col.size() != 3: return Terrain.fail("Bad linear color")
			for value in col:
				if not Terrain.finite_number(value, 1.0) or value < 0: return Terrain.fail("Invalid linear color")
	for p in data.canopies:
		if not p is Dictionary or not p.get("kind") in ["temperate", "tropical", "sapling", "shrub", "tuft", "reed"]: return Terrain.fail("Bad decorative cover kind")
		if not Terrain.integer(p.get("face"),0,world.face_ids.size()-1) or not world.cells.has(p.get("owner", "")) or not data.palette_linear_rgb.has(p.get("ecology", "")): return Terrain.fail("Invalid cover source face/owner/ecology")
		if not Terrain.finite_number(p.get("yaw"),7.0) or not Terrain.finite_number(p.get("color_factor"),2.0) or p.color_factor <= 0: return Terrain.fail("Invalid cover orientation/color")
		if not p.get("barycentric") is Array or p.barycentric.size()!=3: return Terrain.fail("Invalid cover bary shape")
		var sum_bc:=0.0
		for n in p.barycentric:
			if not Terrain.finite_number(n,1.00001) or n < -0.00001: return Terrain.fail("Cover bary outside sourceface")
			sum_bc+=float(n)
		if absf(sum_bc-1.0)>0.00001:return Terrain.fail("Cover bary sum mismatch")
		if not p.get("position") is Array or p.position.size() != 3 or not Terrain.finite_number(p.get("radius"), 1.0) or p.radius <= 0 or not Terrain.finite_number(p.get("height"), 2.0) or p.height <= 0: return Terrain.fail("Bad decorative transform")
		for value in p.position:
			if not Terrain.finite_number(value): return Terrain.fail("Nonfinite cover position")
		var expected:=Vector3.ZERO
		for j in range(3):expected+=world.positions[world.indices[int(p.face)*3+j]]*float(p.barycentric[j])
		if expected.distance_to(Vector3(p.position[0],p.position[1],p.position[2]))>0.00001:return Terrain.fail("Cover transform is not original-face PL anchor")
		if not p.get("crown_xz") is Array or p.crown_xz.size()!=7:return Terrain.fail("Cover crown shape")
		for j in range(7):
			var xy:Variant=p.crown_xz[j]
			if not xy is Array or xy.size()!=2 or not Terrain.finite_number(xy[0]) or not Terrain.finite_number(xy[1]):return Terrain.fail("Invalid crown point")
			var angle:float=float(p.yaw)+TAU*j/7.0
			var actual:=Vector2(float(p.position[0])+float(p.radius)*cos(angle),float(p.position[2])+float(p.radius)*sin(angle))
			if actual.distance_to(Vector2(xy[0],xy[1]))>0.00001:return Terrain.fail("Crown measurement/mesh transform mismatch")
	data.file_sha256 = FileAccess.get_sha256(path)
	return {"ok": true, "cache": data}
