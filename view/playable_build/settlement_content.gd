extends RefCounted
## Separate authored content identity: village/city-state one hex, city at most three.
## Existing source terrain/bundle and historical no-settlement saves stay unchanged.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const PATH := "res://artifacts/settlement_20261003/content_v1.json"
const SHA := "d483575a172b21f964a97e3de6c72d5e3b2d3cb73b9a4b2b255367e760a123f5"
# Public packaging redacts a provenance label only. Preserve existing save identity.
const FILE_SHA := "4813791bd31b2d5b89ba2431f0632ba5d761a54ffffc8cddc31530f79fee27b7"
const VERSION := "coast_settlement_state/v1"
static var _data: Dictionary = {}
static var _edges: Dictionary = {}
static func manifest() -> Dictionary:
	if not _data.is_empty(): return _data
	if not Bundle.ready() or FileAccess.get_sha256(PATH) != FILE_SHA: return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or value.get("schema_version")!="coast_settlement_content/v1" or value.get("bundle_id")!=Bundle.bundle_id() or value.get("source_mesh_sha256")!=Bundle.manifest().source_identity.mesh_sha256: return {}
	_data=C.normalized(value)
	return _data
static func all_settlements() -> Array:
	var data:=manifest()
	return [data]+data.get("additional_settlements",[]) if not data.is_empty() else []
static func site(id: String) -> Dictionary:
	for place in all_settlements():
		if id in [place.id,place.gate_id]: return place
		for district in place.get("districts",[]):
			if district.id==id: return place
	return {}
static func install_new_game(state: Dictionary) -> void:
	var data:=manifest()
	if data.is_empty() or state.get("generated_world",{}).get("bundle_id")!=data.bundle_id: return
	var gates: Dictionary={}
	for place in all_settlements():
		if place.walled:gates[place.gate_id]=false
	state.settlement_state={"schema_version":VERSION,"content_id":data.id,"content_sha256":SHA,"gate_states":gates,"revision":0}
static func active(state: Dictionary) -> bool:
	var data:=manifest()
	return not data.is_empty() and state.get("generated_world",{}).get("bundle_id")==data.bundle_id and valid_record(state.get("settlement_state"))
static func valid_record(value: Variant) -> bool:
	var data:=manifest()
	if data.is_empty() or not C.exact_fields(value,["schema_version","content_id","content_sha256","gate_states","revision"]) or value.schema_version!=VERSION or value.content_id!=data.id or value.content_sha256!=SHA or not value.gate_states is Dictionary or not C.integer(value.revision) or value.revision<0 or value.revision>1000000: return false
	var expected:=0;var open_count:=0
	for place in all_settlements():
		if not place.walled:continue
		expected+=1
		if not value.gate_states.get(place.gate_id) is bool:return false
		if value.gate_states[place.gate_id]:open_count+=1
	return value.gate_states.size()==expected and open_count%2==int(value.revision)%2
static func gate_open(state: Dictionary, gate_id: String = "") -> bool:
	if gate_id.is_empty(): return true
	return state.get("settlement_state",{}).get("gate_states",{}).get(gate_id,false)==true
static func validate(state: Dictionary) -> Dictionary:
	if not state.has("settlement_state"): return {"ok":true}
	if not active(state):return C.fail("SETTLEMENT_CONTENT","Settlement save does not match its authored content/source version.")
	for place in all_settlements():
		for hex in place.interior_hexes+place.road_hexes:
			if not state.get("hexes",{}).has(key(hex)):return C.fail("SETTLEMENT_CONTENT","Settlement source support is absent.")
	return {"ok":true}
static func stable(before: Dictionary,after: Dictionary) -> bool:
	if before.has("settlement_state")!=after.has("settlement_state"):return false
	if not before.has("settlement_state"):return true
	for field in ["schema_version","content_id","content_sha256"]:
		if before.settlement_state[field]!=after.settlement_state.get(field):return false
	return active(after)
static func key(hex:Array)->String:return "%d,%d"%hex
static func wall_edge(from:Array,to:Array)->Dictionary:
	if _edges.is_empty():
		for place in all_settlements():
			if not place.walled:continue
			for edge in place.wall_edges:
				var row:Dictionary=edge.duplicate(true);row.gate_id=place.gate_id;row.settlement_id=place.id
				_edges[key(edge.inside_hex)+"/"+key(edge.outside_hex)]=row
				_edges[key(edge.outside_hex)+"/"+key(edge.inside_hex)]=row
	return _edges.get(key(from)+"/"+key(to),{})
static func edge_allowed(state:Dictionary,actor:Dictionary,from:Array,to:Array,attack:=false)->bool:
	if not state.has("settlement_state") or actor.get("scene_id")!="scene_coast":return true
	if not active(state):return false
	var edge:=wall_edge(from,to)
	if edge.is_empty():return true
	if edge.is_gate and gate_open(state,edge.gate_id):return true
	if not attack:
		for status in actor.get("statuses",{}).values():
			if status.get("kind")=="flight" and status.get("remaining_turns",0)>0:return true
	return false
static func public_facts(state:Dictionary,id:String="")->Dictionary:
	if not active(state):return {}
	var data:=manifest() if id.is_empty() else site(id)
	if data.is_empty():return {}
	return {"id":data.id,"name":data.name,"site_kind":data.site_kind,"walled":data.walled,"scene_id":data.scene_id,"bundle_id":data.bundle_id,"content_sha256":SHA,"center_hex":data.center_hex,"interior_hexes":data.interior_hexes,"road_hexes":data.road_hexes,"gate_id":data.gate_id,"gate_inside_hex":data.gate_inside_hex,"gate_outside_hex":data.gate_outside_hex,"gate_open":gate_open(state,data.gate_id),"revision":state.settlement_state.revision,"districts":data.districts,"rules":data.rules}
static func descriptors()->Array:
	var result:Array=[]
	for data in all_settlements():
		var common:={"scene_id":data.scene_id,"catalog_version":"active-scene-entities/v1","bundle_id":data.bundle_id,"source":{"authored_content":data.id,"content_sha256":SHA,"source_mesh_sha256":data.source_mesh_sha256}}
		var city:Dictionary=common.duplicate(true);city.merge({"id":data.id,"kind":"settlement","name":data.name,"hex":data.center_hex,"public_facts":{"visible_form":data.site_kind,"support_hexes":data.interior_hexes,"description":data.description,"gate_id":data.gate_id,"site_kind":data.site_kind,"footprint_hex_count":data.interior_hexes.size(),"blocking_scope":"perimeter_edges_only" if data.walled else "none","flight_policy":data.rules.flight,"attack_policy":data.rules.attack}});result.append(city)
		if data.walled:
			var gate:Dictionary=common.duplicate(true);gate.merge({"id":data.gate_id,"kind":"settlement","name":data.name+" · 城门","hex":data.gate_outside_hex,"public_facts":{"visible_form":"hinged_gate","blocking_scope":"authored_gate_edge_only","support_hexes":[data.gate_inside_hex,data.gate_outside_hex],"description":"无锁手动木栅门。走到门内或门外落脚点后评估启闭；每次1体力、1行动。","gate_id":data.gate_id,"site_kind":data.site_kind,"flight_policy":data.rules.flight,"attack_policy":data.rules.attack}});result.append(gate)
		for district in data.districts:
			var area:Dictionary=common.duplicate(true);area.merge({"id":district.id,"kind":"district","name":data.name+" · "+district.name,"hex":district.support_hexes[0],"public_facts":{"visible_form":"architectural_district","blocking_scope":"none_architectural_attention_only","support_hexes":district.support_hexes,"description":"建筑风格分区；选择只显示已编写事实，不会进入房间、获得物品或触发经济。","settlement_id":data.id,"architectural_kit":district.architectural_kit,"gate_id":data.gate_id}});result.append(area)
	return result
static func entity_state(state:Dictionary,id:String="")->Dictionary:
	if not active(state):return {}
	var place:=manifest() if id.is_empty() else site(id)
	if place.is_empty():return {}
	if id.begins_with("district:"):return {"posture":"fixed","revision":state.settlement_state.revision,"ground_blocking":false}
	return {"posture":("open" if gate_open(state,place.gate_id) else "closed") if place.walled else "fixed","revision":state.settlement_state.revision,"ground_blocking":place.walled and not gate_open(state,place.gate_id)}
static func valid_entity_state(value:Variant)->bool:
	return C.exact_fields(value,["posture","revision","ground_blocking"]) and value.posture in ["open","closed","fixed"] and C.integer(value.revision) and value.revision>=0 and value.revision<=1000000 and value.ground_blocking is bool and value.ground_blocking==(value.posture=="closed")
static func apply_gate(state:Dictionary,patch:Dictionary)->Dictionary:
	if not C.exact_fields(patch,["type","gate_id","expected_revision","gate_open"]) or not active(state) or not state.settlement_state.gate_states.has(patch.gate_id) or not patch.gate_open is bool or not C.integer(patch.expected_revision) or patch.expected_revision!=state.settlement_state.revision or patch.gate_open==gate_open(state,patch.gate_id) or state.settlement_state.revision>=1000000:return C.fail("GATE_PATCH","Invalid or stale typed gate change.")
	state.settlement_state.gate_states[patch.gate_id]=patch.gate_open;state.settlement_state.revision+=1
	return {"ok":true}
