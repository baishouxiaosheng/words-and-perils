extends RefCounted
## Immutable, source-bound encounter capabilities. Not an AI-created actor/item.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const PROFILE="generated_v3_village_enemy/v1"
const PROJECTION="generated_v3_village_enemy_context/v1"
const WORLD_PREFIX="generated_v3_village_enemy_v1_"
const ENEMY="actor_village_hostile"
const STAFF="item_coast_staff"
const BLADE="item_raider_blade"
const FACTION="village_hostile"
static func weapon(id:String,owner:String)->Dictionary:
	var blade:bool=id==BLADE
	return {"id":id,"name":"苦叶短刃" if blade else "潮岸木杖","description":"固定近战能力：相邻且干地通路连通，攻击耗费1体力。"+("命中2，擦伤1；完整命中可施加两次行动的毒，每次1点，不叠加。" if blade else "命中3，擦伤1。"),"quantity":1,"owner_actor_id":owner,"custody_revision":0,"interaction_profile":Basic.interaction("weapon"),"weapon_profile":Basic.weapon(2 if blade else 3,blade)}
static func actor(hex:Array,scene:String)->Dictionary:
	return {"id":ENEMY,"name":"持刃拦路者","hex":hex.duplicate(),"scene_id":scene,"role":"enemy","faction":FACTION,"health":{"current":5,"max":5},"stamina":{"current":6,"max":6},"inventory":[BLADE],"equipment":{"weapon":BLADE},"statuses":{},"hooks":["status_tick"],"combat_profile":Basic.combatant(["traveler"])}
static func build(identity:Dictionary,placement:Dictionary)->Dictionary:
	var result={"schema_version":"source_enemy_catalog/v1","profile_id":PROFILE,"source_hash":identity.content_hash,"geometry_hash":identity.geometry_hash,"placement_hash":identity.placement_hash,"enemy_id":ENEMY,"actor":actor(placement.hex,"scene_generated_v3"),"weapons":{STAFF:weapon(STAFF,"actor_player"),BLADE:weapon(BLADE,ENEMY)},"placement_witness":placement.duplicate(true),"occupancy":"whole enemy cell, alive or downed","range":"one exact dry village edge; stationary melee only"}
	result["catalog_hash"]=C.digest(result);return C.normalized(result)
static func validate(state:Dictionary)->Dictionary:
	var m:Variant=state.get("generated_world",{});var c:Variant=m.get("enemy_catalog",{}) if m is Dictionary else {}
	if not c is Dictionary or not C.exact_fields(c,["schema_version","profile_id","source_hash","geometry_hash","placement_hash","enemy_id","actor","weapons","placement_witness","occupancy","range","catalog_hash"]):return C.fail("ENEMY_CATALOG","遭遇目录结构无效。")
	if not c.get("placement_witness") is Dictionary or not c.placement_witness.get("hex") is Array or c.placement_witness.hex.size()!=2 or not C.integer(c.placement_witness.hex[0]) or not C.integer(c.placement_witness.hex[1]) or not c.get("actor") is Dictionary or not c.get("weapons") is Dictionary:return C.fail("ENEMY_CATALOG","遭遇目录的角色或位置结构无效。")
	var unsigned:Dictionary=c.duplicate(true);unsigned.erase("catalog_hash")
	if c.schema_version!="source_enemy_catalog/v1" or c.profile_id!=PROFILE or c.enemy_id!=ENEMY or m.get("enemy_catalog_hash")!=c.catalog_hash or C.digest(unsigned)!=c.catalog_hash:return C.fail("ENEMY_CATALOG","遭遇目录身份无效。")
	for pair in [["source_hash","content_hash"],["geometry_hash","geometry_hash"],["placement_hash","placement_hash"]]:
		if c[pair[0]]!=m.get(pair[1]):return C.fail("ENEMY_SOURCE","敌人不属于当前地图。")
	if not state.get("actors") is Dictionary or not state.get("items") is Dictionary or not state.actors.get(ENEMY) is Dictionary or not state.actors.get("actor_player") is Dictionary or not state.get("combat_turn") is Dictionary:return C.fail("ENEMY_STATE","遭遇角色或回合状态缺失。")
	for actor_id in ["actor_player",ENEMY]:
		var subject:Dictionary=state.actors[actor_id]
		if not subject.get("health") is Dictionary or not subject.get("stamina") is Dictionary or not subject.get("inventory") is Array or not subject.get("statuses") is Dictionary:return C.fail("ENEMY_STATE","遭遇角色数值结构无效。")
		for pool in ["health","stamina"]:
			if not C.exact_fields(subject[pool],["current","max"]) or not C.integer(subject[pool].current) or not C.integer(subject[pool].max) or subject[pool].current<0 or subject[pool].current>subject[pool].max:return C.fail("ENEMY_STATE","遭遇角色数值无效。")
	if C.bytes(c.actor)!=C.bytes(actor(c.placement_witness.hex,"scene_generated_v3")) or C.bytes(c.weapons)!=C.bytes({STAFF:weapon(STAFF,"actor_player"),BLADE:weapon(BLADE,ENEMY)}):return C.fail("ENEMY_CAPABILITY","遭遇能力不属于固定目录。")
	var fixed:Dictionary=state.actors[ENEMY].duplicate(true)
	fixed.health.current=c.actor.health.current;fixed.stamina.current=c.actor.stamina.current
	if C.bytes(fixed)!=C.bytes(c.actor):return C.fail("ENEMY_ACTOR","敌人是固定位置的有限近战角色，不能注入移动或能力。")
	for id in [STAFF,BLADE]:
		if C.bytes(state.items.get(id))!=C.bytes(c.weapons[id]):return C.fail("ENEMY_WEAPON","武器归属或能力不能被替换。")
	var p:Dictionary=state.actors.actor_player
	if C.bytes(p.get("equipment"))!=C.bytes({"weapon":STAFF}) or C.bytes(p.get("combat_profile"))!=C.bytes(Basic.combatant([FACTION])) or not STAFF in p.inventory:return C.fail("ENEMY_PLAYER","旅人的固定木杖能力无效。")
	for id in p.statuses:
		var s:Variant=p.statuses[id]
		if not C.exact_fields(s,["id","kind","remaining_turns","magnitude"]) or s.id!=id:return C.fail("ENEMY_STATUS","中毒状态结构无效。")
		if id!="weapon_poison" or s.kind!="poison" or not C.integer(s.remaining_turns) or int(s.remaining_turns) not in [1,2] or not C.integer(s.magnitude) or int(s.magnitude)!=1:return C.fail("ENEMY_STATUS","此遭遇只支持登记短刃造成的有限中毒。")
	return {"ok":true}
static func runtime_digest(m:Dictionary)->String:
	return C.digest({"profile":PROFILE,"profile_hash":m.get("enemy_profile_hash"),"base_runtime_hash":m.get("enemy_base_runtime_hash"),"enemy_catalog_hash":m.get("enemy_catalog_hash"),"occupancy_hash":m.get("enemy_occupancy_hash"),"enemy_melee_neighbors":m.get("enemy_melee_neighbors"),"features":m.get("features"),"vegetation_hash":m.get("vegetation_hash",""),"vegetation_catalog_hash":m.get("vegetation_catalog_hash","")})
