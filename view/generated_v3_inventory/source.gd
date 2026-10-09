extends RefCounted
## A new explicit authority profile composed over byte-exact V3 admission.
## It never changes generator/source/geometry/navigation data or old saves.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseSource = preload("res://view/generated_v3_adventure/source.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const FocusContract = preload("res://core/focus_contract.gd")
const PROFILE := "generated_v3_inventory/v1"
const PROJECTION_ID := "generated_v3_inventory_context/v1"
const WORLD_PREFIX := "generated_v3_inventory_v1_"
const ITEM := "item_travel_bundle"
const SCENE := BaseSource.SCENE
const RENDERER_PROFILE := BaseSource.RENDERER_PROFILE
const MAX_HISTORY_BYTES := 24 * 1024 * 1024
const MAX_HISTORY_RECEIPTS := MAX_HISTORY_BYTES / 512
var data: Dictionary = {}
var world: Dictionary = {}
var navigation: RefCounted
var renderer_bundle: Dictionary = {}
var identity: Dictionary = {}
var immutable: Dictionary = {}
var spawn_component: Dictionary = {}
func admit(value: Variant, renderer_profile: String = RENDERER_PROFILE) -> Dictionary:
	var base := BaseSource.new()
	var checked := base.admit(value,renderer_profile)
	if not checked.ok: return checked
	var descriptor := {"id":ITEM,"kind":"item","name":"行礼包","description":"出发时自带的一件行礼包。可以整件放下或拾回；没有消耗、拆分、装备或特殊效果。","quantity":1,"interaction_profile":Basic.interaction()}
	var built: Dictionary = Catalog.build(PROFILE,base.identity,[descriptor])
	if not built.ok: return built
	var next_identity: Dictionary = base.identity.duplicate(true)
	next_identity.profile = PROFILE
	next_identity.projection_id = PROJECTION_ID
	next_identity["inventory_profile"] = PROFILE
	next_identity["inventory_profile_hash"] = profile_digest()
	next_identity["base_runtime_hash"] = base.identity.runtime_hash
	next_identity["entity_profile"] = PROFILE
	next_identity["entity_catalog"] = built.catalog
	next_identity["entity_catalog_hash"] = built.catalog.catalog_hash
	next_identity.runtime_hash = C.digest({"base_runtime_hash":base.identity.runtime_hash,"profile":PROFILE,"profile_hash":next_identity.inventory_profile_hash,"entity_catalog_hash":built.catalog.catalog_hash})
	var candidate: Dictionary = base.world.duplicate(true)
	candidate.world_id = WORLD_PREFIX + base.data.content_hash
	candidate.generated_world = next_identity.duplicate(true)
	candidate.story_anchors.anchor_generated_v3_scope.text = "你是一位旅人，可以观察当前或相邻地格、沿已验证的干地移动、原地休息。旅人自带一件行礼包，可以整件放下，或从当前地格和直接连通的相邻干地拾回。行动先评估，再由固定程序结算。行礼包没有消耗、拆分、装备、转交或特殊效果；河流仅是地形资料，聚落、战斗、渡河与桥梁效果尚未接入。"
	var item: Dictionary = descriptor.duplicate(true); item.erase("kind")
	item["owner_actor_id"] = "actor_player"; item["custody_revision"] = 0
	candidate.items[ITEM] = item
	candidate.actors.actor_player.inventory = [ITEM]
	checked = WorldSchema.validate(candidate)
	if not checked.ok: return checked
	checked = Catalog.validate_world(candidate)
	if not checked.ok: return checked
	# Published references point only at BaseSource's detached exact data.
	data = base.data; navigation = base.navigation; renderer_bundle = base.renderer_bundle
	spawn_component = base.spawn_component; identity = C.normalized(next_identity)
	world = C.normalized(candidate); immutable = fixed_fields(world)
	checked = validate_state(world)
	return {"ok":true,"identity":identity.duplicate(true),"start":world.actors.actor_player.hex.duplicate(),"component_size":spawn_component.size(),"navigation":navigation.diagnostics.duplicate(true)} if checked.ok else checked
static func profile_digest() -> String:
	var hashes := {}
	for path in ["res://view/generated_v3_inventory/source.gd","res://view/generated_v3_inventory/adapter.gd","res://view/generated_v3_inventory/resolver.gd","res://view/generated_v3_inventory/rule.gd","res://view/generated_v3_inventory/assessments.gd","res://view/generated_v3_inventory/projection.gd","res://core/source_entities/catalog.gd","res://core/source_entities/focus.gd","res://core/source_entities/projection.gd","res://view/generated_inventory/resolver.gd","res://core/ai_gm_rebuilt/basic_actions.gd","res://core/ai_gm_rebuilt/basic_effects.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return C.digest(hashes)
static func fixed_fields(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for field in ["state_version","turn","flags"]: result.erase(field)
	if result.get("actors",{}).has("actor_player"):
		var actor: Dictionary = result.actors.actor_player
		actor.erase("hex"); actor.erase("inventory"); actor.get("stamina",{}).erase("current")
	for item in result.get("items",{}).values():
		for field in ["owner_actor_id","hex","scene_id","custody_revision"]: item.erase(field)
	return C.normalized(result)
func validate_state(state: Variant) -> Dictionary:
	var checked: Dictionary = WorldSchema.validate(state)
	if not checked.ok: return checked
	if not C.exact_fields(state,world.keys()) or C.bytes(fixed_fields(state)) != C.bytes(immutable): return C.fail("V3_INVENTORY_IDENTITY","地图、目录、行礼包或旅人能力不属于此版本。")
	checked = Catalog.validate_world(state)
	if not checked.ok: return checked
	var actor: Dictionary = state.actors.actor_player
	var key: String = "%d,%d" % actor.hex
	if not spawn_component.has(key) or not navigation.supported.get(key,false): return C.fail("V3_LANDING","旅人位置不在已验证连通的干地上。")
	var item: Dictionary = state.items[ITEM]
	if not C.integer(item.get("custody_revision")) or item.custody_revision < 0 or item.custody_revision > state.turn: return C.fail("V3_INVENTORY_REVISION","行礼包归属版本不能超过已提交回合。")
	# Custody is tagged by actual owner/location. Revision is an event counter,
	# never an even/odd proxy for ownership or history.
	if item.has("owner_actor_id"):
		if item.owner_actor_id != "actor_player": return C.fail("V3_INVENTORY_CUSTODY","随身行礼包需要这位旅人的唯一持有记录。")
	else:
		var item_key: String = "%d,%d" % item.hex
		if item.scene_id != SCENE or not spawn_component.has(item_key) or not navigation.supported.get(item_key,false): return C.fail("V3_INVENTORY_CUSTODY","地上行礼包需要已验证连通的干地支撑。")
	if not C.exact_fields(state.flags,["observations","last_observed_cell"]) or not C.integer(state.flags.observations) or state.flags.observations < 0 or state.flags.observations > state.turn or not state.flags.last_observed_cell is String or (not state.flags.last_observed_cell.is_empty() and not state.hexes.has(state.flags.last_observed_cell)) or (state.flags.observations == 0) != state.flags.last_observed_cell.is_empty(): return C.fail("V3_FLAGS","观察记录无效。")
	if state.state_version != state.turn: return C.fail("V3_TURN","行动回合与世界版本不一致。")
	return {"ok":true}
func validate_history(engine_data: Dictionary) -> Dictionary:
	# Called only after Engine.load_data validates receipt structure/hash and
	# pending plans. Reuse typed effects on a detached world; never draw entropy.
	if not engine_data.get("receipts") is Dictionary or engine_data.receipts.size() > MAX_HISTORY_RECEIPTS or C.bytes(engine_data).to_utf8_buffer().size() > MAX_HISTORY_BYTES: return C.fail("V3_INVENTORY_HISTORY","行动历史超出此版本的有界记录格式。")
	var receipts: Array = engine_data.receipts.values()
	receipts.sort_custom(func(a,b): return int(a.turn) < int(b.turn))
	var replay: Dictionary = world.duplicate(true)
	var focus_contract := FocusContract.new()
	for receipt in receipts:
		if receipt.before_version != replay.state_version or receipt.after_version != replay.state_version + 1 or receipt.turn != replay.turn + 1: return C.fail("V3_INVENTORY_HISTORY","行动历史缺失、重复或回合不连续。")
		if not focus_contract.validate_frozen(C.normalized(receipt.attention_focus),replay).is_empty(): return C.fail("V3_INVENTORY_HISTORY_FOCUS","历史目标与该回合真实的物品归属或位置不一致。")
		for patch in receipt.patches:
			var applied: Dictionary = WorldSchema.apply(replay,patch)
			if not applied.ok: return applied
		for patch in receipt.hook_patches:
			var applied: Dictionary = WorldSchema.apply(replay,patch,true)
			if not applied.ok: return applied
		replay.state_version += 1; replay.turn += 1
	if C.bytes(replay) != C.bytes(engine_data.state): return C.fail("V3_INVENTORY_HISTORY","当前事实与已提交行动不一致；未载入或补发物品。")
	return {"ok":true}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result: Dictionary = state.duplicate(true)
	result["generated_v3_source"] = data.duplicate(true)
	return result
