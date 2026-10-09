extends RefCounted
## Authored functional fixture, not generated model judgment or a fixed game theme.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
static func world() -> Dictionary:
	var state := {"schema_version": World.SCHEMA, "world_id": "test_harbor_story", "state_version": 0, "turn": 0, "actors": {}, "items": {}, "hexes": {},
		"scenes": {"scene_harbor": {"id": "scene_harbor", "name": "暮潮渡口", "layer_id": "layer_overworld", "hex_ids": []}},
		"story_anchors": {"anchor_passage": {"id": "anchor_passage", "text": "渡船即将出发。旅人想与码头守卫谈妥通行条件；NPC回应用于框架功能测试。"}},
		"flags": {"gate_open": false, "npc_listened": false, "private_quest_answer": "The lighthouse keeper holds the spare key."}, "generated_world": {}}
	for q in range(-2, 3):
		for r in range(-2, 3):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) > 2: continue
			var id := "hex_%d_%d" % [q, r]
			state.hexes["%d,%d" % [q, r]] = {"id": id, "q": q, "r": r, "scene_id": "scene_harbor", "terrain": "plain", "ground_blocked": false, "air_blocked": false, "all_blocked": false}
			state.scenes.scene_harbor.hex_ids.append(id)
	state.actors.actor_player = actor("actor_player", "旅人", [-1, 0], "player")
	state.actors.actor_guard_z = actor("actor_guard_z", "桐岸", [0, 1], "soldier")
	state.actors.actor_guard_a = actor("actor_guard_a", "芦灯", [0, 0], "soldier")
	state.actors.actor_player.inventory = ["item_wine"]
	state.actors.actor_guard_a.observed_dialogue = ["潮水转向前，请说明你的来意。"]
	state.actors.actor_guard_z.observed_dialogue = ["她说了算，我负责巡查。"]
	state.actors.actor_guard_a.secrets = {"gate_password": "low_tide", "hidden_motive": "Protect the keeper's missing child."}
	state.actors.actor_guard_a.private_notes = "This unknown extension must never appear in a ModelView."
	state.items.item_wine = {"id": "item_wine", "name": "小桶果酒", "description": "准备带上渡船的一桶果酒。实际位置与数量决定是否可用于交涉。", "quantity": 3, "hex": [-1, 0], "scene_id": "scene_harbor"}
	return C.normalized(state)
static func actor(id: String, name: String, hex: Array, role: String) -> Dictionary:
	return {"id": id, "name": name, "hex": hex, "scene_id": "scene_harbor", "role": role, "faction": "traveler" if role == "player" else "harbor_watch", "health": {"current": 12, "max": 12}, "stamina": {"current": 8, "max": 8}, "inventory": [], "statuses": {}, "hooks": []}
static func assessment(request: Dictionary, resolver_id: String = "fixture_gate", dispositions: Array = ["possible", "possible"]) -> Dictionary:
	var facts: Dictionary = request.context.facts
	var refs := [{"id": "wine_quantity", "path": "/items/item_wine/quantity", "expected": facts.items.item_wine.quantity},
		{"id": "wine_location", "path": "/items/item_wine/hex", "expected": facts.items.item_wine.hex},
		{"id": "guards", "path": "/actors/actor_guard_a/health/current", "expected": facts.actors.actor_guard_a.health.current},
		{"id": "player_location", "path": "/actors/actor_player/hex", "expected": facts.actors.actor_player.hex}]
	var components := [{"id": "offer", "parameters": {"A": 2, "D": 2, "P": 0}, "disposition": dispositions[0], "fact_ref_ids": ["wine_quantity", "wine_location", "player_location"]},
		{"id": "talk", "parameters": {"A": 3, "D": 1, "P": 1}, "disposition": dispositions[1], "fact_ref_ids": ["guards"]}]
	if resolver_id != "fixture_gate": components = [components[0]]
	return {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash,
		"narration": "你准备拿出果酒，再向守卫解释渡河的理由；结果尚未发生。", "interpretation": "Functional test assessment: offer wine and speak to the named guard.", "resolver_id": resolver_id,
		"bindings": {"actor_id": "actor_player", "wine_item_id": "item_wine", "target_actor_id": "actor_guard_a"}, "components": components, "fact_refs": refs,
		"provenance": {"provider": "authored_functional_fixture", "live": false, "kind": "fixture"}}
