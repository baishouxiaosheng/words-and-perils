extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const PATH="res://core/generated_v3_placement/asset_catalog.json"
const SHA="21288ad155f489421db8907af91c8990bf4b71e228385bb751043e691f3e54b9"
static func read() -> Dictionary:
	if FileAccess.get_sha256(PATH)!=SHA:return C.fail("PLACEMENT_ASSET_CATALOG","The approved village asset catalog changed.")
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not raw is Dictionary or raw.get("schema_version")!="generated_v3_placement_assets/v1":return C.fail("PLACEMENT_ASSET_CATALOG","Village asset catalog is invalid.")
	for name in raw.assets:
		var row: Dictionary=raw.assets[name]
		for pair in [["glb","sha256"],["lod1_glb","lod1_sha256"]]:
			if FileAccess.get_sha256(raw.asset_root+row[pair[0]])!=row[pair[1]]:return C.fail("PLACEMENT_ASSET_HASH","Approved village asset bytes changed: "+name)
	for prefix in ["material","material_shader"]:
		if FileAccess.get_sha256(raw[prefix+"_path"])!=raw[prefix+"_sha256"]:return C.fail("PLACEMENT_ASSET_MATERIAL","Approved village material changed.")
	return {"ok":true,"data":raw,"hash":SHA}
