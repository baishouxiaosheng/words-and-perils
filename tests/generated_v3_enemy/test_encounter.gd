extends SceneTree
const G=preload("res://core/world_generation_v3/generator.gd")
const A=preload("res://view/generated_v3_enemy/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var assertions=0
func _initialize()->void:call_deferred("run")
func verify(ok:bool,label_:String)->bool:
	assertions+=1
	if not ok:printerr("ENCOUNTER_FAIL ",label_);quit(1)
	return ok
func finish_action(a:RefCounted,save_each:bool=false)->bool:
	for phase in ["prepare_fixture","roll_once","stage","commit"]:
		var before:Dictionary=a.state_copy();var result:Dictionary=a.call(phase)
		if not verify(result.get("ok",false),phase+" "+str(result)):return false
		if phase!="commit" and not verify(C.bytes(before)==C.bytes(a.state_copy()),phase+" leaves facts unchanged"):return false
		if save_each:
			var copy=A.new();var load_:Dictionary=copy.load_data(JSON.parse_string(C.bytes(a.save_data())))
			if not verify(load_.ok,"restore "+phase+" "+str(load_)):
				print("RESTORE_STATUS ",a.state_copy().actors.actor_player.statuses);return false
			if not verify(C.bytes(copy.save_data())==C.bytes(a.save_data()),"exact save "+phase):return false
	var current:String=C.bytes(a.save_data());var duplicate:Dictionary=a.commit()
	return verify(duplicate.get("already_committed",false) and C.bytes(a.save_data())==current,"duplicate commit leaves facts/rolls unchanged")
func run()->void:
	var raw:Dictionary=G.generate(726381,4,"coastal_range")
	var a=A.new();if not verify(a.start_source(raw.source).ok,"admission"):return
	var anchor:Array=a.source.enemy_placement_result.attack_anchor_hex
	if not verify(not a.movement_preview(a.state_copy().actors[a.source.enemy_id].hex).ok,"cannot move into living enemy"):return
	if not verify(a.begin_intent(a.sample_goal("move",{"hex":anchor}),a.tile_reference(anchor)).ok,"approach intent"):return
	if not finish_action(a,true):return
	if not verify(a.enemy_response_available(),"approach schedules separately assessed enemy"):return
	var pending_before:String=C.bytes(a.state_copy());if not verify(a.begin_enemy_response().ok,"enemy intent"):return
	if not verify(C.bytes(a.state_copy())==pending_before,"enemy intent does not damage"):return
	if not finish_action(a,true):return
	var actions=0
	while a.state_copy().actors.actor_player.health.current>0 and a.state_copy().actors[a.source.enemy_id].health.current>0 and actions<32:
		actions+=1
		if a.enemy_response_available():
			if not verify(a.begin_enemy_response().ok,"next enemy intent"):return
		else:
			var kind="attack" if a.state_copy().actors.actor_player.stamina.current>0 else "rest"
			if not verify(a.begin_intent(a.sample_goal(kind),a.enemy_reference()).ok,"next player "+kind):return
		if not finish_action(a):return
	var state:Dictionary=a.state_copy()
	if not verify(state.actors.actor_player.health.current==0 or state.actors[a.source.enemy_id].health.current==0,"encounter reaches terminal health"):return
	if not verify(state.combat_turn.phase=="player","terminal never leaves impossible enemy phase"):return
	if not verify(not a.movement_preview(state.actors[a.source.enemy_id].hex).ok,"enemy occupied after encounter"):return
	var loaded=A.new();var restored:Dictionary=loaded.load_data(JSON.parse_string(C.bytes(a.save_data())))
	if not verify(restored.ok,"full encounter historical reconstruction "+str(restored)):return
	if not verify(a.save_file().ok,"actual disk save"):return
	var disk=A.new();if not verify(disk.load_file().ok and C.bytes(disk.save_data())==C.bytes(a.save_data()),"actual disk roundtrip"):return
	print("ENCOUNTER_PASS ",JSON.stringify({"assertions":assertions,"turn":state.turn,"player_health":state.actors.actor_player.health.current,"enemy_health":state.actors[a.source.enemy_id].health.current,"mock_only":true,"network_calls":0}))
	quit(0)
