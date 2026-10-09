extends SceneTree
## Final accepted-copy check. Inputs: exact mouse save, exact lethal-loot save,
## then two frozen V21 saves. Never reselects RNG or copies input saves to release.
const Gear=preload("res://view/generated_v3_equipment/adapter.gd")
const Old=preload("res://view/generated_v3_enemy/adapter.gd")
const E=preload("res://view/generated_v3_equipment/assessments.gd")
const Main=preload("res://main.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures:Array=[]
var inputs:Array=[]
var snapshots:Array=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("ADOPTED_GEAR_FAIL ",label_)
	return value
func roundtrip(a:RefCounted,label_:String)->bool:
	var raw:String=C.bytes(a.save_data());var json_copy=Gear.new();var loaded:Dictionary=json_copy.load_data(JSON.parse_string(raw))
	if not check(loaded.ok and C.bytes(json_copy.save_data())==raw,label_+" complete JSON history exact"):return false
	var path:String="user://adopted_equipment_"+label_+".json"
	if not check(a.save_file(path).ok,label_+" actual disk write"):return false
	var disk=Gear.new();loaded=disk.load_file(path)
	if not check(loaded.ok and C.bytes(disk.save_data())==raw,label_+" complete disk history exact "+str(loaded.get("code",""))):return false
	snapshots.append({"label":label_,"phase":a.phase(),"turn":a.state_copy().turn,"health":a.state_copy().actors.actor_player.health.current,"weapon":a.state_copy().actors.actor_player.equipment.weapon,"json_exact":true,"disk_exact":true})
	return true
func contains_patch(a:RefCounted,type_:String,item_:String)->bool:
	for receipt in a.engine.save_data().receipts.values():
		for patch in receipt.patches:
			if patch.get("type")==type_ and patch.get("item_id")==item_:return true
	return false
func _input_paths()->PackedStringArray:
	return OS.get_cmdline_user_args()
func run()->void:
	var paths:PackedStringArray=_input_paths()
	if not check(paths.size()==4,"four explicit previously proven input files"):finish();return
	for index in range(4):
		var path:String=paths[index]
		if not check(FileAccess.file_exists(path),"actual proved input exists "+str(index)):finish();return
		var hash_:String=FileAccess.get_sha256(path)
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		var a:RefCounted=Gear.new() if index<2 else Old.new()
		var loaded:Dictionary=a.load_file(path)
		if not check(loaded.ok and C.bytes(a.save_data())==C.bytes(value),"adopted source exactly reads prior proved history "+str(index)+" "+str(loaded.get("code",""))):finish();return
		inputs.append({"filename":path.get_file(),"input_sha256":hash_,"profile":a.source.identity.profile,"turn":a.state_copy().turn})
		if index>=2:
			check(not Gear.new().load_data(value).ok,"historic V21 cannot silently become equipment")
		else:
			var state:Dictionary=a.state_copy()
			check(state.items.item_raider_blade.owner_actor_id=="actor_player" and state.actors.actor_village_hostile.inventory.is_empty() and state.actors.actor_village_hostile.equipment.is_empty(),"loaded conserved blade and emptied original owner "+str(index))
			check(contains_patch(a,"item_relocate","item_raider_blade"),"real pickup receipt replayed through adopted resolver "+str(index))
			check(not a.movement_preview(state.actors.actor_village_hostile.hex).ok,"looted corpse remains occupied "+str(index))
			if not roundtrip(a,"loaded_"+str(index)):finish();return
			if index==0:
				check(state.actors.actor_player.equipment.weapon=="item_coast_staff" and contains_patch(a,"item_equip","item_raider_blade") and contains_patch(a,"item_equip","item_coast_staff"),"real native pickup/blade/staff swap history retained")
				var before:String=C.bytes(a.state_copy());var rng:String=C.bytes(a.engine.save_data().rng)
				var goal_="我把木杖收好，换上已经属于我的短刃。"
				if not check(a.begin_intent(goal_).ok,"new ordinary assessed swap on actual adopted copy"):finish();return
				if not roundtrip(a,"new_swap_pending"):finish();return
				var interpreted:Dictionary=a.request().duplicate(true);interpreted.context.goal=E.goal("equip_blade")
				var reply:Dictionary=E.build(interpreted).assessment;reply.provenance={"provider":"explicit-offline-adopted-copy","kind":"model_reply","live":false}
				if not check(a.import_reply(reply).ok,"adopted new swap assessment accepted"):finish();return
				for step in ["roll_once","stage","commit"]:
					if not check(a.call(step).ok,"adopted new swap "+step):finish();return
					if step!="commit":check(C.bytes(a.state_copy())==before,"adopted provisional phase has no gear/health effect")
				check(a.state_copy().actors.actor_player.equipment.weapon=="item_raider_blade" and C.bytes(a.engine.save_data().rng)==rng,"adopted safe swap selects blade without new dice")
				var exact:String=C.bytes(a.save_data());check(a.commit().get("already_committed",false) and C.bytes(a.save_data())==exact,"adopted repeated commit unchanged")
				if not roundtrip(a,"new_swap_committed"):finish();return
			else:
				check(state.actors.actor_player.health.current==0 and state.actors.actor_player.statuses.is_empty() and state.turn==12,"actual poison-lethal pickup restored after its single final tick")
				var last:Dictionary={}
				for receipt in a.engine.save_data().receipts.values():
					if receipt.turn==state.turn:last=receipt
				var ticks=0
				for patch in last.hook_patches:
					if patch.get("type")=="actor_pool_delta" and patch.get("actor_id")=="actor_player" and patch.get("pool")=="health" and patch.get("delta")==-1:ticks+=1
				check(ticks==1 and last.branch_id=="pickup_item_success","single poison tick is bound to the committed blade pickup")
				var exact:String=C.bytes(a.save_data())
				check(a.engine.commit(last.action_id,last.stage_hash).get("already_committed",false) and C.bytes(a.save_data())==exact,"restored lethal commit cannot repeat pickup or poison")
				check(not a.begin_intent(a.sample_goal("equip_blade")).ok and C.bytes(a.save_data())==exact,"downed traveler cannot mutate gear or add a new intention")
		check(FileAccess.get_sha256(path)==hash_,"input save remains byte-exact "+str(index))
	finish()
func finish()->void:
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"snapshots":snapshots,"network_calls":0,"mock_only":true,"scope":"actual adopted-copy Main parse, exact prior pickup/equip/poison history and JSON/disk, one additional assessed ordinary swap, no RNG reselection, two genuine V21 files unchanged"}
	FileAccess.open("res://artifacts/generated_v3_equipment/adopted_copy_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ADOPTED_EQUIPMENT_COPY ",checks," ",failures);quit(0 if failures.is_empty() else 1)
