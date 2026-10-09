extends "res://view/generated_v3_adventure/presentation.gd"
## New profile only: receipt effects may wait on motion but never outlive it.
var force_reset:=false
func register_actor(id:String,node:Node3D,support:Vector3)->void:
	super.register_actor(id,node,support);actors[id]["generation"]=0
func reset_actor(id:String,support:Vector3)->void:
	if actors.has(id):
		if not force_reset and actors[id].support.distance_to(support)<.000001:return
		actors[id].generation=int(actors[id].get("generation",0))+1
	super.reset_actor(id,support)
func move_actor_path(id:String,points:Array,cell_edges:int=1)->void:
	if actors.has(id):actors[id].generation=int(actors[id].get("generation",0))+1
	super.move_actor_path(id,points,cell_edges)
