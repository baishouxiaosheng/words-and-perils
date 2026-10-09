extends RefCounted
## Five existing action engines, with only a new explicit contract wrapper.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ExplorationResolver = preload("res://view/generated_v3_adventure/resolver.gd")
const ItemResolver = preload("res://view/generated_v3_inventory/resolver.gd")
var delegate: RefCounted
var kind: String
func _init(source_: RefCounted, kind_: String) -> void:
	kind = kind_
	delegate = ItemResolver.new(source_,kind) if kind in ["drop_item","pickup_item"] else ExplorationResolver.new(source_,kind)
func resolver_id() -> String: return delegate.resolver_id()
func action_schema() -> Dictionary:
	var result: Dictionary = delegate.action_schema()
	result.schema_version = "generated_v3_village_npc_actions/v1"
	result["source_profile"] = "generated_v3_village_npc/v1"
	result["static_scope"] = "selection and cell observation only; fixed buildings remove actual dry edges, road has no cost bonus; no building pickup, gate or interior effects; cooperative registered NPC topics have a separate assessed resolver"
	return result
func attempt_key(snapshot: Dictionary, assessment: Dictionary) -> String: return delegate.attempt_key(snapshot,assessment)
func attempt_fingerprint(snapshot: Dictionary, assessment: Dictionary) -> Dictionary:
	var fingerprint:Dictionary=delegate.attempt_fingerprint(snapshot,assessment)
	# Safe movement/rest are new paid turns after real committed activity,
	# even when a route or conversation cycle restores earlier numeric facts.
	# The same frozen pending action still has the same turn/fingerprint;
	# Engine action/stage tokens keep duplicate submit/roll/commit unchanged.
	if kind in ["rest","move"]:fingerprint["committed_turn"]=snapshot.turn
	return fingerprint
func check_policy(snapshot: Dictionary, assessment: Dictionary) -> Dictionary: return local_result(delegate.check_policy(snapshot,assessment))
func freeze(snapshot: Dictionary, assessment: Dictionary) -> Dictionary: return local_result(delegate.freeze(snapshot,assessment))
static func local_result(result: Dictionary) -> Dictionary:
	if result.get("ok",false): return result
	var code: String = result.get("code","")
	if code == "SETTLEMENT_OBSTRUCTION": return C.fail(code,"建筑挡住了这条通路，请沿村落保留的入口绕行。")
	if code.begins_with("PLACEMENT_"): return C.fail(code,"村落通路与地图身份不一致，未执行移动。")
	var messages := {"ITEM_DUPLICATE":"行礼包已经随身携带，不能重复拾取。","ITEM_OWNERSHIP":"只能放下自己随身携带的行礼包。","ITEM_RANGE":"行礼包不在当前场景的脚边或相邻地格。","ITEM_CAPABILITY":"这个对象没有此版本支持的物品能力。","ACTION_BINDING":"行动需要准确的旅人和物品身份。","ACTION_ACTOR":"找不到这位旅人。","ACTOR_DOWNED":"旅人目前无法行动。","ACTION_COMPONENT":"行动评估的组成或数值不符合此版本规则。","ACTION_FACT":"评估需要引用旅人与行礼包的当前公开资料。"}
	if messages.has(code): return C.fail(code,messages[code])
	if code == "GENERATED_ITEM_SCOPE": return C.fail(code,"这里只能整件放下或拾回已登记的行礼包。")
	if code == "GENERATED_ITEM_REACH": return C.fail(code,"只能拾回脚边或直接连通干地上的行礼包；建筑挡住的边不能伸手穿过。")
	return result
