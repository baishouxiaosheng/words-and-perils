extends Node3D
var camera:Camera3D
var target:=Vector3(0,0.45,0)
var distance:=12.0
var pitch:=0.72
var yaw:=0.2
var overview:=false
func _init()->void:
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=6.0;camera.keep_aspect=Camera3D.KEEP_HEIGHT;add_child(camera)
func _update_camera()->void:
	camera.position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target,Vector3.UP)
