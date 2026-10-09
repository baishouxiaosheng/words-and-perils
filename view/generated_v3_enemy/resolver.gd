extends RefCounted
## Wrap registered actions with this profile's one spatial/scheduling policy.
## All health, weapon, poison and event patches come from BasicActions unchanged.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const BasicActions=preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const ResponseBudget=preload("res://view/generated_v3_enemy/response_budget.gd")
const Hooks=preload("res://core/ai_gm_rebuilt/hooks.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const BaseResolver=preload("res://view/generated_v3_npc/resolver.gd")
const Conversation=preload("res://core/source_npc/conversation.gd")
const Policy=preload("res://view/generated_v3_enemy/policy.gd")
var source:RefCounted
var delegate:RefCounted
var kind:String
func _init(source_:RefCounted,kind_:String)->void:
	source=source_;kind=kind_
	delegate=BasicActions.new("basic_attack") if kind=="attack" else (Conversation.new(source.talk_range) if kind=="talk" else BaseResolver.new(source,kind))
func resolver_id()->String:return delegate.resolver_id()
func action_schema()->Dictionary:
	var result:Dictionary=delegate.action_schema();result.schema_version="generated_v3_village_enemy_actions/v1"
	result["source_profile"]="generated_v3_village_enemy/v1"
	result["encounter_policy"]="one stationary hostile; exact dry adjacent edge, 1 stamina/attack; every player action may schedule a separately assessed feasible enemy attack; HP0 blocks intention; enemy cell occupied alive or downed"
	return result
func attempt_key(snapshot:Dictionary,assessment:Dictionary)->String:return delegate.attempt_key(snapshot,assessment)
func attempt_fingerprint(snapshot:Dictionary,assessment:Dictionary)->Dictionary:
	var result:Dictionary=delegate.attempt_fingerprint(snapshot,assessment);result["committed_turn"]=snapshot.turn;result["combat_turn"]=snapshot.combat_turn.duplicate(true);return result
func check_policy(snapshot:Dictionary,assessment:Dictionary)->Dictionary:
	var checked:Dictionary=freeze(snapshot,assessment)
	if not checked.ok:return checked
	var policies:Dictionary={}
	for component in assessment.components:policies[component.id]="contested" if kind=="attack" else "safe_direct"
	return {"ok":true,"policies":policies}
func freeze(snapshot:Dictionary,assessment:Dictionary)->Dictionary:
	var checked:Dictionary=source.validate_state(snapshot)
	if not checked.ok:return checked
	checked=Basic.validate_phase_assessment(snapshot,assessment)
	if not checked.ok:return checked
	if kind=="attack":
		var actor_id:String=assessment.bindings.get("actor_id","");var target_id:String=assessment.bindings.get("target_actor_id","")
		if not Policy.melee_range(snapshot,actor_id,target_id,source.base_navigation):return C.fail("ENEMY_MELEE_RANGE","只能攻击真实干地通路连通的相邻敌人；不能隔水或隔墙攻击。")
	var plan:Dictionary=delegate.freeze(snapshot,assessment)
	if not plan.ok:return plan
	for branch in plan.branches:
		var ordinary:Array=[]
		for patch in branch.patches:
			if patch.get("type")!="combat_turn_set":ordinary.append(patch)
		var candidate:Dictionary=snapshot.duplicate(true)
		for patch in ordinary:
			checked=World.apply(candidate,patch)
			if not checked.ok:return checked
		var scheduled:Dictionary=Policy.schedule_patch(snapshot,candidate,str(assessment.bindings.actor_id),source.base_navigation,source.enemy_id)
		if not scheduled.is_empty():
			ordinary.append(scheduled);checked=World.apply(candidate,scheduled)
			if not checked.ok:return checked
		var after_hooks:Dictionary=candidate.duplicate(true)
		checked=Hooks.freeze(snapshot,after_hooks)
		if not checked.ok:return checked
		after_hooks.state_version+=1;after_hooks.turn+=1
		var capacity:Dictionary=ResponseBudget.check(after_hooks,source.enemy_request_contract)
		source.enemy_capacity_metrics=capacity.duplicate(true)
		if not capacity.ok:return capacity
		branch.patches=ordinary
	return plan
static func local_result(result:Dictionary)->Dictionary:return BaseResolver.local_result(result)
