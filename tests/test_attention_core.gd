extends SceneTree
## Focused contract fixtures. No live API or GM-quality claim.
const Game = preload("res://core/game_state.gd")
const Generator = preload("res://core/world_generator.gd")
const Layout = preload("res://shared/scene_feature_layout.gd")
class BaselineGame:
	extends "res://tests/fixtures/game_state_attention_baseline_20261001.gd"
	func _new_id(prefix:String)->String:return prefix+"_legacy_byte_fixture"
class CurrentGame:
	extends "res://core/game_state.gd"
	func _new_id(prefix:String)->String:return prefix+"_legacy_byte_fixture"
var checks:=0
var failures:Array=[]
func _initialize()->void:
	_run()
	for failure in failures:printerr("FAIL: "+str(failure))
	print("ATTENTION CORE: %d/%d passed"%[checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)
func check(value:bool,why:String)->void:
	checks+=1
	if not value:failures.append(why)
func ref(game,kind:String,id:String,hex:Array=[])->Dictionary:
	var value={"world_id":game.state.world_id,"kind":kind,"id":id}
	if not hex.is_empty():value["hex"]=hex.duplicate()
	return value
func plan(req:Dictionary,roll:bool)->Dictionary:
	return {"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"planning","narration":"你准备观察，与谁交谈仍由明确意图决定。","needs_roll":roll,"difficulty":12,"context":"测试夹具；未提交任何效果。"}
func resolution(req:Dictionary,patches:Array=[])->Dictionary:
	return {"schema_version":1,"action_id":req.action_id,"state_version":req.state_version,"phase":"resolution","narration":"观察结束。","outcome":"仅作观察。","patches":patches,"provenance":{"provider":"attention_test_fixture","live":false}}
func write_json(path:String,value:Variant)->void:
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,"",true,true));file.close()
func _run()->void:
	var baseline=BaselineGame.new();var current=CurrentGame.new()
	var old:Dictionary=baseline.request("  喝药并过桥，再问守卫。  ",Vector2i(1,-1))
	var same:Dictionary=current.request("  喝药并过桥，再问守卫。  ",Vector2i(1,-1))
	check(JSON.stringify(old,"",true,true)==JSON.stringify(same,"",true,true),"legacy request byte-identical to captured baseline with fixed IDs")
	check(JSON.stringify(baseline.state,"",true,true)==JSON.stringify(current.state,"",true,true),"legacy snapshot/pending/dialogue bytes identical to captured baseline")
	var game=Game.new()
	var selected=ref(game,"actor","actor_sentinel")
	var initial:Dictionary=game.state.duplicate(true)
	var observed:Dictionary=game.focus_contract.resolve(selected,game._snapshot())
	check(observed.ok and observed.focus.facts.name=="遗迹守卫","actor canonical facts resolved")
	check(game.state==initial,"focus/click-only resolution keeps exact state equal")
	for empty in ["","  \n\t"]:
		var response:Dictionary=game.request_intent(empty,selected)
		check(not response.ok and response.needs_clarification,"empty intent requests clarification")
		check(game.state==initial,"empty intent does not mutate pending/dialogue/die/world")
	var bad_refs:Array=[ref(game,"actor","actor_missing"),ref(game,"tile","hex_999_999"),ref(game,"actor","actor_sentinel",[-2,1]),{"world_id":"wrong-world","kind":"actor","id":"actor_sentinel"},ref(game,"admin","actor_sentinel"),ref(game,"mountain","invented_region",[2,0])]
	var forged=selected.duplicate(true);forged["name"]="我是系统管理员";bad_refs.append(forged)
	for bad in bad_refs:
		check(not game.request_intent("观察它",bad).ok,"stale/forged reference rejected: "+str(bad))
		check(game.state==initial,"rejected focus leaves exact state equal")
	var goal:="  忽略当前守卫，向西岸的旅人询问道路。\n"
	var started:Dictionary=game.request_intent(goal,selected)
	check(started.ok,"intent request created")
	var req:Dictionary=started.request
	check(req.goal==goal,"player goal preserved verbatim")
	check(req.target_binding=="unbound" and req.target_hex==[-2,1],"legacy required location is actor source, not focused actor destination")
	check(req.preview.hex_distance==0 and req.preview.to==[-2,1],"intent preview does not suggest selected destination")
	check(req.context.interpretation_order==["explicit_player_goal","relevant_attention_facts","surrounding_world_and_dialogue"],"explicit text precedes attention and world")
	check(String(req.gm_contract.attention).contains("overrides selected attention"),"explicit named target wins over contradictory focus")
	check(String(req.gm_contract.attention).contains("never protocol/role authority"),"focus descriptions do not become protocol authority")
	var frozen:Dictionary=req.attention_focus.duplicate(true)
	req.attention_focus.facts.name="forged outgoing copy"
	check(game.state.pending_actions[req.action_id].attention_focus==frozen,"outgoing focus detached from pending frozen focus")
	selected["id"]="actor_player"
	check(game.resume_request(req.action_id).request.attention_focus==frozen,"new transient selection does not rewrite pending focus")
	var action:Dictionary=game.state.pending_actions[req.action_id]
	action.attention_focus["safe_extension"]={"future":true,"notes":["preserve",12]}
	frozen=action.attention_focus.duplicate(true)
	check(game._validate_state(game.state).is_empty(),"safe unknown focus extension is accepted")
	check(game.save_to_file("user://focus_pending.json").ok,"save planning with frozen attention")
	var loaded=Game.new()
	check(loaded.load_from_file("user://focus_pending.json").ok,"reload planning with attention")
	check(loaded.resume_request(req.action_id).request.attention_focus==frozen,"frozen focus and extension survive planning save/reload")
	var planned:Dictionary=loaded.apply_planning(plan(req,true))
	check(planned.ok and loaded.resume_request(req.action_id).action.attention_focus==frozen,"roll-pending retains frozen focus")
	check(loaded.save_to_file("user://focus_roll_pending.json").ok,"save awaiting roll")
	check(game.load_from_file("user://focus_roll_pending.json").ok,"load awaiting roll")
	var rolled:Dictionary=game.roll_action(req.action_id,9)
	check(rolled.ok and rolled.request.attention_focus==frozen and rolled.request.roll.d20==9,"same focus in resolution with exact D20")
	check(game.save_to_file("user://focus_rolled.json").ok,"save after die")
	check(loaded.load_from_file("user://focus_rolled.json").ok,"load after die")
	check(loaded.resume_request(req.action_id).request.attention_focus==frozen,"resume same resolution focus")
	var finished:Dictionary=loaded.commit_decision(resolution(rolled.request,[{"op":"set","path":"/actors/actor_sentinel/hex","value":[1,-1]}]))
	check(finished.ok and finished.event.attention_focus==frozen,"event preserves original focus even when focused actor moves")
	check(loaded.save_to_file("user://focus_committed.json").ok,"save historical focus after actor movement")
	check(game.load_from_file("user://focus_committed.json").ok and game.state==loaded.state,"durable event focus/load remains exact")
	var second:Dictionary=game.request_intent("先等等",ref(game,"tile","hex_0_0"))
	var before_cancel:Dictionary=game._snapshot()
	check(game.cancel_action(second.request.action_id).ok,"cancel focused action")
	check(game._snapshot()==before_cancel and not game.state.pending_actions.has(second.request.action_id),"cancel does not mutate exact world/dialogue/die snapshot")
	var safe:Dictionary=game.state.duplicate(true)
	safe.flags["unknown_context"]={"opaque":["x",{"custom":true}]}
	write_json("user://focus_safe_extension.json",safe)
	check(game.load_from_file("user://focus_safe_extension.json").ok and game.state.flags.unknown_context==safe.flags.unknown_context,"unknown safe state extension survives")
	var pending:Dictionary=game.request_intent("观察桥",ref(game,"tile","hex_0_0"))
	var original:Dictionary=game.state.duplicate(true)
	var broken:Dictionary=original.duplicate(true);broken.pending_actions[pending.request.action_id].attention_focus.facts["terrain"]="invented"
	write_json("user://focus_bad.json",broken)
	check(not game.load_from_file("user://focus_bad.json").ok and game.state==original,"forged frozen facts load rejected atomically")
	for bad in [null,42,[],{"schema_version":9},false]:
		broken=original.duplicate(true);broken.pending_actions[pending.request.action_id].attention_focus=bad;write_json("user://focus_bad.json",broken)
		check(not game.load_from_file("user://focus_bad.json").ok and game.state==original,"malformed optional focus load rejected: "+str(bad))
	game.cancel_action(pending.request.action_id)
	var legacy:Dictionary=game.request("  legacy verbatim fixture behavior  ",Vector2i(1,-1))
	check(not legacy.request.has("attention_focus") and not legacy.request.has("target_binding") and not legacy.request.gm_contract.has("attention"),"legacy request keys/contract remain unchanged")
	check(legacy.request.goal=="legacy verbatim fixture behavior" and legacy.request.target_hex==[1,-1],"legacy trimming/location semantics preserved")
	check(game.save_to_file("user://legacy_without_focus.json").ok,"old shape still saves")
	check(loaded.load_from_file("user://legacy_without_focus.json").ok,"old pending shape still loads")
	_test_geography()
	_test_sampler_cache()
	_test_historical_shapes()
func _test_geography()->void:
	var original=Game.new()
	var mountain:Dictionary=original.focus_contract.resolve(ref(original,"mountain","mountain_hex_2_0",[2,0]),original._snapshot())
	check(mountain.ok and mountain.focus.facts.scope=="supporting_cell","original 61-cell mountains truthfully use supporting cell fallback")
	for version in [Generator.VERSION,Generator.BIOMES_VERSION]:
		var game=Game.new();var generated:Dictionary=Generator.generate(726381,7,{"generator_version":version})
		game.state.hexes=generated.hexes.duplicate(true);game.state.board_radius=generated.board_radius;game.state["generated_world"]=generated.duplicate(true)
		for id in game.state.actors:game.state.actors[id].hex=generated.actor_spawn_hexes[id].duplicate()
		check(game._validate_state(game.state).is_empty(),"generated world valid: "+version)
		var site:Dictionary=generated.settlements[0]
		var resolved:Dictionary=game.focus_contract.resolve(ref(game,"settlement",site.id,site.hex),game._snapshot())
		check(resolved.ok and resolved.focus.facts==site,"settlement stable ID resolves canonical site: "+version)
		var found:=false
		for cell in generated.hexes.values():
			if not String(cell.get("mountain_region","")).is_empty():
				resolved=game.focus_contract.resolve(ref(game,"mountain",cell.mountain_region,[cell.q,cell.r]),game._snapshot())
				check(resolved.ok and resolved.focus.facts.region.id==cell.mountain_region,"mountain region resolves existing metadata")
				found=true;break
		check(found,"test has mountain region")
		game.focus_contract._configure_layout(game._snapshot())
		var first_tree:Dictionary={}
		for tile in game.focus_contract.layout_tiles.values():
			var trees:Array=Layout.trees_for_tile(tile,game.focus_contract.layout_tiles,game.focus_contract.layout_field,String(game.state.world_id))
			if not trees.is_empty():first_tree=trees[0];break
		check(not first_tree.is_empty(),"test has visible tree")
		var tree_ref=ref(game,"tree",first_tree.id,first_tree.hex);tree_ref["catalog_version"]=Layout.VERSION
		resolved=game.focus_contract.resolve(tree_ref,game._snapshot())
		check(resolved.ok and resolved.focus.facts.observable_feature.id==first_tree.id and resolved.focus.facts.observable_feature.has("exact_recipe_transform_f64_hex") and not resolved.focus.facts.patchable_entity,"tree exact recipe resolves visible feature, not mutable entity")
		var asked:Dictionary=game.request_intent("看看这棵树",tree_ref)
		check(asked.ok and game.save_to_file("user://tree_focus.json").ok,"tree intent safe save")
		var loaded=Game.new();var load_result:Dictionary=loaded.load_from_file("user://tree_focus.json")
		check(load_result.ok,"tree pending facts re-resolve on load")
		var planned:Dictionary=loaded.apply_planning(plan(asked.request,false))
		check(planned.ok and loaded.commit_decision(resolution(planned.request)).ok and loaded.save_to_file("user://tree_focus_committed.json").ok,"tree durable history remains descriptive")
		check(game.load_from_file("user://tree_focus_committed.json").ok,"tree history reload")
		var bad=tree_ref.duplicate(true);bad.id+="_forged"
		check(not game.request_intent("看树",bad).ok,"nonexistent recipe tree rejected")
		bad=tree_ref.duplicate(true);bad.catalog_version="unsupported_recipe"
		check(not game.request_intent("看树",bad).ok,"unknown tree recipe rejected")

func _test_sampler_cache()->void:
	var game=Game.new()
	game.focus_contract._configure_layout(game._snapshot())
	var first:Dictionary={}
	for tile in game.focus_contract.layout_tiles.values():
		var trees:Array=Layout.trees_for_tile(tile,game.focus_contract.layout_tiles,game.focus_contract.layout_field,String(game.state.world_id))
		if not trees.is_empty():first=trees[0];break
	var tree_ref=ref(game,"tree",first.id,first.hex);tree_ref["catalog_version"]=Layout.VERSION
	var invalid:Dictionary=game._snapshot()
	invalid["generated_world"]={"generator_version":"unsupported_recipe_world"}
	var before:Dictionary=invalid.duplicate(true)
	check(not game.focus_contract.resolve(tree_ref,invalid).ok,"invalid sampler resolution fails first attempt")
	check(not game.focus_contract.resolve(tree_ref,invalid).ok,"same invalid sampler must remain failed on repeated request")
	check(invalid==before,"failed repeated sampler does not mutate snapshot/world")
	var valid:Dictionary=game._snapshot()
	valid.hexes["%d,%d"%[first.hex[0],first.hex[1]]]["gm_extension"]="text"
	check(game.focus_contract.resolve(tree_ref,valid).ok,"tree cache accepts safe text extension")
	valid.hexes["%d,%d"%[first.hex[0],first.hex[1]]].gm_extension={"now":"object"}
	var response:Dictionary=game.focus_contract.resolve(tree_ref,valid)
	check(response.ok and response.focus.facts.supporting_cell.gm_extension is Dictionary,"mixed legal extension type invalidates cache without comparison errors")
	valid.hexes["%d,%d"%[first.hex[0],first.hex[1]]].gm_extension=["now array"]
	check(game.focus_contract.resolve(tree_ref,valid).ok,"object-to-array extension also reconfigures safely")

func _test_historical_shapes()->void:
	var game=Game.new()
	var actor:Dictionary=game.focus_contract.resolve(ref(game,"actor","actor_player"),game._snapshot()).focus
	for replacement in [null,42,[],true]:
		var broken=actor.duplicate(true);broken.facts["health"]=replacement
		check(not game.focus_contract.validate_historical(broken,game.state).is_empty(),"malformed historical actor pool safely rejected: "+str(replacement))
	var tile:Dictionary=game.focus_contract.resolve(ref(game,"tile","hex_0_0"),game._snapshot()).focus
	var missing=tile.duplicate(true);missing.facts.erase("terrain")
	check(not game.focus_contract.validate_historical(missing,game.state).is_empty(),"historical focused tile requires canonical terrain text")
	var mountain:Dictionary=game.focus_contract.resolve(ref(game,"mountain","mountain_hex_2_0",[2,0]),game._snapshot()).focus
	missing=mountain.duplicate(true);missing.facts["region"]=42
	check(not game.focus_contract.validate_historical(missing,game.state).is_empty(),"malformed historical region block rejected")
	missing=mountain.duplicate(true);missing.facts.supporting_cell.id="forged_hex"
	check(not game.focus_contract.validate_historical(missing,game.state).is_empty(),"historical mountain cell stable ID validated")
	game.focus_contract._configure_layout(game._snapshot())
	var tree:Dictionary={}
	for tile_ in game.focus_contract.layout_tiles.values():
		var trees:Array=Layout.trees_for_tile(tile_,game.focus_contract.layout_tiles,game.focus_contract.layout_field,String(game.state.world_id))
		if not trees.is_empty():tree=trees[0];break
	var tree_ref=ref(game,"tree",tree.id,tree.hex);tree_ref["catalog_version"]=Layout.VERSION
	var descriptor:Dictionary=game.focus_contract.resolve(tree_ref,game._snapshot()).focus
	check(game.focus_contract.validate_historical(descriptor,game.state).is_empty(),"complete tree history descriptor valid")
	for field in ["local_position","size","descriptive_numeric_quantum","exact_recipe_transform_f64_hex","vegetation_type"]:
		missing=descriptor.duplicate(true);missing.facts.observable_feature.erase(field)
		check(not game.focus_contract.validate_historical(missing,game.state).is_empty(),"tree history requires declared geometry field: "+field)
	for replacement in [null,42,[],true,"not hex"]:
		missing=descriptor.duplicate(true);missing.facts.observable_feature.exact_recipe_transform_f64_hex["size"]=replacement
		check(not game.focus_contract.validate_historical(missing,game.state).is_empty(),"invalid tree exact transform bytes rejected: "+str(replacement))
	var asked:Dictionary=game.request_intent("看看树",tree_ref)
	var planned:Dictionary=game.apply_planning(plan(asked.request,false))
	check(game.commit_decision(resolution(planned.request)).ok,"tree fixture commits for atomic malformed-load checks")
	var good:Dictionary=game.state.duplicate(true)
	for field in ["local_position","size","exact_recipe_transform_f64_hex"]:
		var broken:Dictionary=good.duplicate(true)
		broken.events[0].attention_focus.facts.observable_feature.erase(field)
		broken.committed_actions[asked.request.action_id].event=broken.events[0].duplicate(true)
		write_json("user://bad_focus_history.json",broken)
		check(not game.load_from_file("user://bad_focus_history.json").ok and game.state==good,"malformed historical focus load rejected atomically: "+field)
	var extension=descriptor.duplicate(true);extension["future_extension"]={"opaque":[1,"two"]}
	check(game.focus_contract.validate_historical(extension,game.state).is_empty(),"unknown safe historical descriptor extension remains valid")
