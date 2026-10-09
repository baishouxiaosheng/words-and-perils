extends RefCounted
## Small honest action family: no coast IDs, object effects or raw model patches.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
var kind := "observe"
var source: RefCounted
func _init(source_: RefCounted,kind_: String) -> void: source=source_;kind=kind_
func resolver_id() -> String:return "generated_"+kind+"_v1"
func action_schema() -> Dictionary:
	return {"schema_version":"generated_actions/v1","resolver_id":resolver_id(),"components":[kind],"bindings":{"actor_id":"actor_player","target_hex":"explicit public [q,r]"} if kind in ["move","observe"] else {"actor_id":"actor_player"},"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/hexes/<q,r>"] if kind in ["move","observe"] else ["/actors/actor_player"],"terrain_costs":Policy.COSTS,"traversal_policy":Policy.ID,"water_policy":"verified source dry edges only; bridges and flight do not grant crossing","plateau_policy":"independent descriptive landform; cost follows explicit terrain class","every_intent_requires_assessment":true,"arbitrary_patches":false}
func attempt_key(_snapshot: Dictionary,assessment: Dictionary) -> String:return resolver_id()+":"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary,_assessment: Dictionary) -> Dictionary:
	return {"actor":snapshot.actors.actor_player,"source":snapshot.generated_world,"observations":snapshot.flags}
func check_policy(snapshot: Dictionary,assessment: Dictionary) -> Dictionary:
	var checked:=freeze(snapshot,assessment)
	return {"ok":true,"policies":{kind:"safe_direct"}} if checked.ok else checked
func freeze(snapshot: Dictionary,assessment: Dictionary) -> Dictionary:
	var checked: Dictionary=source.validate_state(snapshot)
	if not checked.ok:return checked
	var expected: Array=["actor_id","target_hex"] if kind in ["move","observe"] else ["actor_id"]
	var b: Dictionary=assessment.bindings
	if not kind in ["move","observe","rest"] or not C.exact_fields(b,expected) or b.actor_id!="actor_player" or assessment.components.size()!=1 or assessment.components[0].id!=kind:return C.fail("GENERATED_BINDING","Unknown generated action or unsupported binding/component.")
	var actor: Dictionary=snapshot.actors.actor_player
	if actor.health.current<=0:return C.fail("ACTOR_DOWNED","The traveler cannot initiate an action.")
	if not has_ref(assessment,"/actors/actor_player"):return C.fail("GENERATED_FACT","The exact acting actor must be cited.")
	var patches: Array=[]
	if kind in ["move","observe"]:
		if not b.target_hex is Array or b.target_hex.size()!=2 or not C.integer(b.target_hex[0]) or not C.integer(b.target_hex[1]):return C.fail("GENERATED_TARGET","An explicit current-map coordinate is required.")
		var key: String="%d,%d"%b.target_hex
		if not snapshot.hexes.has(key) or not has_ref(assessment,"/hexes/"+key):return C.fail("GENERATED_FACT","The target must be a cited public cell, never an inferred hidden target.")
		if kind=="move":
			var planned: Dictionary=source.navigation.plan(snapshot,b.target_hex,int(actor.stamina.current))
			if not planned.ok:return planned
			patches.append({"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-planned.cost})
			for i in range(1,planned.route.size()):patches.append({"type":"actor_move","actor_id":"actor_player","scene_id":actor.scene_id,"hex":planned.route[i].duplicate()})
		else:
			var dq: int=b.target_hex[0]-actor.hex[0];var dr: int=b.target_hex[1]-actor.hex[1]
			if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))>1:return C.fail("GENERATED_OBSERVE_RANGE","Observation currently supports the present or adjacent cell only.")
			patches=[{"type":"flag_set","flag_id":"observations","value":int(snapshot.flags.observations)+1},{"type":"flag_set","flag_id":"last_observed_cell","value":key}]
	else:
		var gain:=mini(2,int(actor.stamina.max)-int(actor.stamina.current))
		if gain<=0:return C.fail("GENERATED_REST_FULL","Stamina is already full; no turn or RNG was consumed.")
		patches=[{"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":gain}]
	return {"ok":true,"resolver_id":resolver_id(),"branches":[{"id":kind+"_success","requires":{kind:true},"patches":patches},{"id":kind+"_failure","requires":{kind:false},"patches":[]}]}
static func has_ref(assessment: Dictionary,path: String) -> bool:
	for ref in assessment.fact_refs:
		if ref.path==path and ref.id in assessment.components[0].fact_ref_ids:return true
	return false
