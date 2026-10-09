extends "res://view/generated_v3_inventory/item_view.gd"
const NPCPlacement=preload("res://view/generated_v3_npc/placement.gd")
## Presentation-only overlap rejection for the explicitly composed NPC/forest.
## The original model, dry fitter, custody and item rules remain reused.
func overlaps_static_prop(pose:Dictionary) -> bool:
	if super.overlaps_static_prop(pose):return true
	var n:Array=pose.normal
	var transform_=Transform3D(Basis(Quaternion(Vector3.UP,Vector3(n[0],n[1],n[2])))*float(pose.scale),pose.position)
	var volume:AABB=transform_*AABB(Vector3(-.19,0,-.17),Vector3(.38,.42,.34))
	var source:RefCounted=board.admitted_source
	if source.features.vegetation:
		for plant in source.vegetation_result.manifest.plants:
			var low:Array=plant.visual_bounds.min;var high:Array=plant.visual_bounds.max
			var p=Vector3(low[0],low[1],low[2]);var size_=Vector3(high[0],high[1],high[2])-p
			if volume.intersects(AABB(p,size_)):return true
	var witness:Dictionary=source.npc_placement_result.placement_witness
	var base:Vector3=NPCPlacement.position(witness)
	var low=Vector3(INF,base.y+float(witness.support_witness.bounds.min_y),INF)
	var high=Vector3(-INF,base.y+float(witness.support_witness.bounds.max_y),-INF)
	for p in witness.support_witness.footprint:
		low.x=minf(low.x,float(p[0]));low.z=minf(low.z,float(p[1]));high.x=maxf(high.x,float(p[0]));high.z=maxf(high.z,float(p[1]))
	return volume.intersects(AABB(low,high-low))
