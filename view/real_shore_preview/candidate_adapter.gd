extends RefCounted
## Local diagnostic reader only. Never writes or re-signs frozen accepted data.
const Terrain:=preload("res://view/recovered_terrain_loader.gd")
const Water:=preload("res://view/recovered_terrain_water_loader.gd")
const PATH:="res://artifacts/natural_coast_rebuilt_20261002/candidate_display.json"
static func load_candidate(frozen:Dictionary)->Dictionary:
	if frozen.scope.label.find("ocean:")<0:return Terrain.fail("Candidate is ocean-local only")
	if not FileAccess.file_exists(PATH):return Terrain.fail("Local candidate absent")
	var file:=FileAccess.open(PATH,FileAccess.READ)
	if file==null or file.get_length()>8*1024*1024:return Terrain.fail("Candidate byte/read budget")
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return Terrain.fail("Candidate JSON")
	var raw:Dictionary=parser.data
	if raw.get("schema")!="natural-coast-local-pl-candidate-0.1.0" or not raw.get("diagnostic_only",false) or raw.get("production_compatible",true) or raw.get("upstream_acceptance_inherited",true) or raw.get("full_science_status")!="NOT_RUN_NEW_DRAINAGE_CLIMATE_ZONES":return Terrain.fail("Candidate must remain diagnostic")
	for k in ["mesh","water","receipt"]:
		if raw.get("input",{}).get(k,{}).get("sha256")!=frozen.manifest.source[k].sha256:return Terrain.fail("Candidate source binding: "+k)
	if raw.get("source_faces")!=frozen.local.source_faces:return Terrain.fail("Candidate local face IDs/order/coverage differ")
	var world:Dictionary=frozen.world.duplicate(false)
	world.positions=frozen.world.positions.duplicate()
	var seen:={}
	for row in raw.get("changed_vertices",[]):
		if not row is Dictionary or not Terrain.integer(row.get("vertex_index"),0,world.positions.size()-1):return Terrain.fail("Candidate vertex invalid")
		var vi:int=row.vertex_index
		if seen.has(vi) or row.get("vertex_id")!=world.vertex_ids[vi] or not Terrain.finite_number(row.get("candidate_height"),Terrain.MAX_HEIGHT) or absf(float(row.get("source_height",INF))-world.positions[vi].y)>0.00000015:return Terrain.fail("Candidate original vertex identity/height rejected")
		var p:Vector3=world.positions[vi];p.y=row.candidate_height;world.positions[vi]=p;seen[vi]=true
	world.source_semantic_hash=world.semantic_hash;world.semantic_hash=raw.candidate_semantic_hash;world.diagnostic_candidate=true
	var water:Dictionary=frozen.water.duplicate(false);water.footprints=[];water.by_face={};water.triangles=0
	var indices:=[];var unique:={};var replaced_bodies:={}
	for row in raw.get("candidate_wet_polygons",[]):replaced_bodies[row.body_id]=true
	# The candidate replaces only its target ocean, never unrelated local lakes.
	for source_idx in frozen.local.source_footprint_indices:
		var fp:Dictionary=frozen.water.footprints[int(source_idx)]
		if replaced_bodies.has(fp.body_id):continue
		var idx:int=water.footprints.size();indices.append(idx);water.footprints.append(fp)
		if not water.by_face.has(fp.face):water.by_face[fp.face]=PackedInt32Array()
		water.by_face[fp.face].append(idx);water.triangles+=fp.polygon.size()-2
	for row in raw.get("candidate_wet_polygons",[]):
		if not row is Dictionary or not Terrain.integer(row.get("source_face_index"),0,world.face_ids.size()-1) or not water.bodies.has(row.get("body_id","")):return Terrain.fail("Candidate footprint identity invalid")
		var fi:int=row.source_face_index
		if row.get("source_face_id")!=world.face_ids[fi] or row.get("level")!=water.bodies[row.body_id].surface_level or not row.get("polygon_xz") is Array or row.polygon_xz.size()<3 or row.polygon_xz.size()>4:return Terrain.fail("Candidate footprint original face/level invalid")
		var key:String=str(fi)+"/"+row.body_id
		if unique.has(key):return Terrain.fail("Duplicate candidate footprint")
		unique[key]=true
		var poly:=PackedVector2Array();var a:Vector3=world.positions[world.indices[fi*3]];var b:Vector3=world.positions[world.indices[fi*3+1]];var c:Vector3=world.positions[world.indices[fi*3+2]]
		var u:=Vector2(b.x-a.x,b.z-a.z);var v:=Vector2(c.x-a.x,c.z-a.z);var det:=u.cross(v)
		for pp in row.polygon_xz:
			if not pp is Array or pp.size()!=2 or not Terrain.finite_number(pp[0]) or not Terrain.finite_number(pp[1]):return Terrain.fail("Candidate polygon coordinate invalid")
			var p:=Vector2(pp[0],pp[1]);var rel:=p-Vector2(a.x,a.z);var wb:=rel.cross(v)/det;var wc:=u.cross(rel)/det
			if wb<-.0002 or wc<-.0002 or wb+wc>1.0002 or a.y*(1-wb-wc)+b.y*wb+c.y*wc>row.level+.00004:return Terrain.fail("Candidate footprint escapes changed PL wet support")
			poly.append(p)
		if Water.polygon_area(poly)<=0:return Terrain.fail("Candidate polygon winding/area invalid")
		var idx:int=water.footprints.size();indices.append(idx);water.footprints.append({"face":fi,"body_id":row.body_id,"level":row.level,"polygon":poly,"kind":water.bodies[row.body_id].kind})
		if not water.by_face.has(fi):water.by_face[fi]=PackedInt32Array()
		water.by_face[fi].append(idx);water.triangles+=poly.size()-2
	water.source_semantic_hash=water.semantic_hash;water.semantic_hash=raw.semantic_hash;water.diagnostic_candidate=true;water.local_display_only=true
	var field_path:="res://artifacts/real_shore_preview_20261002/candidate_field_manifest.json"
	if not FileAccess.file_exists(field_path):return Terrain.fail("Candidate visual field absent")
	var field_json:=JSON.new()
	if field_json.parse(FileAccess.get_file_as_string(field_path))!=OK or not field_json.data is Dictionary:return Terrain.fail("Candidate field JSON")
	var field:Dictionary=field_json.data
	if field.get("schema")!="candidate-local-visual-shore-field-0.1.0" or not field.get("diagnostic_only",false) or field.get("accepted_world",true) or field.get("candidate_sha256")!=FileAccess.get_sha256(PATH) or field.get("frozen_visual_manifest_sha256")!=frozen.manifest_sha256 or field.get("exporter_sha256")!=FileAccess.get_sha256("res://tests/real_shore_preview/bake_candidate_field.py") or field.get("bounds_xz")!=frozen.scope.bounds_xz:return Terrain.fail("Candidate visual field binding rejected")
	if not field.get("texture") is Dictionary or field.texture.get("path")!="artifacts/real_shore_preview_20261002/candidate_shore_field.png" or FileAccess.get_sha256("res://"+field.texture.path)!=field.texture.get("sha256"):return Terrain.fail("Candidate visual field bytes rejected")
	var result:Dictionary=frozen.duplicate(false);result.world=world;result.water=water;result.local=frozen.local.duplicate(false);result.local.source_footprint_indices=indices;result.candidate_file_sha256=FileAccess.get_sha256(PATH);result.candidate_semantic_hash=raw.candidate_semantic_hash;result.candidate_changed_vertices=seen.size();result.candidate_status=raw.status;result.scope=frozen.scope.duplicate(true);result.scope.texture=field.texture;result.candidate_field_sha256=FileAccess.get_sha256(field_path)
	return {"ok":true,"admitted":result}
