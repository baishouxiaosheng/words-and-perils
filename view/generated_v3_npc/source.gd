extends RefCounted
## Explicit composition. Every immutable catalogue is reconstructed before load.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const VillageSource=preload("res://view/generated_v3_village/source.gd")
const InventorySource=preload("res://view/generated_v3_inventory/source.gd")
const WorldSchema=preload("res://core/ai_gm_rebuilt/world.gd")
const FocusContract=preload("res://core/focus_contract.gd")
const Catalog=preload("res://core/source_npc/catalog.gd")
const NPCState=preload("res://core/source_npc/state.gd")
const NPCFocus=preload("res://core/source_npc/focus.gd")
const Placement=preload("res://view/generated_v3_npc/placement.gd")
const Vegetation=preload("res://core/generated_v3_vegetation/planner.gd")
const VegetationCatalog=preload("res://core/generated_v3_vegetation/catalog.gd")
const VegetationFocus=preload("res://core/generated_v3_vegetation/focus.gd")
const PROFILE="generated_v3_village_npc/v1"
const PROJECTION_ID="generated_v3_village_npc_context/v1"
const WORLD_PREFIX="generated_v3_village_npc_v1_"
const RENDERER_PROFILE=VillageSource.RENDERER_PROFILE
const SCENE=VillageSource.SCENE
const ITEM=VillageSource.ITEM
const TOPIC="entry_directions"
var data: Dictionary={}
var world: Dictionary={}
var identity: Dictionary={}
var renderer_bundle: Dictionary={}
var placement_result: Dictionary={}
var npc_placement_result: Dictionary={}
var npc_reservations: Array=[]
var vegetation_result: Dictionary={}
var features: Dictionary={"vegetation":false}
var spawn_component: Dictionary={}
var navigation: RefCounted
var base_source: RefCounted
var npc_id=""
func admit(value: Variant, renderer_profile: String=RENDERER_PROFILE, persisted_manifest: Variant=null, options: Dictionary={"vegetation":false}, persisted_vegetation: Variant=null) -> Dictionary:
	if not C.exact_fields(options,["vegetation"]) or not options.vegetation is bool:return C.fail("NPC_FEATURES","旅程设置无效，旧进度不会被改写。")
	if not options.vegetation and persisted_vegetation!=null:return C.fail("NPC_FEATURES","此进度未启用植被，不能注入植被资料。")
	var base:=VillageSource.new()
	var checked: Dictionary=base.admit(value,renderer_profile,persisted_manifest)
	if not checked.ok:return checked
	var site: Dictionary=base.placement_result.manifest.settlements[0]
	var id_=Catalog.stable_id(PROFILE,base.identity,{"settlement_id":site.id,"role":Placement.ROLE},"villager")
	var placement: Dictionary=Placement.build(base,id_)
	if not placement.ok:return placement
	var fact_id="fact:"+id_+":entry_directions"
	var fact={"id":fact_id,"summary":"村落入口与道路","payload":{"settlement_id":site.id,"village_hex":site.center_hex.duplicate(),"entry_hex":site.entry_hex.duplicate(),"road_id":site.road_ids[0],"description":"沿入口道路走到村中空地；建筑占据的通路需要绕行。道路不减少体力耗费。"}}
	var descriptor={"id":id_,"kind":"actor","name":"守路村民","description":"站在入口路旁的村民，可以询问村落的入口道路。","role":"villager","faction":"friendly","health":{"current":1,"max":1},"stamina":{"current":1,"max":1},"inventory":[],"statuses":{},"hooks":[],"scene_id":SCENE,"hex":site.entry_hex.duplicate(),"location_revision":0,"placement_witness":placement.placement_witness,"topics":{TOPIC:{"id":TOPIC,"label":"询问村落入口","fact_ids":[fact_id]}},"facts":{fact_id:fact}}
	var catalog: Dictionary=Catalog.build(PROFILE,base.identity,[descriptor])
	if not catalog.ok:
		catalog["diagnostics"]={"valid_placement":Catalog.valid_placement(descriptor.placement_witness),"support_bytes":C.bytes(descriptor.placement_witness.support_witness).to_utf8_buffer().size(),"descriptor_bytes":C.bytes(descriptor).to_utf8_buffer().size()};return catalog
	var combined: Dictionary=base.identity.duplicate(true)
	combined.profile=PROFILE;combined.projection_id=PROJECTION_ID
	combined["npc_profile"]=PROFILE;combined["npc_profile_hash"]=profile_digest()
	combined["base_village_runtime_hash"]=base.identity.runtime_hash
	combined["npc_catalog"]=catalog.catalog;combined["npc_catalog_hash"]=catalog.catalog.catalog_hash
	combined["features"]=options.duplicate(true)
	combined["npc_reservation_hash"]=C.digest(placement.reservations)
	combined.runtime_hash=runtime_digest(combined)
	var plants: Dictionary={}
	if options.vegetation:
		plants=Vegetation.build(base.data,base.renderer_bundle,base.navigation,base.placement_result,base.world.actors.actor_player.hex,placement.reservations) if persisted_vegetation==null else Vegetation.validate(persisted_vegetation,base.data,base.renderer_bundle,base.navigation,base.placement_result,base.world.actors.actor_player.hex,placement.reservations)
		if not plants.ok:return plants
		var veg: Dictionary=VegetationCatalog.build(PROFILE,combined,plants.manifest,plants.assets.catalog)
		if not veg.ok:return veg
		combined["vegetation_base_runtime_hash"]=combined.runtime_hash
		combined["vegetation_profile"]=VegetationCatalog.PROFILE
		combined["vegetation_hash"]=plants.manifest.vegetation_hash
		combined["vegetation_entity_catalog"]=veg.catalog
		combined["vegetation_catalog_hash"]=veg.catalog.catalog_hash
		combined.runtime_hash=runtime_digest(combined)
	var candidate: Dictionary=base.world.duplicate(true)
	candidate.world_id=WORLD_PREFIX+C.digest({"source":base.data.content_hash,"features":options})
	candidate.generated_world=C.normalized(combined)
	candidate.actors[id_]=Catalog.actor_from_descriptor(descriptor)
	candidate["npc_state"]=NPCState.empty(catalog.catalog)
	candidate.story_anchors.anchor_generated_v3_scope.text="你是一位旅人，可以沿干地移动、观察、休息，放下或拾回行礼包。村落建筑会阻挡占据的通路。守路村民可以谈论登记的话题：写下意图，经评估后交谈，耗费1点体力和1回合，得到的信息会保留。重复交谈不会覆盖首次获知的记录。选择或查看不消耗回合。植被若启用，仅可选择和观察；尚无采集、战斗、室内或河流跨越效果。"
	checked=WorldSchema.validate(candidate)
	if not checked.ok:return checked
	if options.vegetation:
		checked=VegetationCatalog.validate_world(candidate)
		if not checked.ok:return checked
	# The accepted item validator sees the same composed immutable world, with
	# only the new mutable typed block restored in its detached validation copy.
	base.inventory_source.world=C.normalized(candidate)
	base.inventory_source.immutable=InventorySource.fixed_fields(candidate)
	base.inventory_source.identity=C.normalized(combined)
	data=base.data;world=C.normalized(candidate);identity=C.normalized(combined)
	renderer_bundle=base.renderer_bundle;placement_result=base.placement_result
	navigation=base.navigation;spawn_component=base.spawn_component
	base_source=base;npc_id=id_;npc_placement_result=placement;npc_reservations=placement.reservations
	vegetation_result=plants;features=options.duplicate(true)
	checked=validate_state(world)
	return {"ok":true,"identity":identity.duplicate(true),"start":world.actors.actor_player.hex.duplicate(),"component_size":spawn_component.size(),"npc_id":npc_id} if checked.ok else checked
static func profile_digest() -> String:
	var pins={}
	for path in ["source","adapter","resolver","rule","assessments","projection","placement"]:
		var file="res://view/generated_v3_npc/"+path+".gd";pins[file]=FileAccess.get_sha256(file)
	for path in ["catalog","state","focus","projection","conversation"]:
		var file="res://core/source_npc/"+path+".gd";pins[file]=FileAccess.get_sha256(file)
	# Vegetation closure is explicit even when disabled; no old profile changes.
	for path in ["planner","assets","catalog","focus","projection"]:
		var file="res://core/generated_v3_vegetation/"+path+".gd";pins[file]=FileAccess.get_sha256(file)
	pins["res://view/chess_tokens.gd"]=FileAccess.get_sha256("res://view/chess_tokens.gd")
	return C.digest(pins)
static func runtime_digest(metadata: Dictionary) -> String:
	return C.digest({"profile":PROFILE,"profile_hash":metadata.get("npc_profile_hash"),"base_village_runtime_hash":metadata.get("base_village_runtime_hash"),"npc_catalog_hash":metadata.get("npc_catalog_hash"),"npc_reservation_hash":metadata.get("npc_reservation_hash"),"features":metadata.get("features"),"vegetation_hash":metadata.get("vegetation_hash",""),"vegetation_catalog_hash":metadata.get("vegetation_catalog_hash","")})
func validate_state(state: Variant) -> Dictionary:
	if base_source==null:return C.fail("NPC_SOURCE","请先开启村庄冒险。")
	var checked: Dictionary=WorldSchema.validate(state)
	if not checked.ok:return checked
	checked=NPCState.validate_committed(state)
	if not checked.ok:return checked
	if features.vegetation:
		checked=VegetationCatalog.validate_world(state)
		if not checked.ok:return checked
	var shadow: Dictionary=state.duplicate(true);shadow.npc_state=world.npc_state.duplicate(true)
	return base_source.inventory_source.validate_state(shadow)
func talk_range(state: Dictionary,actor_id: String,target_id: String) -> bool:
	if target_id!=npc_id or not state.actors.has(actor_id) or not state.actors.has(target_id):return false
	var a: Dictionary=state.actors[actor_id];var b: Dictionary=state.actors[target_id]
	if a.scene_id!=b.scene_id:return false
	return C.bytes(a.hex)==C.bytes(b.hex) or navigation.step(a.hex,b.hex).get("ok",false)
func validate_history(engine_data: Dictionary) -> Dictionary:
	if not engine_data.get("receipts") is Dictionary or engine_data.receipts.size()>InventorySource.MAX_HISTORY_RECEIPTS or C.bytes(engine_data).to_utf8_buffer().size()>InventorySource.MAX_HISTORY_BYTES:return C.fail("NPC_HISTORY","行动历史超出此版本的有界记录格式。")
	var receipts: Array=engine_data.receipts.values();receipts.sort_custom(func(a,b):return int(a.turn)<int(b.turn))
	var replay: Dictionary=world.duplicate(true);var focus:=FocusContract.new()
	for receipt in receipts:
		if receipt.before_version!=replay.state_version or receipt.after_version!=replay.state_version+1 or receipt.turn!=replay.turn+1:return C.fail("NPC_HISTORY","行动回合不连续。")
		if not focus.validate_frozen(C.normalized(receipt.attention_focus),replay).is_empty():return C.fail("NPC_HISTORY_FOCUS","历史目标与当时的真实位置或交谈记录不一致。")
		var npc_patches: Array=[]
		for patch in receipt.patches:
			if patch.get("type")=="npc_conversation_record":npc_patches.append(patch)
		if receipt.outcomes.has("talk") and npc_patches.is_empty():return C.fail("NPC_HISTORY_TALK","此版本的已完成交谈需要确切信息记录。")
		if not npc_patches.is_empty():
			if receipt.branch_id!="npc_talk_complete" or C.bytes(receipt.outcomes)!=C.bytes({"talk":true}) or not receipt.rolls.is_empty():return C.fail("NPC_HISTORY_TALK","交谈结果与固定合作规则不一致。")
			var patch: Dictionary=npc_patches[0]
			if npc_patches.size()!=1 or not talk_range(replay,receipt.actor_id,npc_id) or patch.action_id!=receipt.action_id or patch.action_start_turn!=replay.turn or patch.observer_id!=receipt.actor_id:return C.fail("NPC_HISTORY_TALK","交谈记录与当时的目标、距离或回合不一致。")
			var expected: Dictionary=NPCState.make_patch(replay,receipt.actor_id,npc_id,TOPIC,receipt.action_id)
			var cost={"type":"actor_pool_delta","actor_id":receipt.actor_id,"pool":"stamina","delta":-1}
			if expected.is_empty() or C.bytes(receipt.patches)!=C.bytes([cost,expected]) or not receipt.hook_patches.is_empty():return C.fail("NPC_HISTORY_TALK","交谈必须保留确切体力耗费与首次获知凭据。")
		for patch in receipt.patches:
			var applied: Dictionary=WorldSchema.apply(replay,patch)
			if not applied.ok:return applied
		for patch in receipt.hook_patches:
			if patch.get("type")=="npc_conversation_record":return C.fail("NPC_HISTORY_TALK","交谈不能作为回合钩子。")
			var applied: Dictionary=WorldSchema.apply(replay,patch,true)
			if not applied.ok:return applied
		replay.state_version+=1;replay.turn+=1
		var checked: Dictionary=validate_state(replay)
		if not checked.ok:return checked
	if C.bytes(replay)!=C.bytes(engine_data.state):return C.fail("NPC_HISTORY","当前事实与已提交行动不一致。")
	return {"ok":true}
func static_reference(id: String,clicked_hex: Array=[]) -> Dictionary:return VillageSource.StaticFocus.make_reference(id,world,clicked_hex)
func npc_reference(state: Dictionary) -> Dictionary:return NPCFocus.make_reference(npc_id,state)
func vegetation_reference(id: String,state: Dictionary) -> Dictionary:return VegetationFocus.make_reference(id,state) if features.vegetation else {}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok:return {}
	var result: Dictionary=state.duplicate(true);result["generated_v3_source"]=data.duplicate(true);return result
