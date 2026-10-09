extends "res://view/terrain_field.gd"
var sample_calls:=0
var vertex_misses:=0
var landscape_calls:=0
var underlying_calls:=0
var underlying_us:=0
var exact_repeated_underlying_calls:=0
var exact_repeated_underlying_us:=0
var first_underlying_calls:=0
var other_underlying_calls:=0
var cache_hits:=0
var in_vertex:=false
var seen_exact:Dictionary={}
var missed_exact:Dictionary={}
var vertex_landscape_calls:=0
var vertex_underlying_calls:=0
var vertex_call_histogram:Dictionary={}
var vertex_miss_histogram:Dictionary={}
func _sample(p:Vector3,terrain:String)->Dictionary:
	sample_calls+=1;in_vertex=true;seen_exact.clear();missed_exact.clear();vertex_landscape_calls=0;vertex_underlying_calls=0
	var result:Dictionary=super._sample(p,terrain)
	if vertex_landscape_calls>0:vertex_misses+=1
	vertex_call_histogram[vertex_landscape_calls]=vertex_call_histogram.get(vertex_landscape_calls,0)+1
	vertex_miss_histogram[vertex_underlying_calls]=vertex_miss_histogram.get(vertex_underlying_calls,0)+1
	in_vertex=false
	return result
func _landscape_sample(p:Vector3)->Dictionary:
	landscape_calls+=1
	var old_misses:=landscape_cache_misses
	var started:=Time.get_ticks_usec()
	var result:Dictionary=super._landscape_sample(p)
	var duration:=Time.get_ticks_usec()-started
	var exact:=Vector2(p.x,p.z)
	if in_vertex:vertex_landscape_calls+=1
	if landscape_cache_misses>old_misses:
		underlying_calls+=1;underlying_us+=duration
		if in_vertex:
			vertex_underlying_calls+=1
			if missed_exact.has(exact):exact_repeated_underlying_calls+=1;exact_repeated_underlying_us+=duration
			else:first_underlying_calls+=1
			missed_exact[exact]=true
		else:other_underlying_calls+=1
	else:cache_hits+=1
	if in_vertex:seen_exact[exact]=true
	return result
func metrics()->Dictionary:
	return {"sample_calls":sample_calls,"vertex_misses":vertex_misses,"landscape_calls":landscape_calls,"cache_hits":cache_hits,"underlying_calls":underlying_calls,"underlying_wall_us_including_wrapper":underlying_us,"exact_repeated_underlying_calls_within_one_vertex":exact_repeated_underlying_calls,"exact_repeated_underlying_wall_us_including_wrapper":exact_repeated_underlying_us,"first_underlying_calls_in_vertex":first_underlying_calls,"other_underlying_calls_outside_vertex":other_underlying_calls,"vertex_call_histogram":vertex_call_histogram,"vertex_miss_histogram":vertex_miss_histogram,"landscape_entries":landscape_cache.size(),"query_entries":query_cache.size(),"vertex_entries":vertex_cache.size(),"triangle_count":triangle_count,"shared_vertex_count":shared_vertex_count}
