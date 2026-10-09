extends RefCounted
## Intent proposal interface only. No provider, API calls, fallback choice or assessment.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const PublicProjection=preload("res://view/actor_status_profile_v1/projection.gd")
var owner_ref:WeakRef
var grant:Dictionary={}
var sequence=0
func _init(owner:RefCounted)->void:owner_ref=weakref(owner)
func invalidate()->void:grant.clear()
func request(now_ms:int,ttl_ms:int=0)->Dictionary:
	var adapter:RefCounted=owner_ref.get_ref()
	if adapter==null:return C.fail("DECISION_OWNER","Adapter no longer exists.")
	if now_ms<0 or ttl_ms<0:return C.fail("DECISION_CLOCK","Clock and optional expiry must be nonnegative.")
	if not grant.is_empty():return C.fail("DECISION_PENDING","Invalidate or answer the existing proposal request first.")
	var slot:Dictionary=adapter.scheduler.next_slot()
	if not slot.get("ok",false):return slot
	if not slot.needs_intent:return C.fail("ACTION_IN_PROGRESS","A frozen action already owns the slot.")
	var state:Dictionary=adapter.engine.state_copy();var actor_id:String=slot.actor_id
	var context={"facts":PublicProjection.facts(state,actor_id),"capabilities":adapter.engine.capability_catalog(actor_id),"memory_context":adapter.engine.memory_context(actor_id)}
	sequence+=1
	grant={"schema_version":"actor_status_intent_proposal/v1","proposal_id":str(get_instance_id())+":"+str(sequence),"actor_id":actor_id,"state_version":state.state_version,"context_hash":C.digest(context),"issued_ms":now_ms,"expires_ms":now_ms+ttl_ms if ttl_ms>0 else -1,"context":context}
	if C.bytes(grant).to_utf8_buffer().size()>65536:grant.clear();return C.fail("DECISION_BUDGET","Complete public proposal exceeds 64 KiB; no truncation or fallback.")
	return {"ok":true,"request":grant.duplicate(true),"network_calls":0,"decision_source":"external_intent_required"}
func accept(reply:Variant,now_ms:int)->Dictionary:
	var adapter:RefCounted=owner_ref.get_ref()
	if adapter==null:return C.fail("DECISION_OWNER","Adapter no longer exists.")
	if grant.is_empty():return C.fail("DECISION_STALE","No current proposal grant.")
	if not C.exact_fields(reply,["schema_version","proposal_id","actor_id","state_version","context_hash","goal","focus"]) or not C.safe(reply):return C.fail("DECISION_SCHEMA","Only bound goal and focus data are accepted, never patches or assessment fields.")
	for field in ["schema_version","proposal_id","actor_id","state_version","context_hash"]:
		if reply[field]!=grant[field]:return C.fail("DECISION_STALE","Proposal no longer owns this actor/context.")
	if now_ms<int(grant.issued_ms):return C.fail("DECISION_CLOCK","Monotonic clock moved backwards.")
	if int(grant.expires_ms)>=0 and now_ms>=int(grant.expires_ms):invalidate();return C.fail("DECISION_EXPIRED","Expired proposal leaves the same world and actor slot unchanged.")
	var state:Dictionary=adapter.engine.state_copy()
	if state.state_version!=grant.state_version or not adapter.scheduler.phase()=="idle":return C.fail("DECISION_STALE","World or current action changed.")
	if not reply.goal is String or reply.goal.strip_edges().is_empty() or reply.goal.to_utf8_buffer().size()>8192 or not reply.focus is Dictionary:return C.fail("DECISION_INTENT","Explicit bounded goal and focus required.")
	if not PublicProjection.visible_focus(state,reply.actor_id,reply.focus):return C.fail("ACTOR_VISIBILITY","Proposal cannot select an unseen target.")
	var result:Dictionary=adapter.begin_intent(reply.actor_id,reply.goal,reply.focus)
	if result.ok:invalidate()
	return result
