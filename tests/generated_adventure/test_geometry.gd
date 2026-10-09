extends SceneTree
## Independent rendered-water triangle check, not the admission half-edge implementation.
const Adapter = preload("res://view/generated_adventure/adapter.gd")
const Generator = preload("res://core/world_generator.gd")
const Field = preload("res://view/terrain_field.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks:=0
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);printerr("FAIL "+message)
static func point_in_triangle(p: Vector2,a: Vector2,b: Vector2,c: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p,PackedVector2Array([a,b,c]))
static func touches_water(a: Vector2,b: Vector2,water: PackedVector3Array) -> bool:
	for i in range(0,water.size(),3):
		var x:=Vector2(water[i].x,water[i].z);var y:=Vector2(water[i+1].x,water[i+1].z);var z:=Vector2(water[i+2].x,water[i+2].z)
		if point_in_triangle(a,x,y,z) or point_in_triangle(b,x,y,z):return true
		for edge in [[x,y],[y,z],[z,x]]:
			if Geometry2D.segment_intersects_segment(a,b,edge[0],edge[1])!=null:return true
	return false
func run() -> void:
	var source:=Generator.generate(726381,4,{"generator_version":Generator.BIOMES_VERSION});var adapter:=Adapter.new(source)
	check(adapter.ready().ok,"fixture source admitted")
	if not adapter.ready().ok:quit(1);return
	var field:=Field.new();var tiles: Dictionary={}
	for key in source.hexes:
		var row: Dictionary=source.hexes[key];tiles[key]={"hex":Vector2i(row.q,row.r),"terrain":row.terrain,"raw":row}
	check(field.configure(tiles,source),"same source configures existing renderer")
	var meshes:=field.build_meshes();var arrays: Array=meshes.water.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var water:=PackedVector3Array()
	if not indices.is_empty():
		for index in indices:water.append(vertices[index])
	else:water=vertices
	var allowed:=0;var blocked_wet:=0;var wet_dry_anchors:=0
	for key in source.hexes:
		var row: Dictionary=source.hexes[key];var a:=Generator.hex_center(Vector2i(row.q,row.r))
		for direction in Generator.DIRS:
			var h: Vector2i=Vector2i(row.q,row.r)+direction;var next:=Generator.hex_key(h)
			if not source.hexes.has(next) or key>=next:continue
			var b:=Generator.hex_center(h);var wet:=touches_water(a,b,water)
			if next in adapter.source.navigation.allowed[key]:
				allowed+=1;check(not wet,"admitted dry edge never intersects actual rendered clipped water triangles")
			elif wet:
				blocked_wet+=1
				if adapter.source.navigation.supported[key] and adapter.source.navigation.supported[next]:wet_dry_anchors+=1
	check(allowed>0 and blocked_wet>0,"independent geometry checks both accepted dry and blocked wet edges")
	# Fail-closed malformed source/save types and immutable source facts.
	var original: String=C.bytes(adapter.save_data())
	for change in ["actor_type","stamina_type","turn_type","flags_type","unknown_state","actor_capability"]:
		var bad:=adapter.save_data()
		match change:
			"actor_type":bad.engine.state.actors.actor_player="invalid"
			"stamina_type":bad.engine.state.actors.actor_player.stamina="invalid"
			"turn_type":bad.engine.state.turn="invalid"
			"flags_type":bad.engine.state.flags=[]
			"unknown_state":bad.engine.state.unknown_field="unregistered"
			"actor_capability":bad.engine.state.actors.actor_player.traversal_profile={"policy_id":"terrain_traversal/v1","terrain_discounts":{"mountain":2},"max_action_cost":32}
		check(not adapter.load_data(bad).ok and C.bytes(adapter.save_data())==original,"malformed or expanded save rejected atomically: "+change)
	print("GENERATED_GEOMETRY ",JSON.stringify({"checks":checks,"failures":failures,"rendered_water_triangles":water.size()/3,"allowed_undirected_edges":allowed,"blocked_wet_edges":blocked_wet,"wet_edges_between_dry_anchors":wet_dry_anchors}))
	quit(0 if failures.is_empty() else 1)
