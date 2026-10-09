extends "res://main.gd"
var legacy_refreshes := 0
var failure_kind := ""
func refresh_world(animate_changes: bool=false)->void:
	if not playtest_mode:legacy_refreshes+=1
	super.refresh_world(animate_changes)
func coast_bundle_available(existing:RefCounted=null)->bool:
	if failure_kind=="bundle":show_world_load_error("TEST_ONLY bundle rejection");return false
	return super.coast_bundle_available(existing)
func _create_scene_board(state:Dictionary)->Node3D:
	if failure_kind=="renderer":return preload("res://tests/loading_startup/rejected_board.gd").new()
	return super._create_scene_board(state)
