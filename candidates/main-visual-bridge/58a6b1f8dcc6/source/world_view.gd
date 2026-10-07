extends "res://view/integrated_ecology_world/performance_variant/world_view66.gd"
signal private_visual_bounds_dirty
func _update_budget()->void:
	super._update_budget()
	private_visual_bounds_dirty.emit()
func _new_world_canopies()->Node3D:
	return preload("sapling_display_loader.gd").new()
func apply_clear_daylight_profile()->void:
	if not clear_daylight_enabled or not is_instance_valid(whole_canopies) or whole_canopies.selected_variant!="natural_v2":return
	clear_daylight_profile=preload("daylight_profile.gd").attach_to(self)
	if natural_shorelines_enabled:apply_natural_shorelines()
	apply_faceted_mountains()
