extends "res://view/integrated_ecology_world/performance_variant/world_view66.gd"
signal private_visual_bounds_dirty
## An orthographic image does not change with camera distance, so the camera is
## set back until nothing on the map can rise between it and the view; nearby
## terrain is then never cut by the near plane. The palette sun's shadow range
## is moved back by the same amount so shadow coverage around the view holds.
const SHADOW_RANGE := 40.0
const SHADOW_SPLIT := .30
var _top_height := NAN
var _top_signature := -1
func _update_camera()->void:
	var authored:=distance
	if camera.projection==Camera3D.PROJECTION_ORTHOGONAL and not overview:
		distance=maxf(distance,_clear_distance())
	var extra:=distance-authored
	super._update_camera()
	distance=authored
	var sun:=get_parent().get_node_or_null("SinglePaletteShadowSun") as DirectionalLight3D if get_parent() else null
	if sun:
		sun.directional_shadow_max_distance=SHADOW_RANGE+extra
		sun.directional_shadow_split_1=(SHADOW_RANGE*SHADOW_SPLIT+extra)/(SHADOW_RANGE+extra)
func _clear_distance()->float:
	# The lowest point of the near plane sits size/2 below the camera along its up axis.
	var s:=maxf(sin(pitch),.05)
	return (_map_top()-target.y+1.0+camera.size*.5*cos(pitch))/s
func _map_top()->float:
	var signature:=content_root.get_child_count()*131+get_child_count()
	for child in content_root.get_children():signature+=child.get_child_count()
	if signature==_top_signature:return _top_height
	_top_signature=signature;_top_height=0.0
	var pending:Array[Node]=[content_root]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		if node is GeometryInstance3D:
			var box:AABB=node.global_transform*node.get_aabb()
			_top_height=maxf(_top_height,box.end.y)
		pending.append_array(node.get_children())
	return _top_height
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
