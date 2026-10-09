extends SceneTree
const Picker=preload("res://view/generated_v3_npc/picking.gd")
var checks=0
var failures=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("NPC_PICKER_FAIL ",label)
func run():
	var token=Node3D.new();root.add_child(token)
	var sphere=MeshInstance3D.new();var mesh=SphereMesh.new();mesh.radius=.2;mesh.height=.4;sphere.mesh=mesh;token.add_child(sphere)
	var picker=Picker.new();check(picker.capture([{"id":"npc_test","kind":"actor","hex":[0,0],"node":token}]).ok,"native PrimitiveMesh capture")
	var hits=picker.query(Vector3(0,0,3),Vector3(0,0,-1),10)
	check(hits.size()==1 and hits[0].id=="npc_test" and absf(hits[0].distance-2.8)<.01,"raw sphere triangles picked")
	token.position.x=.5
	check(picker.query(Vector3(0,0,3),Vector3(0,0,-1),10).is_empty(),"current transform invalidates former location")
	check(picker.query(Vector3(.5,0,3),Vector3(0,0,-1),10).size()==1,"current transform hit")
	sphere.hide();check(picker.query(Vector3(.5,0,3),Vector3(0,0,-1),10).is_empty(),"hidden actor not pickable");sphere.show()
	var glow=MeshInstance3D.new();glow.name="SelectedEdgeGlow";glow.mesh=mesh;glow.position=Vector3(0,0,1);token.add_child(glow)
	check(picker.capture([{"id":"npc_test","kind":"actor","hex":[0,0],"node":token}]).ok,"recapture with selected glow")
	hits=picker.query(Vector3(.5,0,3),Vector3(0,0,-1),10)
	check(hits.size()==1 and absf(hits[0].distance-2.8)<.01,"glow excluded from raw hit")
	check(picker.query(Vector3(.5,0,3),Vector3(0,0,-1),2).is_empty(),"nearer opaque bound hides NPC")
	token.free();check(picker.query(Vector3(.5,0,3),Vector3(0,0,-1),10).is_empty(),"removed token not stale-pickable")
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_npc")
	FileAccess.open("res://artifacts/generated_v3_npc/picker_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty()},"\t"))
	print("NPC_PICKER ",checks," ",failures);quit(0 if failures.is_empty() else 1)
