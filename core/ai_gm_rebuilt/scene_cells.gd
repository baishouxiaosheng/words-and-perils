extends RefCounted
## Backward-compatible scene-local cell namespace. Legacy state.hexes is untouched.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
static func key(hex: Array) -> String: return "%d,%d" % [hex[0],hex[1]]
static func cells(state: Dictionary, scene_id: String) -> Dictionary:
	if state.get("scene_hexes", {}).has(scene_id): return state.scene_hexes[scene_id]
	var result: Dictionary = {}
	for cell_key in state.get("hexes", {}):
		if state.hexes[cell_key].get("scene_id", "") == scene_id: result[cell_key] = state.hexes[cell_key]
	return result
static func cell(state: Dictionary, scene_id: String, hex: Array) -> Dictionary:
	if state.get("scene_hexes", {}).has(scene_id): return state.scene_hexes[scene_id].get(key(hex),{})
	var found: Dictionary = state.get("hexes",{}).get(key(hex),{})
	return found if found.get("scene_id","") == scene_id else {}
static func valid_hex(value: Variant, state: Dictionary, scene_id: String) -> bool:
	return value is Array and value.size()==2 and C.integer(value[0]) and C.integer(value[1]) and abs(value[0])<=1000 and abs(value[1])<=1000 and not cell(state,scene_id,value).is_empty()
static func id(state: Dictionary, scene_id: String, hex: Array) -> String: return cell(state,scene_id,hex).get("id","")
static func local_id(scene_id: String, hex: Array) -> String: return "%s:hex_%d_%d" % [scene_id,hex[0],hex[1]]
