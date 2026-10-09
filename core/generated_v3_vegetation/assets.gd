extends RefCounted
## Native measurements of the unchanged original CC0 procedural asset recipes.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Surface=preload("res://core/generated_v3_placement/surface.gd")
const Trees=preload("res://view/ecology_preview/vegetation_meshes.gd")
const FarTrees=preload("res://view/integrated_ecology_world/performance_variant/whole_canopies.gd")
const ID="v3_vegetation_assets/v1"
const KINDS=["temperate","tropical","sapling","shrub","tuft","reed"]
const PINS={"res://view/ecology_preview/vegetation_meshes.gd":"90f29e8c844d9f0094186c5a61060a831de50ef37ca35da36881c24a4c0c56bb","res://view/ecology_preview/vegetation_surface.gdshader":"e7bc8bdf45017df68daf059c818778f1638a21f3d1f5859a2536d8ffacd8fafb","res://view/ecology_preview/LICENSE.txt":"8f2f09db1ebceff3581d6016eb2c4154c60d15b01709a9add27d83d88b716251","res://view/integrated_ecology_world/performance_variant/whole_canopies.gd":"3426c4617148977022d23226ff858684c5b0a329bf72a24fb8129b106f48a86f"}
static var _cached:Dictionary={}
static func raw_vertices(mesh:ArrayMesh) -> PackedVector3Array:
	var result=PackedVector3Array()
	for surface_id in mesh.get_surface_count():
		var a:Array=mesh.surface_get_arrays(surface_id);var v:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():result.append_array(v)
		else:
			for index in indices:result.append(v[index])
	return result
static func unique_xz(vertices:PackedVector3Array) -> PackedVector3Array:
	# XZ projection is invariant under discarded Y for the declared upright
	# yaw/nonuniform-scale transform. Keep ALL distinct XZ points, not just the
	# hull, so outward-grid enclosure remains byte-identical to the full soup.
	var seen:Dictionary={};var result=PackedVector3Array()
	for v in vertices:
		var key_=Vector2(v.x,v.z)
		if not seen.has(key_):seen[key_]=true;result.append(Vector3(v.x,0,v.z))
	return result
static func digest_bytes(bytes:PackedByteArray) -> String:
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);return hash.finish().hex_encode()
static func bounds(vertices:PackedVector3Array) -> Dictionary:
	var low=Vector3(INF,INF,INF);var high=Vector3(-INF,-INF,-INF)
	for v in vertices:low=low.min(v);high=high.max(v)
	return {"min":[Surface.floor_q(low.x),Surface.floor_q(low.y),Surface.floor_q(low.z)],"max":[Surface.ceil_q(high.x),Surface.ceil_q(high.y),Surface.ceil_q(high.z)]}
static func build() -> Dictionary:
	for path in PINS:
		if FileAccess.get_sha256(path)!=PINS[path]:return C.fail("VEGETATION_ASSET_PIN","The reused vegetation source/material/license changed; no replacement asset was generated.")
	if not _cached.is_empty():return _cached.duplicate(true)
	var full:Dictionary={};var far:Dictionary={};var measurements:Dictionary={};var records:Dictionary={}
	var far_factory=FarTrees.new()
	for kind in KINDS:
		var mesh:ArrayMesh=Trees.make(kind);var low:ArrayMesh=far_factory._low_crown(kind) if kind in ["temperate","tropical","sapling","shrub"] else mesh
		var vertices:PackedVector3Array=raw_vertices(mesh);var low_vertices:PackedVector3Array=raw_vertices(low)
		if vertices.is_empty() or vertices.size()%3!=0 or low_vertices.is_empty() or low_vertices.size()%3!=0:far_factory.free();return C.fail("VEGETATION_ASSET_MESH","An original procedural mesh has invalid native triangle buffers.")
		var woody:bool=kind in ["temperate","tropical","sapling","shrub"]
		var bark_count:int=84 if kind=="tropical" else 42 if woody else 0
		var root=PackedVector3Array();var canopy=PackedVector3Array();var solid=PackedVector3Array();var minimum_y:float=INF
		for v in vertices:minimum_y=minf(minimum_y,v.y)
		for i in vertices.size():
			var v:Vector3=vertices[i]
			if woody and i<bark_count:root.append(v)
			elif not woody and absf(v.y-minimum_y)<0.0000001:root.append(v)
			if i>=bark_count:canopy.append(v)
		if kind in ["temperate","tropical","sapling"]:solid=root
		else:solid=vertices
		var full_hull:Array=[];var far_hull:Array=[]
		for v in vertices:full_hull.append(Surface.xz(v))
		for v in low_vertices:far_hull.append(Surface.xz(v))
		# Compare native hulls before outward grid rounding. Far's closing sin(TAU)
		# may carry a tiny nonzero bit; rounding that independently can create an
		# artificial extra grid strip. Admission encloses BOTH buffers once below.
		full_hull=Surface.hull(full_hull);far_hull=Surface.hull(far_hull)
		if absf(Surface.area(full_hull)-Surface.area(far_hull))>0.000001 or absf(Surface.area(Surface.clip(full_hull,far_hull))-Surface.area(full_hull))>0.000001:far_factory.free();return C.fail("VEGETATION_LOD_FOOTPRINT","The reused far mesh does not preserve its original projected footprint: "+kind)
		full[kind]=mesh;far[kind]=low
		var combined:PackedVector3Array=vertices.duplicate();combined.append_array(low_vertices)
		measurements[kind]={"root_projection":unique_xz(root),"solid_projection":unique_xz(solid),"canopy_projection":unique_xz(combined),"full_vertices":vertices,"far_vertices":low_vertices,"root_vertices":root,"solid_vertices":solid,"canopy_vertices":canopy,"minimum_y":minimum_y}
		records[kind]={"id":kind,"habit":"tree" if kind in ["temperate","tropical","sapling"] else "shrub" if kind=="shrub" else "herbaceous","full_sha256":digest_bytes(vertices.to_byte_array()),"far_sha256":digest_bytes(low_vertices.to_byte_array()),"triangles":vertices.size()/3,"far_triangles":low_vertices.size()/3,"visual_bounds":bounds(vertices),"root_bounds":bounds(root),"solid_bounds":bounds(solid),"canopy_bounds":bounds(canopy),"source_minimum_y_q40":int(round(minimum_y*1099511627776.0)),"minimum_y_scale":1099511627776,"same_projected_footprint":true}
	far_factory.free()
	var catalog:Dictionary=C.normalized({"schema_version":ID,"pins":PINS,"assets":records,"license":"Original procedural vegetation CC0-1.0; unchanged project geometry/material"})
	catalog["catalog_hash"]=C.digest(catalog)
	_cached={"ok":true,"catalog":catalog,"full_meshes":full,"far_meshes":far,"measurements":measurements}
	return _cached.duplicate(true)
