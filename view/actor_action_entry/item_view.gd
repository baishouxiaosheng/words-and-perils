extends "res://view/generated_v3_npc/item_view.gd"
## Existing pack geometry, fitter and owner-following; dynamic enemy body bounds.
func overlaps_static_prop(pose:Dictionary)->bool:
	if super.overlaps_static_prop(pose):return true
	var n:Array=pose.normal
	var transform_=Transform3D(Basis(Quaternion(Vector3.UP,Vector3(n[0],n[1],n[2])))*float(pose.scale),pose.position)
	var volume:AABB=transform_*AABB(Vector3(-.19,0,-.17),Vector3(.38,.42,.34))
	return board.enemy_body_bounds.has_volume() and volume.intersects(board.enemy_body_bounds)
