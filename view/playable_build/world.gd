extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const SCENE := "scene_coast"
static func catalog() -> Dictionary:
	return Bundle.document("catalog")
static func catalog_sha256() -> String:
	return Bundle.catalog_sha256()
static func bundle_id() -> String:
	return Bundle.bundle_id()
static func world(include_basic_content: bool = false) -> Dictionary:
	var data := catalog()
	if data.is_empty(): return {}
	var state := {"schema_version": World.SCHEMA, "world_id": data.world_id, "state_version": 0, "turn": 0, "actors": {}, "items": {}, "hexes": {},
		"scenes": {SCENE: {"id": SCENE, "name": "南潮海岸", "layer_id": "layer_overworld", "hex_ids": []}},
		"story_anchors": {"anchor_coast": {"id": "anchor_coast", "text": "你携果酒抵达南潮海岸。守灯人芦灯正在岸坡守望，巡岸人桐岸沿三格路线巡视。你想了解熄灭的旧灯与失踪船队。角色、故事与行动规则是手写演示；地图来自真实r24地理。旧灯就在芦灯身旁，风暴掀歪挡风罩并浸湿灯芯。先观察岸线获得线索，再走近她修复旧灯；交涉成功可得到她的协助。修灯后本段演示结束，船队去向留待尚未制作的下一段。"},
			"anchor_rules": {"id": "anchor_rules", "text": "临时演示规则：移动可沿合法干燥落脚点自动寻路到明确目标，每经过一格消耗一点体力，全路线只推进一回合；体力不足或路段接触真实湖海、新河时需另行评估，飞行状态也不自动许可跨水；观察可记下岸线线索；交涉需距芦灯一格内且献一份果酒，消耗一点体力；休息恢复最多两点体力；修灯需岸线线索、距芦灯一格内和两点体力，芦灯信任时只需一点；成功会点亮旧灯，已完成后不能重复修灯。已配置巡逻每次提交走一步。所有玩家意图仍需DecisionModel评估，目前仅人工JSON或明确署名样例。含少量水的land不整格封禁；仅相邻anchor连线接触真实水面时暂不采用步行样例。"}},
		"flags": {"coast_observed": false, "keeper_trust": false, "lamp_restored": false}, "generated_world": {"source": "natural-shared-terrain-shore-v03", "catalog_sha256": catalog_sha256(), "bundle_id": bundle_id(), "source_mesh_sha256": data.source_identity.mesh_sha256, "source_drainage_sha256": data.source_identity.drainage_sha256}}
	for row in data.cells:
		var key := "%d,%d" % [row.q, row.r]
		var id := "hex_%d_%d" % [row.q, row.r]
		state.hexes[key] = {"id": id, "q": row.q, "r": row.r, "scene_id": SCENE, "terrain": row.ecology if row.land else row.classification,
			"ground_blocked": not row.walkable, "air_blocked": false, "all_blocked": false}
		state.scenes[SCENE].hex_ids.append(id)
	state.actors.actor_player = actor("actor_player", "旅人", data.spawn.player, "player")
	state.actors.actor_keeper = actor("actor_keeper", "芦灯", data.spawn.keeper, "keeper")
	state.actors.actor_scout = actor("actor_scout", "桐岸", data.spawn.scout, "ranger")
	state.actors.actor_keeper.observed_dialogue = ["旧灯已经熄了三夜。若你愿意帮忙，先看看东面的海岸。"]
	state.actors.actor_scout.observed_dialogue = ["沿干燥岸坡走。潮水覆盖的格子暂时别去。"]
	state.actors.actor_player.hooks = ["status_tick"]
	state.actors.actor_keeper.hooks = ["status_tick"]
	state.actors.actor_scout.hooks = ["status_tick", "patrol"]
	state.environment_entities = {}
	state.actors.actor_scout.patrol = {"route": data.spawn.patrol.duplicate(true), "index": 0}
	state.actors.actor_player.inventory = ["item_wine"]
	state.items.item_wine = {"id": "item_wine", "name": "行囊果酒", "description": "随身携带的三份果酒。当前有限演示可用于和芦灯交涉；名字本身不产生其他效果。", "quantity": 3, "owner_actor_id": "actor_player"}
	preload("res://core/ai_gm_rebuilt/generic_effects.gd").install_starting_supplies(state)
	if include_basic_content:
		preload("res://view/playable_build/basic_examples.gd").install_new_game(state)
		preload("res://view/playable_build/settlement_content.gd").install_new_game(state)
		preload("res://view/playable_build/creative_content.gd").install_new_game(state)
		state.story_anchors.anchor_rules.text = "release-v1可调平衡：所有意图先取得DecisionAI、人工或明确署名离线评估，固定公式与程序决定结果；模型的必成/不可能只是建议。交涉、修理、战斗和施加状态始终掷骰。物品整份拾取/交接/装备/放下须通过所有权与距离检查。可选劫掠者遭遇不影响修灯；近战、短铳与潮光杖均需装备，远程和法术还消耗明示弹药或晶能。零生命角色不能发起行动。"
	return C.normalized(state)
static func actor(id: String, name_: String, hex: Array, role: String) -> Dictionary:
	return {"id": id, "name": name_, "hex": hex.duplicate(), "scene_id": SCENE, "role": role, "faction": "traveler" if role == "player" else "coast_watch", "health": {"current": 12, "max": 12}, "stamina": {"current": 8, "max": 8}, "inventory": [], "statuses": {}, "hooks": []}
