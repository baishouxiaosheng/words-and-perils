extends SceneTree
## Isolated visual fixtures. They never alter the actual gameplay map or GM state.
const Field=preload("res://view/terrain_field.gd")
const Board=preload("res://view/hex_board.gd")
const Game=preload("res://core/game_state.gd")
var failures:Array[String]=[]
var checks:=0
func _initialize() -> void:
	call_deferred("run_tests")
func check(value:bool,message:String) -> void:
	checks+=1
	if not value: failures.append(message)
func run_tests() -> void:
	var game=Game.new();game.new_world()
	var before=game.state.duplicate(true)
	var source={}
	for key in game.state.hexes:
		var cell=game.state.hexes[key]
		source[key]={"hex":Vector2i(cell.q,cell.r),"terrain":cell.terrain}
	var field=Field.new();field.configure(source)
	check(source.size()==61,"Original map has 61 cells")
	check(field.river_nodes.has("0,2"),"Wall crossing keeps visual river culvert")
	check(source["0,2"].terrain=="wall","River culvert does not reclassify semantic wall")
	check(field.land_height(Field.center(Vector2i(0,-2)))<Field.WATER_Y-0.15,"Streambed is below water")
	check(field.land_height(Field.center(Vector2i(-2,-1)))>Field.WATER_Y+0.20,"Land is above water")
	var max_error:=0.0
	for tile in source.values():
		for edge in range(6):
			var neighbor:Vector2i=tile.hex+Field.DIRS[posmod(5-edge,6)]
			if not source.has(Field.key(neighbor)):continue
			for sample in range(11):
				var t=float(sample)/10.0
				var p=Field.center(tile.hex)+Field.corner(edge).lerp(Field.corner(edge+1),t)
				var q=Field.center(neighbor)+Field.corner(edge+4).lerp(Field.corner(edge+3),t)
				max_error=maxf(max_error,absf(field.land_height(p)-field.land_height(q)))
	check(max_error<0.00002,"All shared edge samples match within 0.00002; error=%s"%max_error)
	var mid=(Field.center(Vector2i(2,0))+Field.center(Vector2i(3,0)))*0.5
	check(field.mountain_height(mid)>0.55,"Mountain saddle continues across adjacent hexes")
	check(game.state==before,"Visual field leaves canonical gameplay state unchanged")
	# Six wall cells surrounding a plain cell must produce a closed graph.
	var ring={"0,0":{"hex":Vector2i.ZERO,"terrain":"plain"}}
	for d in Field.DIRS:ring[Field.key(d)]={"hex":d,"terrain":"wall"}
	var edges=0
	for d in Field.DIRS:
		var degree=0
		for step in Field.DIRS:
			var k=Field.key(d+step)
			if ring.has(k) and ring[k].terrain=="wall":degree+=1
		check(degree==2,"Enclosure wall %s has exactly two joined neighbors"%d)
		edges+=degree
	check(edges/2==6,"Enclosure has all six spans, with no open graph endpoints")
	print("TERRAIN METRICS: shared-edge max error=",max_error,", channel segments=",field.channels.size(),", peaks=",field.peaks.size(),", ridges=",field.ridges.size())
	if failures.is_empty(): print("TERRAIN GEOMETRY PASSED: %d assertions"%checks);quit(0)
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
