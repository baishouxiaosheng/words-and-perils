extends SceneTree
const Contract=preload("res://core/world_generation_contract.gd")
const Field=preload("res://tests/height_reuse/count_field.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
class CountRaw extends RefCounted:
	var source
	var calls:=0
	func _init(original)->void:source=original
	func sample_visual_landscape(p:Vector3)->Dictionary:
		calls+=1;return source.sample_visual_landscape(p)
func _initialize()->void:run.call_deferred()
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
	var raw:=CountRaw.new(field.height_field);field.height_field=raw
	var helper=load("res://view/mesh_landscape_reuse.gd")
	var started:=Time.get_ticks_usec()
	var meshes:Dictionary=helper.build_meshes(field)
	var result:=field.metrics();result["instrumented_mesh_build_ms"]=(Time.get_ticks_usec()-started)/1000.0
	result["actual_raw_calls"]=raw.calls;result["restored_counting_source"]=field.height_field==raw
	result["source_hash"]=metadata.content_hash;result["source_unchanged"]=C.digest(metadata)==original
	result["mesh_hashes"]={}
	for layer in meshes:
		var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
		for i in range(meshes[layer].get_surface_count()):context.update(var_to_bytes(meshes[layer].surface_get_arrays(i)))
		result.mesh_hashes[layer]=context.finish().hex_encode()
	var output:=FileAccess.open(OS.get_environment("FOGBANK_PERF_OUT")+"/report.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"\t"));output.close()
	print("HEIGHT_REUSE_PROBE ",JSON.stringify(result));quit(0 if result.source_unchanged else 1)
