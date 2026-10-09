extends RefCounted
## The existing two weapons gain bounded custody/equipment state in this profile
## only. The encounter's original actor, capabilities and catalog stay frozen.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const World = preload("res://core/ai_gm_rebuilt/world.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const EnemyCatalog = preload("res://core/source_enemy/catalog.gd")
const EntityCatalog = preload("res://core/source_entities/catalog.gd")
const NPCCatalog = preload("res://core/source_npc/catalog.gd")
const PROFILE = "generated_v3_village_equipment/v1"
const PROJECTION = "generated_v3_village_equipment_context/v1"
const WORLD_PREFIX = "generated_v3_village_equipment_v1_"
const ENEMY = EnemyCatalog.ENEMY
const STAFF = EnemyCatalog.STAFF
const BLADE = EnemyCatalog.BLADE
const FACTION = EnemyCatalog.FACTION
const PLAYER = "actor_player"
const BUNDLE = "item_travel_bundle"
const ID = "source_equipment_catalog/v1"
const FIELDS = ["schema_version", "profile_id", "source_hash", "geometry_hash", "placement_hash", "enemy_catalog_hash", "base_runtime_hash", "actor_ids", "item_ids", "weapons", "pickup_policy", "equipment_policy", "catalog_hash"]

static func build(metadata: Dictionary) -> Dictionary:
	var actors: Array = [PLAYER, ENEMY]
	for actor_id in metadata.get("npc_catalog", {}).get("entries", {}): actors.append(actor_id)
	actors.sort()
	var items: Array = [BUNDLE, STAFF, BLADE]; items.sort()
	var catalog: Dictionary = {
		"schema_version": ID, "profile_id": PROFILE,
		"source_hash": metadata.get("content_hash"), "geometry_hash": metadata.get("geometry_hash"),
		"placement_hash": metadata.get("placement_hash"), "enemy_catalog_hash": metadata.get("enemy_catalog_hash"),
		"base_runtime_hash": metadata.get("equipment_base_runtime_hash"),
		"actor_ids": actors, "item_ids": items,
		"weapons": {STAFF: EnemyCatalog.weapon(STAFF, PLAYER), BLADE: EnemyCatalog.weapon(BLADE, ENEMY)},
		"pickup_policy": "only existing blade from downed hostile across one original dry building-clear edge; enemy cell stays occupied",
		"equipment_policy": "player swaps owned staff or blade; no weapon drop, transfer, duplication, consumption or NPC inventory change"
	}
	catalog["catalog_hash"] = C.digest(catalog)
	return C.normalized(catalog)

static func validate(state: Dictionary) -> Dictionary:
	# This includes Basic's exact owner/inventory/equipment conservation checks.
	var checked: Dictionary = World.validate(state)
	if not checked.ok: return checked
	var metadata: Variant = state.get("generated_world")
	if not metadata is Dictionary or metadata.get("profile") != PROFILE or metadata.get("projection_id") != PROJECTION or metadata.get("equipment_profile") != PROFILE or metadata.get("enemy_profile") != EnemyCatalog.PROFILE:
		return C.fail("EQUIPMENT_SOURCE", "装备状态不属于此独立村庄冒险版本。")
	if not C.exact_fields(metadata.get("features"), ["vegetation"]) or not metadata.features.vegetation is bool:
		return C.fail("EQUIPMENT_SOURCE", "装备来源的旅程设置无效。")
	if state.world_id != WORLD_PREFIX + C.digest({"source": metadata.get("content_hash"), "features": metadata.features}):
		return C.fail("EQUIPMENT_SOURCE", "装备与旅程身份不一致。")
	for field in ["content_hash", "geometry_hash", "placement_hash", "enemy_catalog_hash", "equipment_profile_hash", "equipment_base_runtime_hash", "equipment_catalog_hash", "runtime_hash"]:
		if not EntityCatalog.valid_hash(metadata.get(field)): return C.fail("EQUIPMENT_SOURCE", "装备来源摘要无效。")
	checked = NPCCatalog.validate_world(state)
	if not checked.ok: return checked
	var catalog: Variant = metadata.get("equipment_catalog")
	if not C.exact_fields(catalog, FIELDS) or not C.safe(catalog) or C.bytes(catalog) != C.bytes(build(metadata)) or metadata.equipment_catalog_hash != catalog.catalog_hash:
		return C.fail("EQUIPMENT_CATALOG", "装备目录或其固定能力被替换。")
	if metadata.runtime_hash != runtime_digest(metadata): return C.fail("EQUIPMENT_SOURCE", "装备运行版本不一致。")
	if not C.exact_fields(state.actors, catalog.actor_ids) or not C.exact_fields(state.items, catalog.item_ids):
		return C.fail("EQUIPMENT_IDENTITIES", "不能增加、遗漏或复制角色与物品身份。")
	# Normalize only integer-valued finite JSON numbers; never round revisions.
	var current: Dictionary = C.normalized(state)
	var player: Dictionary = current.actors[PLAYER]
	var enemy: Dictionary = current.actors[ENEMY]
	for id in [STAFF, BLADE]:
		var item: Dictionary = current.items[id]
		if not C.exact_fields(item, catalog.weapons[id].keys()): return C.fail("EQUIPMENT_WEAPON", "武器不能丢到地面、增加位置或改变能力。")
		var immutable: Dictionary = item.duplicate(true)
		immutable.owner_actor_id = catalog.weapons[id].owner_actor_id
		immutable.custody_revision = catalog.weapons[id].custody_revision
		if C.bytes(immutable) != C.bytes(catalog.weapons[id]): return C.fail("EQUIPMENT_WEAPON", "装备必须保留登记武器的确切能力与数量。")
		if not C.integer(item.custody_revision) or item.custody_revision < 0 or item.custody_revision > current.turn:
			return C.fail("EQUIPMENT_REVISION", "装备版本必须是已提交事件的有界整数计数。")
	if current.items[STAFF].owner_actor_id != PLAYER or not STAFF in player.inventory:
		return C.fail("EQUIPMENT_STAFF", "木杖必须始终由旅人唯一持有。")
	if not C.exact_fields(player.get("equipment"), ["weapon"]) or player.equipment.weapon not in [STAFF, BLADE]:
		return C.fail("EQUIPMENT_PLAYER", "旅人只能装备一件自己持有的登记武器。")
	for id in player.inventory:
		if id not in [BUNDLE, STAFF, BLADE]: return C.fail("EQUIPMENT_PLAYER", "旅人行囊包含未登记物品。")
	var blade: Dictionary = current.items[BLADE]
	if blade.owner_actor_id == ENEMY:
		if C.bytes(enemy.inventory) != C.bytes([BLADE]) or C.bytes(enemy.get("equipment")) != C.bytes({"weapon": BLADE}) or BLADE in player.inventory or blade.custody_revision != 0 or current.items[STAFF].custody_revision != 0 or player.equipment.weapon != STAFF:
			return C.fail("EQUIPMENT_CUSTODY", "尚未拾取的短刃必须保留敌人的原始持有与装备。")
	elif blade.owner_actor_id == PLAYER:
		if enemy.health.current != 0 or not enemy.inventory.is_empty() or C.bytes(enemy.get("equipment")) != C.bytes({}) or not BLADE in player.inventory or blade.custody_revision < 1:
			return C.fail("EQUIPMENT_DOWNED", "只能拾取已倒下敌人的短刃，并清除原持有与装备。")
		if player.equipment.weapon == BLADE and blade.custody_revision < 2:
			return C.fail("EQUIPMENT_REVISION", "拾取与装备是不同的已提交事件。")
	else:
		return C.fail("EQUIPMENT_CUSTODY", "短刃不能转交其他角色或丢到地面。")
	# Revision counts events, including equip/swap. Ownership is never inferred
	# from odd/even parity; exact transition provenance belongs to history replay.
	for actor_id in current.actors:
		if actor_id in [PLAYER, ENEMY]: continue
		if C.bytes(current.actors[actor_id].inventory) != C.bytes(metadata.npc_catalog.entries[actor_id].inventory):
			return C.fail("EQUIPMENT_NPC", "村民行囊保持原样，不能接收装备。")
	return EnemyCatalog.validate(original_gear_shadow(current))

static func original_gear_shadow(state: Dictionary) -> Dictionary:
	# A detached compatibility view, never written back to the live state.
	# Keep health, poison, stamina, turns, bundle custody and NPC facts intact.
	var shadow: Dictionary = C.normalized(state)
	var inventory: Array = []
	for id in shadow.actors[PLAYER].inventory:
		if id not in [STAFF, BLADE]: inventory.append(id)
	inventory.append(STAFF)
	shadow.actors[PLAYER].inventory = inventory
	shadow.actors[PLAYER].equipment = {"weapon": STAFF}
	shadow.actors[ENEMY].inventory = [BLADE]
	shadow.actors[ENEMY].equipment = {"weapon": BLADE}
	shadow.items[STAFF] = EnemyCatalog.weapon(STAFF, PLAYER)
	shadow.items[BLADE] = EnemyCatalog.weapon(BLADE, ENEMY)
	return shadow

static func runtime_digest(metadata: Dictionary) -> String:
	return C.digest({"profile": PROFILE, "profile_hash": metadata.get("equipment_profile_hash"), "base_runtime_hash": metadata.get("equipment_base_runtime_hash"), "equipment_catalog_hash": metadata.get("equipment_catalog_hash"), "features": metadata.get("features"), "vegetation_hash": metadata.get("vegetation_hash", ""), "vegetation_catalog_hash": metadata.get("vegetation_catalog_hash", "")})
