extends RefCounted
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const Effects=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Traversal=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Hooks=preload("res://view/actor_status_profile_v1/hooks.gd")
const Domain=preload("res://view/actor_status_profile_v1/domain.gd")
const Policy=preload("res://view/actor_action_profile_v2/policy.gd")
const PublicProjection=preload("res://view/actor_status_profile_v1/projection.gd")
const StatusAction=preload("res://core/status_gameplay/action.gd")
var source:RefCounted
var kind:String
var delegate:RefCounted
func _init(source_:RefCounted,kind_:String)->void:
	source=source_;kind=kind_
	if kind in Basic.KINDS:delegate=Basic.new(kind)
	elif kind=="status_source":delegate=StatusAction.new()
func resolver_id()->String:return "actor_status_"+kind+"_v1"
func action_schema()->Dictionary:
	var result:Dictionary=delegate.action_schema() if delegate!=null else {"bindings":{"actor_id":"actual authorized actor ID","target_hex":"visible [q,r]"} if kind!="rest" else {"actor_id":"actual authorized actor ID"},"components":[kind],"required_fact_paths":["/actors/<actor_id>"]}
	result.schema_version="actor_status_actions/v1";result.resolver_id=resolver_id();result["source_profile"]="generated_v3_actor_status/v1";result["every_intent_requires_assessment"]=true
	result["numeric_assessment"]={"A":[0,4],"D":[0,4],"P":[-2,2]}
	if kind=="move":
		result["terrain_costs"]=Traversal.COSTS;result["movement_policy"]="Actual actor stamina/traversal budget; source-validated dry edges; no other living/downed combatant cell; visible target only."
	elif kind=="observe":result["range_cells"]=1;result["knowledge_owner"]="acting actor only"
	elif kind=="rest":result["stamina_gain_cap"]=2;result["full_stamina_policy"]="reject without cost or time"
	elif kind=="status_source":result["delivery_policy"]="Self or one real source-bound dry adjacent edge in both directions; no remote or through-wall source delivery. Only poison_vial, feather_vial, antidote and intrinsic land."
	return result
func attempt_key(_state:Dictionary,assessment:Dictionary)->String:return resolver_id()+":"+C.bytes(assessment.bindings)
func attempt_fingerprint(state:Dictionary,assessment:Dictionary)->Dictionary:
	var result:Dictionary=delegate.attempt_fingerprint(state,assessment) if delegate!=null else {"actor":state.actors[assessment.bindings.actor_id],"flags":state.flags}
	# Compatibility profile has always permitted a distinct committed turn attempt.
	result["committed_turn"]=state.turn;result["combat_turn"]=state.combat_turn
	return result
func check_policy(state:Dictionary,assessment:Dictionary)->Dictionary:
	var checked=freeze(state,assessment)
	if not checked.ok:return checked
	var policies:Dictionary={}
	var status_policy="safe_direct" if assessment.bindings.get("source_id")=="land" else "contested"
	for component in assessment.components:policies[component.id]=status_policy if kind=="status_source" else ("contested" if kind=="basic_attack" else "safe_direct")
	return {"ok":true,"policies":policies}
func freeze(state:Dictionary,assessment:Dictionary)->Dictionary:
	var checked:Dictionary=source.validate_state(state)
	if not checked.ok:return checked
	checked=Policy.validate_assessment(state,assessment)
	if not checked.ok:return checked
	var id:String=assessment.bindings.actor_id
	var public:Dictionary=PublicProjection.facts(state,id)
	for field in ["target_actor_id","item_id","weapon_item_id"]:
		if assessment.bindings.has(field):
			var collection:String="actors" if field=="target_actor_id" else "items"
			if not public[collection].has(assessment.bindings[field]):return C.fail("ACTOR_VISIBILITY","Bound target must be visible to the acting actor.")
	var plan:Dictionary
	if delegate!=null:
		if kind=="status_source":
			var target_id:Variant=assessment.bindings.get("target_actor_id","")
			var source_id:Variant=assessment.bindings.get("source_id","")
			if not target_id is String or not source_id is String:return C.fail("STATUS_BINDINGS","Source and target must be stable string IDs.")
			if not target_id in source.ACTORS:return C.fail("STATUS_TARGET","This actor profile only installs status delivery to its two registered encounter actors.")
			if source_id!="land" and not source_id in source.CONSUMABLES:return C.fail("STATUS_SOURCE","Only the three source-bound consumables and intrinsic land are installed.")
			if source_id!="land" and not public.items.has(source_id):return C.fail("ACTOR_VISIBILITY","Status source must be visible to the acting actor.")
			if target_id!=id and not Policy.Legacy.melee_range(state,id,target_id,source.navigation):return C.fail("STATUS_DELIVERY_EDGE","Another target requires real bidirectional source geometry and dry support, with no blocking cell or wall.")
		if kind=="basic_attack" and not Policy.Legacy.melee_range(state,id,assessment.bindings.get("target_actor_id",""),source.navigation):return C.fail("ATTACK_RANGE","Attack requires one real source-validated dry edge.")
		if kind=="pickup_item":
			var item:Dictionary=state.items.get(assessment.bindings.get("item_id",""),{})
			var target:Array=item.get("hex",state.actors.get(item.get("owner_actor_id",""),{}).get("hex",[]))
			if target.size()!=2:return C.fail("ITEM_RANGE","Item has no registered location.")
			if target!=state.actors[id].hex and not source.navigation.step(state.actors[id].hex,target).get("ok",false):return C.fail("ITEM_RANGE","Pickup must cross a real dry adjacent edge.")
		plan=delegate.freeze(Domain.lift(state).world if kind=="status_source" else state,assessment)
	else:plan=_ordinary(state,assessment,public)
	if not plan.ok:return plan
	plan.resolver_id=resolver_id()
	for branch in plan.branches:
		var ordinary:Array=[]
		for patch in branch.patches:
			if patch.get("type")!="combat_turn_set":ordinary.append(patch)
		var candidate=state.duplicate(true)
		for patch in ordinary:
			checked=Domain.apply(candidate,patch)
			if not checked.ok:return checked
		var preview:Dictionary=candidate.duplicate(true)
		checked=Hooks.freeze(state,preview,id,source.navigation)
		if not checked.ok:return checked
		preview.state_version+=1;preview.turn+=1
		checked=source.validate_state(preview)
		if not checked.ok:return checked
		branch.patches=ordinary
	return plan
func _ordinary(state:Dictionary,a:Dictionary,public:Dictionary)->Dictionary:
	var b:Dictionary=a.bindings
	var fields:Array=["actor_id"] if kind=="rest" else ["actor_id","target_hex"]
	if not kind in ["move","observe","rest"] or not C.exact_fields(b,fields) or a.components.size()!=1 or a.components[0].id!=kind:return C.fail("ACTOR_BINDING","Unsupported ordinary action fields.")
	var id:String=b.actor_id;var actor:Dictionary=state.actors[id]
	if not has_ref(a,"/actors/"+id):return C.fail("ACTOR_FACT","Assessment must cite the actual acting actor.")
	var patches:Array=[]
	if kind=="rest":
		var gain=mini(2,int(actor.stamina.max)-int(actor.stamina.current))
		if gain<=0:return C.fail("REST_FULL","Stamina is already full; no action or time charged.")
		patches.append({"type":"actor_pool_delta","actor_id":id,"pool":"stamina","delta":gain})
	else:
		if not World.valid_hex(b.target_hex,state,actor.scene_id):return C.fail("ACTION_TARGET","A real integer cell is required.")
		var key="%d,%d"%b.target_hex
		if not public.hexes.has(key):return C.fail("ACTOR_VISIBILITY","Target cell is not visible to this actor.")
		if not has_ref(a,"/hexes/"+key):return C.fail("ACTOR_FACT","Assessment must cite its exact visible target cell.")
		if kind=="move":
			var edge=func(from:Array,to:Array)->Dictionary:
				if Policy.occupied(state,to,id):return C.fail("ACTOR_OCCUPIED","Living and downed combatants block their actual cells.")
				return source.navigation.step(from,to)
			var planned:Dictionary=Traversal.plan(Domain.lift(state).world,id,b.target_hex,int(actor.stamina.current),edge)
			if not planned.ok:return planned
			patches.append({"type":"actor_pool_delta","actor_id":id,"pool":"stamina","delta":-planned.cost})
			for i in range(1,planned.route.size()):patches.append({"type":"actor_move","actor_id":id,"scene_id":actor.scene_id,"hex":planned.route[i].duplicate()})
		else:
			if Effects._distance(actor.hex,b.target_hex)>1:return C.fail("OBSERVE_RANGE","Observation reaches only current/adjacent cells.")
			patches=[{"type":"flag_set","flag_id":source.observation_key(id),"value":int(state.flags[source.observation_key(id)])+1},{"type":"flag_set","flag_id":source.last_cell_key(id),"value":key}]
	# A registered safe-direct move has no failure outcome. In particular, do not
	# reject a safe last-flight-tick escape by simulating an impossible stay-hovering
	# failure branch. An unconditional branch still covers every boolean mask once.
	if kind=="move":return {"ok":true,"resolver_id":resolver_id(),"branches":[{"id":"move_success","requires":{},"patches":patches}]}
	return {"ok":true,"resolver_id":resolver_id(),"branches":[{"id":kind+"_success","requires":{kind:true},"patches":patches},{"id":kind+"_failure","requires":{kind:false},"patches":[]}]}
static func has_ref(a:Dictionary,path:String)->bool:
	for ref in a.fact_refs:
		if ref.path==path and ref.id in a.components[0].fact_ref_ids:return true
	return false
