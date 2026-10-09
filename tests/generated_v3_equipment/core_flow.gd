extends SceneTree
const A=preload("res://view/generated_v3_equipment/adapter.gd")
const E=preload("res://view/generated_v3_equipment/assessments.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Old=preload("res://view/generated_v3_enemy/adapter.gd")
const Main=preload("res://main.gd")
var checks=0
var failures:Array=[]
var rows:Array=[]
var phase_roundtrips:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("GEAR_FAIL ",label_)
	return value
func roundtrip(a:RefCounted,label_:String)->bool:
	var raw:String=C.bytes(a.save_data());var b=A.new();var result:Dictionary=b.load_data(JSON.parse_string(raw))
	if not check(result.ok and C.bytes(b.save_data())==raw,label_+" JSON "+str(result)):return false
	var path:String="user://equipment_phase_roundtrip.json"
	if not check(a.save_file(path).ok,label_+" actual disk write"):return false
	var disk=A.new();result=disk.load_file(path)
	if not check(result.ok and C.bytes(disk.save_data())==raw,label_+" actual disk read "+str(result)):return false
	phase_roundtrips.append({"label":label_,"phase":a.phase(),"json_exact":true,"disk_exact":true})
	return true
func complete(a:RefCounted,kind:String,focus:Dictionary={},restore_each:bool=false,ordinary_goal:String="")->bool:
	var begun:Dictionary=a.begin_enemy_response() if kind=="enemy_attack" else a.begin_intent(ordinary_goal if not ordinary_goal.is_empty() else a.sample_goal(kind,focus),focus)
	if not check(begun.ok,"begin "+kind+" "+str(begun.get("code",""))):return false
	if restore_each and not roundtrip(a,kind+" awaiting_assessment"):return false
	var interpreted_request:Dictionary=a.request()
	if not ordinary_goal.is_empty():
		check(not a.fixture_available(),"ordinary free text is never silently handled by a signed example")
		# Explicit offline model reply for this exact frozen natural-language request.
		# Only the test interpreter selects the existing resolver; the real request
		# and its context hash retain the user's original words unchanged.
		interpreted_request=interpreted_request.duplicate(true)
		interpreted_request.context.goal=a.sample_goal(kind,focus)
	var made:Dictionary=E.build(interpreted_request)
	if not check(made.ok,"example "+kind+" "+str(made.get("code",""))):return false
	var reply:Dictionary=made.assessment;reply.provenance={"provider":"explicit-offline-equipment-test","live":false,"kind":"model_reply"}
	if kind in ["attack","enemy_attack"]:
		for component in reply.components:component.parameters={"A":4,"D":0,"P":2} if kind=="attack" else {"A":0,"D":4,"P":-2}
	var before:String=C.bytes(a.state_copy());var result:Dictionary=a.import_reply(reply)
	if not check(result.ok,"prepare "+kind+" "+str(result)):return false
	if restore_each and not roundtrip(a,kind+" ready"):return false
	for step in ["roll_once","stage","commit"]:
		result=a.call(step)
		if not check(result.ok,kind+" "+step+" "+str(result)):return false
		if step!="commit":check(C.bytes(a.state_copy())==before,"precommit keeps custody/equipment "+kind)
		if restore_each and not roundtrip(a,kind+" "+step):return false
	var exact:String=C.bytes(a.save_data())
	check(a.commit().get("already_committed",false) and C.bytes(a.save_data())==exact,"duplicate commit "+kind)
	rows.append({"kind":kind,"ordinary_goal":ordinary_goal,"turn":a.state_copy().turn,"blade_owner":a.state_copy().items.item_raider_blade.owner_actor_id,"blade_revision":a.state_copy().items.item_raider_blade.custody_revision,"staff_revision":a.state_copy().items.item_coast_staff.custody_revision,"weapon":a.state_copy().actors.actor_player.equipment.weapon})
	return true
func run()->void:
	var raw:Dictionary=G.generate(726381,4,"coastal_range")
	var a=A.new();a.feature_options={"vegetation":true}
	var result:Dictionary=a.start_source(raw.source)
	if not check(result.ok,"new source admission "+str(result.get("code",""))+str(result.get("errors",[]))):finish();return
	if not roundtrip(a,"initial all-witness"):finish();return
	check(a.save_file("user://equipment_initial.json").ok,"actual initial disk save")
	var disk=A.new();check(disk.load_file("user://equipment_initial.json").ok,"actual initial disk load")
	var old=Old.new();old.feature_options={"vegetation":true};check(old.start_source(raw.source).ok,"frozen v21 still admits")
	check(a.source.identity.geometry_hash==old.source.identity.geometry_hash and C.bytes(a.source.navigation.allowed)==C.bytes(old.source.navigation.allowed),"unchanged exact geometry and occupied graph")
	check(not A.new().load_data(old.save_data()).ok and not Old.new().load_data(a.save_data()).ok,"profiles never silently migrate")
	check(not a._check_destination(old.default_save_path()).ok,"v21 path protected")
	var anchor:Array=a.source.enemy_placement_result.attack_anchor_hex
	if not complete(a,"move",a.tile_reference(anchor)):finish();return
	if a.enemy_response_available() and not complete(a,"enemy_attack"):finish();return
	var snapshot:String=C.bytes(a.state_copy())
	check(a.begin_intent(a.sample_goal("pickup_blade"),a.enemy_reference()).ok,"living-owner intent can await honest assessment")
	result=a.prepare_fixture();check(not result.ok and result.get("code")=="EQUIPMENT_LIVING_OWNER" and C.bytes(a.state_copy())==snapshot,"living owner rejected before mutation")
	check(a.cancel().ok,"cancel rejected theft")
	var attempts=0
	while a.state_copy().actors[a.source.enemy_id].health.current>0 and a.state_copy().actors.actor_player.health.current>0 and attempts<20:
		attempts+=1
		var kind:String="enemy_attack" if a.enemy_response_available() else ("attack" if a.state_copy().actors.actor_player.stamina.current>0 else "rest")
		if not complete(a,kind,a.enemy_reference() if kind=="attack" else {}):finish();return
	if not check(a.state_copy().actors[a.source.enemy_id].health.current==0,"legitimate encounter ends downed"):finish();return
	var stamina:int=a.state_copy().actors.actor_player.stamina.current
	for kind in ["drop_item","pickup_item","pickup_blade","equip_blade","equip_staff","equip_blade"]:
		var natural:String={"pickup_blade":"我俯身取走这个已经倒下的人手里的那把短刀，先收进自己的行囊。","equip_blade":"我把木杖放回行囊，改拿刚取来的短刃。","equip_staff":"我还是换回原来的木杖，把短刀留在行囊里。"}.get(kind,"")
		if not complete(a,kind,a.enemy_reference() if kind=="pickup_blade" else {},true,natural):finish();return
		check(a.state_copy().actors.actor_player.stamina.current==stamina,"custody/equipment no invented stamina cost")
	var state:Dictionary=a.state_copy()
	check(state.items.item_raider_blade.owner_actor_id=="actor_player" and state.actors[a.source.enemy_id].inventory.is_empty() and state.actors[a.source.enemy_id].equipment.is_empty(),"blade conserved and old owner cleared")
	check(state.actors.actor_player.equipment.weapon=="item_raider_blade" and state.items.item_raider_blade.weapon_profile.on_full_hit=="poison","authored capability retained, no new live target claimed")
	check(not a.movement_preview(state.actors[a.source.enemy_id].hex).ok,"looted downed cell remains occupied")
	for kind in ["pickup_blade","equip_blade"]:
		snapshot=C.bytes(a.state_copy());check(a.begin_intent(a.sample_goal(kind),a.enemy_reference()).ok,"duplicate intent waits")
		result=a.prepare_fixture();check(not result.ok and result.get("code")=="ITEM_DUPLICATE" and C.bytes(a.state_copy())==snapshot,"duplicate "+kind+" no effect/tick")
		check(a.cancel().ok,"duplicate cancel")
	check(a.save_file("user://equipment_final.json").ok,"actual complete disk save")
	disk=A.new();result=disk.load_file("user://equipment_final.json");check(result.ok and C.bytes(disk.save_data())==C.bytes(a.save_data()),"actual complete disk restoration "+str(result))
	check_history_tampering(a)
	finish()
func check_history_tampering(a:RefCounted)->void:
	var original:Dictionary=a.save_data();var live:String=C.bytes(original)
	var pickup_id="";var equip_id=""
	for id in original.engine.receipts:
		for patch in original.engine.receipts[id].patches:
			if patch.get("type")=="item_relocate" and patch.get("item_id")=="item_raider_blade":pickup_id=id
			if patch.get("type")=="item_equip":equip_id=id
	if not check(not pickup_id.is_empty() and not equip_id.is_empty(),"real pickup and equip receipts available for hostile replay probes"):return
	for mutation in ["bundle_collision","missing_item","malformed_item","malformed_patch","duplicate_effect"]:
		var forged:Dictionary=original.duplicate(true);forged.engine.erase("campaign_memory")
		var receipt:Dictionary=forged.engine.receipts[pickup_id if mutation=="bundle_collision" else equip_id]
		if mutation=="malformed_patch":receipt.patches=[null]
		else:
			for patch in receipt.patches:
				if mutation=="bundle_collision" and patch.get("type")=="item_relocate":patch.item_id="item_travel_bundle"
				elif patch.get("type")=="item_equip":
					if mutation=="missing_item":patch.erase("item_id")
					elif mutation=="malformed_item":patch.item_id={}
			if mutation=="duplicate_effect":receipt.patches.append(receipt.patches[0].duplicate(true))
		receipt.erase("receipt_hash");receipt.receipt_hash=C.digest(receipt)
		var result:Dictionary=A.new().load_data(JSON.parse_string(C.bytes(forged)))
		check(not result.ok,"self-rehashed malformed receipt rejected "+mutation+" "+str(result.get("code","")))
	check(C.bytes(a.save_data())==live,"hostile replay probes preserve live state/pending/RNG")
func finish()->void:
	FileAccess.open("res://artifacts/generated_v3_equipment/core_flow_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"phase_roundtrips":phase_roundtrips,"mock_only":true,"network_calls":0},"\t"))
	print("GEAR_CORE_FLOW ",checks," ",failures);quit(0 if failures.is_empty() else 1)
