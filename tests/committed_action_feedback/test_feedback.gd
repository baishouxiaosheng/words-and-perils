extends SceneTree
## Small presentation-only test: no terrain cache, scene, browser, or real game load.
const Router = preload("res://view/playable_build/committed_effect_router.gd")
const Presentation = preload("res://view/action_presentation.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array[String] = []
var evidence: Dictionary = {}
func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): printerr("FAIL: feedback watchdog"); quit(2))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func state(version: int = 0) -> Dictionary:
	return {"world_id":"feedback_unit","state_version":version,"actors":{"a":{"id":"a","health":{"current":12},"statuses":{}},"b":{"id":"b","health":{"current":12},"statuses":{}}}}
func receipt(version: int, style := "melee", outcome := "hit", damage := 3) -> Dictionary:
	var patches: Array = [{"type":"combat_event","actor_id":"a","target_actor_id":"b","weapon_item_id":"test_weapon","presentation_kind":style,"outcome":outcome}]
	if damage > 0: patches.append({"type":"actor_pool_delta","actor_id":"b","pool":"health","delta":-damage})
	return seal_receipt({"action_id":"feedback_unit:action_%d"%version,"actor_id":"a","before_version":version-1,"after_version":version,"stage_hash":"test_frozen_stage","branch_id":"attack_"+outcome+"_3","patches":patches,"hook_patches":[]})
func seal_receipt(value: Dictionary) -> Dictionary:
	value.erase("receipt_hash"); value.receipt_hash = C.digest(value); return value
func count(events: Array, kind: String) -> int:
	return events.filter(func(e): return e.kind == kind).size()
func run() -> void:
	var router := Router.new(); root.add_child(router)
	var a := Node3D.new(); var b := Node3D.new(); root.add_child(a); root.add_child(b); b.position = Vector3(2,0,0)
	var nodes := {"a":a,"b":b}
	var before := state(); var after := state(1); after.actors.b.health.current = 9
	var before_bytes := C.bytes(before); var after_bytes := C.bytes(after)
	router.reset_to(before)
	check(router.active_count()==0 and router.pending.is_empty(),"initial display has no effects")
	check(not router.consume({},before,after,nodes).ok,"canceled/uncommitted empty result emits nothing")
	var staged := receipt(1); staged.erase("receipt_hash")
	check(not router.consume(staged,before,after,nodes).ok,"staged result without committed receipt hash emits nothing")
	var hit := receipt(1)
	check(router.consume(hit,before,after,nodes).ok,"fresh commit accepted")
	check(count(router.last_events,"melee")==1 and count(router.last_events,"damage")==1,"melee + exact single authoritative damage event")
	check(router.last_events.filter(func(e):return e.kind=="damage")[0].amount==3,"popup amount exactly matches receipt")
	var emitted := router.emitted_effects
	check(not router.consume(hit,before,after,nodes).ok and router.emitted_effects==emitted,"double commit/refresh cannot replay")
	check(C.bytes(before)==before_bytes and C.bytes(after)==after_bytes,"presentation never mutates before or after authority")
	router._process(0.2)
	check(router.active_count()==2,"impact emitted after attack timing")
	router._process(2.0)
	check(router.active_count()==0 and router.pending.is_empty(),"short effects return to pool")
	var pool_size := router.slots.size()
	router.reset_to(after)
	check(nodes.size()==2 and nodes.a==a and nodes.b==b,"reset never clears the board-owned actor dictionary")
	check(not router.consume(hit,before,after,nodes).ok,"load baseline never replays saved committed receipt")
	var miss := receipt(2,"ranged","miss",0)
	check(router.consume(miss,after,state(2),nodes).ok,"new committed miss accepted after load baseline")
	check(count(router.last_events,"ranged")==1 and count(router.last_events,"miss")==1 and count(router.last_events,"damage")==0,"gunfire miss is whiff with no fake hit or damage")
	router._process(0.2); router._process(2.0)
	check(router.emitted_effects==emitted+3,"ranged projectile and miss popup actually render after a reset")
	check(router.slots.size()==pool_size,"pool is reused across attacks")
	var magic := receipt(3,"magic","graze",1)
	check(router.consume(magic,state(2),state(3),nodes).ok,"magic committed graze accepted")
	check(count(router.last_events,"magic")==1 and count(router.last_events,"damage")==1,"magic retains authoritative damage")
	check(router.last_events.filter(func(e):return e.kind=="damage")[0].text=="擦伤 −1","graze popup distinct from full hit")
	router.reset_to(state(3)); router._process(3.0)
	check(router.active_count()==0 and router.pending.is_empty(),"load cancels both active and delayed impacts")
	var poison_before := state(3)
	poison_before.actors.b.statuses.poison = {"kind":"poison","remaining_turns":1,"magnitude":1}
	var tick: Dictionary = seal_receipt({"action_id":"feedback_unit:action_4","actor_id":"a","before_version":3,"after_version":4,"stage_hash":"tick","branch_id":"observe","patches":[],"hook_patches":[{"type":"actor_pool_delta","actor_id":"b","pool":"health","delta":-1},{"type":"actor_status_remove","actor_id":"b","status_id":"poison"}]})
	check(router.consume(tick,poison_before,state(4),nodes).ok,"committed hook tick accepted")
	check(count(router.last_events,"damage")==1 and count(router.last_events,"status_end")==1,"poison tick plus expiry feedback distinct")
	check(router.last_events[0].cause=="poison" and router.last_events[0].text=="中毒 −1","poison uses semantic color/text and exact amount")
	var apply: Dictionary = seal_receipt({"action_id":"feedback_unit:action_5","actor_id":"a","before_version":4,"after_version":5,"stage_hash":"condition","branch_id":"condition","patches":[{"type":"actor_status_set","actor_id":"a","status_id":"flight","status":{"kind":"flight","remaining_turns":2,"magnitude":1}},{"type":"actor_status_set","actor_id":"b","status_id":"poison","status":{"kind":"poison","remaining_turns":2,"magnitude":1}}],"hook_patches":[]})
	check(router.consume(apply,state(4),state(5),nodes).ok,"committed statuses accepted")
	check(count(router.last_events,"flight")==1 and count(router.last_events,"poison")==1,"flight and poison get different semantic effects")
	var forged := receipt(6); forged.patches[1].delta=-6
	check(not router.consume(forged,state(5),state(6),nodes).ok,"tampered receipt cannot emit effects")
	for i in range(6,36): router.consume(receipt(i),state(i-1),state(i),nodes)
	check(router.slots.size()<=Router.MAX_ACTIVE and router.pending.size()<=Router.MAX_PENDING,"repeated commits bound draw nodes and pending work")
	check(router.slots.size()==Router.MAX_ACTIVE and router.dropped_effects>0,"burst saturation exercises the pool cap rather than silently losing actor bindings")
	router._process(1.0); router._process(2.0)
	check(router.active_count()==0 and router.pending.is_empty(),"saturated pool cleans up without timers or leaked active nodes")
	check(not router.is_processing(),"idle effect router stops processing")
	var gate_motion := Presentation.new(); root.add_child(gate_motion)
	gate_motion.register_actor("a",a,Vector3.ZERO); router.motion_presenter=gate_motion
	router.reset_to(state(35))
	var composite := receipt(36)
	composite.patches.push_front({"type":"actor_move","actor_id":"a","hex":[1,0]}); composite=seal_receipt(composite)
	gate_motion.move_actor_path("a",[Vector3(1,0,0),Vector3(1.5,0,0)],0.75)
	var before_emit := router.emitted_effects
	check(router.consume(composite,state(35),state(36),nodes).ok,"composite committed receipt accepted")
	router._process(1.0)
	check(router.active_count()==0 and router.emitted_effects==before_emit and router.pending.size()==2,"composite attack and impact wait for both route segments")
	gate_motion._process(2.0); gate_motion._process(2.0);router._process(0.0)
	check(router.active_count()==1 and router.emitted_effects==before_emit+1,"attack starts once only after settled arrival")
	var active_slots:Array=router.slots.filter(func(slot):return slot.active)
	check(active_slots[0].source.is_equal_approx(a.position+Vector3(0,0.64,0)),"composite attack originates at actual arrived token")
	router._process(0.2)
	check(router.emitted_effects==before_emit+2,"impact delay is measured after arrival")
	router._process(2.0)
	check(router.active_count()==0 and router.pending.is_empty(),"composite sequence returns completely to pool")
	var superseded:=receipt(37);superseded.patches.push_front({"type":"actor_move","actor_id":"a","hex":[2,0]});superseded=seal_receipt(superseded)
	gate_motion.move_actor("a",Vector3(3,0,0));router.consume(superseded,state(36),state(37),nodes)
	before_emit=router.emitted_effects;gate_motion.move_actor("a",Vector3(4,0,0));router._process(0.0)
	check(router.pending.is_empty() and router.emitted_effects==before_emit,"newer route generation discards stale queued attacks instead of launching from wrong square")
	gate_motion.reset_actor("a",Vector3.ZERO);gate_motion.register_actor("b",b,Vector3(2,0,0))
	gate_motion.move_actor("a",Vector3(1,0,0))
	var fast_player:=receipt(38);fast_player.patches.push_front({"type":"actor_move","actor_id":"a","hex":[1,0]});fast_player=seal_receipt(fast_player)
	var fast_npc:=receipt(39);fast_npc.actor_id="b";fast_npc.patches[0].actor_id="b";fast_npc.patches[0].target_actor_id="a";fast_npc.patches[1].actor_id="a";fast_npc=seal_receipt(fast_npc)
	before_emit=router.emitted_effects
	router.consume(fast_player,state(37),state(38),nodes);router.consume(fast_npc,state(38),state(39),nodes);router._process(0.5)
	check(router.active_count()==0 and router.emitted_effects==before_emit and router.pending.size()==4,"fast NPC receipt waits for moving target even though NPC source is stationary")
	gate_motion._process(2.0);router._process(0.0)
	check(router.active_count()==2 and router.emitted_effects==before_emit+2,"both fresh attacks start once after shared moving endpoint settles")
	var npc_slots:Array=router.slots.filter(func(slot):return slot.active and slot.event.get("source_id","")=="b")
	check(npc_slots.size()==1 and npc_slots[0].destination.is_equal_approx(a.position+Vector3(0,0.58,0)),"NPC effect targets arrived player rather than old mid-arc coordinate")
	router._process(0.2);router._process(2.0)
	check(router.active_count()==0 and router.pending.is_empty(),"fast consecutive committed effects clean up")
	router.reset_to(state(39));gate_motion.queue_free()
	evidence = router.report()
	var motion := Presentation.new(); root.add_child(motion)
	var token := Node3D.new(); token.scale=Vector3.ONE*0.62; root.add_child(token)
	motion.surface_height_sampler=func(xz:Vector2,_y:float):return maxf(0.0,xz.x*0.12)
	motion.register_actor("piece",token,Vector3.ZERO); motion.select_actor("piece"); motion._process(0.3)
	check(token.position.y>0.15,"selected piece lifts above surface")
	motion.move_actor_path("piece",[Vector3(2,0,0),Vector3(3,0,1)],0.75)
	var min_clearance := INF
	var min_foot_clearance := INF
	for i in range(220):
		motion._process(0.016)
		min_clearance=minf(min_clearance,token.position.y-maxf(0.0,token.position.x*0.12))
		if motion.actors.piece.moving and motion.actors.piece.progress>=0.83:
			for step in range(16):
				var angle:=TAU*float(step)/16.0
				var foot:=token.transform*Vector3(cos(angle)*0.38,0,sin(angle)*0.38)
				min_foot_clearance=minf(min_foot_clearance,foot.y-maxf(0.0,token.position.x*0.12))
	check(min_clearance>=-0.00001,"lift arc and settle root never sink below sampled visible surface")
	check(min_foot_clearance>=-0.00001,"rocking foot ring never dips below visible support plane during settle")
	check(not motion.actors.piece.moving and token.position.is_equal_approx(Vector3(3,0.36,1)),"multisegment route settles exactly on visible support")
	check(token.rotation.is_equal_approx(Vector3.ZERO),"settled token upright")
	evidence["checks"]=checks; evidence["failures"]=failures; evidence["minimum_movement_root_clearance"]=min_clearance; evidence["minimum_settle_foot_clearance"]=min_foot_clearance
	var file:=FileAccess.open("res://tests/committed_action_feedback/report.json",FileAccess.WRITE); file.store_string(JSON.stringify(evidence,"\t")); file.close()
	router.queue_free();motion.queue_free();a.queue_free();b.queue_free();token.queue_free();await process_frame
	if failures.is_empty(): print("COMMITTED ACTION FEEDBACK PASSED: %d assertions"%checks); quit(0)
	else: quit(1)
