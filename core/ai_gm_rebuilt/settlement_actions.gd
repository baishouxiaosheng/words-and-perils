extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Content = preload("res://view/playable_build/settlement_content.gd")
const Generic = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const ID := "coast_gate_operation_v1"
func resolver_id() -> String: return ID
func action_schema() -> Dictionary:
	return {"schema_version":"coast_gate/v1","resolver_id":ID,"bindings":{"actor_id":"actor_player","gate_id":"existing authored settlement gate","operation":"open or close"},"components":["operate"],"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/settlements/<settlement_id>"],"every_intent_requires_assessment":true,"authority":"Only the exact unlocked authored gate, from its inside/outside anchor. Trusted safe direct after assessment. One stamina, one action, one hook tick. No lockpicking, new gate, teleport, model-authored effects or arbitrary structure destruction.","obstruction":"Ground-only edge walls; active flight clears them but never water. Attacks use explicitly binary edge line-of-sight, not ballistic height/cover."}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String: return "gate:"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary, _assessment: Dictionary) -> Dictionary:
	return {"actor":snapshot.actors.actor_player,"settlement":snapshot.get("settlement_state",{})}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var frozen:=freeze(snapshot,assessment)
	return {"ok":true,"policies":{"operate":"safe_direct"}} if frozen.ok else frozen
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var b: Dictionary=assessment.bindings
	if not C.exact_fields(b,["actor_id","gate_id","operation"]) or b.actor_id!="actor_player" or not b.operation in ["open","close"] or not Content.active(snapshot) or not snapshot.settlement_state.gate_states.has(b.gate_id): return C.fail("GATE_BINDING","Operation must bind the installed authored gate and traveler.")
	if assessment.components.size()!=1 or assessment.components[0].id!="operate" or not Generic.validate_numeric_parameters(ID,assessment.components[0]): return C.fail("GATE_COMPONENT","Gate requires one bounded operate assessment.")
	if not Generic._has_ref(assessment,"/actors/actor_player") or not Generic._has_ref(assessment,"/settlements/"+Content.site(b.gate_id).id): return C.fail("GATE_FACT","Cite the public traveler and current authored settlement/gate facts.")
	var actor: Dictionary=snapshot.actors.actor_player; var data:=Content.site(b.gate_id)
	if actor.scene_id!=data.scene_id or not actor.hex in [data.gate_inside_hex,data.gate_outside_hex]: return C.fail("GATE_RANGE","Walk to the authored gate's inside or outside anchor before operating it.")
	if actor.health.current<=0 or actor.stamina.current<1: return C.fail("GATE_RESOURCE","A living traveler needs one stamina to operate the gate.")
	var open_:bool=b.operation=="open"
	if Content.gate_open(snapshot,b.gate_id)==open_: return C.fail("GATE_UNCHANGED","The gate is already in the requested state; no cost or turn.")
	var patches: Array=[{"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-1},{"type":"settlement_gate_set","gate_id":data.gate_id,"expected_revision":snapshot.settlement_state.revision,"gate_open":open_}]
	return {"ok":true,"resolver_id":ID,"branches":[{"id":"gate_operated","requires":{"operate":true},"patches":patches},{"id":"gate_unmodified","requires":{"operate":false},"patches":[]}]}
