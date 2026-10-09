extends "res://view/integrated_ecology_world/performance_variant/whole_canopies.gd"
## Coast lifecycle loader only. The parent is the frozen v1 mesh recipe whose
## exact SHA participates in generated-world asset catalogs and saved identities.
## Never move lifecycle edits into that pinned recipe or reinterpret old saves.
var manifest_sha256:=""
func load_cache(base:Dictionary,variant:String="v1")->bool:
	if variant not in ["v1","natural_v2"]:
		last_error="Unsupported whole-world canopy variant: "+variant
		return false
	var root_:String=NATURAL_ROOT if variant=="natural_v2" else ROOT
	if not FileAccess.file_exists(root_+"manifest.json"):
		last_error="Whole-world canopy manifest missing: "+variant
		return false
	if not super.load_cache(base,variant):return false
	manifest_sha256=NATURAL_SHA if variant=="natural_v2" else MANIFEST_SHA
	last_error=""
	return true
