extends "res://tests/committed_action_feedback/test_main_combat_capture.gd"
## Fresh actual main, one assessed move-then-attack, then mandatory NPC response.
## All gameplay changes use the normal explicit authored sample/UI commit path.
func run()->void:
	test_seed=2;report_stem="composite"
	DirAccess.make_dir_recursive_absolute(OUT);root.size=requested_viewport();initial_code=code_signature()
	scene=Main.instantiate();scene.coast_adventure=Adapter.new(test_seed,true);root.add_child(scene);await frames(10)
	check(scene.coast_mode and scene.board.load_error.is_empty(),"actual coast loaded for composite proof")
	check(scene.playtest.engine.rule_id()=="ai_gm_test_coast_release/v1","composite uses honest seeded release-test rule")
	if not sample("pickup"):await finish();return
	if not sample("equip"):await finish();return
	focus_enemy();scene.board.focus_player()
	if not scene.journal_open:scene.toggle_journal()
	await frames(3);scene.apply_responsive_layout()
	var before:Dictionary=scene.playtest.state_copy()
	var actor_origin:Vector3=scene.board.token_nodes.actor_player.position
	var emitted:int=scene.board.committed_feedback.emitted_effects
	if not sample("move_attack"):await finish();return
	var result:Dictionary=scene.playtest.authoritative_result()
	var after:Dictionary=scene.playtest.state_copy()
	check(result.get("rolls",[]).size()==3 and result.get("outcomes",{}).get("move",false),"genuine seed2 resolves all three checks and succeeds at movement")
	check(after.turn==before.turn+1 and after.state_version==before.state_version+1,"composite is exactly one intentional commit")
	check(after.actors.actor_player.hex!=before.actors.actor_player.hex,"committed composite arrives at an actual different legal cell")
	check(after.combat_turn.phase=="enemy","reached living hostile schedules mandatory NPC phase")
	var charged:=0;var patrol_steps:=0;var route_steps:=0
	for effect in result.public_effects:
		if effect.type=="actor_pool_delta" and effect.actor_id=="actor_player" and effect.pool=="stamina":charged-=int(effect.delta)
		if effect.type=="actor_move":
			if effect.actor_id=="actor_player":route_steps+=1
			elif effect.actor_id=="actor_scout":patrol_steps+=1
	check(charged==int(before.actors.actor_player.stamina.current)-int(after.actors.actor_player.stamina.current) and charged>1,"full route and attack costs charged once by real receipt")
	check(patrol_steps<=1,"composite never ticks patrol once per route edge")
	var router:Node3D=scene.board.committed_feedback
	check(scene.board.presentation.actors.actor_player.moving and route_steps>0,"actual route presentation begins from committed movement patches")
	check(router.active_count()==0 and router.emitted_effects==emitted and not router.pending.is_empty(),"attack visuals are queued while the committed actor is still moving")
	# Stop only the FX clock until arrival, allowing the normal per-edge motion.
	router.set_process(false)
	var deadline:=Time.get_ticks_msec()+18000
	while scene.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()<deadline:await process_frame
	check(not scene.board.presentation.actors.actor_player.moving,"composite route finishes before attack presentation")
	router._process(0.0);router.set_process(false)
	check(router.emitted_effects==emitted+1 and router.active_count()==1,"settled arrival starts exactly one melee visual")
	var slots:Array=router.slots.filter(func(slot):return slot.active)
	if not slots.is_empty():
		check(slots[0].source.is_equal_approx(scene.board.token_nodes.actor_player.position+Vector3(0,0.64,0)) and scene.board.token_nodes.actor_player.position.distance_to(actor_origin)>0.1,"attack origin is arrived token, never old square")
	await capture_committed("composite_01_arrive_then_attack","melee",0.21)
	if scene.journal_open:scene.toggle_journal()
	await finish_enemy()
	check(enemy_responses==1,"one composite provokes exactly one adjudicated mandatory NPC response")
	check(scene.playtest.combat_phase().phase=="player","completed NPC response returns authority to player")
	var final_state:=C.bytes(scene.playtest.state_copy())
	scene.save_game();check(scene.last_save_result.get("ok",false),"composite/NPC result saves successfully")
	scene.load_game();check(scene.last_load_result.get("ok",false),"composite/NPC result loads successfully")
	check(C.bytes(scene.playtest.state_copy())==final_state and router.active_count()==0 and router.pending.is_empty(),"loaded composite history never replays movement or attack effects")
	await finish()
