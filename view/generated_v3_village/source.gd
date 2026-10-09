extends RefCounted
## New opt-in authority composed from the frozen inventory source and planner.
## Neither admitted terrain JSON, emitted mesh nor original graph is rewritten.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const InventorySource = preload("res://view/generated_v3_inventory/source.gd")
const BaseSource = preload("res://view/generated_v3_adventure/source.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const Overlay = preload("res://core/generated_v3_placement/navigation_overlay.gd")
const StaticCatalog = preload("res://core/source_entities/static_catalog.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
const PROFILE := "generated_v3_village_inventory/v1"
const PROJECTION_ID := "generated_v3_village_inventory_context/v1"
const WORLD_PREFIX := "generated_v3_village_inventory_v1_"
const ITEM := InventorySource.ITEM
const SCENE := InventorySource.SCENE
const RENDERER_PROFILE := InventorySource.RENDERER_PROFILE
var data: Dictionary = {}
var world: Dictionary = {}
var identity: Dictionary = {}
var renderer_bundle: Dictionary = {}
var placement_result: Dictionary = {}
var spawn_component: Dictionary = {}
var navigation: RefCounted
var inventory_source: RefCounted
var inventory_identity: Dictionary = {}
func admit(value: Variant, renderer_profile: String = RENDERER_PROFILE, persisted_manifest: Variant = null) -> Dictionary:
	var admitted := InventorySource.new()
	var checked: Dictionary = admitted.admit(value,renderer_profile)
	if not checked.ok: return checked
	# Original spawn is input to deterministic placement, never a saved actor hex.
	var origin: Array = admitted.world.actors.actor_player.hex.duplicate()
	var placement: Dictionary
	if persisted_manifest == null:
		placement = Planner.build(admitted.data,admitted.renderer_bundle,admitted.navigation,origin)
	else:
		placement = Planner.validate(persisted_manifest,admitted.data,admitted.renderer_bundle,admitted.navigation,origin)
	if not placement.ok: return placement_error(placement)
	var overlay := Overlay.new()
	checked = overlay.build(admitted.navigation,placement.manifest)
	if not checked.ok: return placement_error(checked)
	var reachable: Dictionary = Planner.distances(overlay.allowed,Planner.key(origin))
	var actual_keys: Array = reachable.keys(); actual_keys.sort()
	var original_keys: Array = admitted.spawn_component.keys(); original_keys.sort()
	if actual_keys != original_keys: return C.fail("V3_VILLAGE_COMPONENT","村落阻断了原本连通的干地，未开启或改变旅程。")
	var effective_component := {}
	for key in actual_keys: effective_component[key] = true
	var catalog: Dictionary = StaticCatalog.build(PROFILE,admitted.identity,placement.manifest)
	if not catalog.ok: return catalog
	var combined: Dictionary = admitted.identity.duplicate(true)
	combined.profile = PROFILE
	combined.projection_id = PROJECTION_ID
	combined["village_inventory_profile"] = PROFILE
	combined["village_inventory_profile_hash"] = profile_digest()
	# Keep base_runtime_hash and the original inventory catalog exactly bound.
	combined["inventory_runtime_hash"] = admitted.identity.runtime_hash
	combined["placement_hash"] = placement.manifest.placement_hash
	combined["placement_profile"] = placement.manifest.profile_id
	combined["placement_context_hash"] = placement.manifest.context_hash
	combined["effective_navigation_id"] = Overlay.ID
	combined["effective_navigation_hash"] = C.digest(overlay.export_data(origin))
	combined["static_entity_catalog"] = catalog.catalog
	combined["static_entity_catalog_hash"] = catalog.catalog.catalog_hash
	combined["static_entity_profile"] = PROFILE
	combined.runtime_hash = runtime_digest(combined)
	var candidate: Dictionary = admitted.world.duplicate(true)
	candidate.world_id = WORLD_PREFIX + admitted.data.content_hash
	candidate.generated_world = C.normalized(combined)
	candidate.story_anchors.anchor_generated_v3_scope.text = "你是一位旅人，可以观察当前或相邻地格、沿已验证的干地移动、原地休息，也可以整件放下或拾回自带的行礼包。村落、建筑和道路是按原地图验证的固定对象，可以选择与观察。建筑会阻挡实际占据的通路，请沿保留的入口通行。选择本身不消耗回合；不能拾取建筑、对话、开关城门、进入室内或触发人物行为。道路不改变地形耗费，河流仍只是原地图资料。"
	checked = StaticCatalog.validate_world(candidate)
	if not checked.ok: return checked
	# Reuse the accepted inventory validator/replay verbatim on this detached
	# combined authority. Its original terrain/catalog hashes remain unchanged.
	inventory_identity = admitted.identity.duplicate(true)
	admitted.world = C.normalized(candidate)
	admitted.immutable = InventorySource.fixed_fields(admitted.world)
	admitted.navigation = overlay
	admitted.spawn_component = effective_component
	admitted.identity = C.normalized(combined)
	checked = admitted.validate_state(admitted.world)
	if not checked.ok: return checked
	data = admitted.data
	world = admitted.world.duplicate(true)
	identity = admitted.identity.duplicate(true)
	renderer_bundle = admitted.renderer_bundle
	placement_result = placement
	navigation = overlay
	spawn_component = admitted.spawn_component.duplicate(true)
	inventory_source = admitted
	return {"ok":true,"identity":identity.duplicate(true),"start":origin,"component_size":spawn_component.size(),"navigation":navigation.diagnostics.duplicate(true)}
static func runtime_digest(metadata: Dictionary) -> String:
	return C.digest({"profile":PROFILE,"profile_hash":metadata.get("village_inventory_profile_hash"),"base_runtime_hash":metadata.get("base_runtime_hash"),"inventory_runtime_hash":metadata.get("inventory_runtime_hash"),"entity_catalog_hash":metadata.get("entity_catalog_hash"),"placement_hash":metadata.get("placement_hash"),"placement_profile":metadata.get("placement_profile"),"placement_context_hash":metadata.get("placement_context_hash"),"effective_navigation_hash":metadata.get("effective_navigation_hash"),"static_entity_catalog_hash":metadata.get("static_entity_catalog_hash")})
static func profile_digest() -> String:
	var hashes := {}
	for path in ["res://view/generated_v3_village/source.gd","res://view/generated_v3_village/adapter.gd","res://view/generated_v3_village/resolver.gd","res://view/generated_v3_village/rule.gd","res://view/generated_v3_village/assessments.gd","res://view/generated_v3_village/projection.gd","res://core/source_entities/static_catalog.gd","res://core/source_entities/static_focus.gd","res://core/source_entities/static_projection.gd","res://core/generated_v3_placement/planner.gd","res://core/generated_v3_placement/navigation_overlay.gd","res://core/generated_v3_placement/surface.gd","res://core/generated_v3_placement/asset_catalog.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return C.digest(hashes)
static func placement_error(result: Dictionary) -> Dictionary:
	var code: String = result.get("code","V3_VILLAGE_PLACEMENT")
	var message := "村落或道路资料与这张地图不一致，未载入或改变旅程。"
	if code == "PLACEMENT_UNAVAILABLE": message = "这张地图没有符合固定条件的村落位置；地形、种子和旅人起点都未改变。"
	elif code == "PLACEMENT_REPRODUCE": message = "村落不能按原地图精确重建，未载入这份进度。"
	return C.fail(code,message)
func validate_state(state: Variant) -> Dictionary:
	if inventory_source == null: return C.fail("V3_VILLAGE_SOURCE","请先开启通过校验的村落旅程。")
	var checked: Dictionary = inventory_source.validate_state(state)
	return StaticCatalog.validate_world(state) if checked.ok else checked
func validate_history(engine_data: Dictionary) -> Dictionary:
	if inventory_source == null: return C.fail("V3_VILLAGE_SOURCE","请先开启通过校验的村落旅程。")
	return inventory_source.validate_history(engine_data)
func static_reference(id: String, clicked_hex: Array = []) -> Dictionary:
	return StaticFocus.make_reference(id,world,clicked_hex) if inventory_source != null else {}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result: Dictionary = state.duplicate(true)
	result["generated_v3_source"] = data.duplicate(true)
	return result
