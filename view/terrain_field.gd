extends RefCounted
## Deterministic visual field only. No movement, cost, or GM decisions live here.
## Adjacent hexes sample the same world-space function, so shared edges agree.
const Generator = preload("res://core/world_generator.gd")
const Profiles = preload("res://view/terrain_profiles.gd")
const ChannelIndex = preload("res://view/channel_index.gd")
const DIRS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]
const WATER_Y := -0.14
const BED_Y := -0.38
const LAND_Y := 0.14
const SUBDIVISIONS := 10
var tiles: Dictionary
var channels: Array[Dictionary] = []
var river_nodes: Dictionary = {}
var peaks: Array[Dictionary] = []
var ridges: Array[Dictionary] = []
var vertex_cache: Dictionary = {}
var triangle_count := 0
var shared_vertex_count := 0
var generated := false
var biomes_v2:=false
var height_field
var generated_world: Dictionary = {}
var query_cache: Dictionary = {}
var channel_index=ChannelIndex.new()
const MAX_LANDSCAPE_CACHE:=200000
var landscape_cache:Dictionary={}
var landscape_cache_hits:=0
var landscape_cache_misses:=0

static func key(h: Vector2i) -> String:
	return "%d,%d" % [h.x,h.y]

static func center(h: Vector2i) -> Vector3:
	return Vector3(sqrt(3.0)*(h.x+h.y*0.5),0,1.5*h.y)

static func corner(i: int) -> Vector3:
	var a := float(i)*PI/3.0+PI/6.0
	return Vector3(cos(a),0,sin(a))

func configure(source: Dictionary, metadata: Dictionary = {}) -> bool:
	tiles=source;biomes_v2=false
	channels.clear();river_nodes.clear();peaks.clear();ridges.clear();vertex_cache.clear()
	generated=metadata.get("generator_version","") in ["macro_hex_v1","macro_hex_biomes_v2"] and metadata.get("seed") is int and metadata.get("hexes") is Dictionary
	generated_world=metadata
	query_cache.clear();landscape_cache.clear();landscape_cache_hits=0;landscape_cache_misses=0
	channel_index.configure([])
	if metadata.has("generator_version") and metadata.generator_version not in ["macro_hex_v1","macro_hex_biomes_v2"]:
		tiles={};generated=false;height_field=null;return false
	if generated:
		height_field=Generator.create_height_field(int(metadata.seed),int(metadata.board_radius))
		if not height_field.configure_visual_world(metadata):
			tiles={};generated=false;height_field=null;return false
		biomes_v2=metadata.generator_version=="macro_hex_biomes_v2"
		height_field.sample_visual_height(Vector3.ZERO)
	channels.clear();river_nodes.clear();peaks.clear();ridges.clear();vertex_cache.clear()
	if generated:
		for edge in metadata.get("river_edges",[]):
			var from=Vector2i(edge.from_hex[0],edge.from_hex[1])
			var to=Vector2i(edge.to_hex[0],edge.to_hex[1])
			river_nodes[key(from)]=from
			river_nodes[key(to)]=to
			var a=center(from);var b=center(to)
			a.y=float(edge.from_elevation)+0.025
			b.y=float(edge.to_elevation)+0.025
			var from_cell:Dictionary=metadata.hexes.get(String(edge.get("from",key(from))),{})
			var to_cell:Dictionary=metadata.hexes.get(String(edge.get("to",key(to))),{})
			var prior=from_cell.get("river_from",[])
			var head=prior is Array and prior.is_empty()
			var from_width=float(edge.width)*(0.25 if head else 1.0)
			var downstream_width=to_cell.get("river_width",0.0)
			var width_valid=(downstream_width is int or downstream_width is float) and is_finite(float(downstream_width)) and float(downstream_width)>=0.0
			var to_width=maxf(float(edge.width),float(downstream_width) if width_valid else 0.0)
			if edge.get("mouth") is bool and edge.mouth:to_width*=1.45
			channels.append({"a":a,"b":b,"width":float(edge.width),"from_width":from_width,"to_width":to_width,"mouth":edge.get("mouth",false) if edge.get("mouth",false) is bool else false})
		# A bounded map is a cutaway, not a dam. Known boundary outlets
		# continue visibly to the cut edge rather than ending as closed pools.
		for cell_key in metadata.hexes:
			var cell:Dictionary=metadata.hexes[cell_key]
			if cell.get("river_outlet","")!="board_boundary":continue
			var h=Vector2i(cell.q,cell.r)
			var outward=Vector3.ZERO;var lowest=INF
			for direction in DIRS:
				if tiles.has(key(h+direction)):continue
				var point=center(h)+center(direction).normalized()*1.10
				var value=float(height_field.sample_visual_height(point))
				if value<lowest:lowest=value;outward=point
			if outward==Vector3.ZERO:continue
			var surface=cell.get("river_surface",float(cell.elevation)+0.015)
			if not (surface is int or surface is float) or not is_finite(float(surface)):surface=float(cell.elevation)+0.015
			var width=cell.get("river_width",0.20)
			if not (width is int or width is float) or not is_finite(float(width)) or float(width)<=0:width=0.20
			var a=center(h);a.y=float(surface)+0.025
			outward.y=minf(a.y,lowest+0.04)
			channels.append({"a":a,"b":outward,"width":float(width),"from_width":float(width),"to_width":float(width),"outlet_extension":true})
		channel_index.configure(channels)
		return true
	for tile in tiles.values():
		if tile.terrain in ["river","bridge"]: river_nodes[key(tile.hex)]=tile.hex
	# A fortification between opposite river cells is drawn as a water gate.
	# The semantic cell remains wall; this only preserves the visible channel.
	for tile in tiles.values():
		if tile.terrain != "wall": continue
		for i in range(3):
			if river_nodes.has(key(tile.hex+DIRS[i])) and river_nodes.has(key(tile.hex+DIRS[i+3])):
				river_nodes[key(tile.hex)]=tile.hex
	for h in river_nodes.values():
		var neighbors: Array[Vector2i]=[]
		for d in DIRS:
			if river_nodes.has(key(h+d)): neighbors.append(h+d)
		for next in neighbors:
			if key(h)>key(next): continue
			_add_channel(_river_center(h),_river_center(next))
		if neighbors.size()==1:
			var outward: Vector2i=h-neighbors[0]
			if not tiles.has(key(h+outward)):
				_add_channel(_river_center(h),_river_center(h)+center(outward).normalized()*1.15)
		elif neighbors.is_empty():
			_add_channel(_river_center(h)-Vector3(0.22,0,0),_river_center(h)+Vector3(0.22,0,0))
	channel_index.configure(channels)
	for tile in tiles.values():
		if tile.terrain != "mountain": continue
		var p: Vector3=center(tile.hex)
		var seed: float=float(tile.hex.x*13+tile.hex.y*29)
		p+=Vector3(sin(seed)*0.27,0,cos(seed*1.7)*0.23)
		peaks.append({"p":p,"height":1.45+0.65*(0.5+0.5*sin(seed*0.73)),"radius":2.02+0.15*cos(seed)})
	for i in range(peaks.size()):
		for j in range(i+1,peaks.size()):
			if peaks[i].p.distance_to(peaks[j].p)<2.3:
				ridges.append({"a":peaks[i].p,"b":peaks[j].p,"height":minf(peaks[i].height,peaks[j].height)*0.72})

	return true

func _river_center(h: Vector2i) -> Vector3:
	var p: Vector3=center(h)
	return p+Vector3(0.18*sin(p.z*0.72),0,0.07*cos(p.z*1.7))

func _add_channel(a: Vector3,b: Vector3) -> void:
	var side := Vector3(-(b-a).z,0,(b-a).x).normalized()
	var previous := a
	for i in range(1,7):
		var t := float(i)/6.0
		var point := a.lerp(b,t)+side*sin(t*PI)*0.075*sin((a.x+b.z)*1.4)
		channels.append({"a":previous,"b":point})
		previous=point

static func distance_segment(p: Vector3,a: Vector3,b: Vector3) -> float:
	var delta := b-a
	var t := clampf((p-a).dot(delta)/delta.length_squared(),0.0,1.0)
	return (p-a-delta*t).length()

func channel_sample(p: Vector3) -> Dictionary:
	var cache_key := "%d:%d" % [roundi(p.x*100000),roundi(p.z*100000)]
	if query_cache.has(cache_key): return query_cache[cache_key]
	var nearest:Dictionary=channel_index.nearest(Vector2(p.x,p.z))
	query_cache[cache_key]=nearest
	return nearest

func water_height(p: Vector3) -> float:
	if not generated: return WATER_Y
	var sample=channel_sample(p)
	if float(sample.distance)<float(sample.width)+0.38: return maxf(0.04,float(sample.height))
	return 0.04

func river_distance(p: Vector3) -> float:
	return float(channel_sample(p).distance)

func bank_width(p: Vector3) -> float:
	if generated:return float(channel_sample(p).width)
	return 0.34+0.030*sin(p.z*1.13+p.x*0.37)+0.016*cos(p.z*2.07)

func bank_shoulder(p: Vector3) -> float:
	if biomes_v2:return clampf(bank_width(p)*1.15,0.065,0.25)
	return 0.32 if generated else 0.40+0.045*sin(p.z*0.71-p.x*0.50)

func bank_mask(p: Vector3) -> float:
	var d=river_distance(p);var width=bank_width(p)
	return 1.0-smoothstep(width+bank_shoulder(p)*0.64,width+bank_shoulder(p),d)

func _landscape_sample(p:Vector3)->Dictionary:
	# A finer key than the existing shared-vertex key bounds geometric error.
	var x=roundi(p.x*1000000.0);var z=roundi(p.z*1000000.0)
	var key_=(x<<32) ^ (z & 0xffffffff)
	if landscape_cache.has(key_):
		landscape_cache_hits+=1;return landscape_cache[key_]
	landscape_cache_misses+=1
	var sample:Dictionary=height_field.sample_visual_landscape(p)
	if landscape_cache.size()<MAX_LANDSCAPE_CACHE:landscape_cache[key_]=sample
	return sample

func mountain_height(p: Vector3) -> float:
	if generated: return maxf(0.0,float(_landscape_sample(p).uplift))
	p.y=0.0
	var h := 0.0
	for peak in peaks:
		var distance: float=p.distance_to(peak.p)
		var v := maxf(0.0,1.0-distance/float(peak.radius))
		h=maxf(h,pow(v,1.40)*float(peak.height))
	for ridge in ridges:
		var d := distance_segment(p,ridge.a,ridge.b)
		h=maxf(h,maxf(0.0,1.0-d/1.18)*float(ridge.height))
	# World-space creases cross cell boundaries instead of repeating tile cones.
	var fold := sin(p.x*6.1+p.z*3.0)*sin(p.z*5.3-p.x*1.4)
	return maxf(0.0,h+(fold*0.070+sin(p.x*13.0+p.z*8.1)*0.028)*smoothstep(0.08,0.5,h))

func land_height(p: Vector3) -> float:
	if generated:
		var macro_height:float=float(_landscape_sample(p).elevation)
		# Banks rise inland, while the actual ocean floor stays below sea level.
		# This avoids a board-wide +14cm offset exposing false brown coastal land.
		var base:float=macro_height+smoothstep(-0.05,0.20,macro_height)*LAND_Y
		var sample=channel_sample(p)
		var width=float(sample.width)
		var distance=float(sample.distance)
		var shoulder=bank_shoulder(p)
		if distance<width+shoulder:
			var bed=float(sample.height)-0.20
			var raised_bank=maxf(base,float(sample.height)+0.12)
			# A sea mouth has no raised terminal berm. Fade the engineered bank
			# back into the actual macro coastline as the river reaches the sea.
			if sample.get("mouth",false):
				raised_bank=lerpf(raised_bank,base,smoothstep(0.30,1.0,float(sample.get("t",0.0))))
			var profile=Profiles.bank_height(distance,width,bed,float(sample.height),base if biomes_v2 else raised_bank,shoulder)
			# V2 channels incise the stored landscape. They never build a berm
			# above adjacent canonical land or lift sea-floor into coastal fingers.
			base=minf(base,profile) if biomes_v2 else profile
		return base
	var m := mountain_height(p)
	var ground := LAND_Y+sin(p.x*1.8+p.z*0.5)*0.023+cos(p.z*2.1-p.x*0.7)*0.019+m
	var d := river_distance(p)
	var width=bank_width(p);var shoulder=bank_shoulder(p)
	if d<width+shoulder:
		ground=Profiles.bank_height(d,width,BED_Y,WATER_Y,ground,shoulder)
	return ground

func surface_height(p: Vector3) -> float:
	return maxf(water_height(p),land_height(p))

func support_height(h: Vector2i) -> float:
	var p := center(h)
	var result := surface_height(p)
	if tiles.has(key(h)) and (tiles[key(h)].terrain=="bridge" or tiles[key(h)].get("raw",{}).get("bridge",false)):
		result=water_height(p)+0.35 if generated else 0.33
	return result

func biome_appearance(p:Vector3)->Dictionary:
	var sample:Dictionary=_landscape_sample(p)
	var moisture=float(sample.moisture);var temperature=float(sample.temperature)
	var soil=(1.0-smoothstep(0.27,0.35,moisture))*smoothstep(0.46,0.52,temperature)
	var jungle=smoothstep(0.63,0.72,moisture)*smoothstep(0.52,0.60,temperature)
	var palette=Color("749b50").lerp(Color("c9ad7b"),soil).lerp(Color("3f7754"),jungle)
	var rock=1.0 if sample.biome=="alpine" else 0.0
	# Plateau cap is neither inferred rock nor a separately fabricated hill.
	# Its own biome controls the cap; the shader exposes its actual steep scarp.
	if sample.landform=="plateau" and sample.biome!="alpine":rock=0.0
	return {"palette":palette,"weights":Vector2(soil,rock),"biome":sample.biome,"landform":sample.landform}

func ground_color(p: Vector3,h: float,terrain: String) -> Color:
	if biomes_v2:return biome_appearance(p).palette
	var variation := 0.5+0.5*sin(p.x*2.7+cos(p.z*2.1))*cos(p.z*3.4)
	var color := Color("849965").lerp(Color("a6b578"),variation*0.14)
	if terrain=="swamp": color=color.lerp(Color("5b7868"),0.48)
	if terrain=="forest": color=color.lerp(Color("5e7952"),0.28)
	if terrain=="ocean": color=Color("a79a78")
	var m := mountain_height(p)
	if m>0.17:
		color=color.lerp(Color("89928b"),smoothstep(0.17,0.62,m))
		color=color.lerp(Color("626f73"),0.15+0.12*sin(p.x*4.0+p.z*3.0))
		if m>1.37: color=color.lerp(Color("cbd3c9"),smoothstep(1.37,1.9,m)*0.85)
	var river_d := river_distance(p)
	if river_d<0.68:
		var shore := 1.0-smoothstep(0.39,0.66,river_d)
		color=color.lerp(Color("b4a17d"),shore)
		if h<water_height(p)+0.06: color=color.lerp(Color("536f69"),0.70)
	return color

func _sample(p: Vector3,terrain: String) -> Dictionary:
	var cache_key := "%d:%d" % [roundi(p.x*100000),roundi(p.z*100000)]
	if vertex_cache.has(cache_key):
		shared_vertex_count+=1
		return vertex_cache[cache_key]
	p.y=land_height(p)
	var sample := {"p":p,"c":ground_color(p,p.y,terrain).srgb_to_linear(),"bank":bank_mask(p)}
	# land_height established the existing nearest-channel cache entry first.
	# Reuse this exact shared vertex water value, never interpolate a new curve.
	sample["water"]=water_height(p)
	if biomes_v2:sample["uv2"]=biome_appearance(p).weights
	vertex_cache[cache_key]=sample
	return sample

func build_meshes() -> Dictionary:
	triangle_count=0;shared_vertex_count=0
	var land := SurfaceTool.new();land.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bank := SurfaceTool.new();bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water := SurfaceTool.new();water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt := SurfaceTool.new();skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tile in tiles.values():
		var subdivisions := 12 if generated and tile.get("raw",{}).get("river",false) else (6 if generated else SUBDIVISIONS)
		var c := center(tile.hex)
		for edge in range(6):
			var a := corner(edge)
			var b := corner(edge+1)
			for u in range(subdivisions):
				for v in range(subdivisions-u):
					var p := c+(a*u+b*v)/subdivisions
					var pa := p+a/subdivisions
					var pb := p+b/subdivisions
					_triangle(land,bank,water,p,pb,pa,tile.terrain)
					if u+v<subdivisions-1:
						_triangle(land,bank,water,pa,pb,p+(a+b)/subdivisions,tile.terrain)
			# Corner edge e faces direction 5-e, modulo six.
			var neighbor: Vector2i=tile.hex+DIRS[posmod(5-edge,6)]
			if not tiles.has(key(neighbor)):
				for step in range(subdivisions):
					var x := c+a.lerp(b,float(step)/subdivisions)
					var y := c+a.lerp(b,float(step+1)/subdivisions)
					x.y=land_height(x);y.y=land_height(y)
					var bottom_x := Vector3(x.x,-0.78,x.z)
					var bottom_y := Vector3(y.x,-0.78,y.z)
					for point in [x,y,bottom_x,y,bottom_y,bottom_x]:
						skirt.set_color((Color("889276") if point.y> -0.50 else Color("6c795f")).srgb_to_linear());skirt.add_vertex(point)
	land.generate_normals();bank.generate_normals();water.generate_normals();skirt.generate_normals()
	return {"land":land.commit(),"bank":bank.commit(),"water":water.commit(),"skirt":skirt.commit()}

func _triangle(land: SurfaceTool,bank: SurfaceTool,water: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,terrain: String) -> void:
	var samples := [_sample(a,terrain),_sample(b,terrain),_sample(c,terrain)]
	# Rocky upper slopes keep deliberate triangular planes, while the banks
	# and low ground stay smooth. This changes normals, not shared heights.
	var rocky := maxf(samples[0].p.y, maxf(samples[1].p.y, samples[2].p.y)) > 0.48
	# Cut both materials at the same interpolated scalar contour. Assigning
	# whole triangles creates a regular sawtooth silhouette at game zoom.
	_emit_ground_polygon(land,_clip_ground(samples,false),false,rocky)
	_emit_ground_polygon(bank,_clip_ground(samples,true),true,rocky)
	triangle_count+=1
	var polygon: Array[Vector3]=[]
	for i in range(3):
		var p: Vector3=samples[i].p
		var q: Vector3=samples[(i+1)%3].p
		var p_water:float=samples[i].water
		var q_water:float=samples[(i+1)%3].water
		if p.y<p_water: polygon.append(Vector3(p.x,p_water,p.z))
		if (p.y<p_water)!=(q.y<q_water):
			var t := (p_water-p.y)/((q.y-q_water)-(p.y-p_water))
			polygon.append(Vector3(lerpf(p.x,q.x,t),lerpf(p_water,q_water,t),lerpf(p.z,q.z,t)))
	for i in range(1,polygon.size()-1):
		for p in [polygon[0],polygon[i],polygon[i+1]]:
			var color:=Color("397c88").lerp(Color("75a6a5"),clampf(river_distance(p)/0.38,0.0,1.0)*0.35)
			water.set_color(color.srgb_to_linear())
			water.set_uv(Vector2(p.x,p.z));water.add_vertex(p)

func _clip_ground(samples:Array,inside:bool)->Array:
	var result:Array=[]
	for i in range(samples.size()):
		var p:Dictionary=samples[i];var q:Dictionary=samples[(i+1)%samples.size()]
		var p_in=float(p.bank)>=0.20;var q_in=float(q.bank)>=0.20
		if p_in==inside:result.append(p)
		if p_in!=q_in:
			var t=(0.20-float(p.bank))/(float(q.bank)-float(p.bank))
			var sample={"p":p.p.lerp(q.p,t),"c":p.c.lerp(q.c,t),"bank":0.20}
			if biomes_v2:sample["uv2"]=p.uv2.lerp(q.uv2,t)
			result.append(sample)
	return result

func _emit_ground_polygon(surface:SurfaceTool,polygon:Array,is_bank:bool,rocky:bool)->void:
	surface.set_smooth_group(-1 if rocky else 0)
	for i in range(1,polygon.size()-1):
		for sample in [polygon[0],polygon[i],polygon[i+1]]:
			var color:Color=sample.c
			if is_bank:
				var level=water_height(sample.p)
				var wetness=1.0-smoothstep(level+0.005,level+0.105,sample.p.y)
				color=Color("aea284").lerp(Color("5e6f64"),wetness*0.64).srgb_to_linear()
			if biomes_v2 and not is_bank:surface.set_uv2(sample.uv2)
			surface.set_color(color);surface.add_vertex(sample.p)
