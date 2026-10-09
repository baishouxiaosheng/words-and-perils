extends RefCounted
## Explicit isolated authority over the unchanged V21 encounter admission.
## Source data, exact geometry, placement and both navigation graphs are reused.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Base = preload("res://view/generated_v3_enemy/source.gd")
const Catalog = preload("res://core/source_equipment/catalog.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Policy = preload("res://view/generated_v3_enemy/policy.gd")
const NPCState = preload("res://core/source_npc/state.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
const VegetationCatalog = preload("res://core/generated_v3_vegetation/catalog.gd")
const VegetationFocus = preload("res://core/generated_v3_vegetation/focus.gd")
const History = preload("res://view/generated_v3_equipment/history.gd")
const PROFILE = Catalog.PROFILE
const PROJECTION_ID = Catalog.PROJECTION
const WORLD_PREFIX = Catalog.WORLD_PREFIX
const RENDERER_PROFILE = Base.RENDERER_PROFILE
const SCENE = Base.SCENE
const ITEM = Base.ITEM
const TOPIC = Base.TOPIC
var data: Dictionary = {}
var world: Dictionary = {}
var identity: Dictionary = {}
var renderer_bundle: Dictionary = {}
var placement_result: Dictionary = {}
var npc_placement_result: Dictionary = {}
var enemy_placement_result: Dictionary = {}
var npc_reservations: Array = []
var vegetation_result: Dictionary = {}
var features: Dictionary = {"vegetation": false}
var spawn_component: Dictionary = {}
var navigation: RefCounted
var base_navigation: RefCounted
var base_source: RefCounted
var npc_id = ""
var enemy_id = Catalog.ENEMY
var _fixed: Dictionary = {}
var enemy_request_contract: Dictionary = {}
var enemy_capacity_metrics: Dictionary = {}

func admit(value: Variant, renderer_profile: String = RENDERER_PROFILE, persisted_manifest: Variant = null, options: Dictionary = {"vegetation": false}, persisted_vegetation: Variant = null, persisted_enemy: Variant = null) -> Dictionary:
	var base := Base.new()
	var checked: Dictionary = base.admit(value, renderer_profile, persisted_manifest, options, persisted_vegetation, persisted_enemy)
	if not checked.ok: return checked
	var combined: Dictionary = base.identity.duplicate(true)
	combined.profile = PROFILE; combined.projection_id = PROJECTION_ID
	combined["equipment_profile"] = PROFILE
	combined["equipment_profile_hash"] = profile_digest()
	combined["equipment_base_runtime_hash"] = base.identity.runtime_hash
	combined["equipment_catalog"] = Catalog.build(combined)
	combined["equipment_catalog_hash"] = combined.equipment_catalog.catalog_hash
	# The original vegetation manifest/geometry is reused byte-for-byte. Its
	# catalog alone needs a new profile/runtime binding for the new world.
	for field in ["vegetation_profile", "vegetation_hash", "vegetation_entity_catalog", "vegetation_catalog_hash", "vegetation_base_runtime_hash"]:
		combined.erase(field)
	combined.runtime_hash = Catalog.runtime_digest(combined)
	if options.vegetation:
		var veg: Dictionary = VegetationCatalog.build(PROFILE, combined, base.vegetation_result.manifest, base.vegetation_result.assets.catalog)
		if not veg.ok: return veg
		combined["vegetation_base_runtime_hash"] = combined.runtime_hash
		combined["vegetation_profile"] = VegetationCatalog.PROFILE
		combined["vegetation_hash"] = base.vegetation_result.manifest.vegetation_hash
		combined["vegetation_entity_catalog"] = veg.catalog
		combined["vegetation_catalog_hash"] = veg.catalog.catalog_hash
		combined.runtime_hash = Catalog.runtime_digest(combined)
	var candidate: Dictionary = base.world.duplicate(true)
	candidate.world_id = WORLD_PREFIX + C.digest({"source": base.data.content_hash, "features": options})
	candidate.generated_world = C.normalized(combined)
	candidate.story_anchors.anchor_generated_v3_scope.text = "旅人可以沿干地探索、观察、休息，放下或拾回行礼包，并向守路村民问路。持刃拦路者固定守住一格；活着或倒下均占据该格。双方各自描述意图并经评估后才能近战，须相邻且真实干地边连通，每次耗费1体力。敌人倒下后，可以从真实干地通路连通的相邻格拾取现有短刃；拾取不会自动装备。旅人可经评估装备或切换自己持有的木杖与短刃，两件武器均不能丢弃或转交。村民行囊保持原样。短刃完整命中可能施毒，中毒在后续每次已提交行动结算，敌方行动也计入。无巡逻、交易、额外敌人、远程或法术。点击、选择与查看不消耗回合。"
	checked = World.validate(candidate)
	if not checked.ok: return checked
	data = base.data; world = C.normalized(candidate); identity = C.normalized(combined)
	renderer_bundle = base.renderer_bundle
	placement_result = base.placement_result; npc_placement_result = base.npc_placement_result
	enemy_placement_result = base.enemy_placement_result; npc_reservations = base.npc_reservations
	vegetation_result = base.vegetation_result; features = base.features
	spawn_component = base.spawn_component; navigation = base.navigation; base_navigation = base.base_navigation
	base_source = base; npc_id = base.npc_id; enemy_id = base.enemy_id
	_fixed = fixed_fields(world)
	checked = validate_state(world)
	return {"ok": true, "identity": identity.duplicate(true), "enemy_id": enemy_id, "start": world.actors.actor_player.hex.duplicate(), "component_size": spawn_component.size()} if checked.ok else checked

static func profile_digest() -> String:
	var pins: Dictionary = {}
	for name_ in ["source", "adapter", "resolver", "rule", "assessments", "projection", "history", "response_budget", "runtime_engine"]:
		var path = "res://view/generated_v3_equipment/" + name_ + ".gd"; pins[path] = FileAccess.get_sha256(path)
	pins["res://core/source_equipment/catalog.gd"] = FileAccess.get_sha256("res://core/source_equipment/catalog.gd")
	return C.digest(pins)

static func fixed_fields(state: Dictionary) -> Dictionary:
	var result: Dictionary = Base.fixed_fields(state)
	# V21 already strips player movement/status/inventory and bundle custody.
	# Only these additional existing gear fields become mutable in this slice.
	for id in ["actor_player", Catalog.ENEMY]:
		if result.actors.has(id): result.actors[id].erase("equipment")
	if result.actors.has(Catalog.ENEMY): result.actors[Catalog.ENEMY].erase("inventory")
	for id in [Catalog.STAFF, Catalog.BLADE]:
		if not result.items.has(id): continue
		for field in ["owner_actor_id", "custody_revision"]: result.items[id].erase(field)
	return C.normalized(result)

func validate_state(state: Variant) -> Dictionary:
	if base_source == null: return C.fail("EQUIPMENT_SOURCE", "请先开启装备版本的村庄冒险。")
	var checked: Dictionary = World.validate(state)
	if not checked.ok: return checked
	if not C.exact_fields(state, world.keys()) or not C.exact_fields(state.actors, world.actors.keys()) or not C.exact_fields(state.items, world.items.keys()) or C.bytes(fixed_fields(state)) != C.bytes(_fixed):
		return C.fail("EQUIPMENT_IDENTITY", "地图、固定敌人、物品能力或装备来源被改写。")
	checked = Catalog.validate(state)
	if not checked.ok: return checked
	checked = NPCState.validate_committed(state)
	if not checked.ok: return checked
	if features.vegetation:
		checked = VegetationCatalog.validate_world(state)
		if not checked.ok: return checked
	if Policy.occupied(state, state.actors.actor_player.hex, "actor_player"):
		return C.fail("ENEMY_OCCUPIED", "敌人即使倒下仍占据此格，不能穿过。")
	if state.combat_turn.phase == "enemy" and not Policy.can_attack(state, enemy_id, "actor_player", base_navigation):
		return C.fail("ENEMY_PHASE", "不能安排无法执行的敌方回合。")
	if state.combat_turn.enemy_actor_id != enemy_id or state.combat_turn.round > state.turn:
		return C.fail("ENEMY_PHASE", "遭遇回合身份无效。")
	var shadow: Dictionary = Catalog.original_gear_shadow(state)
	shadow.world_id = base_source.world.world_id
	shadow.generated_world = base_source.world.generated_world.duplicate(true)
	shadow.story_anchors = base_source.world.story_anchors.duplicate(true)
	return base_source.validate_state(shadow)

func validate_history(engine_data: Dictionary) -> Dictionary: return History.validate(self, engine_data)
func talk_range(state: Dictionary, actor_id: String, target_id: String) -> bool: return base_source.talk_range(state, actor_id, target_id)
func static_reference(id: String, clicked_hex: Array = []) -> Dictionary: return StaticFocus.make_reference(id, world, clicked_hex)
func npc_reference(state: Dictionary) -> Dictionary: return base_source.npc_reference(state)
func vegetation_reference(id: String, state: Dictionary) -> Dictionary: return VegetationFocus.make_reference(id, state) if features.vegetation else {}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result: Dictionary = state.duplicate(true); result["generated_v3_source"] = data.duplicate(true); return result
