extends RefCounted
## Opt-in runtime profile. Generator/source bytes and v1/v2 authority stay unchanged.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseSource = preload("res://view/generated_adventure/source.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const PROFILE := "generated_inventory/v1"
const ITEM := "item_travel_bundle"
const SCENE := BaseSource.SCENE
var data: Dictionary = {}
var world: Dictionary = {}
var navigation: RefCounted
var identity: Dictionary = {}
var immutable: Dictionary = {}

func admit(value: Variant) -> Dictionary:
	var base := BaseSource.new()
	var checked := base.admit(value)
	if not checked.ok: return checked
	data = base.data; navigation = base.navigation; identity = base.identity.duplicate(true)
	identity.projection_id = "generated_inventory_context/v1"
	identity["inventory_profile"] = PROFILE
	identity["inventory_profile_hash"] = profile_digest()
	identity.runtime_hash = C.digest({"base_runtime_hash": base.identity.runtime_hash, "profile": PROFILE, "profile_hash": identity.inventory_profile_hash})
	world = base.world.duplicate(true)
	world.world_id = "generated_inventory_v1_" + data.content_hash
	world.generated_world = identity.duplicate(true)
	world.scenes[SCENE].bundle_id = identity.runtime_hash
	world.story_anchors.anchor_generated_scope.text = "多地貌探索：移动、邻格观察、休息；旅人自带一件行礼包，可按已登记的整件物品规则放下或拾回。行动均先评估，再由固定程序结算。行礼包不是采集物，没有使用、拆分、装备或特殊效果；树木、聚落、桥梁、战斗与海岸故事尚未接入。"
	world.items[ITEM] = {"id": ITEM, "name": "行礼包", "description": "出发时自带的一件行礼包。可以整件放下或拾回；没有消耗、拆分、装备或特殊效果。", "quantity": 1, "owner_actor_id": "actor_player", "interaction_profile": Basic.interaction(), "custody_revision": 0}
	world.actors.actor_player.inventory = [ITEM]
	world = C.normalized(world); immutable = fixed_fields(world)
	checked = validate_state(world)
	return {"ok": true, "identity": identity.duplicate(true)} if checked.ok else checked

static func profile_digest() -> String:
	var hashes := {}
	for path in ["res://view/generated_inventory/source.gd", "res://view/generated_inventory/resolver.gd", "res://view/generated_inventory/projection.gd", "res://view/generated_inventory/rule.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return C.digest(hashes)

static func fixed_fields(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("state_version"); result.erase("turn"); result.erase("flags")
	if result.get("actors", {}).has("actor_player"):
		var actor: Dictionary = result.actors.actor_player
		actor.erase("hex"); actor.erase("inventory"); actor.get("stamina", {}).erase("current")
	for item in result.get("items", {}).values():
		for field in ["owner_actor_id", "hex", "scene_id", "custody_revision"]: item.erase(field)
	return C.normalized(result)

func validate_state(state: Variant) -> Dictionary:
	var checked := WorldSchema.validate(state)
	if not checked.ok: return checked
	if not C.exact_fields(state, world.keys()) or C.bytes(fixed_fields(state)) != C.bytes(immutable):
		return C.fail("INVENTORY_PROFILE_IDENTITY", "Map, registered supply, actor capability or profile differs from this admitted adventure.")
	var actor: Dictionary = state.actors.actor_player
	if not navigation.supported.get("%d,%d" % actor.hex, false): return C.fail("GENERATED_LANDING", "Traveler has no exact dry source support.")
	var item: Dictionary = state.items[ITEM]
	if not item.has("custody_revision") or item.custody_revision > state.turn: return C.fail("INVENTORY_REVISION", "Whole-stack custody revision cannot exceed committed turns.")
	if item.has("owner_actor_id"):
		if item.owner_actor_id != "actor_player" or int(item.custody_revision) % 2 != 0: return C.fail("INVENTORY_CUSTODY", "Carried supply requires the original traveler and even custody revision.")
	elif item.get("scene_id") != SCENE or not navigation.supported.get("%d,%d" % item.hex, false) or int(item.custody_revision) % 2 != 1:
		return C.fail("INVENTORY_CUSTODY", "Dropped supply requires exact dry support and odd custody revision.")
	if not C.exact_fields(state.flags, ["observations", "last_observed_cell"]) or not C.integer(state.flags.observations) or state.flags.observations < 0 or state.flags.observations > state.turn or not state.flags.last_observed_cell is String or (not state.flags.last_observed_cell.is_empty() and not state.hexes.has(state.flags.last_observed_cell)):
		return C.fail("GENERATED_FLAGS", "Observation history is invalid.")
	return {"ok": true}

func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result := state.duplicate(true)
	result.generated_world = data.duplicate(true); result.hexes = data.hexes.duplicate(true)
	for key in result.hexes: result.hexes[key].scene_id = SCENE
	return result
