extends RefCounted
## Isolated source-only prototype. No gameplay, legacy source, or renderer admission.
## Design references and license boundaries: README.md in this directory.
const ID = "coastal_source_v3/prototype1"
const RECIPE_VERSION = "coastal_recipes/v2_tiny_remnant_cleanup"
const Cleanup = preload("res://core/world_generation_v3/tiny_remnant_cleanup.gd")
const CLIMATE_VERSION = "hex_water_cycle/v1"
const NORMALIZATION = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const DIRS = [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]
const RECIPES = ["coastal_range", "plateau_hinterland"]
const EDGE_LENGTH = 1.7320508075688772
const MAX_EDGE_SLOPE = 0.55
const EPSILON = 1.0 / 1024.0
const QUANTUM = 1.0 / 4096.0
const CLIMATE_CYCLES = 48
var cells: Dictionary = {}
var keys: Array = []
var neighbors: Dictionary = {}
var seed: int
var radius: int
var recipe: Dictionary = {}
var axis: Vector2
var tangent: Vector2
var noise: FastNoiseLite

static func generate(seed_value: Variant, extent: Variant = 12, recipe_id: String = "coastal_range") -> Dictionary:
	if not extent is int or extent < 4 or extent > 24: return {"ok":false,"code":"V3_RADIUS"}
	if not recipe_id in RECIPES: return {"ok":false,"code":"V3_RECIPE"}
	var normalized: Dictionary = NORMALIZATION.normalize_seed(seed_value)
	if not normalized.ok: return normalized
	var worker = new()
	return worker._generate(normalized, extent, recipe_id)

static func key(h: Vector2i) -> String: return "%d,%d" % [h.x,h.y]
static func center(h: Vector2i) -> Vector2: return Vector2(EDGE_LENGTH * (h.x + h.y * 0.5), 1.5 * h.y)
static func distance(h: Vector2i) -> int: return maxi(absi(h.x),maxi(absi(h.y),absi(h.x+h.y)))
static func domain_seed(world_seed: int, domain: String) -> int:
	return int(C.digest([ID,world_seed,domain]).substr(0,8).hex_to_int() % 2147483647)

func _generate(normalized: Dictionary, extent: int, recipe_id: String) -> Dictionary:
	seed = normalized.normalized_seed; radius = extent
	_configure(recipe_id)
	recipe = _quantize(recipe)
	axis = Vector2(recipe.coast_axis[0],recipe.coast_axis[1])
	tangent = Vector2(-axis.y,axis.x)
	_sample()
	# This new recipe authors a cleaned source before every dependent stage.
	# raw_elevation remains the original sample for exact change provenance.
	var cleanup: Dictionary = Cleanup.apply_to_sampled_cells(cells,keys)
	var lowered: int = _limit_slopes()
	var order: Array = _drain()
	for k in keys:
		cells[k].elevation = snappedf(float(cells[k].elevation),QUANTUM)
		cells[k].fill_depth = snappedf(float(cells[k].fill_depth),QUANTUM)
	var climate: Dictionary = climate_for_cells(cells, keys, neighbors, Vector2(recipe.wind[0],recipe.wind[1]), float(recipe.temperature_base), Vector2(recipe.latitude_axis[0],recipe.latitude_axis[1]), float(recipe.latitude_gradient), float(radius)*EDGE_LENGTH, float(recipe.elevation_lapse))
	for k in keys:
		cells[k].temperature = climate[k].temperature
		cells[k].moisture = climate[k].moisture
		cells[k].rainfall = climate[k].rainfall
		cells[k].air_humidity = climate[k].air_humidity
		cells[k].flow = 0.0 if cells[k].ocean else 0.02 + float(climate[k].rainfall)
	order.reverse()
	for k in order:
		var next: String = cells[k].flow_to
		if not next.is_empty(): cells[next].flow += cells[k].flow
	var mean_rain = 0.0
	var land_count = 0
	for k in keys:
		if not cells[k].ocean: mean_rain += cells[k].rainfall; land_count += 1
	mean_rain /= maxf(1.0,float(land_count))
	var river_threshold: float = maxf(0.025,(mean_rain+0.02)*maxf(4.0,radius*0.72))
	var rivers: Array = []
	for k in keys:
		var cell: Dictionary = cells[k]
		cell.biome = biome(float(cell.elevation),float(cell.temperature),float(cell.moisture))
		cell.river = not cell.ocean and cell.flow >= river_threshold
		if cell.river and not String(cell.flow_to).is_empty():
			rivers.append({"from":k,"to":cell.flow_to,"flow":cell.flow,"surface_from":cell.elevation,"surface_to":cells[cell.flow_to].elevation})
	var world: Dictionary = _quantize({"schema_version":ID,"recipe_version":RECIPE_VERSION,"climate_version":CLIMATE_VERSION,"seed_token":normalized.seed_token,"seed":seed,"normalization_version":normalized.normalization_version,"board_radius":radius,"recipe":recipe,"cells":cells,"river_edges":rivers,"config":{"edge_length":EDGE_LENGTH,"max_edge_slope":MAX_EDGE_SLOPE,"edge_slope_tolerance":EPSILON,"flow_epsilon":EPSILON,"climate_cycles":CLIMATE_CYCLES,"river_threshold":river_threshold},"scope":{"source_only":true,"gameplay_admitted":false,"visual_quality_checked":false,"shore_area_checked":false,"natural_river_curves":false,"beach_geometry":false}})
	# Classification is derived from the persisted, quantized numbers, so a
	# threshold-adjacent cell cannot change biome merely by round-tripping JSON.
	world.river_edges = []
	for k in world.cells:
		var cell: Dictionary = world.cells[k]
		cell.biome = biome(float(cell.elevation),float(cell.temperature),float(cell.moisture))
		cell.river = not cell.ocean and float(cell.flow)>=float(world.config.river_threshold)
		if cell.river and not String(cell.flow_to).is_empty():
			world.river_edges.append({"from":k,"to":cell.flow_to,"flow":cell.flow,"surface_from":cell.elevation,"surface_to":world.cells[cell.flow_to].elevation})
	world["source_cleanup"] = cleanup
	# Invariant decisions use unrounded values inside diagnose. Persist diagnostics
	# on the same proven binary quantum as cell fields for exact native JSON reload.
	world["diagnostics"] = _quantize(diagnose(world))
	world.diagnostics["slope_limited_cells"] = lowered
	world["content_hash"] = C.digest(world)
	if not world.diagnostics.errors.is_empty(): return {"ok":false,"code":"V3_INVARIANT","diagnostics":world.diagnostics,"source":{}}
	return {"ok":true,"source":world}

func _configure(recipe_id: String) -> void:
	var rng = RandomNumberGenerator.new(); rng.seed = domain_seed(seed, "recipe/"+recipe_id)
	var angle = rng.randf_range(-PI,PI)
	axis = Vector2(cos(angle),sin(angle)); tangent = Vector2(-axis.y,axis.x)
	noise = FastNoiseLite.new(); noise.seed = domain_seed(seed,"continental")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.frequency = 2.2; noise.fractal_octaves = 3
	var relief_scale = 0.75 + 0.033 * radius
	var spines: Array = []
	var inland = 0.23 if recipe_id == "coastal_range" else 0.55
	var tilt = rng.randf_range(-0.55,0.55)
	var spine_axis = tangent.rotated(tilt)
	var offset = axis * (inland+rng.randf_range(-0.07,0.07)) + tangent*rng.randf_range(-0.16,0.16)
	var points: Array = []
	var phase = rng.randf_range(-PI,PI)
	for index in range(7):
		var t = (float(index)/6.0-0.5)*1.30
		var p = offset + spine_axis*t + axis*(sin(t*5.0+phase)*0.075)
		points.append([p.x,p.y])
	spines.append({"id":"main_range","points":points,"width":rng.randf_range(0.15,0.23),"uplift":(1.9 if recipe_id=="coastal_range" else 1.15)*relief_scale,"phase":phase})
	if radius >= 8:
		for branch in range(2):
			var origin = Vector2(points[2+branch*2][0],points[2+branch*2][1])
			var end = origin + axis.rotated(rng.randf_range(-0.55,0.55))*(0.22 if branch==0 else -0.20)
			var middle = origin.lerp(end,0.55)+tangent*rng.randf_range(-0.07,0.07)
			spines.append({"id":"spur_%d"%branch,"points":[[origin.x,origin.y],[middle.x,middle.y],[end.x,end.y]],"width":0.11,"uplift":1.1*relief_scale,"phase":phase+branch})
	var plateau_center = axis*0.36-tangent*0.16
	var plateau = {"enabled":recipe_id=="plateau_hinterland","center":[plateau_center.x,plateau_center.y],"radii":[0.34,0.30],"height":1.12*relief_scale,"core_ratio":0.67,"phase":rng.randf_range(-PI,PI)}
	var wind = axis.rotated(rng.randf_range(-0.50,0.50))
	var latitude = Vector2(0,1)
	recipe = {"id":recipe_id,"coast_axis":[axis.x,axis.y],"coast_phase":rng.randf_range(-PI,PI),"continental_base":0.19 if recipe_id=="coastal_range" else 0.27,"spines":spines,"plateau":plateau,"wind":[wind.x,wind.y],"temperature_base":0.79 if recipe_id=="coastal_range" else 0.68,"latitude_axis":[latitude.x,latitude.y],"latitude_gradient":0.10,"elevation_lapse":0.13,"relief_scale":relief_scale}

func _sample() -> void:
	for q in range(-radius,radius+1):
		for r in range(-radius,radius+1):
			var h = Vector2i(q,r)
			if distance(h)>radius: continue
			var k = key(h); var p = center(h)/(radius*EDGE_LENGTH)
			var continental = float(recipe.continental_base)+p.dot(axis)*0.62+sin(p.dot(tangent)*4.2+float(recipe.coast_phase))*0.095
			continental += noise.get_noise_2d(p.x,p.y)*0.12
			var elevation = continental
			var uplift = 0.0
			for spine in recipe.spines:
				var d = INF; var along = 0.0
				for i in range(spine.points.size()-1):
					var a = Vector2(spine.points[i][0],spine.points[i][1]); var b = Vector2(spine.points[i+1][0],spine.points[i+1][1])
					var t = clampf((p-a).dot(b-a)/maxf((b-a).length_squared(),0.00001),0,1)
					var sample_distance = p.distance_to(a.lerp(b,t))
					if sample_distance<d: d=sample_distance; along=(float(i)+t)/maxf(1.0,spine.points.size()-1)
				var variable_width = float(spine.width)*(0.88+0.16*sin(along*9.0+float(spine.phase)))
				var peak_envelope = 0.63+0.37*pow(0.5+0.5*sin(along*13.0+float(spine.phase)),2.0)
				uplift = maxf(uplift,exp(-pow(d/variable_width,2.0))*float(spine.uplift)*peak_envelope)
			elevation += uplift
			var plateau_weight = 0.0
			if recipe.plateau.enabled:
				var pc = Vector2(recipe.plateau.center[0],recipe.plateau.center[1]); var delta = p-pc
				var elliptical = Vector2(delta.dot(tangent)/recipe.plateau.radii[0],delta.dot(axis)/recipe.plateau.radii[1])
				var radial_boundary = 1.0+0.09*sin(elliptical.angle()*3.0+recipe.plateau.phase)+0.045*cos(elliptical.angle()*5.0-recipe.plateau.phase)
				plateau_weight = 1.0-smoothstep(float(recipe.plateau.core_ratio),1.0,elliptical.length()/radial_boundary)
				elevation = lerpf(elevation,float(recipe.plateau.height),plateau_weight)
			elevation = snappedf(elevation,QUANTUM)
			cells[k] = {"q":q,"r":r,"raw_elevation":elevation,"elevation":elevation,"plateau_weight":plateau_weight,"plateau_core":plateau_weight>=0.99999,"uplift":uplift,"ocean":elevation<=0.0,"flow_to":"","fill_depth":0.0}
			keys.append(k)
	keys.sort()
	for k in keys:
		neighbors[k] = []
		for direction in DIRS:
			var n = key(Vector2i(cells[k].q,cells[k].r)+direction)
			if cells.has(n): neighbors[k].append(n)

## Dijkstra lower envelope, not an iterative height optimizer. Bounds adjacent
## physical world-space slopes; each key is finalized once by a min heap.
func _limit_slopes() -> int:
	var heap: Array = []
	for k in keys: _push(heap,[float(cells[k].elevation),k])
	while not heap.is_empty():
		var entry = _pop(heap); var k: String = entry[1]
		if float(entry[0])>float(cells[k].elevation)+0.0000001: continue
		for n in neighbors[k]:
			var ceiling = float(entry[0])+MAX_EDGE_SLOPE*EDGE_LENGTH
			if float(cells[n].elevation)>ceiling:
				cells[n].elevation=ceiling; _push(heap,[ceiling,n])
	var changed = 0
	for k in keys:
		cells[k].elevation = snappedf(float(cells[k].elevation),QUANTUM)
		cells[k]["slope_limited_elevation"] = cells[k].elevation
		if cells[k].elevation < cells[k].raw_elevation-0.000001: changed += 1
	return changed

func _drain() -> Array:
	var heap: Array = []; var seen: Dictionary = {}; var order: Array = []
	for k in keys:
		if cells[k].ocean or neighbors[k].size()<6:
			seen[k]=true; _push(heap,[maxf(0.0,float(cells[k].elevation)),k])
	while not heap.is_empty():
		var entry = _pop(heap); var k: String = entry[1]; order.append(k)
		for n in neighbors[k]:
			if seen.has(n): continue
			seen[n]=true
			cells[n].elevation=maxf(float(cells[n].elevation),float(entry[0])+EPSILON)
			cells[n].fill_depth=float(cells[n].elevation)-float(cells[n].slope_limited_elevation)
			cells[n].flow_to=k; _push(heap,[float(cells[n].elevation),n])
	return order

## Fixed-cycle, double-buffered hex water cycle. Direction is where wind blows.
## Moisture/runoff/air transport use final conditioned terrain, never labels.
static func climate_for_cells(domain: Dictionary, ordered_keys: Array, adjacent: Dictionary, wind: Vector2, temperature_base: float, latitude: Vector2, latitude_gradient: float, scale: float, elevation_lapse: float = 0.13) -> Dictionary:
	var old: Dictionary = {}
	for k in ordered_keys: old[k]={"cloud":0.0,"moisture":0.0,"rain":0.0}
	for cycle in range(CLIMATE_CYCLES):
		var next: Dictionary = {}
		for k in ordered_keys: next[k]={"cloud":0.0,"moisture":0.0,"rain":old[k].rain}
		for k in ordered_keys:
			var cell: Dictionary=domain[k]
			var evaporation = 0.16 if cell.ocean else float(old[k].moisture)*0.015
			var cloud = float(old[k].cloud)+evaporation
			var rain = cloud*0.12; cloud-=rain
			var capacity = clampf(1.0-maxf(0.0,float(cell.elevation))*0.38,0.10,1.0)
			var excess = maxf(0.0,cloud-capacity); cloud-=excess; rain+=excess
			var moisture = maxf(0.0,float(old[k].moisture)-evaporation)+rain
			var down: Array = []
			for n in adjacent[k]:
				if float(domain[n].elevation)<float(cell.elevation): down.append(n)
			var runoff = moisture*0.12 if not down.is_empty() else 0.0
			moisture-=runoff
			next[k].moisture+=moisture
			next[k].rain+=rain
			for n in down: next[n].moisture+=runoff/down.size()
			var weights: Array = []; var weight_sum = 0.0
			for direction in DIRS:
				var w = 1.0+maxf(0.0,center(direction).normalized().dot(wind.normalized()))*5.0
				weights.append(w); weight_sum+=w
			for i in range(6):
				var n = key(Vector2i(cell.q,cell.r)+DIRS[i])
				if next.has(n): next[n].cloud+=cloud*weights[i]/weight_sum
		for k in ordered_keys: next[k].moisture=clampf(float(next[k].moisture),0.0,1.0)
		old=next
	var result: Dictionary = {}
	for k in ordered_keys:
		var cell: Dictionary=domain[k]; var p = center(Vector2i(cell.q,cell.r))/scale
		result[k]={"temperature":clampf(temperature_base+p.dot(latitude)*latitude_gradient-maxf(0.0,float(cell.elevation))*elevation_lapse,0.0,1.0),"moisture":clampf(float(old[k].moisture),0.0,1.0),"rainfall":float(old[k].rain)/CLIMATE_CYCLES,"air_humidity":clampf(float(old[k].cloud),0.0,1.0)}
	return result

static func biome(height: float, temperature: float, moisture: float) -> String:
	if height<=0.0: return "ocean"
	if temperature<0.32: return "alpine"
	if moisture<0.18: return "desert" if temperature>=0.48 else "dry_steppe"
	if moisture>0.78 and height<0.30: return "wetland"
	if moisture>0.61 and temperature>=0.59: return "jungle"
	if moisture>0.40: return "temperate_forest"
	return "grassland"

static func diagnose(world: Dictionary) -> Dictionary:
	var errors: Array = []; var heights: Array = []; var cap: Array = []
	var max_slope = 0.0; var filled = 0; var biomes: Dictionary = {}; var sea = 0
	var data: Dictionary=world.cells
	for k in data:
		var cell: Dictionary=data[k]; heights.append(float(cell.elevation))
		if cell.plateau_core: cap.append(float(cell.elevation))
		if float(cell.fill_depth)>QUANTUM: filled+=1
		if cell.ocean: sea+=1
		if bool(cell.ocean)!=(float(cell.elevation)<=0.0): errors.append("ocean_height_mismatch:"+k)
		biomes[cell.biome]=int(biomes.get(cell.biome,0))+1
		for field in ["elevation","temperature","moisture","rainfall","flow","fill_depth"]:
			if not is_finite(float(cell[field])): errors.append("nonfinite:"+k+":"+field)
		if String(cell.flow_to).is_empty():
			if not cell.ocean and distance(Vector2i(cell.q,cell.r))!=int(world.board_radius): errors.append("inland_sink:"+k)
		elif not data.has(cell.flow_to) or float(cell.elevation)<=float(data[cell.flow_to].elevation): errors.append("nondescending:"+k)
		for direction in DIRS:
			var n = key(Vector2i(cell.q,cell.r)+direction)
			if data.has(n): max_slope=maxf(max_slope,absf(float(cell.elevation)-float(data[n].elevation))/EDGE_LENGTH)
	if max_slope>float(world.config.max_edge_slope)+float(world.config.edge_slope_tolerance): errors.append("edge_slope_bound")
	if sea<1 or sea>=data.size(): errors.append("land_sea_domain")
	var regions: Dictionary={}
	for name in biomes:
		var seen: Dictionary={}; var sizes: Array=[]
		for k in data:
			if seen.has(k) or data[k].biome!=name: continue
			var queue: Array=[k]; seen[k]=true; var index=0
			while index<queue.size():
				var cell: Dictionary=data[queue[index]]; index+=1
				for direction in DIRS:
					var n=key(Vector2i(cell.q,cell.r)+direction)
					if data.has(n) and not seen.has(n) and data[n].biome==name: seen[n]=true; queue.append(n)
			sizes.append(queue.size())
		sizes.sort(); sizes.reverse(); regions[name]=sizes
	return {"errors":errors,"cell_count":data.size(),"ocean_cells":sea,"height_min":heights.min(),"height_max":heights.max(),"maximum_adjacent_world_slope":max_slope,"conditioned_cells":filled,"plateau_core_cells":cap.size(),"plateau_core_height_range":0.0 if cap.is_empty() else float(cap.max())-float(cap.min()),"biome_counts":biomes,"biome_component_sizes":regions,"river_edge_count":world.river_edges.size(),"source_checks_only":true,"mesh_gradient_checked":false,"hex_area_checked":false}

static func _quantize(value: Variant) -> Variant:
	if value is float: return snappedf(value,QUANTUM)
	if value is Array:
		var output: Array=[]
		for item in value: output.append(_quantize(item))
		return output
	if value is Dictionary:
		var output: Dictionary={}
		for k in value: output[k]=_quantize(value[k])
		return output
	return value
static func _less(a: Array,b: Array) -> bool: return a[0]<b[0] or (a[0]==b[0] and String(a[1])<String(b[1]))
static func _push(heap: Array, item: Array) -> void:
	heap.append(item); var i=heap.size()-1
	while i>0:
		var p=(i-1)>>1
		if not _less(heap[i],heap[p]): break
		var swap=heap[p]; heap[p]=heap[i]; heap[i]=swap; i=p
static func _pop(heap: Array) -> Array:
	var result: Array=heap[0]; var tail: Array=heap.pop_back()
	if heap.is_empty(): return result
	heap[0]=tail; var i=0
	while i*2+1<heap.size():
		var child=i*2+1
		if child+1<heap.size() and _less(heap[child+1],heap[child]): child+=1
		if not _less(heap[child],heap[i]): break
		var swap=heap[i]; heap[i]=heap[child]; heap[child]=swap; i=child
	return result
