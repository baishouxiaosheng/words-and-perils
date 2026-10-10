extends "res://view/playable_build/committed_camera.gd"
## The framing math works in the view plane through the target, where the
## perspective character view shows exactly camera.size of height. It is run
## on the matching orthographic projection, and the next _update_camera puts
## the perspective back before anything is drawn.
func consider(events: Array, tokens: Dictionary, motion: Node3D, route_points:Array[Vector3]=[]) -> bool:
	if not is_instance_valid(camera) or camera.projection!=Camera3D.PROJECTION_PERSPECTIVE:return super.consider(events,tokens,motion,route_points)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	var framed:=super.consider(events,tokens,motion,route_points)
	if is_instance_valid(view):view._update_camera()
	return framed
