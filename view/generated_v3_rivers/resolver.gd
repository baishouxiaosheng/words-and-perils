extends RefCounted
## V3 action wrapper: unchanged move/observe/rest semantics, new closed identity.
## Source admission and Navigation use only the actual emitted V3 triangles.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
var kind := "observe"
var source: RefCounted
func _init(source_: RefCounted,kind_: String) -> void: source=source_;kind=kind_
func resolver_id() -> String:return "generated_v3_rivers_"+kind+"_v1"
func action_schema() -> Dictionary:
	return {"schema_version":"generated_v3_rivers_actions/v1","resolver_id":resolver_id(),"components":[kind],"bindings":{"actor_id":"actor_player","target_hex":"explicit public [q,r]"} if kind in ["move","observe"] else {"actor_id":"actor_player"},"numeric_assessment":{"A":[0,4],"D":[0,4],"P":[-2,2]},"required_fact_paths":["/actors/actor_player","/hexes/<q,r>"] if kind in ["move","observe"] else ["/actors/actor_player"],"terrain_costs":Policy.COSTS,"traversal_policy":Policy.ID,"terrain_mapping_id":"generated_v3_biome_terrain/v1","biome_terrain":{"ocean":"ocean","grassland":"grass","dry_steppe":"grass","desert":"arid","temperate_forest":"forest","jungle":"jungle","alpine":"mountain","wetland":"swamp"},"water_policy":"actual emitted ground and sea/river water triangles, with 0.38 plinth clearance; wet center anchors blocked temporarily, remaining cell land is not inherently impassable; no bank anchors/crossing/bridge/flight capability","plateau_policy":"exact source descriptor; no hidden cost surcharge","every_intent_requires_assessment":true,"arbitrary_patches":false}
func attempt_key(_snapshot: Dictionary,assessment: Dictionary) -> String:return resolver_id()+":"+C.bytes(assessment.bindings)
func attempt_fingerprint(snapshot: Dictionary,_assessment: Dictionary) -> Dictionary:
	return {"actor":snapshot.actors.actor_player,"source":snapshot.generated_world,"observations":snapshot.flags}
func check_policy(snapshot: Dictionary,assessment: Dictionary) -> Dictionary:
	var checked:=freeze(snapshot,assessment)
	return {"ok":true,"policies":{kind:"safe_direct"}} if checked.ok else checked
func freeze(snapshot: Dictionary,assessment: Dictionary) -> Dictionary:
	var checked: Dictionary=source.validate_state(snapshot)
	if not checked.ok:return checked
	var expected: Array=["actor_id","target_hex"] if kind in ["move","observe"] else ["actor_id"]
	var b: Dictionary=assessment.bindings
	if not kind in ["move","observe","rest"] or not C.exact_fields(b,expected) or b.actor_id!="actor_player" or assessment.components.size()!=1 or assessment.components[0].id!=kind:return C.fail("V3_BINDING","行动类型或目标不属于此探索版本。")
	var actor: Dictionary=snapshot.actors.actor_player
	if actor.health.current<=0:return C.fail("ACTOR_DOWNED","旅人目前无法行动。")
	if not has_ref(assessment,"/actors/actor_player"):return C.fail("V3_FACT","评估需要引用这位旅人的当前资料。")
	var patches: Array=[]
	if kind in ["move","observe"]:
		if not b.target_hex is Array or b.target_hex.size()!=2 or not C.integer(b.target_hex[0]) or not C.integer(b.target_hex[1]):return C.fail("V3_TARGET","请选择此地图上的明确坐标。")
		var key: String="%d,%d"%b.target_hex
		if not snapshot.hexes.has(key) or not has_ref(assessment,"/hexes/"+key):return C.fail("V3_FACT","评估需要引用公开资料中的明确目标地格。")
		if kind=="move":
			var planned: Dictionary=source.navigation.plan(snapshot,b.target_hex,int(actor.stamina.current))
			if not planned.ok:return planned
			patches.append({"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":-planned.cost})
			for i in range(1,planned.route.size()):patches.append({"type":"actor_move","actor_id":"actor_player","scene_id":actor.scene_id,"hex":planned.route[i].duplicate()})
		else:
			var dq: int=b.target_hex[0]-actor.hex[0];var dr: int=b.target_hex[1]-actor.hex[1]
			if maxi(absi(dq),maxi(absi(dr),absi(dq+dr)))>1:return C.fail("V3_OBSERVE_RANGE","只能观察当前位置或相邻地格。")
			patches=[{"type":"flag_set","flag_id":"observations","value":int(snapshot.flags.observations)+1},{"type":"flag_set","flag_id":"last_observed_cell","value":key}]
	else:
		var gain:=mini(2,int(actor.stamina.max)-int(actor.stamina.current))
		if gain<=0:return C.fail("V3_REST_FULL","体力已满，无需休息；未消耗回合。")
		patches=[{"type":"actor_pool_delta","actor_id":"actor_player","pool":"stamina","delta":gain}]
	return {"ok":true,"resolver_id":resolver_id(),"branches":[{"id":kind+"_success","requires":{kind:true},"patches":patches},{"id":kind+"_failure","requires":{kind:false},"patches":[]}]}
static func has_ref(assessment: Dictionary,path: String) -> bool:
	for ref in assessment.fact_refs:
		if ref.path==path and ref.id in assessment.components[0].fact_ref_ids:return true
	return false
