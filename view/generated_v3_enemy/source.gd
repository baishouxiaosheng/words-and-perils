extends RefCounted
## New immutable profile over accepted village/NPC authority; old profiles stay byte-exact.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Base=preload("res://view/generated_v3_npc/source.gd")
const Catalog=preload("res://core/source_enemy/catalog.gd")
const World=preload("res://core/ai_gm_rebuilt/world.gd")
const Basic=preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const NPCState=preload("res://core/source_npc/state.gd")
const Placement=preload("res://view/generated_v3_enemy/placement.gd")
const Navigation=preload("res://view/generated_v3_enemy/navigation.gd")
const Policy=preload("res://view/generated_v3_enemy/policy.gd")
const Vegetation=preload("res://core/generated_v3_vegetation/planner.gd")
const VegetationCatalog=preload("res://core/generated_v3_vegetation/catalog.gd")
const History=preload("res://view/generated_v3_enemy/history.gd")
const PROFILE=Catalog.PROFILE
const PROJECTION_ID=Catalog.PROJECTION
const WORLD_PREFIX=Catalog.WORLD_PREFIX
const RENDERER_PROFILE=Base.RENDERER_PROFILE
const SCENE=Base.SCENE
const ITEM=Base.ITEM
const TOPIC=Base.TOPIC
var data:Dictionary={}
var world:Dictionary={}
var identity:Dictionary={}
var renderer_bundle:Dictionary={}
var placement_result:Dictionary={}
var npc_placement_result:Dictionary={}
var enemy_placement_result:Dictionary={}
var npc_reservations:Array=[]
var vegetation_result:Dictionary={}
var features:Dictionary={"vegetation":false}
var spawn_component:Dictionary={}
var navigation:RefCounted
var base_navigation:RefCounted
var base_source:RefCounted
var npc_id=""
var enemy_id=Catalog.ENEMY
var _fixed:Dictionary={}
# Reproduced from the registered engine, never imported from a save/model.
var enemy_request_contract:Dictionary={}
var enemy_capacity_metrics:Dictionary={}
func admit(value:Variant,renderer_profile:String=RENDERER_PROFILE,persisted_manifest:Variant=null,options:Dictionary={"vegetation":false},persisted_vegetation:Variant=null,persisted_enemy:Variant=null)->Dictionary:
	if not C.exact_fields(options,["vegetation"]) or not options.vegetation is bool or (not options.vegetation and persisted_vegetation!=null):return C.fail("ENEMY_FEATURES","遭遇设置无效，旧旅程不会改写。")
	var base:=Base.new();var checked:Dictionary=base.admit(value,renderer_profile,persisted_manifest,{"vegetation":false})
	if not checked.ok:return checked
	var placed:Dictionary=Placement.build(base,enemy_id)
	if not placed.ok:return placed
	if persisted_enemy!=null and C.bytes(persisted_enemy)!=C.bytes(placed.placement_witness):return C.fail("ENEMY_PLACEMENT","敌人位置或完整干地支撑与原来源不一致。")
	var nav:=Navigation.new(base.navigation,placed.placement_witness.hex)
	var combined:Dictionary=base.identity.duplicate(true)
	combined.profile=PROFILE;combined.projection_id=PROJECTION_ID;combined.features=options.duplicate(true)
	combined["enemy_profile"]=PROFILE;combined["enemy_profile_hash"]=profile_digest();combined["enemy_base_runtime_hash"]=base.identity.runtime_hash
	combined["enemy_catalog"]=Catalog.build(base.identity,placed.placement_witness);combined["enemy_catalog_hash"]=combined.enemy_catalog.catalog_hash
	combined["enemy_melee_neighbors"]=base.navigation.allowed["%d,%d"%placed.placement_witness.hex].duplicate()
	combined["enemy_occupancy_hash"]=C.digest({"schema_version":"enemy_occupancy/v1","enemy_hex":placed.placement_witness.hex,"remaining_graph":nav.allowed})
	combined.runtime_hash=Catalog.runtime_digest(combined)
	var reservations:Array=base.npc_reservations.duplicate(true);reservations.append_array(placed.reservations)
	var plants:Dictionary={}
	if options.vegetation:
		plants=Vegetation.build(base.data,base.renderer_bundle,base.navigation,base.placement_result,base.world.actors.actor_player.hex,reservations) if persisted_vegetation==null else Vegetation.validate(persisted_vegetation,base.data,base.renderer_bundle,base.navigation,base.placement_result,base.world.actors.actor_player.hex,reservations)
		if not plants.ok:return plants
		var veg:Dictionary=VegetationCatalog.build(PROFILE,combined,plants.manifest,plants.assets.catalog)
		if not veg.ok:return veg
		combined["vegetation_base_runtime_hash"]=combined.runtime_hash;combined["vegetation_profile"]=VegetationCatalog.PROFILE;combined["vegetation_hash"]=plants.manifest.vegetation_hash;combined["vegetation_entity_catalog"]=veg.catalog;combined["vegetation_catalog_hash"]=veg.catalog.catalog_hash
		combined.runtime_hash=Catalog.runtime_digest(combined)
	var candidate:Dictionary=base.world.duplicate(true)
	candidate.world_id=WORLD_PREFIX+C.digest({"source":base.data.content_hash,"features":options});candidate.generated_world=C.normalized(combined)
	candidate.actors[enemy_id]=combined.enemy_catalog.actor.duplicate(true)
	for id in combined.enemy_catalog.weapons:candidate.items[id]=combined.enemy_catalog.weapons[id].duplicate(true)
	candidate.actors.actor_player.inventory.append(Catalog.STAFF);candidate.actors.actor_player["equipment"]={"weapon":Catalog.STAFF};candidate.actors.actor_player["combat_profile"]=Basic.combatant([Catalog.FACTION])
	candidate["combat_turn"]={"schema_version":"coast_encounter_turn/v1","phase":"player","enemy_actor_id":enemy_id,"round":0}
	candidate.story_anchors.anchor_generated_v3_scope.text="旅人可以沿干地探索、观察、休息，放下或拾回行礼包，并向守路村民问路。持刃拦路者固定守住一格；活着或倒下均占据该格。双方各自描述意图并经评估后才能近战，须相邻且真实干地边连通，每次耗费1体力。你携带木杖；敌人短刃完整命中可能施毒。中毒在后续每次已提交行动结算，敌方行动也计入。无巡逻、交易、额外敌人、远程或法术。点击与查看不消耗回合。"
	checked=World.validate(candidate)
	if not checked.ok:return checked
	data=base.data;world=C.normalized(candidate);identity=C.normalized(combined);renderer_bundle=base.renderer_bundle
	placement_result=base.placement_result;npc_placement_result=base.npc_placement_result;enemy_placement_result=placed;npc_reservations=reservations
	base_source=base;base_navigation=base.navigation;navigation=nav;spawn_component=base.spawn_component.duplicate(true);spawn_component.erase("%d,%d"%placed.placement_witness.hex)
	npc_id=base.npc_id;vegetation_result=plants;features=options.duplicate(true);_fixed=fixed_fields(world)
	checked=validate_state(world)
	return {"ok":true,"identity":identity.duplicate(true),"enemy_id":enemy_id,"start":world.actors.actor_player.hex.duplicate(),"component_size":spawn_component.size()} if checked.ok else checked
static func profile_digest()->String:
	var pins:Dictionary={}
	for name_ in ["source","adapter","resolver","rule","assessments","projection","placement","navigation","policy","history","response_budget"]:
		var path="res://view/generated_v3_enemy/"+name_+".gd";pins[path]=FileAccess.get_sha256(path)
	pins["res://core/source_enemy/catalog.gd"]=FileAccess.get_sha256("res://core/source_enemy/catalog.gd")
	return C.digest(pins)
static func fixed_fields(state:Dictionary)->Dictionary:
	var result:Dictionary=state.duplicate(true)
	for field in ["state_version","turn","flags","npc_state","combat_turn"]:result.erase(field)
	for id in ["actor_player",Catalog.ENEMY]:
		if not result.actors.has(id):continue
		var a:Dictionary=result.actors[id];a.health.erase("current");a.stamina.erase("current")
		if id=="actor_player":a.erase("hex");a.erase("inventory");a.erase("statuses")
	for field in ["owner_actor_id","hex","scene_id","custody_revision"]:result.items[ITEM].erase(field)
	return C.normalized(result)
func validate_state(state:Variant)->Dictionary:
	if base_source==null:return C.fail("ENEMY_SOURCE","请先开启村庄冒险。")
	var checked:Dictionary=World.validate(state)
	if not checked.ok:return checked
	if not C.exact_fields(state,world.keys()) or not C.exact_fields(state.actors,world.actors.keys()) or not C.exact_fields(state.items,world.items.keys()) or C.bytes(fixed_fields(state))!=C.bytes(_fixed):return C.fail("ENEMY_IDENTITY","遭遇来源、能力或固定位置与登记世界不一致。")
	checked=Catalog.validate(state)
	if not checked.ok:return checked
	checked=NPCState.validate_committed(state)
	if not checked.ok:return checked
	if features.vegetation:
		checked=VegetationCatalog.validate_world(state)
		if not checked.ok:return checked
	if Policy.occupied(state,state.actors.actor_player.hex,"actor_player"):return C.fail("ENEMY_OCCUPIED","敌人即使倒下仍占据此格，不能穿过。")
	if state.combat_turn.phase=="enemy" and not Policy.can_attack(state,enemy_id,"actor_player",base_navigation):return C.fail("ENEMY_PHASE","不能安排无法执行的敌方回合。")
	if state.combat_turn.enemy_actor_id!=enemy_id or state.combat_turn.round>state.turn:return C.fail("ENEMY_PHASE","遭遇回合身份无效。")
	var shadow:Dictionary=state.duplicate(true)
	shadow.world_id=base_source.world.world_id;shadow.generated_world=base_source.world.generated_world.duplicate(true);shadow.story_anchors=base_source.world.story_anchors.duplicate(true)
	shadow.actors.erase(enemy_id);shadow.items.erase(Catalog.STAFF);shadow.items.erase(Catalog.BLADE);shadow.erase("combat_turn")
	var player:Dictionary=shadow.actors.actor_player;player.inventory.erase(Catalog.STAFF);player.erase("equipment");player.erase("combat_profile");player.health=base_source.world.actors.actor_player.health.duplicate(true);player.statuses={}
	return base_source.validate_state(shadow)
func validate_history(engine_data:Dictionary)->Dictionary:return History.validate(self,engine_data)
func talk_range(state:Dictionary,actor_id:String,target_id:String)->bool:return base_source.talk_range(state,actor_id,target_id)
func static_reference(id:String,clicked_hex:Array=[])->Dictionary:return Base.VillageSource.StaticFocus.make_reference(id,world,clicked_hex)
func npc_reference(state:Dictionary)->Dictionary:return base_source.npc_reference(state)
func vegetation_reference(id:String,state:Dictionary)->Dictionary:return Base.VegetationFocus.make_reference(id,state) if features.vegetation else {}
func render_state(state:Dictionary)->Dictionary:
	if not validate_state(state).ok:return {}
	var result:Dictionary=state.duplicate(true);result["generated_v3_source"]=data.duplicate(true);return result
