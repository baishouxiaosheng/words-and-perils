extends SceneTree
const Adapter=preload("res://view/generated_v3_npc/adapter.gd")
const Source=preload("res://view/generated_v3_npc/source.gd")
const Examples=preload("res://view/generated_v3_npc/assessments.gd")
const Generator=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const WorldSchema=preload("res://core/ai_gm_rebuilt/world.gd")
const NPCState=preload("res://core/source_npc/state.gd")
const ExplorationResolver=preload("res://view/generated_v3_adventure/resolver.gd")
const NPCFocus=preload("res://core/source_npc/focus.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
const PublicProjection=preload("res://view/generated_v3_npc/projection.gd")
const OldVillage=preload("res://view/generated_v3_village/adapter.gd")
var checks=0
var failures=[]
var policy={"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]}
func _initialize():call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
	return ok
func finish():
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_npc")
	FileAccess.open("res://artifacts/generated_v3_npc/adapter_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty()},"\t"))
	print("NPC_ADAPTER ",checks," ",failures);quit(0 if failures.is_empty() else 1)
func execute(a:RefCounted,kind:String,focus:Dictionary={})->bool:
	for result in [a.begin_intent(a.sample_goal(kind,focus),focus)]:
		if not result.ok:printerr("BEGIN ",kind," ",result);return false
	for step in ["prepare_fixture","roll_once","stage","commit"]:
		var result:Dictionary=a.call(step)
		if not result.ok:printerr(step," ",kind," ",result);return false
	return true
func roundtrip(a:RefCounted,label:String):
	var bytes=C.bytes(a.save_data());var b=Adapter.new();var result:Dictionary=b.load_data(JSON.parse_string(bytes))
	check(result.ok,label+" load "+str(result))
	if result.ok:check(C.bytes(b.save_data())==bytes and b.phase()==a.phase(),label+" byte-exact")
func reject(a:RefCounted,bad:Dictionary,label:String):
	var before=C.bytes(a.save_data());check(not a.load_data(bad).ok and C.bytes(a.save_data())==before,label+" atomic rejection")
func rehash(receipt:Dictionary):
	var payload=receipt.duplicate(true);payload.erase("receipt_hash");receipt.receipt_hash=C.digest(payload)
func walk_to_npc(a:RefCounted)->bool:
	var target:Array=a.state_copy().actors[a.source.npc_id].hex
	var start:String="%d,%d"%a.state_copy().actors.actor_player.hex
	var goal:String="%d,%d"%target
	var queue:Array=[start];var parents={start:""};var at=0
	while at<queue.size() and not parents.has(goal):
		var key:String=queue[at];at+=1
		for next in a.source.navigation.allowed[key]:
			if not parents.has(next):parents[next]=key;queue.append(next)
	if not parents.has(goal):return false
	var route:Array=[];var key:String=goal
	while key!=start:route.push_front(key);key=parents[key]
	for next in route:
		var parts=next.split(",");var hex=[int(parts[0]),int(parts[1])]
		while not a.movement_preview(hex).ok:
			var stamina:int=a.state_copy().actors.actor_player.stamina.current
			if not execute(a,"rest") or a.state_copy().actors.actor_player.stamina.current<=stamina:return false
		if not execute(a,"move",a.tile_reference(hex)):return false
	return true
func run():
	for malformed in [null,[],"bad",17,true]:
		var rejected:Dictionary=Adapter.new().load_data(malformed)
		check(not rejected.ok and rejected.code=="V3_NPC_SAVE_SCHEMA","malformed top-level save rejected without throw")
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_npc")
	var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
	var a=Adapter.new()
	if not check(a.start_source(generated.source).ok,"new NPC profile admits source"):printerr(a.ready());finish();return
	var id:String=a.source.npc_id;var initial=a.state_copy();var rng=C.bytes(a.engine.save_data().rng)
	check(initial.actors.size()==2 and initial.actors[id].inventory==[],"one NPC with shared actor shape")
	check(a.attention(a.item_reference()).ok,"item focus remains with NPC present")
	var ref=a.npc_reference();var before=C.bytes(a.save_data());var full:Dictionary=a.attention(ref).focus
	for control in [1,8,12,31]:
		var invalid:Dictionary=a.begin_intent("intent"+String.chr(control),ref)
		check(not invalid.ok and invalid.code=="NPC_INTENT_TEXT" and C.bytes(a.save_data())==before,"unsupported C0 rejected before any action mutation")
	check(not ref.is_empty() and C.bytes(a.save_data())==before,"NPC selection read-only")
	for field in ["catalog_version","catalog_id","location_revision","contact_revision"]:
		var bad=ref.duplicate(true);bad.erase(field);check(not a.attention(bad).ok,"missing typed "+field+" cannot fall through actor")
	var bare={"world_id":initial.world_id,"kind":"actor","id":id,"hex":initial.actors[id].hex,"scene_id":Source.SCENE}
	check(not a.attention(bare).ok,"bare registered NPC actor denied")
	check(a.attention({"world_id":initial.world_id,"kind":"actor","id":"actor_player","hex":initial.actors.actor_player.hex}).ok,"ordinary player actor remains")
	roundtrip(a,"initial")
	var old=OldVillage.new(generated.source);reject(a,old.save_data(),"old village not injected into NPC")
	check(not old.load_data(a.save_data()).ok,"new NPC not loaded as old village")
	check(a.begin_intent("请问村口怎么走？",ref).ok and not a.fixture_available(),"free text awaits assessment")
	var request=a.request();var payload:String=initial.generated_world.npc_catalog.entries[id].facts.values()[0].payload.description
	check(not C.bytes(request).contains(payload),"unlearned answer absent from whole assessment")
	var control_save=a.save_data();control_save.engine.pending[a.active_action].goal+=String.chr(1)
	var control_load:Dictionary=Adapter.new().load_data(control_save)
	check(not control_load.ok and control_load.code=="NPC_INTENT_TEXT","pending control-text readmission fails at new boundary")
	var bad=a.save_data();bad.engine.pending[a.active_action].focus["unknown_safe"]=1
	reject(a,bad,"unknown pending NPC top-level field")
	roundtrip(a,"pending free intent")
	check(a.cancel().ok and C.bytes(a.state_copy())==C.bytes(initial),"cancel no mutation")
	check(a.begin_intent(a.sample_goal("talk"),ref).ok,"distant talk submitted")
	check(not a.prepare_fixture().ok and C.bytes(a.state_copy())==C.bytes(initial),"distant talk cannot learn or charge")
	check(a.cancel().ok,"distant attempt cancel")
	if not check(walk_to_npc(a),"real assessed travel to NPC"):finish();return
	roundtrip(a,"travel history")
	var target_ref=a.npc_reference();var pre=a.state_copy()
	check(a.begin_intent(a.sample_goal("talk"),target_ref).ok,"nearby talk submitted")
	request=a.request();check(not C.bytes(request).contains(payload),"focused NPC still hides unknown payload")
	var badreply:Dictionary=Examples.build(request).assessment;badreply.provenance={"provider":"offline_test","live":false,"kind":"model_reply"};badreply.bindings.topic_id="invented_topic"
	before=C.bytes(a.save_data());check(not a.import_reply(badreply).ok and C.bytes(a.save_data())==before,"model cannot mint topic or fact")
	check(a.prepare_fixture().ok,"assessed cooperative talk ready")
	roundtrip(a,"talk ready")
	check(a.roll_once().ok,"talk lock")
	before=C.bytes(a.save_data());check(a.roll_once().ok and not a.cancel().ok and C.bytes(a.save_data())==before,"locked talk idempotent and uncancelable")
	roundtrip(a,"talk locked")
	check(a.stage().ok and C.bytes(a.state_copy())==C.bytes(pre),"staging does not publish knowledge")
	var staged_request=a.engine.narration_request(a.active_action)
	check(staged_request.context.provisional_until_commit and C.bytes(staged_request).contains(payload),"typed staged answer explicit provisional")
	roundtrip(a,"talk staged")
	check(a.commit().ok,"talk commit")
	var first_action:String=a.last_action;var first_state=a.state_copy();var first_knowledge=C.bytes(first_state.npc_state.learned_facts)
	control_save=a.save_data();control_save.engine.receipts[first_action].goal+=String.chr(31)
	rehash(control_save.engine.receipts[first_action]);control_load=Adapter.new().load_data(control_save)
	check(not control_load.ok and control_load.code=="NPC_INTENT_TEXT","rehashed historical control text rejected before history replay")
	check(first_state.turn==pre.turn+1 and first_state.actors.actor_player.stamina.current==pre.actors.actor_player.stamina.current-1,"talk costs exact1 turn/stamina")
	check(first_state.npc_state.contacts[id].conversation_count==1 and not first_state.npc_state.learned_facts.actor_player.is_empty(),"typed persisted information")
	var historical_request=C.bytes(a.engine.narration_request(first_action))
	check(historical_request.contains(payload),"committed narration includes authoritative learned answer")
	before=C.bytes(a.save_data());check(a.commit().get("already_committed",false) and C.bytes(a.save_data())==before,"repeat commit no duplicate learning")
	check(not a.attention(target_ref).ok and a.attention(a.npc_reference()).ok,"current contact revision refresh")
	roundtrip(a,"first committed talk")
	if a.state_copy().actors.actor_player.stamina.current<1:check(execute(a,"rest"),"rest before repeat")
	check(execute(a,"talk",a.npc_reference()),"second legitimate assessed conversation")
	var second_action:String=a.last_action
	check(C.bytes(a.state_copy().npc_state.learned_facts)==first_knowledge and a.state_copy().npc_state.contacts[id].conversation_count==2,"first acquisition stays exact and idempotent")
	check(C.bytes(a.engine.narration_request(first_action))==historical_request,"historical narration unchanged by later talk")
	check(a.authoritative_result().public_effects[1].already_known_fact_ids.size()==1 and a.authoritative_result().public_effects[1].newly_learned_facts.is_empty(),"repeat public effect truthful")
	roundtrip(a,"repeated history")
	check(execute(a,"drop_item",a.item_reference()) and execute(a,"pickup_item",a.item_reference()),"shared inventory actions remain")
	var neighbor:String=a.source.navigation.allowed["%d,%d"%a.state_copy().actors.actor_player.hex][0];var parts=neighbor.split(",");var h=[int(parts[0]),int(parts[1])]
	while not a.movement_preview(h).ok:check(execute(a,"rest"),"rest before leaving")
	check(execute(a,"move",a.tile_reference(h)),"move after learning")
	check(C.bytes(a.engine.narration_request(first_action))==historical_request,"historical narration unchanged after moving")
	roundtrip(a,"complete long journey")
	var route_a:Array=a.state_copy().actors.actor_player.hex.duplicate()
	var route_b_key:String=a.source.navigation.allowed["%d,%d"%route_a][0]
	var route_b_parts=route_b_key.split(",");var route_b:Array=[int(route_b_parts[0]),int(route_b_parts[1])]
	while a.state_copy().actors.actor_player.stamina.current<a.state_copy().actors.actor_player.stamina.max:
		if not check(execute(a,"rest"),"restore stamina for reversible route"):finish();return
	var old_move_fingerprint=C.bytes(ExplorationResolver.new(a.source,"move").attempt_fingerprint(a.state_copy(),{}))
	check(execute(a,"move",a.tile_reference(route_b)),"cycle A to B")
	while not a.movement_preview(route_a).ok:
		if not check(execute(a,"rest"),"rest for return edge"):finish();return
	check(execute(a,"move",a.tile_reference(route_a)),"cycle B to A")
	while a.state_copy().actors.actor_player.stamina.current<a.state_copy().actors.actor_player.stamina.max:
		if not check(execute(a,"rest"),"restore prior exact actor stamina"):finish();return
	check(C.bytes(ExplorationResolver.new(a.source,"move").attempt_fingerprint(a.state_copy(),{}))==old_move_fingerprint,"cycle recreates original legacy move fingerprint")
	check(execute(a,"move",a.tile_reference(route_b)),"new committed-turn move remains legitimate after A B A")
	while not a.movement_preview(route_a).ok:
		if not check(execute(a,"rest"),"rest before returning near NPC"):finish();return
	check(execute(a,"move",a.tile_reference(route_a)),"return near NPC after cycle")
	roundtrip(a,"reversible movement cycle")
	for cycle in range(3):
		while a.state_copy().actors.actor_player.stamina.current>0:
			if not check(execute(a,"talk",a.npc_reference()),"paid talk drains stamina for real cycle"):finish();return
		var zero_turn:int=a.state_copy().turn
		check(a.begin_intent(a.sample_goal("rest")).ok and a.prepare_fixture().ok,"legitimate rest after prior identical stamina")
		before=C.bytes(a.save_data());check(not a.begin_intent(a.sample_goal("rest")).ok and C.bytes(a.save_data())==before,"duplicate pending rest submit blocked")
		check(a.roll_once().ok,"rest result locks")
		before=C.bytes(a.save_data());check(a.roll_once().ok and not a.cancel().ok and C.bytes(a.save_data())==before,"locked rest unchanged by repeat or cancel")
		check(a.stage().ok and a.commit().ok and a.state_copy().actors.actor_player.stamina.current==2 and a.state_copy().turn==zero_turn+1,"rest keeps original+2 and1turn formula")
		before=C.bytes(a.save_data());check(a.commit().get("already_committed",false) and C.bytes(a.save_data())==before,"same rest commit remains idempotent")
		check(execute(a,"talk",a.npc_reference()) and execute(a,"talk",a.npc_reference()),"two paid talks return stamina to previous exact value")
		roundtrip(a,"rest talk cycle"+str(cycle))
	check(C.bytes(a.state_copy().npc_state.learned_facts)==first_knowledge,"cycling rest and talk never rewrites first proof")
	check(C.bytes(a.engine.save_data().rng)==rng,"all direct actions preserve production RNG")
	var history=a.engine.save_data();var receipt:Dictionary=history.receipts[first_action];var record:Dictionary=receipt.patches[1]
	var hook_world=pre.duplicate(true);check(not WorldSchema.apply(hook_world,record,true).ok and C.bytes(hook_world)==C.bytes(pre),"NPC effect forbidden as hook")
	receipt.hook_patches=[record];receipt.patches=[];rehash(receipt)
	check(not a.source.validate_history(history).ok,"hook moved record zero-cost bypass rejected")
	bad=a.save_data();bad.engine.receipts[first_action]=receipt;reject(a,bad,"rehashed history hook bypass")
	history=a.engine.save_data();receipt=history.receipts[second_action]
	receipt.attention_focus.facts.public_state.last_action_id=a.state_copy().world_id+":action_1";receipt.attention_focus.facts.public_state.last_action_start_turn=0;rehash(receipt)
	check(NPCFocus.validate_historical(receipt.attention_focus,a.state_copy()).is_empty(),"forged old public contact is shape-valid but unauthenticated")
	check(not a.source.validate_history(history).ok,"forged prior NPC public state rejected by exact pre-state")
	bad=a.save_data();bad.identity.npc_catalog.entries[id].placement_witness.position_q40[0]+=1
	reject(a,bad,"saved NPC pose cannot move")
	var factkey:String=a.state_copy().npc_state.learned_facts.actor_player.keys()[0]
	bad=a.save_data();bad.engine.state.npc_state.learned_facts.actor_player[factkey].payload.description="invented"
	reject(a,bad,"replaced learned payload cannot load")
	var restarted=a.restarted();check(restarted.ready().ok and restarted.state_copy().turn==0 and restarted.source.features==a.source.features,"explicit restart keeps feature choice and resets knowledge")
	bad=restarted.save_data()
	var meta:Dictionary=bad.identity
	meta.npc_catalog.entries[id].placement_witness.position_q40[0]+=1099511627776
	var catalog_payload:Dictionary=meta.npc_catalog.duplicate(true);catalog_payload.erase("catalog_hash")
	meta.npc_catalog.catalog_hash=C.digest(catalog_payload);meta.npc_catalog_hash=meta.npc_catalog.catalog_hash
	meta.runtime_hash=Source.runtime_digest(meta);bad.engine.state.generated_world=meta.duplicate(true)
	check(WorldSchema.validate(bad.engine.state).ok,"rehashed moved pose is internally consistent transport")
	reject(restarted,bad,"fully rehashed moved pose rejected by exact Source reproduction")
	FileAccess.open("res://artifacts/generated_v3_npc/committed.json",FileAccess.WRITE).store_string(C.bytes(a.save_data()))
	finish()
