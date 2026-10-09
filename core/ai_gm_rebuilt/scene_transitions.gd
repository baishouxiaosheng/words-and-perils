extends RefCounted
## Immutable authored doorway graph; no inferred doors, destination or teleportation.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const FIELDS := ["id","name","source_scene_id","source_hex","destination_scene_id","landing_hex","return_entrance_id","stamina_cost","enabled"]
static func validate_state(state: Dictionary) -> Dictionary:
	if not state.has("scene_transitions"): return {"ok":true}
	if not state.scene_transitions is Dictionary: return C.fail("SCENE_TRANSITIONS","场景入口必须是明确的作者配置。")
	for id in state.scene_transitions:
		var entrance: Variant = state.scene_transitions[id]
		if not id is String or id.is_empty() or not C.exact_fields(entrance,FIELDS) or entrance.id!=id or not entrance.name is String or entrance.name.is_empty() or not entrance.enabled is bool or not C.integer(entrance.stamina_cost) or entrance.stamina_cost<1 or entrance.stamina_cost>8: return C.fail("SCENE_TRANSITIONS","入口身份或消耗配置无效。")
		if not entrance.source_scene_id is String or not entrance.destination_scene_id is String or entrance.source_scene_id==entrance.destination_scene_id or not state.scenes.has(entrance.source_scene_id) or not state.scenes.has(entrance.destination_scene_id): return C.fail("SCENE_DESTINATION","入口指向尚未安装的目标场景。")
		if not Cells.valid_hex(entrance.source_hex,state,entrance.source_scene_id) or not Cells.valid_hex(entrance.landing_hex,state,entrance.destination_scene_id): return C.fail("SCENE_LANDING","入口或目标落脚点不属于声明场景。")
		if not entrance.return_entrance_id is String or not state.scene_transitions.has(entrance.return_entrance_id): return C.fail("SCENE_RETURN","入口缺少明确返回路径。")
		var back: Variant = state.scene_transitions[entrance.return_entrance_id]
		if not back is Dictionary or back.get("return_entrance_id")!=id or back.get("source_scene_id")!=entrance.destination_scene_id or back.get("destination_scene_id")!=entrance.source_scene_id or back.get("source_hex")!=entrance.landing_hex or back.get("landing_hex")!=entrance.source_hex: return C.fail("SCENE_RETURN","往返入口不匹配。")
	return {"ok":true}
static func plan(state: Dictionary, actor_id: String, entrance_id: String) -> Dictionary:
	var valid := validate_state(state)
	if not valid.ok: return valid
	if not state.actors.has(actor_id) or not state.get("scene_transitions",{}).has(entrance_id): return C.fail("SCENE_ENTRANCE","找不到已制作的场景入口。")
	var actor: Dictionary = state.actors[actor_id]; var entrance: Dictionary = state.scene_transitions[entrance_id]
	if actor.health.current<=0: return C.fail("ACTOR_INCAPACITATED","旅人已无法行动。")
	if not entrance.enabled: return C.fail("SCENE_CLOSED","入口当前未开放。")
	if actor.scene_id!=entrance.source_scene_id or actor.hex!=entrance.source_hex: return C.fail("SCENE_RANGE","必须先经评估移动到入口格，才能进入其他场景。")
	var cell := Cells.cell(state,entrance.destination_scene_id,entrance.landing_hex)
	# Scene entry always requires grounded safe landing, even during flight.
	if cell.is_empty() or cell.ground_blocked or cell.all_blocked or cell.air_blocked: return C.fail("SCENE_LANDING","目标没有已验证的安全落脚点。")
	if actor.stamina.current<entrance.stamina_cost: return C.fail("STAMINA_REQUIRED","进入场景的体力不足。")
	return {"ok":true,"entrance":entrance.duplicate(true),"cost":int(entrance.stamina_cost)}
static func apply(state: Dictionary, patch: Dictionary) -> Dictionary:
	if not C.exact_fields(patch,["type","actor_id","entrance_id","source_scene_id","source_hex","scene_id","hex"]) or not patch.actor_id is String or not patch.entrance_id is String: return C.fail("INVALID_PATCH","场景转换补丁无效。")
	var checked := plan(state,patch.actor_id,patch.entrance_id)
	if not checked.ok: return checked
	var entrance: Dictionary = checked.entrance
	if patch.source_scene_id!=entrance.source_scene_id or patch.source_hex!=entrance.source_hex or patch.scene_id!=entrance.destination_scene_id or patch.hex!=entrance.landing_hex: return C.fail("INVALID_PATCH","场景转换与冻结的作者入口不一致。")
	state.actors[patch.actor_id].scene_id=patch.scene_id
	state.actors[patch.actor_id].hex=patch.hex.duplicate()
	return {"ok":true}
static func stable(before: Dictionary, after: Dictionary) -> bool:
	return C.bytes(before.get("scene_transitions",{}))==C.bytes(after.get("scene_transitions",{}))
