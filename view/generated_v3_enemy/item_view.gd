extends "res://view/generated_v3_npc/item_view.gd"
## Add the immutable full hostile body to existing bag placement exclusions.
func overlaps_static_prop(pose:Dictionary)->bool:
	if super.overlaps_static_prop(pose):return true
	var n:Array=pose.normal
	var transform_=Transform3D(Basis(Quaternion(Vector3.UP,Vector3(n[0],n[1],n[2])))*float(pose.scale),pose.position)
	var volume:AABB=transform_*AABB(Vector3(-.19,0,-.17),Vector3(.38,.42,.34))
	var witness:Dictionary=board.admitted_source.enemy_placement_result.placement_witness
	var base:Vector3=preload("res://view/generated_v3_enemy/placement.gd").position(witness)
	var low=Vector3(INF,base.y,INF);var high=Vector3(-INF,base.y+2.0,-INF)
	for point in witness.support_witness.footprint:
		low.x=minf(low.x,float(point[0]));low.z=minf(low.z,float(point[1]));high.x=maxf(high.x,float(point[0]));high.z=maxf(high.z,float(point[1]))
	return volume.intersects(AABB(low,high-low))
