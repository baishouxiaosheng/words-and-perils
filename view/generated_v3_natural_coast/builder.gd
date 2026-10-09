extends RefCounted
## Experimental2 native port. Only a frozen structured mesh is deformed.
## No source generation changes, original center/crop movement, or visual shore mask.
const Legacy = preload("res://view/generated_v3_runtime/structured_hex_builder.gd")
const PROFILE = "natural_coast_shared_chain/experimental2"
const RECIPE = "shore_convolution_bounded_noise/float32-chain-v1"
const PARAMS = {"subdivisions":3,"smoothing_radius":0.30,"noise_amplitude":0.065,"noise_wavelength":1.8,"max_displacement":0.105,"minimum_class_area":0.8,"minimum_triangle_fraction":0.08,"minimum_triangle_angle_xz_degrees":2.0,"scales":[1.0,0.5,0.25,0.125]}

static func build(source: Dictionary) -> Dictionary:
	return Worker.new().run(source)

class Worker:
	extends RefCounted
	var failure = ""
	static func key(a: int,b: int) -> String: return "%d,%d" % [mini(a,b),maxi(a,b)]
	static func cross(a: Array,b: Array,c: Array) -> float: return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
	static func xz(p: Array) -> Array: return [p[0],p[2]]
	static func distance(a: Array,b: Array) -> float: return sqrt(pow(a[0]-b[0],2)+pow(a[1]-b[1],2))
	static func round_even(value: float) -> int:
		var low=floor(value);var fraction=value-low
		if fraction>0.5 or (fraction==0.5 and int(low)%2!=0):low+=1.0
		return int(low)
	static func compensated_sum(values: Array) -> float:
		# Match CPython 3.12 sum's compensated finite-float reduction.
		var high=0.0;var low=0.0
		for value in values:
			var next=high+value
			low+=(high-next)+value if absf(high)>=absf(value) else (value-next)+high
			high=next
		return high+low
	static func lerp2(a: Array,b: Array,t: float) -> Array: return [a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]
	static func f32(p: Array) -> Array:
		var v=Vector3(p[0],p[1],p[2]);return [float(v.x)+0.0,float(v.y)+0.0,float(v.z)+0.0]
	static func before(a: Array,b: Array) -> bool:
		for i in range(a.size()):
			if a[i]!=b[i]:return a[i]<b[i]
		return false
	static func polygon_area(p: Array) -> float:
		if p.size()<3:return 0.0
		var sum_=0.0
		for i in range(p.size()):sum_+=p[i][0]*p[(i+1)%p.size()][1]-p[i][1]*p[(i+1)%p.size()][0]
		return absf(sum_)*0.5
	static func min_angle(p: Array) -> float:
		var answer=180.0
		for i in range(3):
			var a=p[i];var b=p[(i+1)%3];var c=p[(i+2)%3]
			var ux=b[0]-a[0];var uz=b[1]-a[1];var vx=c[0]-a[0];var vz=c[1]-a[1]
			var length=sqrt((ux*ux+uz*uz)*(vx*vx+vz*vz))
			if length==0:return 0.0
			answer=minf(answer,rad_to_deg(acos(clampf((ux*vx+uz*vz)/length,-1,1))))
		return answer
	static func clip(poly: Array,convex: Array) -> Array:
		for i in range(convex.size()):
			if poly.is_empty():break
			var a=convex[i];var b=convex[(i+1)%convex.size()];var output=[];var p=poly[-1];var fp=cross(a,b,p)
			for q in poly:
				var fq=cross(a,b,q)
				if (fp>=0)!=(fq>=0):output.append(lerp2(p,q,fp/(fp-fq)))
				if fq>=0:output.append(q)
				p=q;fp=fq
			poly=output
		return poly
	static func wet_polygon(points: Array) -> Array:
		var output=[];var previous=points[-1]
		for p in points:
			if (previous[1]<=0)!=(p[1]<=0):output.append(lerp2(xz(previous),xz(p),-previous[1]/(p[1]-previous[1])))
			if p[1]<=0:output.append(xz(p))
			previous=p
		return output
	static func edge_table(ids: Array) -> Dictionary:
		var edges={}
		for i in range(0,ids.size(),3):
			for j in range(3):
				var a=ids[i+j];var b=ids[i+(j+1)%3];var k=key(a,b)
				if not edges.has(k):edges[k]={"pair":[mini(a,b),maxi(a,b)],"count":0,"sides":{}}
				edges[k].count+=1
		return edges
	func chains(base: Dictionary) -> Array:
		var vertices: Array=base.vertices;var graph={};var unused={};var edges=edge_table(base.indices);var boundary={}
		for e in edges.values():
			if e.count==1:
				boundary[e.pair[0]]=true;boundary[e.pair[1]]=true
			if e.count>2:failure="Nonmanifold input mesh";return []
		for i in range(0,base.indices.size(),3):
			var side="water"
			for j in range(3):
				if vertices[base.indices[i+j]][1]>0:side="land"
			for j in range(3):edges[key(base.indices[i+j],base.indices[i+(j+1)%3])].sides[side]=true
		var actual={}
		for k in edges:
			if edges[k].sides.size()==2:actual[k]=true
		for pair in base.intended_shore_edges:
			var a=int(pair[0]);var b=int(pair[1]);var k=key(a,b)
			if unused.has(k) or not actual.has(k) or vertices[a][1]!=0 or vertices[b][1]!=0:failure="Invalid or duplicate actual shore edge";return []
			unused[k]=[a,b]
			if not graph.has(a):graph[a]=[]
			if not graph.has(b):graph[b]=[]
			graph[a].append(b);graph[b].append(a)
		if unused.size()!=actual.size():failure="Incomplete actual shore graph";return []
		for v in graph:
			if graph[v].size() not in [1,2] or (graph[v].size()==1 and not boundary.has(v)):failure="Invalid shore endpoint or branch";return []
		var result=[]
		while not unused.is_empty():
			var active={};var ends=[]
			for pair in unused.values():active[pair[0]]=true;active[pair[1]]=true
			for v in active:
				if graph[v].size()==1:ends.append(v)
			var candidates=ends if not ends.is_empty() else active.keys()
			candidates.sort_custom(func(a,b):return before(vertices[a],vertices[b]))
			var first=candidates[0];var current=first;var sequence=[first]
			while true:
				var choices=[]
				for n in graph[current]:
					if unused.has(key(current,n)):choices.append(n)
				if choices.is_empty():break
				choices.sort_custom(func(a,b):return before(vertices[a],vertices[b]))
				var next=choices[0];unused.erase(key(current,next));sequence.append(next)
				if next==first:break
				current=next
			result.append(sequence)
		return result
	func refine(base: Dictionary) -> Dictionary:
		var vs: Array=base.vertices.duplicate(true);var splits={};var sorted_edges=[]
		for e in base.intended_shore_edges:sorted_edges.append([mini(e[0],e[1]),maxi(e[0],e[1])])
		sorted_edges.sort_custom(func(a,b):return before(a,b))
		for pair in sorted_edges:
			var a=pair[0];var b=pair[1];var list_=[a]
			for j in range(1,PARAMS.subdivisions):
				var t=float(j)/PARAMS.subdivisions;var p=[]
				for d in range(3):p.append(vs[a][d]+t*(vs[b][d]-vs[a][d]))
				p[1]=0.0;list_.append(vs.size());vs.append(f32(p))
			list_.append(b);splits[key(a,b)]=list_
		var ids=[];var parent_area=[]
		for i in range(0,base.indices.size(),3):
			var t=base.indices.slice(i,i+3);var marked=[]
			var area_=cross(xz(vs[t[0]]),xz(vs[t[1]]),xz(vs[t[2]]))
			for j in range(3):
				if splits.has(key(t[j],t[(j+1)%3])):marked.append([t[j],t[(j+1)%3]])
			if marked.size()>1:failure="Multiple shore edges on a face";return {}
			if marked.is_empty():ids.append_array(t);parent_area.append(area_);continue
			var a=marked[0][0];var b=marked[0][1];var third=-1
			for v in t:
				if v!=a and v!=b:third=v
			var list_: Array=splits[key(a,b)].duplicate()
			if list_[0]!=a:list_.reverse()
			for j in range(list_.size()-1):ids.append_array([list_[j],list_[j+1],third]);parent_area.append(area_)
		return {"vertices":vs,"indices":ids,"splits":splits,"parent_area":parent_area}
	static func sample_line(points: Array,lengths: Array,s: float,closed: bool) -> Array:
		var total=float(lengths[-1]);s=fposmod(s,total) if closed else clampf(s,0,total)
		var i=0
		while i<points.size()-2 and lengths[i+1]<=s:i+=1
		return lerp2(points[i],points[i+1],(s-lengths[i])/(lengths[i+1]-lengths[i]))
	static func phase_bytes(points: Array,token: String) -> PackedByteArray:
		var tb=token.to_utf8_buffer();var bytes=PROFILE.to_utf8_buffer();var count=PackedByteArray();count.resize(4);count.encode_u32(0,tb.size());bytes.append_array(count);bytes.append_array(tb)
		count.encode_u32(0,points.size());bytes.append_array(count)
		var pair=PackedByteArray();pair.resize(8)
		for p in points:pair.encode_float(0,p[0]);pair.encode_float(4,p[1]);bytes.append_array(pair)
		var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(bytes);return hash_.finish()
	static func evaluate(points: Array,lengths: Array,s: float,closed: bool,phase: float,phase2: float) -> Array:
		var radius=float(PARAMS.smoothing_radius);var center=sample_line(points,lengths,s,closed);var smooth=[0.0,0.0];var weights=[1,2,3,4,5,4,3,2,1];var weighted=[[],[]]
		for i in range(9):
			var v=sample_line(points,lengths,s+radius*(-1.0+float(i)*0.25),closed)
			for d in range(2):weighted[d].append(v[d]*weights[i])
		for d in range(2):smooth[d]=compensated_sum(weighted[d])/25.0
		var a=sample_line(points,lengths,s-radius,closed);var b=sample_line(points,lengths,s+radius,closed);var length=distance(a,b);var normal=[0.0,0.0]
		if length>0.000000000001:normal=[-(b[1]-a[1])/length,(b[0]-a[0])/length]
		var cycles=maxf(1.0,round_even(float(lengths[-1])/PARAMS.noise_wavelength)) if closed else float(lengths[-1])/PARAMS.noise_wavelength
		var u=TAU*cycles*s/lengths[-1];var noise=PARAMS.noise_amplitude*(0.72*sin(u+phase)+0.28*sin(2*u+phase2))
		var fade=1.0 if closed else minf(1.0,minf(s/(radius*2),(lengths[-1]-s)/(radius*2)))
		fade=maxf(fade,0.0);fade=fade*fade*(3-2*fade)
		var delta=[(smooth[0]-center[0]+normal[0]*noise)*fade,(smooth[1]-center[1]+normal[1]*noise)*fade];var magnitude=distance(delta,[0.0,0.0])
		var cap=minf(1.0,PARAMS.max_displacement/magnitude) if magnitude>0 else 1.0
		return [delta[0]*cap,delta[1]*cap]
	func movements(base: Dictionary,refined: Dictionary,chains_: Array,token: String) -> Dictionary:
		var moves={}
		for chain in chains_:
			var points=[];var lengths=[0.0]
			for v in chain:points.append(xz(base.vertices[v]))
			for i in range(points.size()-1):lengths.append(lengths[-1]+distance(points[i],points[i+1]))
			var closed=chain[0]==chain[-1];var bytes=phase_bytes(points,token)
			var phase=float(bytes.decode_u32(0))/4294967296.0*TAU;var phase2=float(bytes.decode_u32(4))/4294967296.0*TAU
			for i in range(chain.size()-1):
				var a=chain[i];var b=chain[i+1];var list_: Array=refined.splits[key(a,b)].duplicate()
				if list_[0]!=a:list_.reverse()
				for j in range(list_.size()):
					var s=lengths[i]+(lengths[i+1]-lengths[i])*float(j)/(list_.size()-1);var delta=evaluate(points,lengths,s,closed,phase,phase2);var v=list_[j]
					if moves.has(v) and distance(moves[v],delta)>0.0000001:failure="Shared chain endpoint mismatch";return {}
					moves[v]=delta
		for e in edge_table(base.indices).values():
			if e.count==1:
				for v in e.pair:
					if moves.has(v):moves[v]=[0.0,0.0]
		return moves
	static func area_audit(hexes: Dictionary,vs: Array,ids: Array) -> Dictionary:
		var output={};var minimum=1.0;var maximum_gap=0.0
		var triangles_=[];var bins={}
		for i in range(0,ids.size(),3):
			var points=[vs[ids[i]],vs[ids[i+1]],vs[ids[i+2]]];var face=triangles_.size();triangles_.append(points)
			var lx=floori(minf(points[0][0],minf(points[1][0],points[2][0])));var hx=floori(maxf(points[0][0],maxf(points[1][0],points[2][0])))
			var lz=floori(minf(points[0][2],minf(points[1][2],points[2][2])));var hz=floori(maxf(points[0][2],maxf(points[1][2],points[2][2])))
			for x in range(lx,hx+1):
				for z in range(lz,hz+1):
					var k="%d,%d"%[x,z]
					if not bins.has(k):bins[k]=[]
					bins[k].append(face)
		for k in hexes:
			var poly: Array=hexes[k].polygon;var total=0.0;var wet=0.0
			var lx=poly[0][0];var hx=lx;var lz=poly[0][1];var hz=lz
			for p in poly:lx=minf(lx,p[0]);hx=maxf(hx,p[0]);lz=minf(lz,p[1]);hz=maxf(hz,p[1])
			var candidates={}
			for x in range(floori(lx),floori(hx)+1):
				for z in range(floori(lz),floori(hz)+1):
					for face in bins.get("%d,%d"%[x,z],[]):candidates[face]=true
			var ordered=candidates.keys();ordered.sort()
			for face in ordered:
				var points=triangles_[face];var triangle=[xz(points[0]),xz(points[1]),xz(points[2])]
				if maxf(points[0][0],maxf(points[1][0],points[2][0]))<lx or minf(points[0][0],minf(points[1][0],points[2][0]))>hx or maxf(points[0][2],maxf(points[1][2],points[2][2]))<lz or minf(points[0][2],minf(points[1][2],points[2][2]))>hz:continue
				total+=polygon_area(clip(triangle,poly));wet+=polygon_area(clip(wet_polygon(points),poly))
			var denominator=polygon_area(poly);var fraction=(wet if hexes[k].declared_class=="water" else total-wet)/denominator
			minimum=minf(minimum,fraction);maximum_gap=maxf(maximum_gap,absf(total/denominator-1.0));output[k]={"main_class_fraction":fraction,"coverage":total/denominator,"original_area":denominator}
		return {"per_hex":output,"minimum":minimum,"maximum_coverage_error":maximum_gap}
	func run(source: Dictionary) -> Dictionary:
		var start=Time.get_ticks_usec();var original=Legacy.build(source)
		if not original.get("ok",false):return original
		var base: Dictionary=original.data;var chains_=chains(base)
		if not failure.is_empty():return {"ok":false,"error_code":"COAST_INPUT","message":failure}
		var refined=refine(base)
		if not failure.is_empty():return {"ok":false,"error_code":"COAST_REFINE","message":failure}
		var moves=movements(base,refined,chains_,source.seed_token)
		if not failure.is_empty():return {"ok":false,"error_code":"COAST_CHAIN","message":failure}
		var vs=[];var ids: Array=refined.indices;var accepted=0.0;var attempts=[];var min_fraction=0.0;var min_angle_=0.0;var areas={}
		for scale in PARAMS.scales:
			vs=refined.vertices.duplicate(true)
			for v in moves:vs[v]=f32([vs[v][0]+scale*moves[v][0],vs[v][1],vs[v][2]+scale*moves[v][1]])
			min_fraction=INF;min_angle_=180.0
			for i in range(0,ids.size(),3):
				var triangle=[xz(vs[ids[i]]),xz(vs[ids[i+1]]),xz(vs[ids[i+2]])]
				min_fraction=minf(min_fraction,cross(triangle[0],triangle[1],triangle[2])/refined.parent_area[i/3]);min_angle_=minf(min_angle_,min_angle(triangle))
			if min_fraction<PARAMS.minimum_triangle_fraction or min_angle_<PARAMS.minimum_triangle_angle_xz_degrees:attempts.append({"scale":scale,"reason":"triangle_quality","minimum_parent_fraction":min_fraction,"minimum_angle_xz":min_angle_});continue
			areas=area_audit(base.original_hexes,vs,ids)
			if areas.minimum<PARAMS.minimum_class_area or areas.maximum_coverage_error>0.000002:attempts.append({"scale":scale,"reason":"actual_area","minimum":areas.minimum,"coverage_error":areas.maximum_coverage_error});continue
			accepted=scale;break
		if accepted==0.0:return {"ok":false,"error_code":"COAST_NO_BOUNDED_CANDIDATE","message":"All four bounded attempts were rejected","attempts":attempts}
		var packed=PackedVector3Array();var normals=PackedVector3Array()
		for v in vs:packed.append(Vector3(v[0],v[1],v[2]));normals.append(Vector3.ZERO)
		var expanded=PackedVector3Array();var triangles_=[]
		for i in range(0,ids.size(),3):
			var a=ids[i];var b=ids[i+1];var c=ids[i+2];var n=(packed[c]-packed[a]).cross(packed[b]-packed[a]);normals[a]+=n;normals[b]+=n;normals[c]+=n
			expanded.append(packed[a]);expanded.append(packed[b]);expanded.append(packed[c]);triangles_.append([vs[a],vs[b],vs[c]])
		for i in range(normals.size()):normals[i]=normals[i].normalized()
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=packed;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(ids)
		var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256);hash_.update(expanded.to_byte_array());var geometry_hash=hash_.finish().hex_encode()
		var shore=[]
		for list_ in refined.splits.values():
			for i in range(list_.size()-1):shore.append([list_[i],list_[i+1]])
		var data=base.duplicate(true);data.geometry_version=PROFILE;data.canonical_geometry_hash=geometry_hash;data.vertices=vs;data.indices=ids;data.triangles=triangles_;data.intended_shore_edges=shore
		data.erase("face_kinds");data.erase("face_owners");data.erase("face_classes")
		data.parameters=PARAMS.duplicate(true);data["coast_recipe"]=RECIPE;data["upstream_geometry_hash"]=base.canonical_geometry_hash
		data.construction={"vertices":vs.size(),"triangles":ids.size()/3,"build_ms":(Time.get_ticks_usec()-start)/1000.0,"accepted_scale":accepted,"attempts":attempts,"minimum_parent_area_fraction":min_fraction,"minimum_triangle_angle_xz_degrees":min_angle_}
		data["area_audit"]=areas;data.scope={"production_default":false,"gameplay_admitted":false,"native_candidate":true,"rivers_rendered":false}
		return {"ok":true,"mesh":mesh,"data":data}
