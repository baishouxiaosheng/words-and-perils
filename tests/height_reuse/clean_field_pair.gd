extends SceneTree
const Contract=preload("res://core/world_generation_contract.gd")
const Field=preload("res://view/terrain_field.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var candidate:=false
func _initialize()->void:
	candidate=OS.get_environment("HEIGHT_REUSE_CANDIDATE")=="1"
	run.call_deferred()
func digest_entries(values:Dictionary)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	for k in values:context.update(var_to_bytes([k,values[k]]))
	return context.finish().hex_encode()
func mesh_rows(meshes:Dictionary)->Dictionary:
	var rows:Dictionary={}
	for layer in meshes:
		var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
		for i in range(meshes[layer].get_surface_count()):context.update(var_to_bytes(meshes[layer].surface_get_arrays(i)))
		rows[layer]={"sha256":context.finish().hex_encode(),"bounds":str(meshes[layer].get_aabb()),"surfaces":meshes[layer].get_surface_count()}
	return rows
func run()->void:
	var envelope:Dictionary=Contract.generate("726381","wide_coast",24)
	if not envelope.ok or envelope.source.content_hash!="b80ef7fdc90db70ec80f1b63ae17942c95e0fb90f25c9de1475e4c252743f9b2":printerr("SOURCE_MISMATCH");quit(1);return
	var metadata:Dictionary=envelope.source
	var original:=C.digest(metadata)
	var tiles:Dictionary={}
	for key_ in metadata.hexes:
		var cell:Dictionary=metadata.hexes[key_];tiles[key_]={"hex":Vector2i(cell.q,cell.r),"terrain":cell.terrain,"raw":cell}
	var field:=Field.new()
	if not field.configure(tiles,metadata):printerr("CONFIGURE_FAIL");quit(1);return
	var original_height_field=field.height_field
	var helper=load("res://view/mesh_landscape_reuse.gd") if candidate else null
	var started:=Time.get_ticks_usec()
	var meshes:Dictionary
	if candidate:meshes=helper.build_meshes(field)
	else:meshes=field.build_meshes()
	var result:Dictionary={"candidate":candidate,"clean_build_ms":(Time.get_ticks_usec()-started)/1000.0,"static_after_meshes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"height_field_restored":field.height_field==original_height_field,"source_hash":metadata.content_hash,"source_unchanged":C.digest(metadata)==original}
	result["meshes"]=mesh_rows(meshes)
	result["caches"]={"landscape":{"entries":field.landscape_cache.size(),"sha256":digest_entries(field.landscape_cache),"hits":field.landscape_cache_hits,"misses":field.landscape_cache_misses},"query":{"entries":field.query_cache.size(),"sha256":digest_entries(field.query_cache)},"vertex":{"entries":field.vertex_cache.size(),"sha256":digest_entries(field.vertex_cache)}}
	result["counts"]={"triangles":field.triangle_count,"shared_vertex_count":field.shared_vertex_count,"channel_index":field.channel_index.metrics()}
	field.vertex_cache.clear()
	result["later_queries"]=[]
	for i in range(300):
		var p:=Vector3(sin(i*0.313)*37.0,0,cos(i*0.721)*33.0)
		result.later_queries.append([p,field.land_height(p),field.water_height(p),field.bank_mask(p),field.biome_appearance(p)])
	var query_digest:=HashingContext.new();query_digest.start(HashingContext.HASH_SHA256);query_digest.update(var_to_bytes(result.later_queries))
	result["later_queries_sha256"]=query_digest.finish().hex_encode();result.erase("later_queries")
	var output:=FileAccess.open(OS.get_environment("FOGBANK_PERF_OUT")+"/report.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"\t"));output.close()
	print("CLEAN_HEIGHT_PAIR ",JSON.stringify(result));quit(0 if result.source_unchanged and result.height_field_restored else 1)
