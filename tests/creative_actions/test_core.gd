extends SceneTree
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Coast = preload("res://view/playable_build/world.gd")
const Content = preload("res://view/playable_build/creative_content.gd")
const Actions = preload("res://core/ai_gm_rebuilt/creative_actions.gd")
const Effects = preload("res://core/ai_gm_rebuilt/creative_effects.gd")
const Examples = preload("res://view/playable_build/creative_examples.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const BasicExamples = preload("res://view/playable_build/basic_examples.gd")
const ControlReply = preload("res://core/ai_gm_rebuilt/creative_control.gd")
const BasicEffects = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Rule = preload("res://tests/core_gameplay/test_release_rule.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Scope = preload("res://view/runtime_ai/scoped_engine.gd")
const Adapter = preload("res://view/playable_build/adapter.gd")
const NORTH := "passage:coast_brace:north"
const SOUTH := "passage:coast_brace:south"
const PLANK := "item_brace_plank"
var checks := 0
var failures: Array = []
var base: Dictionary = {}
var evidence: Dictionary = {"kind":"program_rng_test_only","live_provider":false,"semantic_model_evaluation":false,"branches":{}}
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: "+message)
func make(seed_: int, initial: Dictionary = {}) -> RefCounted:
	var registry := {Actions.ID:Actions.new()}
	for kind in Basic.KINDS:
		var r := Basic.new(kind); registry[r.resolver_id()] = r
	return GMEngine.new(base if initial.is_empty() else initial,Rule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":["coast_observed","keeper_trust","lamp_restored"]},seed_)
func seed_for(first: bool, second: bool, threshold := 5000) -> int:
	for n in range(1,1000):
		var rng := RandomNumberGenerator.new(); rng.seed=n
		if (rng.randi_range(1,10000)<=threshold)==first and (rng.randi_range(1,10000)<=threshold)==second: return n
	return -1
func reply(e: RefCounted, source_id := PLANK, target_id := NORTH, operation := "place_obstruction", focus: Dictionary = {}) -> Dictionary:
	var goal := Examples.public_goal(operation,e.state_copy(),source_id,target_id)
	var begun: Dictionary = e.begin_intent(goal,focus)
	if not begun.ok: expect(false,"begin "+str(begun)); return {}
	var built := Examples.assessment(begun.request,source_id,target_id,operation)
	if not built.ok: expect(false,"build "+str(built)); return {}
	return built.assessment
func finish(e: RefCounted, a: Dictionary) -> Dictionary:
	var checked: Dictionary = e.prepare_assessment(a)
	if not checked.ok: return checked
	checked=e.roll_once(a.action_id)
	if not checked.ok: return checked
	checked=e.stage(a.action_id)
	if not checked.ok: return checked
	return e.commit(a.action_id,e.action_copy(a.action_id).stage_hash)
func reject(e: RefCounted, a: Dictionary, code: String, label_: String) -> void:
	var before: Dictionary=e.save_data(); var result: Dictionary=e.prepare_assessment(a)
	expect(not result.ok and (code.is_empty() or result.get("code")==code),label_+" "+str(result.get("code")))
	expect(C.bytes(before)==C.bytes(e.save_data()),label_+" atomic before dice")
	e.cancel_intent(a.action_id)
func write_json(name_: String, value: Dictionary) -> void:
	var file:=FileAccess.open("res://artifacts/creative_actions_20261003/"+name_,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true));file.close()
func run() -> void:
	base=Coast.world(true)
	expect(base.has("physical_catalog"),"new release world installs trusted physical catalog")
	if not base.has("physical_catalog"): quit(1); return
	base.actors.actor_player.hex=base.passage_targets[NORTH].support_hex.duplicate()
	for actor in base.actors.values(): actor.hooks=[]
	expect(World.validate(base).ok,"base fully validates "+str(World.validate(base)))
	var resolver:=Actions.new()
	for first in [false,true]:
		for second in [false,true]:
			var e:=make(seed_for(first,second)); expect(e.ready().ok,"engine ready")
			var a:=reply(e); var before: Dictionary=e.state_copy(); var result:=finish(e,a)
			expect(result.ok,"four-way commit "+str([first,second])+" "+str(result))
			if not result.ok: continue
			var after: Dictionary=e.state_copy(); var item: Dictionary=after.items[PLANK]
			expect(result.receipt.outcomes=={"placement":first,"stability":second},"real RNG matches intended test branch")
			expect(after.actors.actor_player.stamina.current==7 and after.turn==1 and after.state_version==1,"exact one stamina/turn/version")
			expect(after.items.size()==before.items.size() and item.quantity==1,"object count and quantity conserved")
			expect(Effects.active_source(after,PLANK)==(first and second),"active relation iff both checks pass")
			expect(Traversal.edge_allowed(after,after.actors.actor_player,after.passage_targets[NORTH].endpoints[0],after.passage_targets[NORTH].endpoints[1])!= (first and second),"canonical edge follows branch")
			if first:
				expect(not item.has("owner_actor_id") and not PLANK in after.actors.actor_player.inventory and item.hex==after.passage_targets[NORTH].support_hex,"placement leaves inventory once at support")
				expect(after.creative_placements[PLANK].posture==("braced" if second else "loose"),"exact actual pose")
			else: expect(C.bytes(before.items[PLANK])==C.bytes(item),"failed placement retains exact source custody")
			expect(e.commit(a.action_id,result.receipt.stage_hash).get("already_committed",false),"duplicate commit idempotent")
			expect(e.commit(a.action_id,"conflict").get("code")=="COMMIT_CONFLICT","conflicting token rejected")
			var restored:=make(1); expect(restored.load_data(e.save_data()).ok and C.bytes(restored.save_data())==C.bytes(e.save_data()),"committed save roundtrip")
			evidence.branches[str([first,second])] = {"seed":seed_for(first,second),"request":a,"receipt":result.receipt,"source_after":item,"placements":after.creative_placements,"relations":after.creative_relations}
			if not (first and second):
				var again:=reply(e); again.provenance={"provider":"manual test adversarial","live":false,"kind":"model_reply"};again.interpretation="Different words";again.components.reverse()
				for component in again.components: component.parameters={"A":4,"D":0,"P":2};component.disposition="certain";component.fact_ref_ids.reverse()
				reject(e,again,"REPEAT_ATTEMPT","own cost/partial placement cannot buy retry")
	# Dissimilar objects and second target instantiate one resolver without ID dispatch.
	for source in Content.ITEM_IDS:
		for target_id in [NORTH,SOUTH]:
			var initial:=base.duplicate(true);initial.actors.actor_player.hex=initial.passage_targets[target_id].support_hex.duplicate();initial.items[source].name="陌生的物件-"+source
			var e:=make(seed_for(true,true),initial);expect(finish(e,reply(e,source,target_id)).ok,"same mechanism different source/target "+source+target_id)
	# Full deployment -> remove -> separate pickup; all IDs and other blockers survive.
	var e:=make(seed_for(true,true));var a:=reply(e);expect(finish(e,a).ok,"full for removal")
	var blocked: Dictionary=e.state_copy();var actor: Dictionary=blocked.actors.actor_player;var t: Dictionary=blocked.passage_targets[NORTH]
	expect(not Traversal.edge_allowed(blocked,actor,t.endpoints[1],t.endpoints[0]),"undirected reverse edge blocked")
	var flying:=actor.duplicate(true);flying.statuses.flight={"kind":"flight","remaining_turns":3};expect(Traversal.edge_allowed(blocked,flying,t.endpoints[0],t.endpoints[1]),"ground-only brace flight bypass")
	var route:=Policy.plan(blocked,actor.id,t.endpoints[0],1,func(_from,_to):return {"ok":true});expect(not route.ok,"weighted movement cannot cross blocked edge at one-edge budget")
	var patch:={"type":"item_relocate","item_id":PLANK,"expected_owner_id":"","expected_hex":t.support_hex,"owner_actor_id":"actor_player","scene_id":"","hex":[]}
	var trial:=blocked.duplicate(true);expect(not World.apply(trial,patch).ok and C.bytes(trial)==C.bytes(blocked),"active source cannot be picked up")
	trial=blocked.duplicate(true);expect(not World.apply(trial,{"type":"item_quantity_delta","item_id":PLANK,"delta":-1}).ok,"active source cannot be consumed")
	expect(finish(e,reply(e,PLANK,NORTH,"remove_obstruction")).ok,"assessed removal commits")
	var loose: Dictionary=e.state_copy();expect(not Effects.active_source(loose,PLANK) and loose.creative_placements[PLANK].posture=="loose" and loose.items[PLANK].hex==t.support_hex,"removal leaves exact same loose source")
	expect(Traversal.edge_allowed(loose,loose.actors.actor_player,t.endpoints[0],t.endpoints[1]),"edge reopens after exact removal")
	expect(World.apply(loose,patch).ok and not loose.creative_placements.has(PLANK) and loose.items[PLANK].owner_actor_id=="actor_player","existing relocation clears loose anchor")
	var pickup_focus:=Content.make_reference(PLANK,e.state_copy())
	var pickup_goal:=BasicExamples.goal("pickup",e.state_copy(),pickup_focus)
	var pickup_begin: Dictionary=e.begin_intent(pickup_goal,pickup_focus)
	var pickup_reply:=BasicExamples.assessment(pickup_begin.request,"pickup")
	expect(pickup_reply.ok and finish(e,pickup_reply.assessment).ok,"separate assessed pickup returns exact same object")
	expect(e.state_copy().items[PLANK].owner_actor_id=="actor_player" and not e.state_copy().creative_placements.has(PLANK),"assessed pickup clears anchor and restores one custody")
	expect(e.prepare_assessment(reply(e)).ok,"successful cycle allows legitimate deliberate reuse");e.cancel_intent(e.save_data().pending.keys()[0])
	# Equipped source full clears equipment, failed placement preserves equipment.
	for success in [false,true]:
		var initial:=base.duplicate(true);initial.actors.actor_player.equipment.weapon=PLANK
		var equipped:=make(seed_for(success,success),initial);expect(finish(equipped,reply(equipped)).ok,"equipped compatible object accepted")
		expect(equipped.state_copy().actors.actor_player.equipment.has("weapon")!=success,"equipment follows real custody outcome")
	# Loose source already at support anchors without duplicate relocation.
	var initial:=base.duplicate(true);initial.items[PLANK].erase("owner_actor_id");initial.items[PLANK].hex=t.support_hex.duplicate();initial.items[PLANK].scene_id=t.scene_id;initial.actors.actor_player.inventory.erase(PLANK)
	e=make(seed_for(true,false),initial);expect(finish(e,reply(e)).ok,"unowned same-support source placement works")
	expect(e.state_copy().items[PLANK].get("custody_revision",0)==0,"same-cell anchoring does not fabricate custody movement")
	# Own fatigue boundary/status expiry are normalized before and after hooks.
	initial=base.duplicate(true);initial.actors.actor_player.stamina.current=3;initial.actors.actor_player.hooks=["status_tick"];initial.actors.actor_player.statuses.drunk={"id":"drunk","kind":"drunk","remaining_turns":1,"magnitude":1}
	e=make(seed_for(false,false,4750),initial);expect(finish(e,reply(e)).ok,"failed cost/hook case");reject(e,reply(e),"REPEAT_ATTEMPT","own fatigue/status changes cannot grant reroll")
	# Retained episode remembers original arrangement after a partial placement.
	e=make(seed_for(true,false));expect(finish(e,reply(e)).ok,"partial history seed")
	var data: Dictionary=e.save_data();data.state.items[PLANK]=base.items[PLANK].duplicate(true);data.state.actors.actor_player.inventory=base.actors.actor_player.inventory.duplicate();data.state.creative_placements={}
	expect(e.load_data(data).ok,"test-only restored custody arrangement validates");reject(e,reply(e),"REPEAT_ATTEMPT","A->B->A retained history blocks revision loophole")
	# Stale/forged and capability hard failures never reach dice.
	for mutation in ["raw_patch","extra_binding","nan","short","flexible","heavy","bearing","section","zero","stack","owned_other","exhausted","downed","wrong_approach"]:
		initial=base.duplicate(true);e=make(1,initial);a=reply(e)
		match mutation:
			"raw_patch": a["patches"]=[]
			"extra_binding":a.bindings["script"]="grant_gold()"
			"nan":a.components[0].parameters.A=NAN
			"short","flexible","heavy","bearing","section":
				var changed:=initial.duplicate(true)
				var field: String={"short":"length_mm","flexible":"rigidity","heavy":"mass_g","bearing":"bearing","section":"section_mm"}[mutation]
				changed.items[PLANK].physical_traits[field]={"short":50,"flexible":0,"heavy":9000,"bearing":0,"section":999}[mutation]
				expect(not World.validate(changed).ok,"catalog cannot fabricate physical trait "+mutation)
				var direct:=resolver.freeze(changed,a);expect(not direct.ok,"hard predicate rejects "+mutation);e.cancel_intent(a.action_id);continue
			"zero","stack":
				initial.items[PLANK].quantity=0 if mutation=="zero" else 2;expect(not World.validate(initial).ok,"singleton count enforced "+mutation);e.cancel_intent(a.action_id);continue
			"owned_other","exhausted","downed","wrong_approach":
				e.cancel_intent(a.action_id)
				match mutation:
					"owned_other": initial.items[PLANK].owner_actor_id="actor_keeper";initial.actors.actor_player.inventory.erase(PLANK);initial.actors.actor_keeper.inventory.append(PLANK)
					"exhausted": initial.actors.actor_player.stamina.current=0
					"downed":initial.actors.actor_player.health.current=0
					"wrong_approach":initial.actors.actor_player.hex=t.endpoints[0].duplicate()
				e=make(1,initial)
				if mutation=="downed":
					var downed_before: Dictionary=e.save_data();expect(e.begin_intent("Try bracing").get("code")=="ACTOR_DOWNED" and C.bytes(downed_before)==C.bytes(e.save_data()),"downed actor rejected before new intention");continue
				a=reply(e)
		reject(e,a,"","adversarial "+mutation)
	# Wrong JSON types reject, including the control dispatch before legacy validation.
	for path in ["schema_version","source_kind","target_kind","mechanism","intended_effect"]:
		e=make(1);a=reply(e)
		match path:
			"schema_version":a.schema_version=true
			"source_kind":a.bindings.source.kind=true
			"target_kind":a.bindings.target.kind=1
			"mechanism":a.bindings.mechanism=false
			"intended_effect":a.bindings.intended_effect=2
		reject(e,a,"","exact typed schema "+path)
	# Existing hooks remain once-per-turn and see the selected obstruction branch.
	for placement in [false,true]:
		for stability in [false,true]:
			initial=base.duplicate(true);initial.actors.actor_player.hooks=["status_tick"];initial.actors.actor_player.statuses.poison={"id":"poison","kind":"poison","remaining_turns":2,"magnitude":1}
			initial.actors.actor_scout.hex=t.endpoints[0].duplicate();initial.actors.actor_scout.hooks=["patrol"];initial.actors.actor_scout.patrol={"route":[t.endpoints[0].duplicate(),t.support_hex.duplicate()],"index":0}
			e=make(seed_for(placement,stability),initial);var hook_result:=finish(e,reply(e))
			expect(hook_result.ok and e.state_copy().actors.actor_player.health.current==11 and e.state_copy().actors.actor_player.statuses.poison.remaining_turns==1,"ordinary poison ticks once in every creative branch")
			expect((e.state_copy().actors.actor_scout.hex==t.endpoints[0])==(placement and stability),"patrol uses selected branch obstruction")
	# Removing one brace cannot clear a separate intrinsic cell blocker.
	e=make(seed_for(true,true));expect(finish(e,reply(e)).ok,"independent blocker setup")
	data=e.save_data();data.state.hexes[Traversal.key(t.endpoints[0])].ground_blocked=true;expect(e.load_data(data).ok,"independent obstruction fixture")
	expect(finish(e,reply(e,PLANK,NORTH,"remove_obstruction")).ok and not Traversal.can_enter(e.state_copy(),e.state_copy().actors.actor_player,t.endpoints[0]),"removal preserves unrelated cell blocker")
	# Two retained source-target pairs are allowed for one legitimately reused object.
	e=make(seed_for(true,true));expect(finish(e,reply(e)).ok and finish(e,reply(e,PLANK,NORTH,"remove_obstruction")).ok,"completed first pair")
	initial=e.state_copy();initial.actors.actor_player.hex=initial.passage_targets[SOUTH].support_hex.duplicate()
	var pair_engine:=make(seed_for(true,true),initial)
	expect(finish(pair_engine,reply(pair_engine,PLANK,SOUTH)).ok and pair_engine.state_copy().creative_relations.size()==2,"same source second target retains two pairs without active duplicate")
	# Versioned history capacity is fail-closed, and stale relation/pose saves reject.
	e=make(seed_for(false,false));expect(finish(e,reply(e)).ok,"history capacity seed")
	data=e.save_data();var ledger_key: String=data.attempt_ledger.keys()[0];data.attempt_ledger[ledger_key].fingerprints=[]
	for i in range(256):data.attempt_ledger[ledger_key].fingerprints.append(C.digest(["capacity fixture",i]))
	expect(e.load_data(data).ok,"bounded 256-entry history fixture accepted")
	reject(e,reply(e),"RETRY_HISTORY_CAPACITY","history cap cannot evict old attempts for a new roll")
	var forged: Dictionary=pair_engine.save_data();forged.state.creative_relations.values()[0].target_revision=9;expect(not pair_engine.load_data(forged).ok,"forged target revision rejected")
	forged=pair_engine.save_data();forged.state.creative_placements[PLANK]["free_transform"]=[1,2,3];expect(not pair_engine.load_data(forged).ok,"unknown free pose rejected")
	for malformed in [{},true,{"source_item_id":true,"active":"yes"}]:
		forged=pair_engine.save_data();forged.state.creative_relations[Effects.relation_id(PLANK,SOUTH)]=malformed
		expect(not pair_engine.load_data(forged).ok,"malformed relation cannot crash cross-pose validation")
	# Exact pending rederivation at every phase, with files for a fresh process.
	e=make(seed_for(true,true));a=reply(e)
	for phase in ["awaiting_assessment","ready_roll","rolled","staged"]:
		if phase=="ready_roll":expect(e.prepare_assessment(a).ok,"pending prepare")
		elif phase=="rolled":expect(e.roll_once(a.action_id).ok,"pending roll")
		elif phase=="staged":expect(e.stage(a.action_id).ok,"pending stage")
		write_json("pending_"+phase+".json",e.save_data())
		var restored:=make(999);expect(restored.load_data(e.save_data()).ok and C.bytes(restored.save_data())==C.bytes(e.save_data()),"exact pending load "+phase)
	expect(e.commit(a.action_id,e.action_copy(a.action_id).stage_hash).ok,"pending baseline commit");write_json("pending_expected.json",e.save_data())
	# Actual adapter registry, fixture, selection and transport projection.
	var adapter:=Adapter.new(1,true);expect(adapter.engine.ready().ok,"current adapter ready")
	var saved: Dictionary=adapter.engine.save_data();saved.state.actors.actor_player.hex=saved.state.passage_targets[NORTH].support_hex.duplicate();expect(adapter.engine.load_data(saved).ok,"isolated adapter fixture setup")
	var focus:=Content.make_reference(SOUTH,adapter.state_copy());var goal:=Examples.public_goal("place_obstruction",adapter.state_copy(),"item_brace_bar",NORTH)
	expect(adapter.begin_intent(goal,focus).ok and adapter.fixture_available(),"explicit source/target fixture while focus distracts")
	var pending_before: Dictionary=adapter.action_copy();adapter.attention(Content.make_reference(PLANK,adapter.state_copy()))
	expect(C.bytes(pending_before)==C.bytes(adapter.action_copy()),"read-only attention leaves request target/hash frozen")
	expect(adapter.prepare_fixture().ok and adapter.action_copy().assessment.bindings.source.id=="item_brace_bar" and adapter.action_copy().assessment.bindings.target.id==NORTH,"explicit text wins over focus in actual fixture path")
	var scoped:=Scope.new(adapter.engine,func():return true);var request:=scoped.model_request(adapter.active_action)
	expect(not request.is_empty() and C.bytes(request).to_utf8_buffer().size()<=65536,"actual scoped creative request fits 64KiB")
	write_json("public_request.json",request)
	var changed: Dictionary=adapter.engine.save_data();changed.state.items[PLANK].physical_traits.mass_g=1;expect(not adapter.engine.load_data(changed).ok,"forged saved profile rejected")
	changed=adapter.engine.save_data();changed.state.passage_targets[NORTH].pose_frames.loose.origin_mm[0]+=1;expect(not adapter.engine.load_data(changed).ok,"forged target geometry rejected")
	# New attention projection cannot bypass existing public-field allowlists.
	var private_state:=base.duplicate(true);private_state.items[PLANK]["private_notes"]="NEVER_EXPORT_CREATIVE_PRIVATE"
	private_state.hexes[Traversal.key(private_state.actors.actor_player.hex)]["private_notes"]="NEVER_EXPORT_CREATIVE_CELL"
	var private_engine:=make(1,private_state);var private_request:Dictionary=private_engine.begin_intent("Look at this",Content.make_reference(PLANK,private_state)).request
	expect(not C.bytes(private_request).contains("NEVER_EXPORT_CREATIVE"),"creative attention cannot leak arbitrary item/cell private metadata")
	expect(Content.make_reference(PLANK,private_state).entity_revision==Content.make_reference(PLANK,base).entity_revision,"attention revision does not expose a private-field hash oracle")
	# Strict feedback never grants authority; public expansion is frozen/read-only.
	adapter.cancel()
	expect(adapter.begin_intent("Could I use this long thing to stop him?",Content.make_reference(PLANK,adapter.state_copy())).ok,"question remains an unexecuted request")
	var control_request: Dictionary=adapter.request()
	for code in ControlReply.CODES:
		var feedback: Dictionary={"schema_version":ControlReply.SCHEMA,"action_id":control_request.action_id,"state_version":control_request.state_version,"context_hash":control_request.context_hash,"code":code,"message":"Please clarify the intended object and consequence." if code=="NEEDS_CLARIFICATION" else "This installed mechanism needs exact public facts.","candidates":[{"kind":"item","id":PLANK}],"context_paths":["/hexes/-1,14"] if code=="NEEDS_PUBLIC_CONTEXT" else [],"provenance":{"provider":"offline mock model feedback","live":false,"kind":"model_reply"}}
		var before_feedback: Dictionary=adapter.engine.save_data();var result: Dictionary=adapter.import_reply(feedback)
		expect(result.get("code")==code and C.bytes(before_feedback)==C.bytes(adapter.engine.save_data()),"strict non-mutating feedback "+code)
		if code=="NEEDS_PUBLIC_CONTEXT":
			expect(result.public_context.has("/hexes/-1,14"),"known public fact expanded")
			feedback.context_paths=["/actors/actor_keeper/secrets"]
			expect(adapter.import_reply(feedback).get("code")=="INVALID_CONTROL","context expansion cannot disclose private paths")
		feedback["patches"]=[];expect(adapter.import_reply(feedback).get("code")=="INVALID_CONTROL","control envelope rejects raw effect extension")
	adapter.cancel()
	# Old idle world may adopt resolver IDs but never new physical facts or inventory.
	var old: Dictionary=adapter.engine.save_data();old.resolver_ids.erase(Actions.ID)
	for field in Content.EXTENSION_FIELDS:old.state.erase(field)
	for id in Content.ITEM_IDS:old.state.items.erase(id);old.state.actors.actor_player.inventory.erase(id)
	old.receipts={};old.attempt_ledger={};old.pending={};old.next_action=1
	var old_path: String="user://creative_old_idle.json";var old_file:=FileAccess.open(old_path,FileAccess.WRITE);old_file.store_string(C.bytes(old));old_file.close()
	var old_adapter:=Adapter.new(1,true);expect(old_adapter.load_file(old_path).ok,"old registry/world loads exactly")
	expect(old_adapter.begin_intent("Observe the shoreline").ok and not old_adapter.state_copy().has("physical_catalog") and not old_adapter.state_copy().items.has(PLANK),"idle migration grants no objects or traits")
	evidence["checks"]=checks;evidence["failures"]=failures;write_json("core_report.json",evidence)
	print("CREATIVE_CORE ",checks-failures.size(),"/",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
