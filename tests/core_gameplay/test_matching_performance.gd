extends SceneTree
## Reproduce the exact old UI predicate in a test-only subclass, then compare
## identical pending input with the fixed implementation. Not a GPU benchmark.
const Adapter=preload("res://view/playable_build/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/core_gameplay_20261003/matching_performance.json"
class OldLookupAdapter extends "res://view/playable_build/adapter.gd":
	var goal_calls:=0
	func _init()->void:super(27,true)
	func movement_goal(target:Array)->String:
		goal_calls+=1
		return ("【署名样例】按地形耗力行至（%d，%d）。" if WeightedMovement.ID in engine.save_data().resolver_ids else "【署名样例】沿干燥路线步行到（%d，%d）。") % target
class NewLookupAdapter extends "res://view/playable_build/adapter.gd":
	var goal_calls:=0
	func _init()->void:super(27,true)
	func movement_goal(target:Array)->String:
		goal_calls+=1
		return super.movement_goal(target)
func _initialize()->void:call_deferred("run")
func run()->void:
	var old=OldLookupAdapter.new();var current=NewLookupAdapter.new()
	var text:String=current.sample_goal("move",{})
	var a:Dictionary=old.begin_intent(text);var b:Dictionary=current.begin_intent(text)
	if not a.get("ok",false) or not b.get("ok",false):printerr("PERF_BEGIN_FAILED");quit(1);return
	var old_before:String=C.bytes(old.engine.save_data());var new_before:String=C.bytes(current.engine.save_data())
	print("MATCH_BENCH_START exact predicate fixture_available; cells=",old.state_copy().hexes.size())
	var start:int=Time.get_ticks_usec();var old_match:bool=old.fixture_available();var old_usec:int=Time.get_ticks_usec()-start
	print("MATCH_OLD_USEC ",old_usec," full_save_data_calls=",old.goal_calls)
	start=Time.get_ticks_usec();var new_match:bool=current.fixture_available();var new_usec:int=Time.get_ticks_usec()-start
	print("MATCH_NEW_USEC ",new_usec," metadata_only_goal_calls=",current.goal_calls)
	var unchanged:bool=old_before==C.bytes(old.engine.save_data()) and new_before==C.bytes(current.engine.save_data())
	var same_request:bool=C.bytes(old.request())==C.bytes(current.request())
	var passed:bool=old_match and new_match and unchanged and same_request and old.goal_calls==current.goal_calls and old.goal_calls==old.state_copy().hexes.size()
	var report:Dictionary={"passed":passed,"predicate":"adapter.fixture_available as called by actual main update_adapter","scenario":"fresh release-test pending no-focus movement sample; exact same world, goal, action and RNG","old_elapsed_usec":old_usec,"new_elapsed_usec":new_usec,"old_per_candidate_full_save_serializations":old.goal_calls,"new_per_candidate_full_save_serializations":0,"candidate_goal_comparisons":current.goal_calls,"matching_identical":old_match==new_match,"same_frozen_request":same_request,"no_authoritative_mutation":unchanged,"test_only_old_implementation":true,"gpu_or_target_hardware_certification":false}
	var f:=FileAccess.open(OUT,FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("MATCHING_PERFORMANCE ","PASSED" if passed else "FAILED")
	quit(0 if passed else 1)
