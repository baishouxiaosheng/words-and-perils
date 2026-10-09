extends SceneTree
const Adapter=preload("res://view/generated_inventory/adapter.gd")
const Legacy=preload("res://view/generated_adventure/adapter.gd")
const Seeded=preload("res://view/generated_adventure/seeded_adapter.gd")
const Contract=preload("res://core/world_generation_contract.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Focus=preload("res://view/generated_inventory/item_focus.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
const Examples=preload("res://view/generated_inventory/assessments.gd")
const Details=preload("res://view/playable_build/player_details.gd")
const OUT="res://artifacts/generated_pack_selection/"
var checks:=0
var failures:Array[String]=[]
var envelope:Dictionary
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> bool:
	checks+=1
	if not ok:failures.append(label);printerr("PACK_FOCUS_FAIL ",label)
	return ok
func execute(a:RefCounted,kind:String,focus:Dictionary={}) -> bool:
	return a.begin_intent(a.sample_goal(kind,focus),focus).ok and a.prepare_fixture().ok and a.roll_once().ok and a.stage().ok and a.commit().ok
func roundtrip(a:RefCounted,label:String) -> RefCounted:
	var exact:String=C.bytes(a.save_data());var b:=Adapter.new()
	check(b.load_data(JSON.parse_string(exact)).ok,label+" loads")
	check(C.bytes(b.save_data())==exact,label+" exact source/focus/receipt/RNG")
	check(a.save_file(OUT+label+".json").ok,label+" durable file")
	return b
func reject_focus(a:RefCounted,ref:Dictionary,label:String) -> void:
	var exact:String=C.bytes(a.save_data())
	check(not a.attention(ref).ok,label+" selection rejected")
	check(not a.begin_intent("拿起这个行礼包",ref).ok,label+" intent rejected")
	check(C.bytes(a.save_data())==exact,label+" atomic no facts/RNG change")
func legacy_replays() -> void:
	var path:String=OUT+"legacy_fixtures/index.json"
	if not check(FileAccess.file_exists(path),"prechange fixture index available"):return
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string(path))
	for row in rows:
		var full:String=OUT+"legacy_fixtures/"+row.file
		var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(full))
		var a:RefCounted=Legacy.new() if row.profile=="legacy_v1" else Seeded.new() if row.profile=="seeded_v2" else Adapter.new()
		check(FileAccess.get_sha256(full)==row.sha256,"prechange file hash "+row.file)
		if not check(a.load_data(original).ok,"prechange load "+row.file):continue
		check(C.bytes(a.save_data())==C.bytes(original),"prechange byte-exact replay "+row.file)
		if not row.request.is_empty():check(C.bytes(a.request())==C.bytes(row.request),"prechange request unchanged "+row.file)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	legacy_replays()
	envelope=Contract.generate("雪岸-行囊","compact_coast",4)
	var a:=Adapter.new()
	if not check(a.start_seeded(envelope).ok,"existing inventory profile admission"):finish();return
	var before:String=C.bytes(a.save_data());var ref:Dictionary=a.item_reference()
	var selected:Dictionary=a.attention(ref)
	check(selected.ok and selected.focus.facts.item==a.state_copy().items.item_travel_bundle,"carried item exact selected facts")
	for i in range(4):check(a.attention(ref).ok and C.bytes(a.save_data())==before,"repeat select does not act "+str(i))
	check(selected.focus.hex==a.state_copy().actors.actor_player.hex and selected.focus.entity_revision==0,"carried support is owner cell and exact custody revision")
	check(Details.description(selected.focus).contains("整件放下") and not Details.description(selected.focus).contains("每次操作消耗1体力"),"pack details do not borrow coast bracing rules")
	for field in ["world_id","id","scene_id","catalog_version"]:
		var bad:Dictionary=ref.duplicate(true);bad[field]="missing";reject_focus(a,bad,"invalid "+field)
	var bad:Dictionary=ref.duplicate(true);bad.entity_revision=1;reject_focus(a,bad,"stale revision")
	bad=ref.duplicate(true);bad.hex=[999,999];reject_focus(a,bad,"unknown position")
	bad=ref.duplicate(true);bad.erase("entity_revision");reject_focus(a,bad,"missing revision")
	bad=ref.duplicate(true);bad["quantity"]=2;reject_focus(a,bad,"unsupported field")
	var forged:Dictionary=a.state_copy();forged.items.item_travel_bundle.owner_actor_id="actor_other"
	check(Focus.make_reference(Focus.ITEM,forged).is_empty(),"other actor ownership is not selectable through this closed profile")
	var save:Dictionary=a.save_data();save.engine.state.items.item_travel_bundle.owner_actor_id="actor_other"
	check(not a.load_data(save).ok and C.bytes(a.save_data())==before,"forged other-owner save rejects with live world unchanged")
	# Natural text remains an honest pending request. The explicit manual reply is
	# a test artifact, not an automatic keyword parser or claimed live model.
	check(a.begin_intent("把选中的行礼包放到脚边。",ref).ok and not a.fixture_available(),"free intent uses selected item but awaits external assessment")
	var request:Dictionary=a.request();var frozen:String=C.bytes(request)
	check(request.context.attention_focus.facts.item==a.state_copy().items.item_travel_bundle,"public request freezes exact item")
	check(not request.has("rng") and not request.context.facts.has("pending") and not request.context.facts.has("receipts") and C.bytes(request).to_utf8_buffer().size()<=65536,"public selected pack context bounded with no private RNG/receipt")
	a.attention(a.tile_reference(a.state_copy().actors.actor_player.hex))
	check(C.bytes(a.request())==frozen,"new selection does not retarget pending request")
	roundtrip(a,"free_pending")
	check(a.cancel().ok and C.bytes(a.state_copy())==C.bytes(JSON.parse_string(before).engine.state),"cancel free intent preserves custody")
	check(a.begin_intent("把选中的行礼包放到脚边。",ref).ok,"fresh natural drop intent")
	request=a.request();var template:Dictionary=request.duplicate(true);template.context.goal=Examples.goal("drop_item")
	var reply:Dictionary=Examples.build(template).assessment;reply.provenance={"provider":"test_manual_prepared_reply","live":false,"kind":"model_reply"}
	check(a.import_reply(reply).ok,"valid manually prepared decision binds free text context through original validator")
	roundtrip(a,"free_ready")
	var fixed_rng:String=C.bytes(a.engine.save_data().rng)
	check(a.roll_once().ok and C.bytes(a.engine.save_data().rng)==fixed_rng,"registered direct item lock consumes no RNG")
	var locked:String=C.bytes(a.save_data())
	check(a.roll_once().ok and C.bytes(a.save_data())==locked and not a.cancel().ok,"locked action cannot reroll/cancel")
	a=roundtrip(a,"free_locked")
	var pending:Dictionary=a.action_copy();pending.focus.facts.item.quantity=2
	save=a.save_data();save.engine.pending[a.active_action]=pending
	check(not a.load_data(save).ok and C.bytes(a.save_data())==locked,"forged frozen focus cannot alter locked transaction")
	check(a.stage().ok,"free drop stage")
	a=roundtrip(a,"free_staged")
	check(a.commit().ok,"free drop commits through original ownership rule")
	var receipt:Dictionary=a.engine.save_data().receipts[a.last_action]
	var drop_id:String=a.last_action;var public_history:Dictionary=a.engine.narration_request(drop_id)
	before=C.bytes(a.save_data())
	check(a.engine.commit(drop_id,receipt.stage_hash).already_committed and C.bytes(a.save_data())==before,"repeat commit leaves one pack and one turn")
	check(a.state_copy().items.item_travel_bundle.hex==ref.hex and a.state_copy().items.item_travel_bundle.custody_revision==1,"ground pack retains same ID and increments custody once")
	reject_focus(a,ref,"old carried reference after drop")
	var ground:Dictionary=a.item_reference()
	check(a.attention(ground).ok and ground.entity_revision==1,"new ground reference valid")
	check(execute(a,"pickup_item",ground),"existing assessed pickup with exact selected ground pack")
	check(C.bytes(a.engine.narration_request(drop_id))==C.bytes(public_history),"pickup cannot rewrite drop historical selected facts or receipt")
	check(a.engine.narration_request(drop_id).context.attention_focus.facts.item.owner_actor_id=="actor_player","drop receipt retains pre-drop owned focus")
	reject_focus(a,ground,"old ground reference after pickup")
	roundtrip(a,"free_committed")
	check(a.state_copy().items.size()==1 and a.state_copy().items.item_travel_bundle.quantity==1 and a.state_copy().items.item_travel_bundle.owner_actor_id=="actor_player","one existing pack preserved after round trip")
	# Leave the real pack behind, then test selected far-away custody, not guessed reach.
	check(execute(a,"drop_item",a.item_reference()),"drop for distance test")
	var origin:Array=a.state_copy().actors.actor_player.hex.duplicate();var target:Array=[]
	for cell in a.state_copy().hexes.values():
		var dq:int=cell.q-origin[0];var dr:int=cell.r-origin[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))<2:continue
		if a.movement_preview([cell.q,cell.r]).ok:target=[cell.q,cell.r];break
	if check(not target.is_empty() and execute(a,"move",a.tile_reference(target)),"travel real route away from dropped pack"):
		before=C.bytes(a.save_data());ground=a.item_reference()
		check(a.attention(ground).ok and C.bytes(a.save_data())==before,"known distant pack can be inspected without pickup")
		check(a.begin_intent(a.sample_goal("pickup_item"),ground).ok,"selected far pack request")
		check(a.request().context.attention_focus.hex==origin and C.bytes(a.request()).to_utf8_buffer().size()<=65536,"far selected pack exact cell and bounded context")
		var facts_before:String=C.bytes(a.state_copy());fixed_rng=C.bytes(a.engine.save_data().rng)
		check(not a.prepare_fixture().ok and C.bytes(a.state_copy())==facts_before and C.bytes(a.engine.save_data().rng)==fixed_rng,"far selected pickup rejects without teleport or RNG")
		check(a.cancel().ok,"far rejected action cancels")
	finish()
func finish() -> void:
	var report:Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}
	var f:=FileAccess.open(OUT+"focus_report.json",FileAccess.WRITE);f.store_string(C.bytes(report));f.close()
	print("PACK_FOCUS_RESULT ",report.status," ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
