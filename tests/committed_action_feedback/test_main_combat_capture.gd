extends SceneTree
## Actual default main + authored offline examples. Genuine seeded release-test RNG.
## No world/engine edits, teleports, forced rolls, injected damage, or fake VFX.
const Main=preload("res://main.tscn")
const Adapter=preload("res://view/playable_build/adapter.gd")
const Navigation=preload("res://view/playable_build/navigation.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/core_gameplay_20261003/"
var scene
var checks:=0
var failures:Array[String]=[]
var actions:Array=[]
var captures:Array=[]
var capture_frame_metrics:Array=[]
var enemy_responses:=0
var enemy_records:Array=[]
var initial_code:Dictionary={}
var test_seed:=1
var report_stem:="combat"
var watchdog:Timer
func _initialize()->void:
	watchdog=Timer.new();watchdog.one_shot=true;watchdog.wait_time=210.0;watchdog.autostart=true
	root.add_child(watchdog);watchdog.timeout.connect(_watchdog_expired)
	call_deferred("run")
func _watchdog_expired()->void:
	printerr("FAIL: combat native watchdog");exit_test(2)
func exit_test(code:int)->void:
	if is_instance_valid(watchdog):
		watchdog.stop();watchdog.timeout.disconnect(_watchdog_expired);watchdog.queue_free();watchdog=null
	if is_instance_valid(scene):scene.queue_free();scene=null
	quit(code)
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("COMBAT_CAPTURE_FAIL "+label)
func frames(n:=2)->void:
	for i in range(n):await process_frame
func distance(a:Array,b:Array)->int:
	var dq:=int(a[0])-int(b[0]);var dr:=int(a[1])-int(b[1])
	return maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))
func line_clear(state:Dictionary,from:Array,to:Array)->bool:
	for point in Basic.attack_line(from,to):
		var key:="%d,%d"%point
		if not state.hexes.has(key):return false
		var cell:Dictionary=state.hexes[key]
		if cell.ground_blocked or cell.air_blocked or cell.all_blocked:return false
	return true
func choose_position(min_range:int,max_range:int)->Array:
	var state:Dictionary=scene.playtest.state_copy();var origin:Array=state.actors.actor_player.hex;var target:Array=state.actors.actor_raider.hex
	if distance(origin,target)>=min_range and distance(origin,target)<=max_range and line_clear(state,origin,target):return origin.duplicate()
	var candidates:Array=[]
	for cell in state.hexes.values():
		var hex:Array=[cell.q,cell.r];var d:=distance(hex,target)
		if d<min_range or d>max_range or cell.ground_blocked or cell.all_blocked or not line_clear(state,hex,target):continue
		var occupied:=false
		for id in state.actors:
			if id!="actor_player" and state.actors[id].hex==hex:occupied=true
		if not occupied:candidates.append(hex)
	candidates.sort_custom(func(a,b):return distance(origin,a)<distance(origin,b))
	for hex in candidates:
		var route:Dictionary=Navigation.plan_route(state,"actor_player",hex,int(state.actors.actor_player.stamina.current))
		if route.get("ok",false):return hex
	return []
func focus_enemy()->void:
	var state:Dictionary=scene.playtest.state_copy()
	scene._apply_focus({"world_id":state.world_id,"kind":"actor","id":"actor_raider","hex":state.actors.actor_raider.hex.duplicate()})
func sample(kind:String)->bool:
	if scene.playtest.phase()!="idle" or scene._waiting_enemy_phase():
		check(false,kind+" starts only on player turn");return false
	var before:Dictionary=scene.playtest.state_copy();var accepted:int=scene.board.committed_feedback.accepted_receipts
	scene.fill_coast_sample(kind)
	check(not scene.goal.text.is_empty(),kind+" exact authored sample available")
	scene.end_turn()
	check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.state_copy())==C.bytes(before),kind+" intent does not mutate facts")
	scene.playtest_fixture()
	var after:Dictionary=scene.playtest.state_copy()
	var committed:bool=after.state_version==before.state_version+1
	check(committed,kind+" true committed resolution")
	check(scene.board.committed_feedback.accepted_receipts==accepted+1,kind+" fresh receipt reaches default board once")
	actions.append({"sample":kind,"before_version":before.state_version,"after_version":after.state_version,"player_hp":after.actors.actor_player.health.current,"target_hp":after.actors.actor_raider.health.current,"stamina":after.actors.actor_player.stamina.current,"events":scene.board.committed_feedback.last_events.duplicate(true)})
	return committed
func finish_enemy()->void:
	await frames()
	if scene._waiting_enemy_phase():scene._begin_required_enemy_turn()
	if scene.playtest.phase()=="awaiting_assessment" and scene.playtest.action_copy().get("actor_id","")!="actor_player":
		var before:Dictionary=scene.playtest.state_copy()
		check(before.combat_turn.phase=="enemy","enemy phase is authority, not a showcase")
		var frozen:=C.bytes(scene.playtest.action_copy())
		check(not scene.goal.editable and scene.submit_button.disabled,"pending enemy phase locks player input and primary submission")
		scene.end_turn()
		check(C.bytes(scene.playtest.state_copy())==C.bytes(before) and C.bytes(scene.playtest.action_copy())==frozen,"player End Turn cannot skip frozen enemy wait")
		scene.save_game();check(scene.last_save_result.get("ok",false),"pending enemy save reports success")
		scene.load_game();check(scene.last_load_result.get("ok",false),"pending enemy load reports success")
		check(scene.playtest.phase()=="awaiting_assessment" and C.bytes(scene.playtest.action_copy())==frozen and C.bytes(scene.playtest.state_copy())==C.bytes(before),"load restores exact frozen enemy request and unchanged combat facts")
		check(not scene.goal.editable and scene.submit_button.disabled,"restored enemy request still locks player input")
		scene.playtest_fixture()
		if scene.playtest.phase() in ["ready_roll","rolled","staged"]:scene.end_turn()
		var after:Dictionary=scene.playtest.state_copy()
		check(after.state_version==before.state_version+1,"explicit enemy fixture uses same real commit path")
		if after.state_version==before.state_version+1:enemy_responses+=1
		enemy_records.append({"before_version":before.state_version,"after_version":after.state_version,"before_player_hp":before.actors.actor_player.health.current,"after_player_hp":after.actors.actor_player.health.current,"events":scene.board.committed_feedback.last_events.duplicate(true)})
		scene.complete_requested_turn()
		check(C.bytes(scene.playtest.state_copy())==C.bytes(after),"duplicate enemy completion does not apply damage or costs twice")
		await frames()
	check(scene.playtest.phase()=="idle" and not scene._waiting_enemy_phase(),"pending enemy phase resolved before next player action")
func move_to(hex:Array)->bool:
	if hex.is_empty():check(false,"legal combat approach found");return false
	if hex==scene.playtest.state_copy().actors.actor_player.hex:return true
	scene.on_hex_selected(Vector2i(hex[0],hex[1]))
	if not sample("move"):return false
	var deadline:=Time.get_ticks_msec()+18000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<deadline:await process_frame
	check(not scene.board.presentation.actors.actor_player.moving,"committed approach plays each edge and settles")
	await finish_enemy();return true
func wait_for_production_framing()->void:
	var deadline:=Time.get_ticks_msec()+4000
	while scene.board.committed_camera.active and Time.get_ticks_msec()<deadline:await process_frame
	check(not scene.board.committed_camera.active,"ordinary production camera framing settles within bounded time")
func check_feedback_region()->void:
	var safe:Rect2=scene.board.committed_camera.raw_rect()
	check(safe.has_area(),"main supplies a real visible feedback region")
	for control in [scene.area_panel,scene.map_cluster,scene.hero_panel,scene.action_panel,scene.journal_panel]:
		if control.visible:check(not safe.intersects(control.get_global_rect()),"feedback region never overlaps visible "+str(control.name))
func sample_battle_frame_metrics(style:String)->Dictionary:
	var intervals:Array=[];var process_deltas:Array=[];var fps_samples:Array=[]
	var last_us:=-1
	for i in range(6):
		await process_frame
		if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
		var now_us:=Time.get_ticks_usec()
		if last_us>=0:intervals.append(float(now_us-last_us)/1000.0)
		last_us=now_us
		process_deltas.append(scene.get_process_delta_time())
		fps_samples.append(Engine.get_frames_per_second())
	var sum_ms:=0.0;var maximum_ms:=0.0
	for interval in intervals:sum_ms+=float(interval);maximum_ms=maxf(maximum_ms,float(interval))
	var submitted:Array=[]
	var viewport_rect:Rect2=root.get_visible_rect()
	for slot in scene.board.committed_feedback.slots:
		if not slot.active:continue
		var anchor:Vector2=scene.board.camera.unproject_position(slot.label.global_position)
		submitted.append({"kind":slot.event.kind,"mesh_instances_submitted":slot.drawing.multimesh.visible_instance_count,"label":slot.label.text,"label_visible_in_tree":slot.label.is_visible_in_tree(),"label_anchor_inside_viewport":viewport_rect.has_point(anchor)})
	var metrics:={"style":style,"viewport_size":[root.size.x,root.size.y],"display_server":DisplayServer.get_name(),"rendered_frame_samples":DisplayServer.get_name()!="headless","frame_intervals_ms":intervals,"mean_frame_interval_ms":sum_ms/maxi(1,intervals.size()),"max_frame_interval_ms":maximum_ms,"scene_process_delta_seconds":process_deltas,"engine_fps_samples":fps_samples,"submitted_effects":submitted,"measurement_scope":"Scene rendering while only the committed VFX clock is paused; geometry submission is not an occlusion/pixel visibility test","natural_time_effect_visibility_verified":false}
	capture_frame_metrics.append(metrics)
	return metrics
func capture_committed(name_:String,style:String,at:float)->void:
	var router:Node3D=scene.board.committed_feedback
	var committed_bytes:=C.bytes(scene.playtest.state_copy())
	var events:Array=router.last_events.duplicate(true)
	check(events.filter(func(e):return e.kind==style).size()==1,"committed "+style+" appears exactly once")
	# Freeze only the presentation clock at a real committed effect's sample.
	# This enables a reliable llvmpipe screenshot without extending gameplay.
	router.set_process(false)
	await wait_for_production_framing()
	router._process(0.0);router._process(at);router.set_process(false)
	check_feedback_region()
	var safe:Rect2=scene.board.committed_camera.usable_rect()
	for id in ["actor_player","actor_raider"]:
		check(safe.has_point(scene.board.camera.unproject_position(scene.board.token_nodes[id].global_position+Vector3(0,0.5,0))),"ordinary End Turn frames actual "+id+" body outside HUD")
	var frame_metrics:Dictionary=await sample_battle_frame_metrics(style)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+name_+".png")
	check(C.bytes(scene.playtest.state_copy())==committed_bytes,"screenshot sampling changes no authoritative fact")
	captures.append({"file":name_+".png" if DisplayServer.get_name()!="headless" else "","rendered":DisplayServer.get_name()!="headless","style":style,"effect_time":at,"capture_mode":"Ordinary production camera only; frozen VFX clock on a genuinely committed event for shape/alignment","natural_time_visibility_verified":false,"frame_metrics":frame_metrics,"production_camera":scene.board.committed_camera.report(),"events":events,"pool":router.report()})
	router._process(3.0)
	check(router.active_count()==0 and router.pending.is_empty(),"captured effects return completely to pool")
func collect_code(path:String,records:Dictionary)->void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	directory.list_dir_begin()
	var name_:String=directory.get_next()
	while not name_.is_empty():
		var child:String=path.path_join(name_)
		if directory.current_is_dir():collect_code(child,records)
		elif name_.get_extension() in ["gd","gdshader","tscn","tres"]:records[child]=FileAccess.get_sha256(child)
		name_=directory.get_next()
	directory.list_dir_end()
func code_signature()->Dictionary:
	var records:Dictionary={}
	for path in ["res://main.gd","res://main.tscn","res://project.godot","res://artifacts/world_bundle_20261002/manifest.json","res://tests/core_gameplay/test_release_rule.gd"]:records[path]=FileAccess.get_sha256(path)
	for path in ["res://core","res://view","res://shared","res://relay","res://tests/committed_action_feedback"]:collect_code(path,records)
	return records
func requested_viewport()->Vector2i:
	var parts:=OS.get_environment("FOGBANK_QA_VIEWPORT").split("x")
	if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():return Vector2i(clampi(int(parts[0]),800,2560),clampi(int(parts[1]),600,1440))
	return Vector2i(1440,900)
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT);root.size=requested_viewport();initial_code=code_signature()
	scene=Main.instantiate();scene.coast_adventure=Adapter.new(test_seed,true);root.add_child(scene);await frames(10)
	check(scene.coast_mode and scene.board.load_error.is_empty(),"actual default coast board loaded")
	check(scene.playtest.engine.rule_id()=="ai_gm_test_coast_release/v1","deterministic proof remains honestly test-labelled")
	check(scene.playtest.state_copy().actors.has("actor_raider"),"authored hostile and weapon capabilities exist")
	if not sample("pickup"):await finish();return
	if not sample("equip_bow"):await finish();return
	if not await move_to(choose_position(2,3)):await finish();return
	if scene.playtest.state_copy().actors.actor_player.stamina.current<2:
		if not sample("rest"):await finish();return
	focus_enemy();scene.board.focus_player()
	if not sample("attack"):await finish();return
	check(scene.board.committed_feedback.last_events.filter(func(e):return e.kind=="miss").size()==1,"seed1 genuine first firearm attack misses")
	check(scene.board.committed_feedback.last_events.filter(func(e):return e.kind=="damage").is_empty(),"firearm miss has no damage popup or hit flash")
	await capture_committed("combat_01_firearm_miss","ranged",0.14)
	await finish_enemy()
	if not sample("equip_wand"):await finish();return
	focus_enemy()
	if not sample("attack"):await finish();return
	await capture_committed("combat_02_magic_committed","magic",0.54)
	await finish_enemy()
	if not sample("equip"):await finish();return
	if scene.playtest.state_copy().actors.actor_player.stamina.current<3:
		if not sample("rest"):await finish();return
	root.size=Vector2i(1280,720) if root.size.x>=1440 else Vector2i(1440,900);await frames(3);scene.apply_responsive_layout()
	if not scene.journal_open:scene.toggle_journal()
	await frames(3);scene.apply_responsive_layout()
	if not await move_to(choose_position(1,1)):await finish();return
	if scene.playtest.state_copy().actors.actor_player.stamina.current<1:
		if not sample("rest"):await finish();return
	focus_enemy()
	if not sample("attack"):await finish();return
	await capture_committed("combat_03_melee_committed","melee",0.21)
	if scene.journal_open:scene.toggle_journal()
	await finish_enemy()
	var state:Dictionary=scene.playtest.state_copy();var token_count:int=scene.board.token_nodes.size()
	var accepted:int=scene.board.committed_feedback.accepted_receipts
	scene.complete_requested_turn();scene.refresh_world(true)
	check(scene.board.committed_feedback.accepted_receipts==accepted,"repeat completion and ordinary refresh emit no new effects")
	scene.save_game();check(scene.last_save_result.get("ok",false),"combat save actually reports success")
	scene.load_game();check(scene.last_load_result.get("ok",false),"combat load actually reports success")
	check(C.bytes(scene.playtest.state_copy())==C.bytes(state),"save/load retains exact combat facts")
	check(scene.board.token_nodes.size()==token_count and scene.board.committed_feedback.active_count()==0 and scene.board.committed_feedback.pending.is_empty(),"load preserves token identities and never replays combat")
	await finish()
func finish()->void:
	check(enemy_responses>=1,"at least one actual mandatory NPC response exercised")
	var final_code:=code_signature()
	check(C.bytes(initial_code)==C.bytes(final_code),"core/view/main source unchanged throughout proof")
	var report:={"checks":checks,"failures":failures,"actions":actions,"captures":captures,"capture_frame_metrics":capture_frame_metrics,"enemy_responses":enemy_responses,"enemy_records":enemy_records,"source_start":initial_code,"source_end":final_code,"actual_main":true,"deterministic_release_test_seed":test_seed,"synthetic_damage":false,"forced_rng_outcomes":false}
	var file:=FileAccess.open(OUT+report_stem+("_headless_report.json" if DisplayServer.get_name()=="headless" else "_native_report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ACTUAL MAIN COMBAT CAPTURE %s: %d assertions"%["PASSED" if failures.is_empty() else "FAILED",checks])
	# Drain ordinary UI/font deferred work while the scene remains alive, then
	# mirror the clean core harness: do not render new frames after destruction.
	await frames(4)
	exit_test(0 if failures.is_empty() else 1)
