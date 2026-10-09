extends "res://view/integrated_ecology_world/performance_variant/whole_canopies_loader.gd"
## Test only: aliases reload the SAME complete hash-verified shipped natural_v2
## records. This does not make the absent v1 cache available or change production.
func load_cache(base:Dictionary,variant:String="v1")->bool:
	if variant=="fixture_load_failure":last_error="TEST_ONLY rejected candidate";return false
	if not variant.begins_with("fixture_"):return super.load_cache(base,variant)
	if not super.load_cache(base,"natural_v2"):return false
	selected_variant=variant
	if variant=="fixture_wrong_instance_source":
		manifest=manifest.duplicate(true);manifest.runtime.sha256="TEST_ONLY incompatible instance source"
	elif variant=="fixture_wrong_anchor_source":manifest_sha256="TEST_ONLY incompatible anchor source"
	return true
