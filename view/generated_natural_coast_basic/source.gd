extends RefCounted
## A new explicit authority profile composed over byte-exact V3 admission.
## It never changes generator/source/geometry/navigation data or old saves.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const BaseSource = preload("res://view/generated_natural_coast_basic/base_source.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_effects.gd")
const Catalog = preload("res://core/source_entities/catalog.gd")
const FocusContract = preload("res://core/focus_contract.gd")
const AuthorityInputs = preload("res://view/generated_natural_coast_basic/authority_inputs.gd")
const Resolver = preload("res://view/generated_natural_coast_basic/resolver.gd")
const ItemResolver = preload("res://view/generated_natural_coast_basic/item_resolver.gd")
const Hooks = preload("res://core/ai_gm_rebuilt/hooks.gd")
const ID := BaseSource.ID
const PROFILE := "natural_coast_basic/v1"
const PROJECTION_ID := "natural_coast_basic_context/v1"
const WORLD_PREFIX := "natural_coast_basic_v1_"
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
var physical_base: RefCounted
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
	if not valid_hash(next_identity.inventory_profile_hash): return C.fail("COAST_PIPELINE","A gameplay dependency is missing.")
	next_identity["base_runtime_hash"] = base.identity.runtime_hash
	next_identity["entity_profile"] = PROFILE
	next_identity["entity_catalog"] = built.catalog
	next_identity["entity_catalog_hash"] = built.catalog.catalog_hash
	next_identity.runtime_hash = C.digest({"base_runtime_hash":base.identity.runtime_hash,"profile":PROFILE,"profile_hash":next_identity.inventory_profile_hash,"entity_catalog_hash":built.catalog.catalog_hash})
	var candidate: Dictionary = base.world.duplicate(true)
	candidate.world_id = WORLD_PREFIX + next_identity.runtime_hash
	candidate.generated_world = next_identity.duplicate(true)
	candidate.story_anchors.anchor_generated_v3_scope.text = "你是一位旅人，可以观察当前或相邻地格、沿已验证的干地移动、原地休息。旅人自带一件行礼包，可以整件放下，或从当前地格和直接连通的相邻干地拾回。行动先评估，再由固定程序结算。行礼包没有消耗、拆分、装备、转交或特殊效果；海岸地面、水面、拾取和通行使用同一已校验物理网格。此入口没有实体河道、聚落、NPC、战斗、植被或装备能力。"
	var item: Dictionary = descriptor.duplicate(true); item.erase("kind")
	item["owner_actor_id"] = "actor_player"; item["custody_revision"] = 0
	candidate.items[ITEM] = item
	candidate.actors.actor_player.inventory = [ITEM]
	checked = WorldSchema.validate(candidate)
	if not checked.ok: return checked
	checked = Catalog.validate_world(candidate)
	if not checked.ok: return checked
	# Published references point only at BaseSource's detached exact data.
	physical_base = base
	data = base.data; navigation = base.navigation; renderer_bundle = base.renderer_bundle
	spawn_component = base.spawn_component; identity = C.normalized(next_identity)
	world = C.normalized(candidate); immutable = fixed_fields(world)
	checked = validate_state(world)
	return {"ok":true,"identity":identity.duplicate(true),"start":world.actors.actor_player.hex.duplicate(),"component_size":spawn_component.size(),"navigation":navigation.diagnostics.duplicate(true)} if checked.ok else checked
static func profile_digest() -> String:
	var hashes := {}
	for path in AuthorityInputs.FILES:
		var value := FileAccess.get_sha256(path)
		if not BaseSource.valid_hash(value): return ""
		hashes[path] = value
	return C.digest(hashes)
static func valid_hash(value: Variant) -> bool: return BaseSource.valid_hash(value)
static func fixed_fields(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for field in ["state_version","turn","flags"]: result.erase(field)
	if result.get("actors",{}).has("actor_player"):
		var actor: Dictionary = result.actors.actor_player
		actor.erase("hex"); actor.erase("inventory"); actor.get("stamina",{}).erase("current")
	for item in result.get("items",{}).values():
		for field in ["owner_actor_id","hex","scene_id","custody_revision"]: item.erase(field)
	return C.normalized(result)
func validate_physical() -> Dictionary:
	if physical_base == null or physical_base.custody == null: return C.fail("COAST_CUSTODY","Physical custody is missing.")
	var snapshot: Dictionary = physical_base.custody.snapshot()
	if snapshot.is_empty() or C.bytes(snapshot.identity) != C.bytes(identity.get("physical_custody",{})) or C.bytes(data) != C.bytes(snapshot.source): return C.fail("COAST_CUSTODY","Source, mesh, water or producer identity changed after admission.")
	if C.digest({"supported":navigation.supported,"support_heights":navigation.support_heights,"allowed":navigation.allowed}) != identity.navigation_content_hash: return C.fail("COAST_NAV_CUSTODY","Navigation changed after physical admission.")
	return {"ok":true}
func validate_state(state: Variant) -> Dictionary:
	var physical: Dictionary = validate_physical()
	if not physical.ok: return physical
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
		var semantic: Dictionary = validate_receipt_semantics(receipt,replay)
		if not semantic.ok: return semantic
		for patch in receipt.patches:
			var applied: Dictionary = WorldSchema.apply(replay,patch)
			if not applied.ok: return applied
		for patch in receipt.hook_patches:
			var applied: Dictionary = WorldSchema.apply(replay,patch,true)
			if not applied.ok: return applied
		replay.state_version += 1; replay.turn += 1
	if C.bytes(replay) != C.bytes(engine_data.state): return C.fail("V3_INVENTORY_HISTORY","当前事实与已提交行动不一致；未载入或补发物品。")
	return {"ok":true}
func validate_receipt_semantics(receipt: Dictionary, before: Dictionary) -> Dictionary:
	# Every admitted action is safe-direct. Reconstruct its typed bindings from
	# its declared branch and exact effects, then ask the SAME trusted resolver.
	# Receipts are not authenticated, so generic World.apply alone is insufficient.
	if not receipt.get("patches") is Array or not receipt.get("hook_patches") is Array: return C.fail("COAST_HISTORY_SEMANTICS","Historical effects must be bounded typed arrays.")
	for patch in receipt.patches + receipt.hook_patches:
		if not patch is Dictionary: return C.fail("COAST_HISTORY_SEMANTICS","Historical effects must be typed patch objects.")
	var kind: String = str(receipt.get("branch_id","")).trim_suffix("_success")
	if kind not in ["move","observe","rest","drop_item","pickup_item"] or receipt.get("branch_id") != kind+"_success" or receipt.get("actor_id") != "actor_player": return C.fail("COAST_HISTORY_SEMANTICS","Historical action is outside the five admitted basic actions.")
	var component := "interact" if kind in ["drop_item","pickup_item"] else kind
	if C.bytes(receipt.get("outcomes")) != C.bytes({component:true}) or C.bytes(receipt.get("rolls")) != "[]": return C.fail("COAST_HISTORY_SEMANTICS","Basic safe-direct history cannot invent a random or failed outcome.")
	var bindings := {"actor_id":"actor_player"}
	var refs: Array = [{"id":"actor","path":"/actors/actor_player","expected":before.actors.actor_player}]
	var ref_ids: Array = ["actor"]
	if kind in ["move","observe"]:
		var target: Array = []
		for patch in receipt.get("patches",[]):
			if kind == "move" and patch.get("type") == "actor_move":
				if not patch.get("hex") is Array: return C.fail("COAST_HISTORY_SEMANTICS","Historical movement needs an array coordinate.")
				target = patch.hex
			elif kind == "observe" and patch.get("type") == "flag_set" and patch.get("flag_id") == "last_observed_cell":
				var cell: Dictionary = before.hexes.get(str(patch.get("value","")),{})
				if not cell.is_empty(): target = [cell.q,cell.r]
		if target.size() != 2 or not C.integer(target[0]) or not C.integer(target[1]) or not before.hexes.has("%d,%d" % target): return C.fail("COAST_HISTORY_SEMANTICS","Historical movement or observation lacks a valid target.")
		bindings["target_hex"] = target
		refs.append({"id":"target","path":"/hexes/"+"%d,%d" % target,"expected":before.hexes["%d,%d" % target]}); ref_ids.append("target")
	elif kind in ["drop_item","pickup_item"]:
		bindings["item_id"] = ITEM
		refs.append({"id":"item","path":"/items/"+ITEM,"expected":before.items[ITEM]}); ref_ids.append("item")
	var assessment := {"bindings":bindings,"components":[{"id":component,"parameters":{"A":3,"D":1,"P":0},"fact_ref_ids":ref_ids}],"fact_refs":refs}
	var resolver: RefCounted = ItemResolver.new(self,kind) if kind in ["drop_item","pickup_item"] else Resolver.new(self,kind)
	var plan: Dictionary = resolver.freeze(before,assessment)
	if not plan.get("ok",false): return C.fail("COAST_HISTORY_SEMANTICS","Historical action violates source support, exact route cost, ownership or pickup reach.")
	var expected: Dictionary = plan.branches[0]
	if expected.id != receipt.branch_id or C.bytes(expected.patches) != C.bytes(receipt.patches): return C.fail("COAST_HISTORY_SEMANTICS","Historical effects differ from the trusted action's exact route, cost or custody effects.")
	var candidate: Dictionary = before.duplicate(true)
	for patch in expected.patches:
		var applied: Dictionary = WorldSchema.apply(candidate,patch)
		if not applied.ok: return applied
	var hooks: Dictionary = Hooks.freeze(before,candidate,"actor_player")
	if not hooks.ok or C.bytes(hooks.patches) != C.bytes(receipt.hook_patches): return C.fail("COAST_HISTORY_SEMANTICS","Historical automatic effects differ from the unchanged trusted hooks.")
	return {"ok":true}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result: Dictionary = state.duplicate(true)
	result["natural_coast_source"] = data.duplicate(true)
	return result
