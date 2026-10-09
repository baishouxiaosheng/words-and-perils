extends RefCounted
## Lift only detached views; execute the frozen v2 hook exactly once.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Domain=preload("res://view/actor_status_profile_v1/domain.gd")
const FrozenHooks=preload("res://view/actor_action_profile_v2/hooks.gd")
static func freeze(before:Dictionary,candidate:Dictionary,actor_id:String,navigation:RefCounted)->Dictionary:
	var old_view:Dictionary=Domain.lift(before)
	if not old_view.ok:return old_view
	var new_view:Dictionary=Domain.lift(candidate)
	if not new_view.ok:return new_view
	var result:Dictionary=FrozenHooks.freeze(old_view.world,new_view.world,actor_id,navigation)
	if not result.ok:return result
	var expected:Dictionary=Domain.restore(new_view.world)
	if not expected.ok:return expected
	var replay:Dictionary=candidate.duplicate(true)
	for patch in result.patches:
		var checked:Dictionary=Domain.apply(replay,patch,true)
		if not checked.ok:return checked
	if C.bytes(replay)!=C.bytes(expected.world):return C.fail("ACTOR_STATUS_HOOK","Canonical patch replay differs from the exactly-once frozen hook view.")
	candidate.clear();candidate.merge(replay,true)
	return result
