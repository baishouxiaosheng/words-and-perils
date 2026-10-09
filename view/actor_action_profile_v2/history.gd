extends RefCounted
## Replays the original assessed action and actual RNG lineage through real Engine.
## Never reconstructs an enemy decision from example text or inferred patches.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
static func validate(source:RefCounted,installed:RefCounted,journal:Array,saved:Dictionary)->Dictionary:
	if journal.size()!=saved.receipts.size():return C.fail("ACTOR_HISTORY","Every committed receipt requires exactly one assessed-action witness.")
	var replay=installed.get_script().new(source.world,installed._calculator,installed._resolvers,installed._policy)
	var seen:Dictionary={};var previous_sequence=0
	for row in journal:
		if not C.exact_fields(row,["action_id","actor_id","goal","reference","assessment","rng_before"]) or not row.action_id is String or not row.actor_id is String or not row.goal is String or not row.reference is Dictionary or not row.assessment is Dictionary or not row.rng_before is Dictionary or not saved.receipts.has(row.action_id) or seen.has(row.action_id):return C.fail("ACTOR_HISTORY","Malformed or duplicate assessed history witness.")
		var suffix:String=str(row.action_id).trim_prefix(source.world.world_id+":action_")
		if not suffix.is_valid_int() or suffix!=str(int(suffix)) or int(suffix)<=previous_sequence or int(suffix)>=int(saved.next_action):return C.fail("ACTOR_HISTORY_SEQUENCE","Committed action IDs must have ordered unique lineage.")
		if not C.exact_fields(row.rng_before,["seed","state"]) or not C.int64_string(row.rng_before.seed) or not C.int64_string(row.rng_before.state):return C.fail("ACTOR_HISTORY_RNG","History needs exact serialized RNG lineage.")
		if seen.is_empty():replay._rng.seed=int(row.rng_before.seed);replay._rng.state=int(row.rng_before.state)
		elif str(replay._rng.seed)!=row.rng_before.seed or str(replay._rng.state)!=row.rng_before.state:return C.fail("ACTOR_HISTORY_RNG","RNG cannot reset between committed actions.")
		replay._next_action=int(suffix)
		var begun:Dictionary=replay.begin_intent(row.goal,row.reference,row.actor_id)
		if not begun.ok:return begun
		if begun.request.action_id!=row.action_id:return C.fail("ACTOR_HISTORY_SEQUENCE","World/action identity differs.")
		var checked:Dictionary=replay.prepare_assessment(row.assessment)
		if not checked.ok:return checked
		checked=replay.roll_once(row.action_id)
		if not checked.ok:return checked
		checked=replay.stage(row.action_id)
		if not checked.ok:return checked
		var result:Dictionary=replay.commit(row.action_id,checked.stage_hash)
		if not result.ok:return result
		if C.bytes(result.receipt)!=C.bytes(saved.receipts[row.action_id]):return C.fail("ACTOR_HISTORY_RECEIPT","Stored receipt differs from exact ordinary Engine replay.")
		seen[row.action_id]=true;previous_sequence=int(suffix)
	for field in ["state","receipts","attempt_ledger","campaign_memory"]:
		if C.bytes(replay.save_data()[field])!=C.bytes(saved[field]):return C.fail("ACTOR_HISTORY_STATE","Saved "+field+" differs from exact source-bound history.")
	if not journal.is_empty():
		var expected:Dictionary=saved.rng
		if not saved.pending.is_empty():expected=saved.pending.values()[0].rng_before
		if str(replay._rng.seed)!=expected.seed or str(replay._rng.state)!=expected.state:return C.fail("ACTOR_HISTORY_RNG","Committed and pending RNG lineages disagree.")
	return {"ok":true,"replayed_receipts":journal.size()}
