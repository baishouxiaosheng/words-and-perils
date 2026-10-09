extends RefCounted
## Isolated physical-river extension of the frozen structured producer.
## Baseline fan/strip/corner construction is MIT-derived, David Pruitt (2024).
## Retained notices: ../ATTRIBUTION.md and ../provenance/upstream/LICENSE.md.txt.
## Only river-cell cores, source-edge strips, mouth receiving fan sectors, and
## explicit crop-outlet strips are replaced. No coastline perturbation occurs.
const VERSION = "v3_structured_rivers_gd/1"
const PROFILE = "structured_rivers_v1"
const Baseline = preload("res://view/generated_v3_runtime/structured_hex_builder.gd")
const Layout = preload("res://core/generated_v3_rivers/layout.gd")

static func build(source: Variant, original: Variant=null) -> Dictionary:
	return Worker.new().run(source,original)

class Worker:
	extends RefCounted
	const WATER_HALF=0.078125
	const BED_HALF=0.0625
	const BANK_HALF=0.109375
	const DEPTH=0.03125
	const FREEBOARD=0.00390625
	const HUB_REACH=0.25
	const MAX_INCISION=0.30
	const MAX_TRIANGLES=65536
	var source: Dictionary
	var base: Dictionary
	var manifest: Dictionary
	var cores: Dictionary={}
	var hub: Dictionary={}
	var rows: Dictionary={}
	var changed_ocean: Dictionary={}
	var ground: Array=[]
	var ground_kinds: Array=[]
	var ground_owners: Array=[]
	var water: Array=[]
	var water_kinds: Array=[]
	var water_owners: Array=[]
	var native_core_ids: Dictionary={}
	var native_fan_faces: Dictionary={}
	var protected_removed_faces: Dictionary={}
	var natural_faces: Dictionary={}
	var failure=""
	var max_incision=0.0
	var min_bank_clearance=INF

	static func error(code: String,message: String)->Dictionary:
		return {"ok":false,"error_code":code,"message":message}
	static func pack(p: Array)->Array:
		var v=Vector3(float(p[0]),float(p[1]),float(p[2]))
		return [float(v.x)+0.0,float(v.y)+0.0,float(v.z)+0.0]
	static func xz(p: Array)->Vector2:
		return Vector2(p[0],p[2])
	static func cross(a: Array,b: Array,c: Array)->float:
		return (b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
	static func interpolate(a: Array,b: Array,t: float)->Array:
		return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t]
	func emit(a: Array,b: Array,c: Array,kind: String,owner: Array,wet: bool=false)->void:
		if not failure.is_empty():return
		var triangle=[pack(a),pack(b),pack(c)]
		var area=cross(triangle[0],triangle[1],triangle[2])
		if absf(area)<0.000000000001:failure="Degenerate triangle in "+kind;return
		if area<0.0:
			var swap=triangle[1];triangle[1]=triangle[2];triangle[2]=swap
		if ground.size()+water.size()>=MAX_TRIANGLES:failure="River geometry exceeds bounded triangle allocation";return
		if wet:water.append(triangle);water_kinds.append(kind);water_owners.append(owner.duplicate())
		else:ground.append(triangle);ground_kinds.append(kind);ground_owners.append(owner.duplicate())
	func quad(a: Array,b: Array,c: Array,d: Array,kind: String,owner: Array,wet: bool=false)->void:
		emit(a,b,c,kind,owner,wet);emit(b,d,c,kind,owner,wet)

	func natural(p: Array,owners: Array)->float:
		# Actual frozen triangle support, not a source-center elevation approximation.
		var candidates: Dictionary={}
		for owner in owners:
			for index in natural_faces.get(owner,[]):candidates[index]=true
		for index in candidates:
			var t: Array=base.triangles[index]
			var den=cross(t[0],t[1],t[2])
			var u=cross(p,t[1],t[2])/den
			var v=cross(t[0],p,t[2])/den
			var w=1.0-u-v
			if minf(u,minf(v,w))>=-0.000003:return u*t[0][1]+v*t[1][1]+w*t[2][1]
		failure="No frozen ground support at "+str(p)+" owners "+str(owners)
		return 0.0

	func native_face_ids(face: int)->Array:
		return [base.indices[face*3],base.indices[face*3+1],base.indices[face*3+2]]

	func native_points(ids: Array)->Array:
		var result: Array=[]
		for id in ids:result.append(base.vertices[id].duplicate())
		return result

	func recover_native_cores()->void:
		# Ordered native fan topology is the authority for every protected core
		# anchor. Never reconstruct an owner from rounded coordinates or heights.
		for key in source.cells:
			var fan: Array=[]
			for face in natural_faces[key]:
				if base.face_kinds[face]=="cell_fan":fan.append(face)
			if fan.size()!=24:failure="Frozen cell fan topology is not six four-face sides at "+key;return
			var core: Array=[];var sides: Array=[];var side_faces: Array=[]
			var center_id: int=base.indices[fan[0]*3]
			for side in range(6):
				var ids: Array=[];var faces: Array=[]
				for j in range(4):
					var face: int=fan[side*4+j];var triangle=native_face_ids(face)
					if triangle[0]!=center_id:failure="Frozen fan changed center ownership at "+key;return
					if j==0:ids.append(triangle[1])
					elif triangle[1]!=ids[-1]:failure="Frozen fan changed ordered boundary ownership at "+key;return
					ids.append(triangle[2]);faces.append(face)
				sides.append(ids);side_faces.append(faces);core.append(base.vertices[ids[0]].duplicate())
			for side in range(6):
				if sides[side][-1]!=sides[(side+1)%6][0]:failure="Frozen core rows do not share their native corner at "+key;return
			native_core_ids[key]=sides;native_fan_faces[key]=side_faces;cores[key]=core

	func recover_native_strip(core_ids: Array,candidates: Array,label: String)->Dictionary:
		# Each frozen quad emits two adjacent faces. Recover its other row by
		# integer vertex incidence, independent of winding or decimal precision.
		var outer: Array=[];var used: Array=[]
		for j in range(4):
			var chosen=-1;var other=-1
			for face in candidates:
				var triangle=native_face_ids(face)
				if core_ids[j] in triangle and core_ids[j+1] in triangle:
					if chosen>=0:failure="Ambiguous native strip ownership at "+label;return {}
					chosen=face
					for id in triangle:
						if id!=core_ids[j] and id!=core_ids[j+1]:other=id
			if chosen<0 or other<0 or not candidates.has(chosen+1):failure="Native strip pair missing at "+label;return {}
			var second=native_face_ids(chosen+1)
			if not core_ids[j+1] in second or not other in second:failure="Native strip pair incidence changed at "+label;return {}
			var next=-1
			for id in second:
				if id!=core_ids[j+1] and id!=other:next=id
			if next<0:failure="Native strip second endpoint missing at "+label;return {}
			if j==0:outer.append(other)
			elif outer[-1]!=other:failure="Native strip row is not shared exactly at "+label;return {}
			outer.append(next);used.append(chosen);used.append(chosen+1)
		return {"ids":outer,"points":native_points(outer),"faces":used}

	func make_row(a: Array,b: Array,owners: Array,name: String,anchor_ids: Array=[])->Dictionary:
		var center=interpolate(a,b,0.5)
		var dx=float(b[0])-float(a[0]);var dz=float(b[2])-float(a[2])
		var length=sqrt(dx*dx+dz*dz)
		var tx=dx/length;var tz=dz/length
		var offsets=[-length*0.5,-length*0.25,-BANK_HALF,-WATER_HALF,-BED_HALF,0.0,BED_HALF,WATER_HALF,BANK_HALF,length*0.25,length*0.5]
		var anchors={0:0,1:1,5:2,9:3,10:4}
		var points: Array=[]
		for i in range(offsets.size()):
			var point: Array
			if anchor_ids.size()==5 and anchors.has(i):
				# Keep exact XYZ, including near-zero components, and do not
				# recompute protected native Y by barycentric sampling.
				point=base.vertices[anchor_ids[anchors[i]]].duplicate()
			else:
				point=pack([center[0]+tx*offsets[i],0.0,center[2]+tz*offsets[i]])
				point[1]=natural(point,owners)
			points.append(pack(point))
		return {"name":name,"natural":points,"ground":[],"water":[],"water_y":0.0,"protected_native_vertex_ids":anchor_ids.duplicate(),"protected_row_indices":[0,1,5,9,10] if anchor_ids.size()==5 else [],"native_anchor_scope":"Natural row XYZ; outer/quarter ground anchors retain XYZ; channel midpoint retains native XZ with excavated Y."}

	func set_row_level(row: Dictionary,level: float,channel: bool=true)->void:
		row.water_y=float(Vector3(0.0,level,0.0).y)
		row.ground=row.natural.duplicate(true)
		if channel:
			for i in [3,7]:row.ground[i][1]=row.water_y
			for i in [4,5,6]:row.ground[i][1]=float(Vector3(0.0,level-DEPTH,0.0).y)
			for i in range(3,8):
				if row.ground[i][1]>row.natural[i][1]+0.000002:failure="Channel would raise existing ground at "+row.name
				max_incision=maxf(max_incision,row.natural[i][1]-row.ground[i][1])
			row.water=[]
			for i in range(3,8):row.water.append(pack([row.ground[i][0],level,row.ground[i][2]]))
		else:row.water=[]
		row["banks"]=[row.ground[2].duplicate(),row.ground[8].duplicate()]
		row["waterline"]=[row.ground[3].duplicate(),row.ground[7].duplicate()]
		row["bed"]=[row.ground[4].duplicate(),row.ground[5].duplicate(),row.ground[6].duplicate()]
		if channel:
			for p in row.banks:min_bank_clearance=minf(min_bank_clearance,p[1]-level)

	func prepare()->void:
		for i in range(base.triangles.size()):
			for owner in base.face_owners[i]:
				if not natural_faces.has(owner):natural_faces[owner]=[]
				natural_faces[owner].append(i)
		recover_native_cores()
		if not failure.is_empty():return
		for key in manifest.nodes:
			var node: Dictionary=manifest.nodes[key];var center: Array=base.center_samples[key].center_xz
			var active: Dictionary={}
			for arm in node.arms:active[arm.side]=true
			var h={"bank":[],"shore":[],"bed":[],"active":active,"center":center}
			for side in range(6):
				var midpoint=interpolate(cores[key][side],cores[key][(side+1)%6],0.5)
				var radial=(xz(midpoint)-Vector2(center[0],center[1])).normalized();var tangent=Vector2(-radial.y,radial.x)
				for polarity in [-1.0,1.0]:
					for pair in [["bank",BANK_HALF],["shore",WATER_HALF],["bed",BED_HALF]]:
						var pos: Vector2
						if active.has(side):pos=Vector2(center[0],center[1])+radial*HUB_REACH+tangent*float(pair[1])*polarity
						else:pos=Vector2(center[0],center[1])+radial.rotated(polarity*PI/9.0)*float(pair[1])
						var point=pack([pos.x,0.0,pos.y]);point[1]=natural(point,[key]);h[pair[0]].append(pack(point))
			hub[key]=h
		# Each port has one canonical owner and three physically distinct rows.
		var port_ids=manifest.ports.keys();port_ids.sort()
		for id in port_ids:
			var port: Dictionary=manifest.ports[id]
			if port.kind=="crop":
				var key: String=port.from;var side: int=port.crop_side
				var core_ids: Array=native_core_ids[key][side]
				var candidates: Array=[]
				for face in natural_faces[key]:
					if base.face_kinds[face]=="full_hex_rim_cap":candidates.append(face)
				var recovered=recover_native_strip(core_ids,candidates,"crop:"+key)
				if not failure.is_empty():return
				for face in recovered.faces:protected_removed_faces[face]=true
				var core_points=native_points(core_ids);var rim: Array=recovered.points
				var core_row=make_row(core_points[0],core_points[4],[key],"core:"+key,core_ids)
				var boundary=make_row(rim[0],rim[4],[key],"crop_boundary:"+key,recovered.ids)
				port.sections=[core_row,boundary];port["canonical_side"]=side
				rows[key+":"+str(side)]=core_row
			else:
				var ka: String=port.canonical_cells[0];var kb: String=port.canonical_cells[1]
				var sa=Layout.edge_index(source.cells[ka],source.cells[kb]);var sb=(sa+3)%6
				var ids_a: Array=native_core_ids[ka][sa].duplicate();var ids_b: Array=native_core_ids[kb][sb].duplicate();ids_b.reverse()
				var points_a=native_points(ids_a);var points_b=native_points(ids_b)
				var a: Array=points_a[0];var b: Array=points_a[4];var c: Array=points_b[0];var d: Array=points_b[4]
				var core_a=make_row(a,b,[ka,kb],"core:"+ka,ids_a)
				var core_b=make_row(c,d,[ka,kb],"core:"+kb,ids_b)
				var pa=interpolate(a,c,0.5);var pb=interpolate(b,d,0.5);var boundary_ids: Array=[]
				if port.kind=="mouth":
					var candidates: Array=[]
					for face in natural_faces[ka]:
						if base.face_kinds[face] in ["mixed_edge_land","mixed_edge_water"] and base.face_owners[face].has(kb):candidates.append(face)
					var recovered=recover_native_strip(ids_a,candidates,"mouth:"+id)
					if not failure.is_empty():return
					boundary_ids=recovered.ids;pa=recovered.points[0];pb=recovered.points[4]
				var boundary=make_row(pa,pb,[ka,kb],"shared_boundary:"+id,boundary_ids)
				if port.kind=="mouth":
					for point in boundary.natural:point[1]=0.0
				port.sections=[core_a,boundary,core_b];port["canonical_side"]=sa
				rows[ka+":"+str(sa)]=core_a
				# Per-cell rows are viewed in that cell's polygon orientation.
				rows[kb+":"+str(sb)]={"canonical":core_b,"reverse":true}
				if port.kind=="mouth":
					var sea: String=port.to;var side=Layout.edge_index(source.cells[sea],source.cells[port.from])
					if not changed_ocean.has(sea):changed_ocean[sea]=[]
					changed_ocean[sea].append(side)
					for face in native_fan_faces[sea][side]:protected_removed_faces[face]=true

	func local_row(key: String,side: int)->Array:
		var row: Dictionary=rows[key+":"+str(side)]
		if row.has("canonical"):
			var result: Array=row.canonical.ground.duplicate();result.reverse();return result
		return row.ground

	func local_water(key: String,side: int)->Array:
		var row: Dictionary=rows[key+":"+str(side)]
		if row.has("canonical"):
			var result: Array=row.canonical.water.duplicate();result.reverse();return result
		return row.water

	func row_bound(row: Dictionary)->float:
		var bound=INF
		for i in range(2,9):bound=minf(bound,row.natural[i][1]-FREEBOARD)
		return maxf(0.0,bound)

	func solve_levels()->void:
		# A local station DAG: hub -> outlet core -> boundary -> receiving core
		# -> receiving hub. A junction receives every incoming core constraint.
		var stations: Dictionary={};var station_edges: Array=[]
		for key in manifest.nodes:
			var bound=float(source.cells[key].elevation)-WATER_HALF
			for family in ["bank","shore","bed"]:
				for p in hub[key][family]:bound=minf(bound,p[1]-FREEBOARD)
			manifest.nodes[key]["bank_supported_upper_bound"]=maxf(0.0,bound)
			stations["hub:"+key]={"kind":"hub","cell":key,"upper_bound":maxf(0.0,bound),"water_y":0.0}
		for id in manifest.ports:
			var port: Dictionary=manifest.ports[id]
			for i in range(port.sections.size()):
				var row: Dictionary=port.sections[i]
				row["station_id"]=id+"/"+str(i)
				row["bank_supported_upper_bound"]=row_bound(row)
				stations[row.station_id]={"kind":row.name,"upper_bound":row.bank_supported_upper_bound,"water_y":0.0}
		for key in manifest.topological_order:
			var node: Dictionary=manifest.nodes[key]
			var level=float(node.bank_supported_upper_bound)
			for arm in node.arms:
				if arm.direction=="in":
					var incoming_row: Dictionary=rows[key+":"+str(arm.side)]
					if incoming_row.has("canonical"):incoming_row=incoming_row.canonical
					level=minf(level,incoming_row.water_y)
			level=float(Vector3(0.0,level,0.0).y)
			node.water_y=level;stations["hub:"+key].water_y=level
			for arm in node.arms:
				if arm.direction!="out":continue
				var port: Dictionary=manifest.ports[arm.port_id]
				var ordered: Array=port.sections.duplicate()
				if port.kind!="crop" and port.canonical_cells[0]!=key:ordered.reverse()
				var previous="hub:"+key
				for i in range(ordered.size()):
					var row: Dictionary=ordered[i]
					var sea_core=port.kind=="mouth" and i==2
					if sea_core:
						set_row_level(row,0.0,false);continue
					level=minf(level,float(row.bank_supported_upper_bound))
					if port.kind=="mouth" and i==1:level=0.0
					set_row_level(row,level)
					stations[row.station_id].water_y=row.water_y
					station_edges.append([previous,row.station_id]);previous=row.station_id
				if port.kind=="connection":station_edges.append([previous,"hub:"+port.to])
		for key in manifest.nodes:
			var level=float(manifest.nodes[key].water_y)
			for i in range(12):
				for family in ["shore","bed"]:
					var target=level if family=="shore" else level-DEPTH
					var p: Array=hub[key][family][i]
					if target>p[1]+0.000002:failure="Hub would raise terrain at "+key
					max_incision=maxf(max_incision,p[1]-target);p[1]=float(Vector3(0.0,target,0.0).y)
				min_bank_clearance=minf(min_bank_clearance,hub[key].bank[i][1]-level)
			max_incision=maxf(max_incision,float(source.cells[key].elevation)-level+DEPTH)
		manifest["stations"]=stations;manifest["station_edges"]=station_edges
		if max_incision>MAX_INCISION:failure="Required channel incision %.9f exceeds explicit %.2f world-unit bound"%[max_incision,MAX_INCISION]
		if min_bank_clearance < -0.000002:failure="River surface overtops final bank support"

	func preserve_baseline()->void:
		for i in range(base.triangles.size()):
			var owner: Array=base.face_owners[i];var kind: String=base.face_kinds[i]
			var replace=protected_removed_faces.has(i)
			if kind=="cell_fan":replace=replace or manifest.nodes.has(owner[0])
			elif kind in ["same_class_edge","mixed_edge_land","mixed_edge_water"]:
				replace=manifest.ports.has(Layout.pair_key(owner[0],owner[1]))
			if not replace:
				ground.append(base.triangles[i].duplicate(true));ground_kinds.append(kind);ground_owners.append(owner.duplicate())

	static func native_delta_area(a: Array,b: Array,c: Array)->float:
		# Mirror the existing consumer's float32 Vector2 differences. A robust
		# local ear must stay positive under both packed-coordinate predicates.
		var ab=Vector2(b[0]-a[0],b[2]-a[2]);var ac=Vector2(c[0]-a[0],c[2]-a[2])
		return ab.x*ac.y-ab.y*ac.x

	func triangulate(points: Array,kind: String,owner: Array)->void:
		# Small simple polygons only. Retain every shared boundary subdivision.
		# Largest valid ear first avoids near-collinear needles caused by taking
		# the first positive ear on a straight bank; ties keep boundary order.
		var remaining: Array=[]
		for i in range(points.size()):remaining.append(i)
		var area=0.0
		for i in range(points.size()):area+=points[i][0]*points[(i+1)%points.size()][2]-points[(i+1)%points.size()][0]*points[i][2]
		if area<0.0:remaining.reverse()
		var guard=0
		while remaining.size()>3:
			var best_index=-1;var best_area=-INF;var best_ids: Array=[]
			for j in range(remaining.size()):
				var ai=remaining[(j+remaining.size()-1)%remaining.size()];var bi=remaining[j];var ci=remaining[(j+1)%remaining.size()]
				var a: Array=points[ai];var b: Array=points[bi];var c: Array=points[ci]
				var ear_area=cross(a,b,c)
				if ear_area<=0.000000000001 or native_delta_area(a,b,c)<=0.00000000000001:continue
				var blocked=false
				for index in remaining:
					if index in [ai,bi,ci]:continue
					var p: Array=points[index]
					if minf(cross(a,b,p),minf(cross(b,c,p),cross(c,a,p)))>=-0.000000000001:blocked=true;break
				if blocked:continue
				if ear_area>best_area:best_area=ear_area;best_index=j;best_ids=[ai,bi,ci]
			guard+=1
			if best_index<0 or guard>128:failure="Local dry-gap polygon has no robust positive triangulation at "+str(owner);return
			emit(points[best_ids[0]],points[best_ids[1]],points[best_ids[2]],kind,owner)
			remaining.remove_at(best_index)
		if remaining.size()==3:
			var a: Array=points[remaining[0]];var b: Array=points[remaining[1]];var c: Array=points[remaining[2]]
			if cross(a,b,c)<=0.000000000001 or native_delta_area(a,b,c)<=0.00000000000001:
				failure="Local dry-gap final face is not robustly positive at "+str(owner);return
			emit(a,b,c,kind,owner)

	func cell_piece(key: String)->void:
		var h: Dictionary=hub[key];var node: Dictionary=manifest.nodes[key]
		var level=float(node.water_y);var center=[h.center[0],level-DEPTH,h.center[1]];var surface=[h.center[0],level,h.center[1]]
		for i in range(12):
			var next=(i+1)%12
			if i%2==0 and h.active.has(int(i/2)):
				var midpoint=pack(interpolate(h.bed[i],h.bed[next],0.5))
				emit(center,h.bed[i],midpoint,"river_bed",[key])
				emit(center,midpoint,h.bed[next],"river_bed",[key])
			else:emit(center,h.bed[i],h.bed[next],"river_bed",[key])
			if not (i%2==0 and h.active.has(int(i/2))):
				quad(h.bed[i],h.bed[next],h.shore[i],h.shore[next],"river_bank_submerged",[key])
			if i%2==0 and h.active.has(int(i/2)):
				var line=[h.shore[i],pack([h.bed[i][0],level,h.bed[i][2]]),pack([0.5*(h.bed[i][0]+h.bed[next][0]),level,0.5*(h.bed[i][2]+h.bed[next][2])]),pack([h.bed[next][0],level,h.bed[next][2]]),h.shore[next]]
				for n in range(4):emit(surface,line[n],line[n+1],"river",[key],true)
			else:emit(surface,h.shore[i],h.shore[next],"river",[key],true)
			if not (i%2==0 and h.active.has(int(i/2))):
				quad(h.shore[i],h.shore[next],h.bank[i],h.bank[next],"river_bank",[key])
		var perimeter: Array=[];var bank_indices: Dictionary={}
		for side in range(6):
			var edge: Array=[]
			if h.active.has(side):edge=local_row(key,side)
			else:
				edge=native_points(native_core_ids[key][side])
			if h.active.has(side):
				bank_indices[side]=[perimeter.size()+2,perimeter.size()+8]
				var a=side*2;var b=a+1
				var hub_row=[h.bank[a],h.shore[a],h.bed[a],pack(interpolate(h.bed[a],h.bed[b],0.5)),h.bed[b],h.shore[b],h.bank[b]]
				for j in range(6):quad(hub_row[j],hub_row[j+1],edge[j+2],edge[j+3],"river_bank" if j in [0,5] else "river_bank_submerged" if j in [1,4] else "river_bed",[key])
				var hub_water: Array=[];var edge_water: Array=local_water(key,side)
				for j in range(1,6):hub_water.append(pack([hub_row[j][0],level,hub_row[j][2]]))
				for j in range(4):quad(hub_water[j],hub_water[j+1],edge_water[j],edge_water[j+1],"river",[key],true)
			for i in range(edge.size()-1):perimeter.append(edge[i])
		for arm_index in range(node.arms.size()):
			var side: int=node.arms[arm_index].side;var next_side: int=node.arms[(arm_index+1)%node.arms.size()].side
			var polygon: Array=[];var index: int=bank_indices[side][1];var end: int=bank_indices[next_side][0]
			polygon.append(perimeter[index]);index=(index+1)%perimeter.size()
			while index!=end:polygon.append(perimeter[index]);index=(index+1)%perimeter.size()
			polygon.append(perimeter[end]);index=next_side*2
			polygon.append(h.bank[index]);index=(index+11)%12
			while index!=side*2+1:polygon.append(h.bank[index]);index=(index+11)%12
			polygon.append(h.bank[index]);triangulate(polygon,"river_dry_gap",[key])

	func strip(a: Dictionary,b: Dictionary,owner: Array,sea: bool=false,kind: String="river",unsplit_outer: bool=false)->void:
		for j in range(10):
			if unsplit_outer and j in [0,9]:continue
			var face_kind="river_sea_mouth_ground" if sea else "river_dry_gap" if j in [0,1,8,9] else "river_bank" if j in [2,7] else "river_bank_submerged" if j in [3,6] else "river_bed"
			quad(a.ground[j],a.ground[j+1],b.ground[j],b.ground[j+1],face_kind,owner)
		if not sea:
			for j in range(4):quad(a.water[j],a.water[j+1],b.water[j],b.water[j+1],kind,owner,true)

	func connections()->void:
		var ids=manifest.ports.keys();ids.sort()
		for id in ids:
			var port: Dictionary=manifest.ports[id];var sections: Array=port.sections
			if port.kind=="crop":strip(sections[0],sections[1],[port.from,id],false,"river")
			else:
				for i in range(2):
					var sea=port.kind=="mouth" and source.cells[port.canonical_cells[0 if i==0 else 1]].ocean
					strip(sections[i],sections[i+1],[port.from,port.to,id],sea,"mouth" if port.kind=="mouth" else "river",port.kind=="connection")
				if port.kind=="connection":
					# The preserved corner has a single A-B edge. Do not introduce
					# an outer midpoint T-junction merely to split the inner channel.
					for pair in [[0,1],[10,9]]:
						var outer: int=pair[0];var inner: int=pair[1]
						var polygon=[sections[0].ground[outer],sections[0].ground[inner],sections[1].ground[inner],sections[2].ground[inner],sections[2].ground[outer]]
						for n in range(1,4):emit(polygon[0],polygon[n],polygon[n+1],"river_dry_gap",[port.from,port.to,id])
					port["outer_strip_seam"]="Unsplit A-core to B-core edge; boundary row dry endpoint indices 0 and 10 are support samples, not mesh vertices."
		for key in changed_ocean:
			var center: Array=base.center_samples[key].center_xz
			var point=[center[0],source.cells[key].elevation,center[1]]
			for side in changed_ocean[key]:
				var edge=local_row(key,side)
				for j in range(edge.size()-1):emit(point,edge[j],edge[j+1],"river_sea_receiving_fan",[key])

	func sea_water()->void:
		for i in range(ground.size()):
			if ground_kinds[i] in ["river_bed","river_bank_submerged"]:continue
			var polygon: Array=[];var triangle: Array=ground[i];var previous: Array=triangle[-1]
			for p in triangle:
				if (previous[1]<=0.0)!=(p[1]<=0.0):polygon.append(pack(interpolate(previous,p,-previous[1]/(p[1]-previous[1]))))
				if p[1]<=0.0:polygon.append(p.duplicate())
				previous=p
			for p in polygon:p[1]=0.0
			for j in range(1,polygon.size()-1):
				if absf(cross(polygon[0],polygon[j],polygon[j+1]))>0.000000000001:emit(polygon[0],polygon[j],polygon[j+1],"sea",ground_owners[i],true)

	func bundle(triangles: Array)->Dictionary:
		var vertices: Array=[];var indices: Array=[];var lookup: Dictionary={}
		var packed=PackedVector3Array();var normals=PackedVector3Array();var flat=PackedVector3Array()
		for triangle in triangles:
			for p in triangle:
				var v=Vector3(p[0],p[1],p[2]);flat.append(v)
				# Exact packed float32 bytes determine welding, never a rounded epsilon key.
				var bytes=PackedVector3Array([v]).to_byte_array().hex_encode()
				if not lookup.has(bytes):lookup[bytes]=vertices.size();vertices.append(pack(p));packed.append(v);normals.append(Vector3.ZERO)
				indices.append(lookup[bytes])
		for i in range(0,indices.size(),3):
			var a=indices[i];var b=indices[i+1];var c=indices[i+2]
			var n=(packed[c]-packed[a]).cross(packed[b]-packed[a])
			normals[a]+=n;normals[b]+=n;normals[c]+=n
		for i in range(normals.size()):normals[i]=normals[i].normalized()
		var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=packed;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(indices)
		var mesh=ArrayMesh.new()
		if not indices.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(flat.to_byte_array())
		return {"mesh":mesh,"vertices":vertices,"indices":indices,"hash":digest.finish().hex_encode()}

	func run(input: Variant,original: Variant)->Dictionary:
		var started=Time.get_ticks_usec()
		if not input is Dictionary:return error("RIVER_SOURCE_TYPE","source must be Dictionary")
		source=input
		var baseline=Baseline.build(source,original)
		if not baseline.ok:return baseline
		base=baseline.data
		var planned=Layout.build(source)
		if not planned.ok:return planned
		manifest=planned.layout
		prepare()
		if not failure.is_empty():return error("RIVER_SUPPORT",failure)
		solve_levels()
		if not failure.is_empty():return error("RIVER_PROFILE",failure)
		preserve_baseline()
		var keys=manifest.nodes.keys();keys.sort()
		for key in keys:cell_piece(key)
		connections()
		if not failure.is_empty():return error("RIVER_CONSTRUCTION",failure)
		sea_water()
		if not failure.is_empty():return error("RIVER_WATER_CONSTRUCTION",failure)
		var g=bundle(ground);var w=bundle(water)
		var data=base.duplicate(false)
		data.schema_version="v3_river_arraymesh/v1";data.geometry_version=VERSION
		data.vertices=g.vertices;data.indices=g.indices;data.triangles=ground
		data.face_kinds=ground_kinds;data.face_owners=ground_owners
		data.water_vertices=w.vertices;data.water_indices=w.indices;data.water_triangles=water
		data.water_face_kinds=water_kinds;data.water_face_owners=water_owners
		data.canonical_geometry_hash=g.hash;data.water_hash=w.hash
		data["hash_encoding"]="SHA256 of expanded triangle-order PackedVector3Array little-endian float32 xyz bytes"
		data["face_classes"]=[]
		for triangle in ground:
			var positive=false;var negative=false
			for p in triangle:positive=positive or p[1]>0.0;negative=negative or p[1]<0.0
			data.face_classes.append("mixed" if positive and negative else "land" if positive else "water" if negative else "zero")
		# The original index pairs refer to a different vertex buffer. Water
		# boundary triangles, not stale sea-only indices, are the new authority.
		data.intended_shore_edges=[]
		data["shore_boundary_authority"]="Actual water triangle union boundary; sea and elevated rivers together"
		var low=[INF,INF,INF];var high=[-INF,-INF,-INF]
		for p in g.vertices:
			for i in range(3):low[i]=minf(low[i],p[i]);high[i]=maxf(high[i],p[i])
		data.bounds={"min":low,"max":high}
		manifest["parameters"]={"water_width":WATER_HALF*2.0,"bank_fringe":BANK_HALF-WATER_HALF,"bed_width":BED_HALF*2.0,"depth":DEPTH,"hub_reach":HUB_REACH,"max_incision":MAX_INCISION,"freeboard_target":FREEBOARD,"shoreline_perturbation":false}
		manifest["native_anchor_baseline_hash"]=base.canonical_geometry_hash
		manifest["surface_hash_fields"]=["version","profile_id","layout_hash","parameters","nodes","ports","stations","station_edges","native_anchor_baseline_hash"]
		var surface_payload: Dictionary={}
		for field in manifest.surface_hash_fields:surface_payload[field]=manifest[field]
		manifest["surface_canonical_json"]=JSON.stringify(surface_payload,"",true,true)
		manifest["surface_profile_hash"]=manifest.surface_canonical_json.sha256_text()
		manifest["surface_hash_encoding"]="SHA256 UTF-8 of surface_canonical_json; JSON parsed value equals the named surface_hash_fields; sorted keys/full_precision=true"
		manifest["geometry_hash"]=g.hash;manifest["water_hash"]=w.hash
		manifest["changed_region"]={"river_cell_cores":keys,"ports":manifest.ports.keys(),"ocean_receiving_sides":changed_ocean,"unchanged":"All other original fans, edge strips, corners and rim caps are retained byte-exact per triangle.","protected_anchor_authority":"Integer vertex incidence in frozen cell-fan and adjacent strip faces; no coordinate matching or height resampling of native anchors."}
		data["river_manifest"]=manifest
		var metrics={"build_ms":(Time.get_ticks_usec()-started)/1000.0,"baseline_ground_triangles":base.triangles.size(),"ground_triangles":ground.size(),"water_triangles":water.size(),"ground_triangle_growth":float(ground.size()-base.triangles.size())/base.triangles.size(),"river_cells":manifest.nodes.size(),"ports":manifest.ports.size(),"junctions":manifest.junctions.size(),"max_incision":max_incision,"minimum_bank_clearance":min_bank_clearance,"river_water_width":WATER_HALF*2.0,"coastline_perturbed":false}
		data.construction={"vertices":g.vertices.size(),"triangles":ground.size(),"build_ms":metrics.build_ms}
		data.parameters=manifest.parameters
		return {"ok":true,"ground_mesh":g.mesh,"water_mesh":w.mesh,"data":data,"geometry_hash":g.hash,"water_hash":w.hash,"river_manifest":manifest,"metrics":metrics}
