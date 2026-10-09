extends SceneTree
## Actual procedural mesh shell/orientation tests, not metadata-only assertions.
const Geometry=preload("res://view/miniature_geometry.gd")
const Field=preload("res://view/terrain_field.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func vertex_key(p:Vector3)->String:return "%d:%d:%d"%[roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000)]
func shell(mesh:ArrayMesh,center:Vector3,name:String,expected_volume:float=-1.0)->void:
	var arrays=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var edges={};var volume=0.0
	for i in range(0,vertices.size(),3):
		var a=vertices[i];var b=vertices[i+1];var c=vertices[i+2]
		var outward=(c-a).cross(b-a)
		check(outward.length()>0.000001,name+" has no collapsed face at %d"%i)
		outward=outward.normalized()
		check(outward.dot((a+b+c)/3.0-center)>0.00001,name+" clockwise faces point outward at %d"%i)
		for j in range(3):check(normals[i+j].dot(outward)>0.999,name+" actual normal agrees with clockwise front face at %d"%(i+j))
		volume-=a.dot(b.cross(c))/6.0
		for pair in [[a,b],[b,c],[c,a]]:
			var keys=[vertex_key(pair[0]),vertex_key(pair[1])];keys.sort();var edge=keys[0]+"/"+keys[1]
			edges[edge]=int(edges.get(edge,0))+1
	for edge in edges:check(edges[edge]==2,name+" closed shell edge has exactly two incident faces: "+edge)
	check(volume>0.0,name+" has positive outward enclosed volume")
	if expected_volume>0:check(absf(volume-expected_volume)<0.000001,name+" enclosed volume matches solid wedge")
func projected_area(polygon:Array)->float:
	var total=0.0
	for i in range(1,polygon.size()-1):total+=absf((polygon[i].p-polygon[0].p).cross(polygon[i+1].p-polygon[0].p).y)*0.5
	return total
func _initialize()->void:
	shell(Geometry.chamfered_block(Vector3(0.24,0.17,0.23),0.014),Vector3.ZERO,"battlement")
	shell(Geometry.chamfered_block(Vector3(0.66,0.18,0.29),0.035),Vector3.ZERO,"bridge abutment")
	shell(Geometry.grounded_wall(Vector3.ZERO,Vector3(0,0,1),0.0,0.2,1.0,0.28),Vector3(0,0.55,0.5),"grounded wall",0.252)
	var field=Field.new()
	var samples=[{"p":Vector3(0,0.1,0),"c":Color.WHITE,"bank":0.0},{"p":Vector3(1,0.2,0),"c":Color.WHITE,"bank":0.5},{"p":Vector3(0,0.3,1),"c":Color.WHITE,"bank":1.0}]
	var meadow:Array=field._clip_ground(samples,false);var bank:Array=field._clip_ground(samples,true)
	check(meadow.size()==3 and bank.size()==4,"Bank contour clips the triangle instead of assigning a sawtooth whole face")
	check(absf(projected_area(meadow)+projected_area(bank)-0.5)<0.000001,"Meadow plus bank cover the exact original face without overlap or missing wedge")
	var joins=0
	for a in meadow:
		if not is_equal_approx(float(a.bank),0.20):continue
		check(bank.any(func(b):return b.p.is_equal_approx(a.p)),"Both material contours use the same interpolated seam point")
		joins+=1
	check(joins==2,"Bank seam is the two-point scalar contour")
	if failures.is_empty():print("MASONRY SOLIDS PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
