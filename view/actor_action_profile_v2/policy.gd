extends RefCounted
## Ordinary actor eligibility and existing contact scope are separate from attack rules.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Legacy=preload("res://view/generated_v3_enemy/policy.gd")
const Foundation=preload("res://core/status_foundation/engine_bridge.gd")
const ACTORS=["actor_player","actor_village_hostile"]
static func authorized(state:Dictionary)->String:return Basic.authorized_actor(state)
static func occupied(state:Dictionary,hex:Array,actor_id:String)->bool:return Legacy.occupied(state,hex,actor_id)
static func eligible(state:Dictionary,actor_id:String)->bool:
	if actor_id not in ACTORS or not state.get("actors",{}).has(actor_id):return false
	return state.actors[actor_id].health.current>0 and Foundation.permits_intent(state,actor_id)
static func can_schedule(state:Dictionary,navigation:RefCounted)->bool:
	# Preserve the original living-hostile, same-scene, dry-adjacent encounter scope.
	# Weapon, ammunition and attack stamina belong to the chosen attack resolver.
	if not state.get("actors",{}).has(ACTORS[0]) or not eligible(state,ACTORS[1]) or state.actors[ACTORS[0]].health.current<=0:return false
	var enemy:Dictionary=state.actors[ACTORS[1]];var player:Dictionary=state.actors[ACTORS[0]]
	if player.faction==enemy.faction or player.faction not in enemy.get("combat_profile",{}).get("hostile_factions",[]):return false
	return Legacy.melee_range(state,ACTORS[1],ACTORS[0],navigation)
static func validate_assessment(state:Dictionary,assessment:Dictionary)->Dictionary:
	var id:Variant=assessment.bindings.get("actor_id","")
	if id not in ACTORS or id!=authorized(state):return C.fail("TURN_ACTOR","The authoritative slot belongs to another registered actor.")
	if state.actors[id].health.current<=0:return C.fail("ACTOR_DOWNED","A downed actor has no deliberate action slot.")
	if not Foundation.permits_intent(state,id):return C.fail("STATUS_ACTION_BLOCKED","Registered status blocks intentional action.")
	return {"ok":true}
static func after_hooks(before:Dictionary,candidate:Dictionary,actor_id:String,navigation:RefCounted)->Dictionary:
	if actor_id not in ACTORS or authorized(before)!=actor_id or C.bytes(before.combat_turn)!=C.bytes(candidate.combat_turn):return C.fail("ACTOR_PHASE_HOOK","Ordinary patches cannot replace the current authoritative phase.")
	var phase="player";var round_=int(before.combat_turn.round)
	if actor_id==ACTORS[0] and can_schedule(candidate,navigation):phase="enemy";round_+=1
	return {"ok":true,"patch":Basic.turn_patch(candidate,phase,ACTORS[1],round_)}
