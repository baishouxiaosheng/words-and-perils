extends SceneTree
const Assets=preload("res://core/generated_v3_vegetation/assets.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const BASELINE_SHA="fdc5901bd445985c9d906cdf093c62703d23b1beaa7d7d45f55b23de02577361"
var checks:Array=[]
func check(ok:bool,name_:String)->void:checks.append({"passed":ok,"name":name_})
func _initialize()->void:
	var result:Dictionary=Assets.build()
	check(result.get("ok",false),"strict frozen-v1 assets build")
	var snapshot:Dictionary={}
	if result.get("ok",false):
		snapshot={"catalog":result.catalog,"buffers":{}}
		for kind in Assets.KINDS:
			snapshot.buffers[kind]={}
			for field in ["full_vertices","far_vertices","root_vertices","solid_vertices","canopy_vertices"]:
				snapshot.buffers[kind][field]=Assets.digest_bytes(result.measurements[kind][field].to_byte_array())
	var path:String=OS.get_environment("FOGBANK_ASSET_BASELINE")
	if path.is_empty():path="res://tests/fixtures/vegetation_v1/asset_catalog_v24.json"
	if OS.get_environment("FOGBANK_ASSET_CAPTURE")=="1":
		if result.get("ok",false):FileAccess.open(path,FileAccess.WRITE).store_string(C.bytes(snapshot))
	else:
		var prior:Variant=null
		check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==BASELINE_SHA,"frozen v24 asset baseline SHA is exact")
		if FileAccess.file_exists(path):prior=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(prior is Dictionary,"explicit verified-v24 asset snapshot is available")
		if prior is Dictionary and result.get("ok",false):
			check(C.bytes(result.catalog)==C.bytes(prior.catalog),"complete prior asset catalog including pins/hash byte-identical")
			for kind in Assets.KINDS:
				for field in snapshot.buffers[kind]:check(snapshot.buffers[kind][field]==prior.buffers[kind][field],kind+" "+field+" raw native bytes unchanged")
	var failures:int=0
	for row in checks:if not row.passed:failures+=1
	var report:Dictionary={"checks":checks,"failures":failures,"result_code":result.get("code",""),"assets_hash":result.get("catalog",{}).get("catalog_hash","")}
	FileAccess.open(OS.get_environment("FOGBANK_PERF_OUT")+"/asset_catalog.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ASSET_CATALOG_COMPAT ",checks.size()-failures,"/",checks.size()," ",result.get("code",""));quit(0 if failures==0 else 1)
