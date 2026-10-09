extends "res://view/generated_v3_rivers/adapter.gd"
## Optional v22 entry adapter. Existing geometry/gameplay/save identity unchanged.
## Additional namespace protection is defensive even if those files do not exist.
const V22_PROTECTED_NAMES := [
	"generated_v3_village_equipment_v1.json",
	"generated_v3_village_equipment_request_v1.json",
]
func _init(generated: Dictionary = {}, renderer_profile: String = Source.RENDERER_PROFILE) -> void:
	super(generated, renderer_profile)

func _check_destination(path: String, request_file: bool = false) -> Dictionary:
	if path.get_file().to_lower() in V22_PROTECTED_NAMES:
		return C.fail("RIVER_V22_NAMESPACE", "实验河流不能覆盖正式村庄装备进度或请求文件。")
	return super._check_destination(path, request_file)
