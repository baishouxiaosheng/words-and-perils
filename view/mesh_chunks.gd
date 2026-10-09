extends RefCounted
## Partition completed meshes, preserving exact positions/normals/colors/UVs.
## Global normal generation precedes splitting, so chunk borders cannot relight.
class Builder extends RefCounted:
	var source:Array
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colors:=PackedColorArray()
	var uv:=PackedVector2Array()
	var uv2:=PackedVector2Array()
	var tangents:=PackedFloat32Array()
	func add(index:int)->void:
		vertices.append(source[Mesh.ARRAY_VERTEX][index])
		if source[Mesh.ARRAY_NORMAL]!=null:normals.append(source[Mesh.ARRAY_NORMAL][index])
		if source[Mesh.ARRAY_COLOR]!=null:colors.append(source[Mesh.ARRAY_COLOR][index])
		if source[Mesh.ARRAY_TEX_UV]!=null:uv.append(source[Mesh.ARRAY_TEX_UV][index])
		if source[Mesh.ARRAY_TEX_UV2]!=null:uv2.append(source[Mesh.ARRAY_TEX_UV2][index])
		if source[Mesh.ARRAY_TANGENT]!=null:
			for j in range(4):tangents.append(source[Mesh.ARRAY_TANGENT][index*4+j])
	func commit()->ArrayMesh:
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
		if not normals.is_empty():arrays[Mesh.ARRAY_NORMAL]=normals
		if not colors.is_empty():arrays[Mesh.ARRAY_COLOR]=colors
		if not uv.is_empty():arrays[Mesh.ARRAY_TEX_UV]=uv
		if not uv2.is_empty():arrays[Mesh.ARRAY_TEX_UV2]=uv2
		if not tangents.is_empty():arrays[Mesh.ARRAY_TANGENT]=tangents
		var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
static func axial(point:Vector3)->Vector2i:
	var qf=point.x/sqrt(3.0)-point.z/3.0;var rf=point.z*2.0/3.0;var sf=-qf-rf
	var q=roundi(qf);var r=roundi(rf);var s=roundi(sf)
	var dq=absf(q-qf);var dr=absf(r-rf);var ds=absf(s-sf)
	if dq>dr and dq>ds:q=-r-s
	elif dr>ds:r=-q-s
	return Vector2i(q,r)
static func split(mesh:ArrayMesh,size_:int=6)->Dictionary:
	var result={}
	if mesh==null:return result
	for surface in range(mesh.get_surface_count()):
		var arrays=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count=indices.size() if not indices.is_empty() else vertices.size()
		var builders={}
		for i in range(0,count,3):
			var ids=[indices[i],indices[i+1],indices[i+2]] if not indices.is_empty() else [i,i+1,i+2]
			var cell=axial((vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3.0)
			var key_="%d,%d"%[floori(float(cell.x)/size_),floori(float(cell.y)/size_)]
			if not builders.has(key_):var builder=Builder.new();builder.source=arrays;builders[key_]=builder
			for id in ids:builders[key_].add(id)
		for key_ in builders:
			# The terrain layers each have one surface. Keep a general surface key
			# for diagnostics rather than silently merge incompatible attributes.
			result[key_ if mesh.get_surface_count()==1 else key_+"/"+str(surface)]=builders[key_].commit()
	return result
