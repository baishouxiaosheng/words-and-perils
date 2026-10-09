extends Node3D
## View-only continuous traversal of exact triangle-crossing points.
## A point is not a new game step; the engine already committed the whole route.
signal movement_finished(actor_id: String)
var actors: Dictionary={}
var selected_id:=""
func register_actor(id:String,node:Node3D,support:Vector3) -> void:
	actors[id]={"node":node,"support":support,"rotation":node.rotation,"selected":false,"moving":false,"route":[],"elapsed":0.0,"duration":0.0,"distances":[]}
	node.position=support
func reset_actor(id:String,support:Vector3) -> void:
	if not actors.has(id):return
	var track:Dictionary=actors[id];track.support=support;track.moving=false;track.route=[];track.selected=false;track.node.position=support;track.node.rotation=track.rotation
func select_actor(id:String) -> void:
	selected_id=id if actors.has(id) else ""
	for key in actors:actors[key].selected=key==selected_id
func set_actor_rotation(id:String,rotation_:Vector3) -> void:
	if actors.has(id):actors[id].rotation=rotation_
func move_actor_path(id:String,points:Array,cell_edges:int=1) -> void:
	if not actors.has(id) or points.size()<2:return
	for point in points:
		if not point is Vector3:return
	var track:Dictionary=actors[id]
	track.start_rotation=track.node.rotation;track.node.position=points[0];track.route=points.duplicate();track.support=points.back();track.selected=false;track.elapsed=0.0
	var distances:Array=[0.0];var length:=0.0
	for i in range(1,points.size()):length+=points[i-1].distance_to(points[i]);distances.append(length)
	track.distances=distances;track.length=length;track.duration=clampf(float(cell_edges)*0.85,0.85,12.0);track.moving=true
func forget_actor(id:String) -> void:actors.erase(id)
func _process(delta:float) -> void:
	for id in actors:
		var t:Dictionary=actors[id]
		if not is_instance_valid(t.node):continue
		if not t.moving:
			t.node.position=t.node.position.lerp(t.support+Vector3(0,.16 if t.selected else 0,0),1.0-exp(-delta*15.0));continue
		t.elapsed+=delta
		var progress:float=minf(1.0,t.elapsed/t.duration)
		var smooth:float=progress*progress*(3.0-2.0*progress)
		var along:float=smooth*t.length;var segment:=1
		while segment<t.distances.size()-1 and float(t.distances[segment])<along:segment+=1
		var extent:float=maxf(0.000001,float(t.distances[segment])-float(t.distances[segment-1]))
		var fraction:float=clampf((along-float(t.distances[segment-1]))/extent,0,1)
		var support:Vector3=t.route[segment-1].lerp(t.route[segment],fraction)
		t.node.position=support+Vector3(0,sin(progress*PI)*.45,0)
		t.node.quaternion=Quaternion.from_euler(t.start_rotation).slerp(Quaternion.from_euler(t.rotation),smooth)
		t.node.rotation+=Vector3(.025*sin(progress*TAU),0,.018*sin(progress*PI))
		if progress>=1.0:
			t.moving=false;t.route=[];t.node.position=t.support;t.node.rotation=t.rotation;movement_finished.emit(id)
