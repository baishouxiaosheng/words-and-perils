extends RefCounted
## Exact observable vegetation recipe. Descriptors are not patchable game entities.
const VERSION := "scene_features_v1"
const TerrainField = preload("res://view/terrain_field.gd")

static func trees_for_tile(tile: Dictionary, tiles: Dictionary, field, world_id: String) -> Array[Dictionary]:
	var trees:Array[Dictionary]=[]
	var h:Vector2i=tile.hex
	var origin:Vector3=TerrainField.center(h)
	var terrain=String(tile.terrain)
	var raw:Dictionary=tile.get("raw",{})
	var seed=abs(int(h.x*31+h.y*17))
	if not String(raw.get("settlement_id","")).is_empty():return trees
	if field.biomes_v2 and String(raw.get("biome",""))=="jungle":
		var rng=RandomNumberGenerator.new();rng.seed=absi((h.x*73856093) ^ (h.y*19349663)) ^ int(field.generated_world.seed)
		var grouping=0.5+0.5*sin(origin.x*0.43+sin(origin.z*0.34))*cos(origin.z*0.37)
		var count=1 if grouping<0.44 else 2
		var placed:Array[Vector3]=[]
		for slot in range(count):
			for attempt in range(6):
				var p=Vector3(rng.randf_range(-0.57,0.57),0,rng.randf_range(-0.53,0.53))
				if placed.any(func(other):return other.distance_to(p)<0.43):continue
				var world_p=origin+p
				if field.river_distance(world_p)<field.bank_width(world_p)+field.bank_shoulder(world_p)+0.15:continue
				var near_road=false
				for neighbor in raw.get("road_neighbors",[]):
					if tiles.has(neighbor) and TerrainField.distance_segment(world_p,origin,TerrainField.center(tiles[neighbor].hex))<0.39:near_road=true
				if near_road:continue
				placed.append(p);p.y=field.land_height(world_p)
				trees.append(_tree(world_id,h,slot,"broadleaf",p,rng.randf_range(0.79,1.17),int(rng.randi()%997)))
				break
	elif not (field.biomes_v2 and String(raw.get("biome",""))=="desert") and terrain in ["plain","plains","forest"] and (seed%3==0 or terrain=="forest"):
		for slot in range(3):
			var p=Vector3(-0.40+slot*0.35,0,0.25+sin(float(seed+slot))*0.12)
			var world_p=origin+p
			if field.river_distance(world_p)<0.78 or field.mountain_height(world_p)>0.28:continue
			p.y=field.land_height(world_p)
			trees.append(_tree(world_id,h,slot,"conifer",p,0.78+0.16*sin(float(seed+slot)*2.1),seed+slot))
	return trees

static func _tree(world_id:String,h:Vector2i,slot:int,type_:String,p:Vector3,size_:float,seed:int)->Dictionary:
	return {"id":tree_id(world_id,h,slot),"hex":[h.x,h.y],"slot":slot,"vegetation_type":type_,"local_position":[p.x,p.y,p.z],"size":size_,"shape_seed":seed,"catalog_version":VERSION}

static func tree_id(world_id: String, h: Vector2i, slot: int) -> String:
	return "tree_%s_%s_hex_%d_%d_slot_%d" % [world_id, VERSION, h.x, h.y, slot]
