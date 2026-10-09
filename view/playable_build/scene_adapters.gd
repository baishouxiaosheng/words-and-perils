extends RefCounted
## Closed renderer/navigation registry. Source coast and authored room never share water queries.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const ROOM_ID := "authored_test_room/v1"
static func descriptor(state: Dictionary, scene_id: String) -> Dictionary:
	if not state.scenes.has(scene_id): return C.fail("SCENE_ADAPTER","目标场景尚未制作。")
	var scene: Dictionary = state.scenes[scene_id]
	if scene_id=="scene_coast":
		if not Bundle.ready() or state.get("generated_world",{}).get("bundle_id","")!=Bundle.bundle_id() or scene.get("bundle_id",Bundle.bundle_id())!=Bundle.bundle_id(): return C.fail("BUNDLE_MISMATCH","海岸场景与当前地理版本不一致。")
		if scene.get("renderer_id","source_coast/v1")!="source_coast/v1" or scene.get("navigation_id","source_coast_dry/v1")!="source_coast_dry/v1": return C.fail("SCENE_ADAPTER","海岸场景适配器未注册。")
		return {"ok":true,"scene_id":scene_id,"renderer_id":"source_coast/v1","navigation_id":"source_coast_dry/v1","script_path":"res://view/playable_build/board.gd","bundle_id":Bundle.bundle_id(),"framework_fixture":false}
	if scene.get("renderer_id")==ROOM_ID and scene.get("navigation_id")=="authored_dry_cells/v1" and scene.get("bundle_id")==ROOM_ID and state.get("scene_hexes",{}).has(scene_id):
		return {"ok":true,"scene_id":scene_id,"renderer_id":ROOM_ID,"navigation_id":"authored_dry_cells/v1","script_path":"res://view/playable_build/scene_test_board.gd","bundle_id":ROOM_ID,"framework_fixture":true}
	return C.fail("SCENE_ADAPTER","目标场景没有已注册的显示与导航适配器。")
static func authored_step(state: Dictionary, scene_id: String, from: Array, to: Array) -> Dictionary:
	var registered := descriptor(state,scene_id)
	if not registered.ok: return registered
	if registered.navigation_id!="authored_dry_cells/v1": return C.fail("SCENE_ADAPTER","不能将室内干地查询用于海岸。")
	var a := Cells.cell(state,scene_id,from); var b := Cells.cell(state,scene_id,to)
	if a.is_empty() or b.is_empty(): return C.fail("NO_DRY_SUPPORT","目标不在当前场景的已制作格内。")
	if a.terrain in ["ocean","main_lake","water","river"] or b.terrain in ["ocean","main_lake","water","river"]: return C.fail("CROSS_WATER_ASSESSMENT","此适配器没有制作水上移动能力。")
	var dq: int = int(to[0])-int(from[0]); var dr: int = int(to[1])-int(from[1])
	return {"ok":true} if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))==1 else C.fail("NOT_ADJACENT","场景移动必须逐格。")
static func projection(state: Dictionary, scene_id: String) -> Dictionary:
	var result := state.duplicate(true)
	result.hexes=Cells.cells(state,scene_id).duplicate(true)
	result.actors={}; result.items={}
	for id in state.actors:
		if state.actors[id].scene_id==scene_id: result.actors[id]=state.actors[id].duplicate(true)
	for id in state.items:
		if state.items[id].get("scene_id")==scene_id or result.actors.has(state.items[id].get("owner_actor_id","")): result.items[id]=state.items[id].duplicate(true)
	# Rendering a declared tiny room must not sample the outer world's generator.
	if scene_id!="scene_coast":
		result.generated_world={}
		result.board_radius=1
	return result
