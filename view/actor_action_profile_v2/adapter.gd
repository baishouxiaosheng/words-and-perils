extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Source=preload("res://view/actor_action_profile_v2/source.gd")
const GMEngine=preload("res://view/actor_action_profile_v2/engine.gd")
const Resolver=preload("res://view/actor_action_profile_v2/resolver.gd")
const Rule=preload("res://view/actor_action_profile_v2/rule.gd")
const Scheduler=preload("res://view/actor_action_profile_v2/scheduler.gd")
const Decision=preload("res://view/actor_action_profile_v2/decision.gd")
const History=preload("res://view/actor_action_profile_v2/history.gd")
const SAVE="generated_v3_actor_actions_save/v2"
const MAX_BYTES=24*1024*1024
var source:RefCounted
var engine:RefCounted
var scheduler=Scheduler.new()
var decision:RefCounted
var journal:Array=[]
func _init()->void:decision=Decision.new(self)
func start_source(data:Variant)->Dictionary:
	var next=Source.new();var checked:Dictionary=next.admit(data)
	if not checked.ok:return checked
	return _publish(next,make_engine(next),[])
static func make_engine(candidate:RefCounted)->RefCounted:
	var registry:Dictionary={}
	for kind in Source.KINDS:
		var resolver=Resolver.new(candidate,kind);registry[resolver.resolver_id()]=resolver
	var flags:Array=[]
	for id in Source.ACTORS:flags.append_array([Source.observation_key(id),Source.last_cell_key(id)])
	return GMEngine.new(candidate.world,Rule.new(registry),registry,{"npc_secret_allowlist":[],"public_flag_ids":flags})
func _publish(next_source:RefCounted,next_engine:RefCounted,history:Array)->Dictionary:
	if not next_engine.ready().ok:return next_engine.ready()
	var next_scheduler=Scheduler.new()
	var checked:Dictionary=next_scheduler.bind_validated_engine(next_engine,next_engine.save_data().pending)
	if not checked.ok:return checked
	source=next_source;engine=next_engine;scheduler=next_scheduler;journal=history.duplicate(true);decision.invalidate()
	return {"ok":true}
func begin_intent(actor_id:String,goal:String,focus:Dictionary={})->Dictionary:
	var result:Dictionary=scheduler.begin_intent(actor_id,goal,focus)
	if result.ok and C.bytes(result.request).to_utf8_buffer().size()>65536:
		scheduler.cancel();return C.fail("ASSESSMENT_BUDGET","Complete actor assessment exceeds 64 KiB; no partial disclosure or action.")
	if result.ok:decision.invalidate()
	return result
func commit(action_id:String,stage_hash:String)->Dictionary:
	var action:Dictionary=engine.action_copy(action_id)
	if not action.is_empty() and C.bytes(save_data()).to_utf8_buffer().size()>MAX_BYTES-65536:return C.fail("HISTORY_BUDGET","Insufficient reserved history capacity; no commit.")
	var result:Dictionary=scheduler.commit(action_id,stage_hash)
	if result.ok and not result.already_committed:
		journal.append({"action_id":action_id,"actor_id":action.actor_id,"goal":action.goal,"reference":engine._focus.reference_for(action.focus),"assessment":action.assessment.duplicate(true),"rng_before":action.rng_before.duplicate(true)})
		decision.invalidate()
	return result
func cancel()->Dictionary:
	decision.invalidate();return scheduler.cancel()
func save_data()->Dictionary:
	if source==null or engine==null:return {}
	return C.normalized({"schema_version":SAVE,"profile":Source.PROFILE,"identity":source.identity,"source":source.base.data,"placement":source.base.placement_result.manifest,"enemy_placement":source.base.enemy_placement_result.placement_witness,"engine":engine.save_data(),"journal":journal})
func load_data(value:Variant)->Dictionary:
	if not C.exact_fields(value,["schema_version","profile","identity","source","placement","enemy_placement","engine","journal"]) or not C.safe(value) or not GMEngine.valid_transport_strings(value) or value.schema_version!=SAVE or value.profile!=Source.PROFILE or not value.journal is Array or not value.engine is Dictionary or not value.engine.get("campaign_memory") is Dictionary or not value.identity is Dictionary or not value.source is Dictionary or not value.placement is Dictionary or not value.enemy_placement is Dictionary or C.bytes(value).to_utf8_buffer().size()>MAX_BYTES:return C.fail("ACTOR_SAVE_SCHEMA","Use this profile's separate save; legacy saves are never migrated or rewritten.")
	value=C.normalized(value)
	var next=Source.new();var checked:Dictionary=next.admit(value.source,value.placement,value.enemy_placement)
	if not checked.ok:return checked
	if C.bytes(next.identity)!=C.bytes(value.identity):return C.fail("ACTOR_SAVE_IDENTITY","Source, registered code or capabilities changed.")
	checked=next.validate_state(value.engine.get("state"))
	if not checked.ok:return checked
	var next_engine=make_engine(next);checked=next_engine.load_data(value.engine)
	if not checked.ok:return checked
	checked=History.validate(next,next_engine,value.journal,value.engine)
	if not checked.ok:return checked
	return _publish(next,next_engine,value.journal)
func save_file(path:String)->Dictionary:
	if path.get_file()!="actor_actions_v2.json":return C.fail("ACTOR_SAVE_NAMESPACE","Candidate writes only actor_actions_v2.json; legacy names are protected.")
	if FileAccess.file_exists(path):
		var old:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not old is Dictionary or old.get("schema_version")!=SAVE:return C.fail("ACTOR_SAVE_NAMESPACE","Existing file belongs to another profile.")
	var f=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null:return C.fail("SAVE_FAILED","Cannot write candidate save.")
	f.store_string(C.bytes(save_data()));f.flush();f.close()
	return {"ok":true} if DirAccess.rename_absolute(path+".tmp",path)==OK else C.fail("SAVE_FAILED","Atomic rename failed.")
