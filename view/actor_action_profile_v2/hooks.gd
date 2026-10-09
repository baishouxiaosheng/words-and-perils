extends RefCounted
## New-profile phase seam. Reuse exact original status/patrol/landing results;
## apply every non-phase effect once, then one actor-aware phase decision.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OriginalHooks=preload("res://core/ai_gm_rebuilt/hooks.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Policy=preload("res://view/actor_action_profile_v2/policy.gd")
static func freeze(before:Dictionary,candidate:Dictionary,actor_id:String,navigation:RefCounted)->Dictionary:
	if C.bytes(before.combat_turn)!=C.bytes(candidate.combat_turn):return C.fail("ACTOR_PHASE_HOOK","Only the new profile hook owns phase advancement.")
	# The probe is detached: original hooks may calculate their legacy attack-only
	# phase reset, but that reset is not applied to this profile's candidate.
	var probe:Dictionary=candidate.duplicate(true)
	var original:Dictionary=OriginalHooks.freeze(before,probe,actor_id)
	if not original.ok:return original
	var patches:Array=[]
	for patch in original.patches:
		if patch.get("type")=="combat_turn_set":continue
		var applied:Dictionary=World.apply(candidate,patch,true)
		if not applied.ok:return applied
		patches.append(patch.duplicate(true))
	# Ensure only the legacy phase differs from the original complete hook result.
	var expected:Dictionary=probe.duplicate(true);expected.combat_turn=candidate.combat_turn.duplicate(true)
	if C.bytes(expected)!=C.bytes(candidate):return C.fail("ACTOR_HOOK_REUSE","Non-phase hook effects differ from the original registered hook result.")
	var phase:Dictionary=Policy.after_hooks(before,candidate,actor_id,navigation)
	if not phase.ok:return phase
	var applied:Dictionary=World.apply(candidate,phase.patch,true)
	if not applied.ok:return applied
	patches.append(phase.patch)
	return {"ok":true,"patches":patches}
