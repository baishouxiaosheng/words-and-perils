extends SceneTree
## Actual, normally rolled release histories, including poison-lethal loot.
## Bounded fresh-world retries select a stochastic fixture, never replace RNG.
const A=preload("res://view/generated_v3_equipment/adapter.gd")
const E=preload("res://view/generated_v3_equipment/assessments.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures:Array=[]
var attempts:Array=[]
var phases:Array=[]
var outcomes:Array=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("POISON_HISTORY_FAIL ",label_)
	return value
func action(a:RefCounted,kind:String,strength:String="weak")->bool:
	var focus:Dictionary=a.tile_reference(a.source.enemy_placement_result.attack_anchor_hex) if kind=="move" else (a.enemy_reference() if kind=="attack" else {})
	if kind=="observe":focus=a.tile_reference(a.state_copy().actors.actor_player.hex)
	var begin:Dictionary=a.begin_enemy_response() if kind=="enemy_attack" else a.begin_intent(a.sample_goal(kind,focus),focus)
	if not check(begin.ok,"honest assessed setup begin "+kind+" "+str(begin.get("code",""))):return false
	var made:Dictionary=E.build(a.request())
	if not check(made.ok,"explicit offline setup interpretation "+kind):return false
	var reply:Dictionary=made.assessment;reply.provenance={"provider":"explicit-offline-poison-history","live":false,"kind":"model_reply"}
	if kind in ["attack","enemy_attack"]:
		for component in reply.components:component.parameters={"A":4,"D":0,"P":2} if kind=="attack" or strength=="strong" else {"A":0,"D":4,"P":-2}
	var prepared:Dictionary=a.import_reply(reply)
	if not check(prepared.ok,"honest assessed setup prepare "+kind+" "+str(prepared.get("code",""))+" "+str(prepared.get("message",""))):return false
	for step in ["roll_once","stage","commit"]:
		if not check(a.call(step).ok,"honest assessed setup "+kind+" "+step):return false
	return true
func match_state(a:RefCounted,expected:Array)->bool:
	var s:Dictionary=a.state_copy();var player:Dictionary=s.actors.actor_player
	return player.health.current==expected[2] and s.actors.actor_village_hostile.health.current==expected[3] and int(player.statuses.get("weapon_poison",{}).get("remaining_turns",0))==expected[4]
func make_fixture(raw:Dictionary,lethal:bool)->RefCounted:
	var steps:Array=[["move","weak",12,5,0],["enemy_attack","weak",12,5,0],["attack","weak",12,2,0],["enemy_attack","strong",10,2,2],["attack","weak",9,0,1]]
	if lethal:steps=[["move","weak",12,5,0],["enemy_attack","strong",10,5,2],["observe","weak",9,5,1],["enemy_attack","weak",8,5,0],["attack","weak",8,2,0],["enemy_attack","strong",6,2,2],["observe","weak",5,2,1],["enemy_attack","weak",4,2,0],["observe","weak",4,2,0],["enemy_attack","strong",2,2,2],["attack","weak",1,0,1]]
	for index in range(8):
		var a=A.new();a.feature_options={"vegetation":true}
		var admitted:Dictionary=a.start_source(raw)
		if not check(admitted.ok,"fresh poisoned-history source admission"):return null
		var matched=true;var completed=0
		for step in steps:
			if not action(a,step[0],step[1]):return null
			completed+=1
			if not match_state(a,step):matched=false;break
		attempts.append({"lethal":lethal,"attempt":index+1,"completed_setup_actions":completed,"matched_stochastic_fixture":matched,"health":a.state_copy().actors.actor_player.health.current,"enemy_health":a.state_copy().actors.actor_village_hostile.health.current})
		if matched:
			check(a.engine.save_data().rng.mode=="runtime_random","runtime entropy never overridden for poisoned history")
			return a
	check(false,"bounded normal-RNG poisoned-history fixture exhausted "+str(lethal));return null
func roundtrip(a:RefCounted,label_:String)->bool:
	var raw:String=C.bytes(a.save_data());var json_copy=A.new();var loaded:Dictionary=json_copy.load_data(JSON.parse_string(raw))
	if not check(loaded.ok and C.bytes(json_copy.save_data())==raw,"poison "+label_+" exact JSON history"):return false
	var path="user://equipment_poisoned_history.json"
	if not check(a.save_file(path).ok,"poison "+label_+" actual disk write"):return false
	var disk=A.new();loaded=disk.load_file(path)
	if not check(loaded.ok and C.bytes(disk.save_data())==raw,"poison "+label_+" actual disk history reload "+str(loaded.get("code",""))):return false
	phases.append({"case":label_,"phase":a.phase(),"health":a.state_copy().actors.actor_player.health.current,"blade_owner":a.state_copy().items.item_raider_blade.owner_actor_id,"poison":a.state_copy().actors.actor_player.statuses.duplicate(true),"json_exact":true,"disk_exact":true})
	return true
func run()->void:
	var generated:Dictionary=G.generate(726381,4,"coastal_range")
	if not check(generated.ok,"finite seed generated"):finish();return
	for lethal in [false,true]:
		var a:RefCounted=make_fixture(generated.source,lethal)
		if a==null:finish();return
		var prefix:String="lethal" if lethal else "surviving"
		var before:String=C.bytes(a.state_copy());var hp:int=a.state_copy().actors.actor_player.health.current
		if not check(a.begin_intent(a.sample_goal("pickup_blade"),a.enemy_reference()).ok,prefix+" begin real poisoned pickup"):finish();return
		if not roundtrip(a,prefix+" awaiting_assessment"):finish();return
		var reply:Dictionary=E.build(a.request()).assessment;reply.provenance={"provider":"explicit-offline-poison-history","live":false,"kind":"model_reply"}
		if not check(a.import_reply(reply).ok,prefix+" prepare real poisoned pickup"):finish();return
		if not roundtrip(a,prefix+" ready"):finish();return
		for step in ["roll_once","stage","commit"]:
			if not check(a.call(step).ok,prefix+" "+step):finish();return
			if step!="commit":check(C.bytes(a.state_copy())==before,prefix+" no provisional poison or custody mutation")
			if not roundtrip(a,prefix+" "+step):finish();return
		var s:Dictionary=a.state_copy()
		check(s.actors.actor_player.health.current==hp-1 and s.actors.actor_player.statuses.is_empty(),prefix+" exactly one final poison tick and expiration")
		check(s.items.item_raider_blade.owner_actor_id=="actor_player" and s.items.item_raider_blade.custody_revision==1 and s.actors.actor_village_hostile.inventory.is_empty(),prefix+" pickup survives the final poison tick exactly once")
		var exact:String=C.bytes(a.save_data())
		check(a.commit().get("already_committed",false) and C.bytes(a.save_data())==exact,prefix+" duplicate commit cannot tick or relocate again")
		if lethal:
			check(s.actors.actor_player.health.current==0 and not a.begin_intent(a.sample_goal("equip_blade")).ok,"poison-lethal pickup saved but downed actor cannot equip")
		else:
			if not action(a,"equip_blade"):finish();return
			check(a.state_copy().actors.actor_player.health.current==hp-1,"later equip cannot replay expired poison")
			if not roundtrip(a,prefix+" equip after poison expired"):finish();return
		outcomes.append({"lethal":lethal,"turn":a.state_copy().turn,"health":a.state_copy().actors.actor_player.health.current,"blade_owner":a.state_copy().items.item_raider_blade.owner_actor_id,"weapon":a.state_copy().actors.actor_player.equipment.weapon})
	finish()
func finish()->void:
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"attempts":attempts,"phases":phases,"outcomes":outcomes,"mock_only":true,"network_calls":0,"scope":"normally rolled, separately assessed real histories; poisoned pickup including lethal final tick at each JSON/disk phase; equip occurs after natural poison expiry; poisoned equip remains detached authority coverage"}
	FileAccess.open("res://artifacts/generated_v3_equipment/poisoned_history_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EQUIPMENT_POISONED_HISTORY ",checks," ",failures);quit(0 if failures.is_empty() else 1)
