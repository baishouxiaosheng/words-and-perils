extends "res://tests/generated_v3_equipment/test_adopted_copy.gd"
## Permanent release gate: strict exact historical vegetation/equipment/enemy
## inputs, then the existing complete history/new-action/JSON/disk checks.
const FIXTURE_ROOT="res://tests/fixtures/vegetation_v1/"
const FILES=["generated_v3_village_equipment_v1.json", "equipment_poisoned_history.json", "generated_v3_village_enemy_v1.json", "terminal_presentation_save.json"]
const EXPECTED={"generated_v3_village_equipment_v1.json":"bf0815e9b3ee265c8df90a0ace21840c02600708c9e9b669ff608e010788e3d3","equipment_poisoned_history.json":"19269f461ffc5147a2eb80a4f3f7a74ee83a6e8c92fa798dd57aecbc7dc998ca","generated_v3_village_enemy_v1.json":"9a236f96cc773c1a85d11a2fef5a3dce7fbaf0500e456f99df11fbaf68171f79","terminal_presentation_save.json":"2946c7f1af5597e6741ee690612ba8b1390b1d9436632d00d44121d76ed19135"}
func _input_paths()->PackedStringArray:
	var paths:=PackedStringArray()
	for name_ in FILES:paths.append(FIXTURE_ROOT+name_)
	return paths
func run()->void:
	for name_ in FILES:
		if not check(FileAccess.file_exists(FIXTURE_ROOT+name_) and FileAccess.get_sha256(FIXTURE_ROOT+name_)==EXPECTED[name_],"permanent prior native save exact SHA "+name_):finish();return
	super.run()
