extends SceneTree
## Exact query/field equivalence against frozen accepted geometry, plus BVH shells.
const Field=preload("res://view/terrain_field.gd")
const Baseline=preload("res://tests/fixtures/accepted_art_renderer/terrain_field.gd")
const Index=preload("res://view/channel_index.gd")
const Game=preload("res://core/game_state.gd")
const Generator=preload("res://core/world_generator.gd")
var checks:=0
var failures:Array[String]=[]
var reports:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func sources(hexes:Dictionary)->Dictionary:
	var result={}
	for key in hexes:
		var c:Dictionary=hexes[key]
		result[key]={"hex":Vector2i(c.q,c.r),"terrain":c.terrain,"raw":c}
	return result
func brute(channels:Array[Dictionary],point:Vector2)->Dictionary:
	var result={"distance":1000.0,"height":0.04,"width":0.24}
	for segment in channels:
		var a:Vector3=segment.a;var b:Vector3=segment.b
		var delta=Vector2(b.x-a.x,b.z-a.z)
		var t=clampf((point-Vector2(a.x,a.z)).dot(delta)/maxf(delta.length_squared(),0.0001),0.0,1.0)
		var distance=(point-Vector2(a.x,a.z)).distance_to(delta*t)
		if distance<float(result.distance):result={"distance":distance,"height":lerpf(a.y,b.y,t),"width":lerpf(float(segment.get("from_width",segment.get("width",0.24))),float(segment.get("to_width",segment.get("width",0.24))),t),"mouth":segment.get("mouth",false),"t":t}
	return result
func compare(field,baseline,range_:float,label:String,compare_height:bool=true)->void:
	var maximum=0.0
	for x in range(-19,20):
		for z in range(-19,20):
			var p=Vector3(x*range_/19.0,0,z*range_/19.0)
			var got:Dictionary=field.channel_sample(p);var expected=brute(field.channels,Vector2(p.x,p.z))
			if got!=expected:print("INDEX DIFFERENCE ",label," p=",p," cached=",got," brute=",expected," direct=",field.channel_index.nearest(Vector2(p.x,p.z)))
			check(field.channel_index.nearest(Vector2(p.x,p.z))==expected,label+" direct nearest sample matches brute source order exactly")
			check(absf(float(got.distance)-float(expected.distance))<0.000004 and absf(float(got.height)-float(expected.height))<0.000004 and absf(float(got.width)-float(expected.width))<0.000004,label+" cached nearest sample stays within existing shared-coordinate quantization")
			if compare_height:
				maximum=maxf(maximum,absf(field.land_height(p)-baseline.land_height(p)))
				maximum=maxf(maximum,absf(field.water_height(p)-baseline.water_height(p)))
				check(absf(field.river_distance(p)-baseline.river_distance(p))<0.000004,label+" original/global nearest distance remains equivalent")
	for segment in field.channels:
		var a:Vector3=segment.a;var b:Vector3=segment.b
		for t in [0.0,0.25,0.50,0.75,1.0]:
			var p=a.lerp(b,t);p.y=0
			var expected=brute(field.channels,Vector2(p.x,p.z))
			var got:Dictionary=field.channel_sample(p)
			if got!=expected:print("INDEX END DIFFERENCE ",label," p=",p," cached=",got," brute=",expected," direct=",field.channel_index.nearest(Vector2(p.x,p.z)))
			check(field.channel_index.nearest(Vector2(p.x,p.z))==expected,label+" direct endpoints/junction tie agrees exactly")
			check(absf(float(got.distance)-float(expected.distance))<0.000004 and absf(float(got.height)-float(expected.height))<0.000004 and absf(float(got.width)-float(expected.width))<0.000004,label+" cached endpoint/junction stays within shared-coordinate quantization")
	if compare_height:check(maximum<0.000004,label+" all sampled land/water remain the accepted field; maximum=%s"%maximum)
	var metrics:Dictionary=field.channel_index.metrics();metrics.label=label;metrics.maximum_height_error=maximum;reports.append(metrics)
	check(float(metrics.mean_candidates)<field.channels.size()*0.8,label+" spatial bounds reduce candidate work without changing samples")
func run()->void:
	var game=Game.new();var original:Dictionary=game.state.duplicate(true)
	var source=sources(game.state.hexes)
	var field=Field.new();field.configure(source);var before=Baseline.new();before.configure(source)
	compare(field,before,8.0,"original61")
	check(game.state==original,"Indexed rendering leaves original canonical state unchanged")
	for data in [[0,7],[726381,7],[726381,12],[726381,24]]:
		var world:Dictionary=Generator.generate(data[0],data[1]);var hash_=world.content_hash
		source=sources(world.hexes);field=Field.new();field.configure(source,world);before=Baseline.new();before.configure(source,world)
		compare(field,before,float(data[1])*1.8,"v1_%s_r%s"%data)
		check(world.content_hash==hash_,"Indexed v1 river queries preserve canonical world hash")
	var world:Dictionary=Generator.generate(726381,12,{"generator_version":"macro_hex_biomes_v2"})
	if world.generator_version=="macro_hex_biomes_v2":
		field=Field.new();field.configure(sources(world.hexes),world)
		check(field.generated,"Renderer explicitly recognizes canonical v2 continuous sampler")
		compare(field,null,21.6,"v2_726381_r12",false)
	var index=Index.new();index.configure([])
	check(index.nearest(Vector2.ZERO)=={"distance":1000.0,"height":0.04,"width":0.24},"Empty channel index preserves dry/default sample")
	index.configure([{"a":Vector3.ZERO,"b":Vector3.ZERO,"width":0.24}])
	check(index.nearest(Vector2.ZERO).distance==0.0,"Zero-length defensive segment remains finite")
	print("CHANNEL INDEX METRICS ",JSON.stringify(reports))
	var f=FileAccess.open("user://channel_index_equivalence.json",FileAccess.WRITE);f.store_string(JSON.stringify(reports,"\t"));f.close()
	if failures.is_empty():print("CHANNEL INDEX PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
