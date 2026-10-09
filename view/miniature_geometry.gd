extends RefCounted
## New procedural masonry sections. No downloaded or copied model assets.
static func chamfered_block(size:Vector3,bevel:float=0.025)->ArrayMesh:
	var s=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x=size.x*0.5;var z=size.z*0.5;var y=size.y*0.5
	var b=minf(bevel,minf(x,z)*0.35)
	var outline=[Vector2(-x+b,-z),Vector2(x-b,-z),Vector2(x,-z+b),Vector2(x,z-b),Vector2(x-b,z),Vector2(-x+b,z),Vector2(-x,z-b),Vector2(-x,-z+b)]
	var bottom:Array[Vector3]=[];var top:Array[Vector3]=[];var crown:Array[Vector3]=[]
	for p in outline:
		bottom.append(Vector3(p.x,-y,p.y));top.append(Vector3(p.x,y-b,p.y))
		crown.append(Vector3(p.x*maxf(0.1,(x-b)/x),y,p.y*maxf(0.1,(z-b)/z)))
	for i in range(8):
		var j=(i+1)%8
		var points=[bottom[i],top[i],bottom[j],bottom[j],top[i],top[j],top[i],crown[i],top[j],top[j],crown[i],crown[j],Vector3(0,y,0),crown[j],crown[i],Vector3(0,-y,0),bottom[i],bottom[j]]
		for j3 in range(0,points.size(),3):_outward_triangle(s,points[j3],points[j3+1],points[j3+2])
	return s.commit()

static func grounded_wall(a:Vector3,b:Vector3,bottom_a:float,bottom_b:float,top:float,width:float)->ArrayMesh:
	var side=Vector3(-(b-a).z,0,(b-a).x).normalized()*width*0.5
	var p=[a-side,a+side,b-side,b+side,a-side,a+side,b-side,b+side]
	for i in range(8):p[i].y=(bottom_a if i<2 else bottom_b) if i<4 else top
	var s=SurfaceTool.new();s.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices=[0,4,2,2,4,6,3,7,1,1,7,5,1,5,0,0,5,4,2,6,3,3,6,7,4,5,6,6,5,7,1,0,3,3,0,2]
	for i in range(0,indices.size(),3):_outward_triangle(s,p[indices[i]],p[indices[i+1]],p[indices[i+2]])
	return s.commit()

static func _outward_triangle(surface:SurfaceTool,a:Vector3,b:Vector3,c:Vector3)->void:
	# Mathematical outward cross is supplied explicitly. Godot front faces use
	# clockwise order, so reverse the authored counter-clockwise positions.
	var outward=(b-a).cross(c-a).normalized()
	for point in [a,c,b]:
		surface.set_normal(outward);surface.add_vertex(point)
