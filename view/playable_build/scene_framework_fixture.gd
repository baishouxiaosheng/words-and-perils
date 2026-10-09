extends RefCounted
## Explicitly labelled framework test content, never silently installed into old saves.
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const ROOM := "scene_framework_room"
static func install(state: Dictionary) -> void:
	if state.has("scene_hexes") or state.has("scene_transitions"): return
	state.scene_hexes={ROOM:{}}
	state.scenes[ROOM]={"id":ROOM,"name":"场景切换测试室（非正式室内内容）","layer_id":"layer_framework_fixture","hex_ids":[],"renderer_id":"authored_test_room/v1","navigation_id":"authored_dry_cells/v1","bundle_id":"authored_test_room/v1"}
	for hex in [[0,0],[1,0],[0,1],[-1,1],[-1,0],[0,-1],[1,-1]]:
		var id := Cells.local_id(ROOM,hex)
		state.scene_hexes[ROOM][Cells.key(hex)]={"id":id,"q":hex[0],"r":hex[1],"scene_id":ROOM,"terrain":"floor","ground_blocked":false,"air_blocked":false,"all_blocked":false}
		state.scenes[ROOM].hex_ids.append(id)
	var entry: Array = state.actors.actor_player.hex.duplicate()
	state.scene_transitions={"entrance_framework_room":{"id":"entrance_framework_room","name":"测试室入口","source_scene_id":"scene_coast","source_hex":entry,"destination_scene_id":ROOM,"landing_hex":[0,0],"return_entrance_id":"entrance_framework_return","stamina_cost":1,"enabled":true},"entrance_framework_return":{"id":"entrance_framework_return","name":"返回海岸","source_scene_id":ROOM,"source_hex":[0,0],"destination_scene_id":"scene_coast","landing_hex":entry,"return_entrance_id":"entrance_framework_room","stamina_cost":1,"enabled":true}}
