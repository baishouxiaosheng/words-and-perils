extends RefCounted
## Finite cooperative conversation. No provider, geometry or second transaction
## engine. Trusted Source supplies connected-neighbor range validation.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/source_npc/catalog.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const NPCFocus = preload("res://core/source_npc/focus.gd")
const PublicProjection = preload("res://core/source_npc/projection.gd")
const Numeric = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const ID := "source_npc_conversation_v1"
var _range_check: Callable
func _init(range_check: Callable = Callable()) -> void: _range_check = range_check
func resolver_id() -> String: return ID
func action_schema() -> Dictionary:
	return {"schema_version":"source_npc_actions/v1","resolver_id":ID,"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"every_intent_requires_assessment":true,"arbitrary_effects_allowed":false,"bindings":{"actor_id":"existing observing actor","target_actor_id":"registered source-bound NPC","topic_id":"exact offered topic ID"},"components":["talk"],"fixed_rule":"One cooperative topic; same scene and same or truly connected neighbor cell. Every legitimate conversation costs 1 stamina and 1 turn, no random draw. Repeats record contact but never overwrite first learned evidence.","required_fact_paths":["/actors/<actor_id>","/npc_targets/<target_actor_id>"]}
func attempt_key(_snapshot: Dictionary, assessment: Dictionary) -> String:
	return ID + ":" + C.bytes(assessment.get("bindings",{}))
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var bindings: Dictionary = assessment.get("bindings",{})
	return {"actor":snapshot.get("actors",{}).get(bindings.get("actor_id"),{}),"target":snapshot.get("actors",{}).get(bindings.get("target_actor_id"),{}),"contact":snapshot.get("npc_state",{}).get("contacts",{}).get(bindings.get("target_actor_id"),{}),"catalog_hash":snapshot.get("generated_world",{}).get("npc_catalog_hash","")}
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var checked: Dictionary = freeze(snapshot,assessment)
	return {"ok":true,"policies":{"talk":"safe_direct"}} if checked.ok else checked
func _has_ref(assessment: Dictionary, path: String, expected: Variant = null) -> bool:
	for ref in assessment.get("fact_refs",[]):
		if not ref is Dictionary or ref.get("path") != path or not ref.get("id") is String: continue
		if expected != null and C.bytes(ref.get("expected")) != C.bytes(expected): continue
		if ref.id in assessment.components[0].fact_ref_ids: return true
	return false
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var checked: Dictionary = NPCState.validate_world(snapshot)
	if not checked.ok or not snapshot.has("npc_state"): return checked if not checked.ok else C.fail("NPC_STATE","当前世界没有可交谈人物。")
	var bindings: Variant = assessment.get("bindings")
	if assessment.get("resolver_id") != ID or not C.exact_fields(bindings,["actor_id","target_actor_id","topic_id"]): return C.fail("NPC_BINDING","对话需要明确旅人、登记人物与话题。")
	for value in bindings.values():
		if not Catalog.valid_id(value): return C.fail("NPC_BINDING","对话绑定不是合法身份。")
	if not snapshot.actors.has(bindings.actor_id) or not snapshot.npc_state.learned_facts.has(bindings.actor_id) or not snapshot.generated_world.npc_catalog.entries.has(bindings.target_actor_id): return C.fail("NPC_BINDING","对话人物或学习者未登记。")
	var actor_value: Variant = snapshot.actors[bindings.actor_id]
	if not actor_value is Dictionary or actor_value.get("id") != bindings.actor_id or not actor_value.get("scene_id") is String: return C.fail("NPC_ACTOR","旅人的公开身份无效。")
	var actor: Dictionary = actor_value
	var target: Dictionary = snapshot.actors[bindings.target_actor_id]
	for pool_name in ["health","stamina"]:
		var pool: Variant = actor.get(pool_name)
		if not C.exact_fields(pool,["current","max"]) or not C.integer(pool.current) or not C.integer(pool.max) or pool.current < 0 or pool.max < pool.current: return C.fail("NPC_ACTOR","旅人的公开数值无效。")
	if actor.health.current <= 0: return C.fail("ACTOR_DOWNED","旅人目前无法交谈。")
	if actor.stamina.current < 1: return C.fail("NPC_STAMINA","交谈需要1点体力。")
	if actor.scene_id != target.scene_id or not Catalog.valid_hex(actor.get("hex")): return C.fail("NPC_RANGE","人物不在旅人的同一场景。")
	var q: int = int(actor.hex[0])-int(target.hex[0]); var r: int = int(actor.hex[1])-int(target.hex[1])
	if maxi(absi(q),maxi(absi(r),absi(q+r))) > 1 or not _range_check.is_valid(): return C.fail("NPC_RANGE","只能与脚边或实际连通的相邻人物交谈。")
	var range_result: Variant = _range_check.call(snapshot.duplicate(true),bindings.actor_id,bindings.target_actor_id)
	if range_result is Dictionary:
		if not range_result.get("ok") is bool or not range_result.ok: return C.fail("NPC_RANGE","通路未通过来源验证，不能隔着阻挡交谈。")
	elif not range_result is bool or not range_result: return C.fail("NPC_RANGE","通路未通过来源验证，不能隔着阻挡交谈。")
	var components: Variant = assessment.get("components")
	if not components is Array or components.size() != 1 or not C.exact_fields(components[0],["id","parameters","disposition","fact_ref_ids"]): return C.fail("NPC_COMPONENT","对话需要唯一talk评估。")
	var component: Dictionary = components[0]
	if component.id != "talk" or not component.parameters is Dictionary or not component.disposition in ["possible","certain","impossible"] or not component.fact_ref_ids is Array or not Numeric.validate_numeric_parameters(ID,component): return C.fail("NPC_COMPONENT","对话评估数值或组成无效。")
	if not assessment.get("fact_refs") is Array or not _has_ref(assessment,"/actors/"+bindings.actor_id): return C.fail("NPC_FACT","对话评估需要引用旅人的冻结公开资料。")
	var reference: Dictionary = NPCFocus.make_reference(bindings.target_actor_id,snapshot)
	var resolved: Dictionary = NPCFocus.resolve(reference,snapshot)
	if not resolved.ok or not _has_ref(assessment,"/npc_targets/"+bindings.target_actor_id,PublicProjection.target_summary(resolved.focus)): return C.fail("NPC_FACT","评估需要真实对话目标的冻结公开凭据。")
	if not assessment.get("action_id") is String: return C.fail("NPC_ACTION","对话缺少行动凭据。")
	var patch: Dictionary = NPCState.make_patch(snapshot,bindings.actor_id,bindings.target_actor_id,bindings.topic_id,assessment.action_id)
	if patch.is_empty(): return C.fail("NPC_TOPIC","话题不在有限目录内，或接触版本不能继续。")
	var cost: Dictionary = {"type":"actor_pool_delta","actor_id":bindings.actor_id,"pool":"stamina","delta":-1}
	return {"ok":true,"resolver_id":ID,"branches":[{"id":"npc_talk_failed","requires":{"talk":false},"patches":[cost.duplicate(true)]},{"id":"npc_talk_complete","requires":{"talk":true},"patches":[cost,patch]}]}
