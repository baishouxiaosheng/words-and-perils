extends SceneTree
const Adapter = preload("res://view/generated_v3_village/adapter.gd")
const Source = preload("res://view/generated_v3_village/source.gd")
const PublicProjection = preload("res://view/generated_v3_village/projection.gd")
const LegacyV3Inventory = preload("res://view/generated_v3_inventory/adapter.gd")
const FocusContract = preload("res://core/focus_contract.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
const StaticCatalog = preload("res://core/source_entities/static_catalog.gd")
const Planner = preload("res://core/generated_v3_placement/planner.gd")
const LegacyV3 = preload("res://view/generated_v3_adventure/adapter.gd")
const LegacyInventory = preload("res://view/generated_inventory/adapter.gd")
const LegacySeeded = preload("res://view/generated_adventure/seeded_adapter.gd")
const SeedContract = preload("res://core/world_generation_contract.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const ItemResolver = preload("res://view/generated_v3_inventory/resolver.gd")
const Examples = preload("res://view/generated_v3_village/assessments.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> bool:
	checks += 1
	if not ok: failures.append(label_); printerr("FAIL "+label_)
	return ok
func roundtrip(adapter: RefCounted, label_: String) -> void:
	var exact := C.bytes(adapter.save_data())
	var restored := Adapter.new(); var result := restored.load_data(JSON.parse_string(exact))
	check(result.ok,label_+" exact reload admitted")
	if not result.ok: printerr(result); return
	check(C.bytes(restored.save_data()) == exact and restored.phase() == adapter.phase(),label_+" retains source, catalog, custody, plans, history and RNG byte-exact")
func execute(adapter: RefCounted, kind: String, focus: Dictionary = {}) -> bool:
	return adapter.begin_intent(adapter.sample_goal(kind,focus),focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok
func reject_load(adapter: RefCounted, value: Dictionary, label_: String) -> void:
	var before := C.bytes(adapter.save_data())
	check(not adapter.load_data(value).ok and C.bytes(adapter.save_data()) == before,label_+" rejects atomically")
func run() -> void:
	if "history_wire" in OS.get_cmdline_user_args():
		numeric_focus_boundary_checks()
		real_board_reload_checks()
		var fixture: Dictionary = Generator.generate(726381,4,"coastal_range")
		if check(fixture.ok,"plain inventory wire fixture generated"): plain_inventory_actor_rest_reload(fixture.source)
		finish()
		return
	var generated := Generator.generate(726381,4,"coastal_range")
	if not check(generated.ok,"exact V3 fixture generated"): finish(); return
	var raw: Dictionary = generated.source; var raw_bytes := C.bytes(raw)
	var malformed := raw.duplicate(true); malformed.schema_version = "unsupported"
	var rejected := Adapter.new(malformed)
	check(not rejected.ready().ok and rejected.state_copy().is_empty(),"rejected source never installs a traveler or bundle")
	var rejected_renderer := Adapter.new(raw,"alternative_b")
	check(not rejected_renderer.ready().ok and rejected_renderer.state_copy().is_empty(),"unsupported renderer never changes source or injects inventory")
	var a := Adapter.new()
	check(not a.ready().ok and a.state_copy().is_empty(),"blank profile has no inherited test-world or item")
	if not check(a.start_source(raw).ok,"explicit V3 inventory start admits original source"): printerr(a.ready()); finish(); return
	var initial := a.state_copy(); var start: Array = initial.actors.actor_player.hex
	var initial_rng := C.bytes(a.engine.save_data().rng)
	check(C.bytes(a.source.data) == raw_bytes and C.bytes(raw) == raw_bytes,"raw caller/source JSON never changes")
	check(a.source.identity.profile == Source.PROFILE and a.source.identity.entity_profile == "generated_v3_inventory/v1" and initial.world_id == Source.WORLD_PREFIX+raw.content_hash,"new explicit source profile and world namespace")
	check(initial.items.keys() == [Source.ITEM] and initial.items[Source.ITEM].quantity == 1 and initial.items[Source.ITEM].owner_actor_id == "actor_player" and initial.actors.actor_player.inventory == [Source.ITEM],"exactly one initial registered carried bundle")
	check(not a.start_source(raw).ok and C.bytes(a.state_copy()) == C.bytes(initial),"second admission cannot inject or reset supply")
	var item_ref := a.item_reference(); var before := C.bytes(a.save_data())
	check(not item_ref.is_empty() and a.attention(item_ref).ok,"source-independent catalog item focus resolves")
	check(a.attention(item_ref).readonly and C.bytes(a.save_data()) == before,"repeated item selection is read only")
	for field in ["id","world_id","catalog_id"]:
		var bad_ref := item_ref.duplicate(true); bad_ref[field] = "stale"
		check(not a.attention(bad_ref).ok and C.bytes(a.save_data()) == before,"stale item "+field+" fails without mutation")
	var projected := ModelView.facts(initial,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]},item_ref)
	check(projected.context_scope.schema_version == PublicProjection.ID and projected.items[Source.ITEM] == initial.items[Source.ITEM] and projected.hexes.size() <= 62,"new bounded model projector includes exact public item facts")
	check(not projected.has("generated_world") and not projected.has("generated_v3_source") and not projected.has("rng") and not projected.has("receipts"),"projection excludes raw source, RNG and private history")
	var broken := initial.duplicate(true); broken.generated_world.projection_id = "stale"
	check(PublicProjection.active(broken) and ModelView.facts(broken,{"npc_secret_allowlist":[],"public_flag_ids":[]}).is_empty(),"malformed profile remains closed, never falls back")
	placement_and_static_checks(a,raw)
	roundtrip(a,"idle")
	check(a.begin_intent("把行礼包放下",item_ref).ok and not a.fixture_available() and not a.roll_once().ok,"ordinary text waits for assessment without keyword execution")
	reject_pending_extension(a,"item")
	roundtrip(a,"unassessed pending")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(initial) and C.bytes(a.engine.save_data().rng) == initial_rng,"pending cancel preserves item and RNG")
	before = C.bytes(a.save_data()); check(not a.cancel().ok and C.bytes(a.save_data()) == before,"duplicate cancel cannot consume an ID or alter state")
	roundtrip(a,"canceled")
	check(a.begin_intent(a.sample_goal("drop_item"),item_ref).ok,"exact authored drop starts")
	var request := a.request()
	check(request.contract.resolver_ids == ["generated_v3_drop_item_v1","generated_v3_move_v1","generated_v3_observe_v1","generated_v3_pickup_item_v1","generated_v3_rest_v1"],"five-action closed registry, no equip/use/transfer/NPC/creation")
	check(C.bytes(request).to_utf8_buffer().size() <= Adapter.MAX_REQUEST_BYTES,"request retains original 64 KiB bound")
	var manual: Dictionary = Examples.build(request).assessment
	manual.provenance = {"provider":"offline_test","live":false,"kind":"model_reply"}
	manual.resolver_id = "generated_v3_equip_item_v1"; before = C.bytes(a.save_data())
	check(not a.import_reply(manual).ok and C.bytes(a.save_data()) == before,"unregistered equipment resolver cannot gain authority")
	manual.resolver_id = "generated_v3_drop_item_v1"; manual.bindings.item_id = "invented_loot"
	check(not a.import_reply(manual).ok and C.bytes(a.save_data()) == before,"unregistered item binding cannot create or move loot")
	check(a.prepare_fixture().ok and a.action_copy().checks[0].method == "direct_success","shared ownership policy creates direct success after assessment")
	roundtrip(a,"ready")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(initial),"ready drop cancels without loss")
	check(a.begin_intent(a.sample_goal("drop_item"),item_ref).ok and a.prepare_fixture().ok and a.roll_once().ok,"new assessed drop locks")
	before = C.bytes(a.save_data())
	check(a.roll_once().ok and not a.cancel().ok and C.bytes(a.save_data()) == before,"locked drop never rerolls or cancels")
	check(C.bytes(a.engine.save_data().rng) == initial_rng and C.bytes(a.state_copy()) == C.bytes(initial),"direct lock consumes no entropy and moves no item")
	roundtrip(a,"locked")
	check(a.stage().ok and C.bytes(a.state_copy()) == C.bytes(initial),"staged drop is preview only")
	roundtrip(a,"staged")
	check(a.commit().ok,"whole-stack drop commits")
	var dropped := a.state_copy()
	check(dropped.items[Source.ITEM].hex == start and dropped.items[Source.ITEM].scene_id == Source.SCENE and not dropped.items[Source.ITEM].has("owner_actor_id") and dropped.items[Source.ITEM].custody_revision == 1 and dropped.actors.actor_player.inventory.is_empty() and dropped.turn == 1,"drop keeps one ID/quantity and relocates at feet once")
	for water_key in a.source.navigation.supported:
		if not a.source.navigation.supported[water_key]:
			var unsupported := dropped.duplicate(true); var wet_cell: Dictionary = unsupported.hexes[water_key]
			unsupported.items[Source.ITEM].hex = [wet_cell.q,wet_cell.r]
			check(not a.source.validate_state(unsupported).ok,"ground custody cannot rest on unsupported or wet geometry")
			break
	check(not a.attention(item_ref).ok and a.attention(a.item_reference()).ok,"custody update makes old live ref stale")
	before = C.bytes(a.save_data()); check(a.commit().get("already_committed",false) and C.bytes(a.save_data()) == before,"duplicate commit preserves byte-exact state/history/RNG")
	roundtrip(a,"committed drop with historical carried focus")
	check(a.begin_intent(a.sample_goal("drop_item"),a.item_reference()).ok and not a.prepare_fixture().ok and C.bytes(a.state_copy()) == C.bytes(dropped),"cannot drop an unowned ground item")
	check(a.cancel().ok,"rejected ownership assessment cancels")
	check(execute(a,"pickup_item",a.item_reference()),"current-cell pickup succeeds")
	check(a.state_copy().items[Source.ITEM].owner_actor_id == "actor_player" and a.state_copy().items[Source.ITEM].custody_revision == 2,"pickup restores one owner/inventory with monotonic revision")
	check(a.begin_intent(a.sample_goal("pickup_item"),a.item_reference()).ok and not a.prepare_fixture().ok,"already-carried pickup rejects duplication")
	check(a.cancel().ok,"duplicate pickup rejection cancels")
	check(execute(a,"drop_item",a.item_reference()),"later genuine drop remains legal")
	var from_key: String = "%d,%d" % start
	var neighbor: String = a.source.navigation.allowed[from_key][0]
	var cell: Dictionary = a.state_copy().hexes[neighbor]; var target := [cell.q,cell.r]
	check(execute(a,"move",a.tile_reference(target)),"original V3 move works with ground item")
	# A locally modified graph tests the wrapper's exact-edge guard, without
	# replacing source data or persisting an altered authority.
	check(a.begin_intent(a.sample_goal("pickup_item"),a.item_reference()).ok,"neighbor pickup request prepared")
	var built := Examples.build(a.request())
	var edges: Array = a.source.navigation.allowed[neighbor].duplicate()
	a.source.navigation.allowed[neighbor].erase(from_key)
	check(not ItemResolver.new(a.source,"pickup_item").freeze(a.state_copy(),built.assessment).ok,"geometric adjacency without verified dry edge cannot pick up")
	a.source.navigation.allowed[neighbor] = edges
	check(a.prepare_fixture().ok and a.roll_once().ok and a.stage().ok and a.commit().ok,"verified adjacent dry pickup succeeds with unchanged shared resolver")
	var carried_ref := a.item_reference()
	check(execute(a,"move",a.tile_reference(start)),"carry follows traveler through original movement")
	check(not a.attention(carried_ref).ok and a.attention(a.item_reference()).ok,"owner movement invalidates old effective support reference")
	check(execute(a,"observe",a.tile_reference(start)) and execute(a,"rest"),"original observation/rest rules and authored examples remain")
	roundtrip(a,"five-action history and changed owner support")
	check(C.bytes(a.source.data) == raw_bytes and C.bytes(a.engine.save_data().rng) == initial_rng,"all five direct actions preserve source and RNG")
	check(execute(a,"drop_item",a.item_reference()),"drop for distant range test")
	var distant: Array = []
	for possible in a.state_copy().hexes.values():
		var dq: int = possible.q-start[0]; var dr: int = possible.r-start[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) > 1 and a.movement_preview([possible.q,possible.r]).ok: distant = [possible.q,possible.r]; break
	check(not distant.is_empty() and execute(a,"move",a.tile_reference(distant)),"real dry route reaches distant cell")
	before = C.bytes(a.state_copy())
	check(a.begin_intent(a.sample_goal("pickup_item"),a.item_reference()).ok and not a.prepare_fixture().ok and C.bytes(a.state_copy()) == before,"distant pickup cannot teleport ground item")
	check(a.cancel().ok,"distant rejected action cancels")
	# State-only tampering cannot be justified by revision parity or a valid map.
	var corrupt := a.save_data(); corrupt.engine.state.items[Source.ITEM].custody_revision += 1
	reject_load(a,corrupt,"forged current custody revision")
	corrupt = a.save_data(); corrupt.engine.state.items[Source.ITEM].hex = distant.duplicate()
	reject_load(a,corrupt,"forged supported current ground location")
	corrupt = a.save_data(); corrupt.engine.state.items[Source.ITEM].erase("hex"); corrupt.engine.state.items[Source.ITEM].erase("scene_id"); corrupt.engine.state.items[Source.ITEM].owner_actor_id = "actor_player"; corrupt.engine.state.actors.actor_player.inventory = [Source.ITEM]
	reject_load(a,corrupt,"forged current owner")
	corrupt = a.save_data(); corrupt.engine.state.items[Source.ITEM].quantity = 2
	reject_load(a,corrupt,"injected quantity")
	corrupt = a.save_data(); corrupt.engine.state.items[Source.ITEM].interaction_profile.equip_slot = "weapon"
	reject_load(a,corrupt,"injected equipment capability")
	corrupt = a.save_data(); corrupt.engine.state.actors.actor_player.inventory = [Source.ITEM,Source.ITEM]
	reject_load(a,corrupt,"duplicate inventory references")
	corrupt = a.save_data(); corrupt.engine.state.generated_world.entity_catalog.entries[Source.ITEM].name = "forged"
	reject_load(a,corrupt,"forged immutable catalog")
	var history: Dictionary = a.engine.save_data(); var receipt_ids: Array = history.receipts.keys()
	receipt_ids.sort_custom(func(x,y): return int(history.receipts[x].turn) < int(history.receipts[y].turn))
	history.receipts.erase(receipt_ids[0]); check(not a.source.validate_history(history).ok,"replay rejects missing receipt")
	history = a.engine.save_data(); history.receipts[receipt_ids[1]].turn = history.receipts[receipt_ids[0]].turn
	check(not a.source.validate_history(history).ok,"replay rejects duplicate receipt turn")
	history = a.engine.save_data(); history.receipts[receipt_ids[0]].before_version += 1
	check(not a.source.validate_history(history).ok,"replay rejects gapped receipt version")
	corrupt = a.save_data()
	var first_receipt: Dictionary = corrupt.engine.receipts[receipt_ids[0]]
	var forged_focus: Dictionary = first_receipt.attention_focus
	forged_focus.hex = target.duplicate()
	forged_focus.facts.supporting_cell = corrupt.engine.state.hexes[neighbor].duplicate(true)
	forged_focus.facts.custody_witness.hex = target.duplicate()
	var receipt_payload: Dictionary = first_receipt.duplicate(true); receipt_payload.erase("receipt_hash")
	first_receipt.receipt_hash = C.digest(receipt_payload)
	check(a.source.validate_history(corrupt.engine).get("code") == "V3_INVENTORY_HISTORY_FOCUS","reconstructed pre-action state rejects consistently forged historical owner support")
	reject_load(a,corrupt,"rehashed historical carried location/support/witness forgery")
	check(a.source.validate_history(a.engine.save_data()).ok,"unaltered complete committed replay remains valid")
	# Cross-profile sources/save envelopes are never migrated or injected.
	var old := LegacyV3.new(raw); var old_bytes := C.bytes(old.save_data())
	check(C.bytes(a.source.data) == C.bytes(old.source.data) and a.source.identity.geometry_hash == old.source.identity.geometry_hash and a.source.identity.base_runtime_hash == old.source.identity.runtime_hash,"inventory retains exact original source, emitted geometry and base runtime identity")
	check(C.bytes(a.source.navigation.base.allowed) == C.bytes(old.source.navigation.allowed) and C.bytes(a.source.navigation.supported) == C.bytes(old.source.navigation.supported) and C.bytes(a.source.spawn_component) == C.bytes(old.source.spawn_component),"combined overlay preserves exact underlying terrain graph and connected spawn component")
	var inventory_mesh: Array = a.source.renderer_bundle.ground_mesh.surface_get_arrays(0)
	var original_mesh: Array = old.source.renderer_bundle.ground_mesh.surface_get_arrays(0)
	check(inventory_mesh[Mesh.ARRAY_VERTEX] == original_mesh[Mesh.ARRAY_VERTEX] and inventory_mesh[Mesh.ARRAY_INDEX] == original_mesh[Mesh.ARRAY_INDEX],"renderer retains byte-exact original emitted vertices and triangle indices")
	check(old.ready().ok and old.state_copy().items.is_empty() and old.state_copy().actors.actor_player.inventory.is_empty(),"accepted V3 exploration stays item-free")
	reject_load(a,old.save_data(),"old V3 save")
	check(not old.load_data(a.save_data()).ok and C.bytes(old.save_data()) == old_bytes,"old V3 rejects inventory save byte-exact")
	var envelope := SeedContract.generate("雪岸-行囊","compact_coast",4)
	var old_inventory := LegacyInventory.new(); check(old_inventory.start_seeded(envelope).ok,"accepted V2 inventory still starts")
	var old_inventory_bytes := C.bytes(old_inventory.save_data()); var old_copy := LegacyInventory.new()
	check(old_copy.load_data(JSON.parse_string(old_inventory_bytes)).ok and C.bytes(old_copy.save_data()) == old_inventory_bytes,"accepted V2 inventory save stays byte-exact")
	reject_load(a,old_inventory.save_data(),"old V2 inventory save")
	check(not old_inventory.load_data(a.save_data()).ok and C.bytes(old_inventory.save_data()) == old_inventory_bytes,"V2 inventory rejects V3 inventory without mutation")
	var seeded := LegacySeeded.new(); check(seeded.start_seeded(envelope).ok and seeded.state_copy().items.is_empty(),"accepted V2 exploration receives no item injection")
	check(not a.load_data(a.engine.save_data()).ok,"raw engine save cannot migrate into profile")
	check(a.default_save_path() == Adapter.VILLAGE_SAVE and a.default_request_path() == Adapter.VILLAGE_REQUEST,"save and request have new independent defaults")
	for path in [LegacyV3Inventory.INVENTORY_SAVE,LegacyV3Inventory.INVENTORY_REQUEST,LegacyV3.GENERATED_SAVE,LegacyV3.V3_REQUEST,"user://generated_inventory_v1.json","user://generated_adventure_v2.json","user://generated_adventure_request_v1.json"]:
		var hash_before := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(not a.save_file(path).ok and not a.export_request(path).ok and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == hash_before,"protected old namespace untouched "+path)
	check(not a.save_file(a.default_request_path()).ok and not a.export_request(a.default_save_path()).ok,"save/request defaults cannot collide")
	var path := "user://v3_village_suite_save.json"
	check(a.save_file(path).ok,"own profile atomic file save")
	var disk := FileAccess.get_file_as_string(path); var loaded := Adapter.new()
	check(loaded.load_file(path).ok and C.bytes(loaded.save_data()) == C.bytes(a.save_data()),"actual save file roundtrip is exact")
	DirAccess.make_dir_absolute(path+".tmp"); before = C.bytes(a.save_data())
	check(not a.save_file(path).ok and FileAccess.get_file_as_string(path) == disk and C.bytes(a.save_data()) == before,"failed temporary write loses neither old file nor item/RNG")
	DirAccess.remove_absolute(path+".tmp")
	var request_path := "user://v3_village_suite_request.json"
	check(a.export_request(request_path).ok and a.export_request(request_path).ok,"own valid narration request can be exported repeatedly")
	check(not a.save_file(request_path).ok and not a.export_request(path).ok,"recognized save/request schemas cannot overwrite each other")
	var unrelated := "user://v3_village_suite_unrelated.json"
	var file := FileAccess.open(unrelated,FileAccess.WRITE); file.store_string('{"note":"preserve"}'); file.close()
	check(not a.save_file(unrelated).ok and not a.export_request(unrelated).ok and FileAccess.get_file_as_string(unrelated) == '{"note":"preserve"}',"arbitrary existing JSON is never overwritten")
	DirAccess.remove_absolute(unrelated)
	var accepted_inventory := LegacyV3Inventory.new(raw)
	var inventory_bytes := C.bytes(accepted_inventory.save_data())
	check(accepted_inventory.ready().ok and a.source.identity.inventory_runtime_hash == accepted_inventory.source.identity.runtime_hash,"original inventory runtime identity is separately retained")
	check(C.bytes(a.source.identity.entity_catalog) == C.bytes(accepted_inventory.source.identity.entity_catalog),"current inventory catalog remains exactly bound")
	reject_load(a,accepted_inventory.save_data(),"accepted inventory save")
	check(not accepted_inventory.load_data(a.save_data()).ok and C.bytes(accepted_inventory.save_data()) == inventory_bytes,"accepted inventory rejects combined save without mutation")
	var reset: RefCounted = a.restarted()
	check(reset.ready().ok and reset.state_copy().turn == 0 and reset.state_copy().actors.actor_player.inventory == [Source.ITEM] and C.bytes(reset.source.data) == raw_bytes and C.bytes(reset.source.identity) == C.bytes(a.source.identity),"explicit restart alone recreates one starting bundle and exact source identity")
	check(FileAccess.get_file_as_string(path) == disk,"explicit restart never overwrites saved journey")
	static_history_checks(reset)
	request_budget_checks(reset,"radius4")
	var large_generated: Dictionary = Generator.generate(726381,12,"coastal_range")
	if check(large_generated.ok,"radius12 budget fixture generated"):
		var large := Adapter.new(large_generated.source)
		if check(large.ready().ok,"radius12 combined budget fixture admitted"): request_budget_checks(large,"radius12")
	numeric_focus_boundary_checks()
	real_board_reload_checks()
	plain_inventory_actor_rest_reload(raw)
	finish()
func finish() -> void:
	print("V3 VILLAGE ADAPTER ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)

func placement_and_static_checks(a: RefCounted, raw: Dictionary) -> void:
	var manifest: Dictionary = a.source.placement_result.manifest
	var original := LegacyV3Inventory.new(raw)
	check(original.ready().ok,"independent inventory comparison admission")
	check(C.bytes(manifest.origin_hex) == C.bytes(original.state_copy().actors.actor_player.hex),"placement determinism binds original inventory starting actor hex")
	check(a.source.identity.base_runtime_hash == original.source.identity.base_runtime_hash and a.source.identity.inventory_runtime_hash == original.source.identity.runtime_hash,"terrain and inventory runtime identities remain distinct")
	check(a.source.identity.placement_hash == manifest.placement_hash and a.source.identity.placement_profile == manifest.profile_id and a.source.identity.effective_navigation_hash == C.digest(a.source.navigation.export_data(manifest.origin_hex)),"new identity binds validated placement and effective graph separately")
	check(C.bytes(a.source.data) == C.bytes(original.source.data),"placement never mutates original source JSON")
	var before_mesh: Array = original.source.renderer_bundle.ground_mesh.surface_get_arrays(0)
	var after_mesh: Array = a.source.renderer_bundle.ground_mesh.surface_get_arrays(0)
	check(before_mesh[Mesh.ARRAY_VERTEX].to_byte_array() == after_mesh[Mesh.ARRAY_VERTEX].to_byte_array() and before_mesh[Mesh.ARRAY_INDEX].to_byte_array() == after_mesh[Mesh.ARRAY_INDEX].to_byte_array(),"placement leaves native mesh byte-exact")
	check(manifest.blocked_edges.size() > 0,"combined source retains real physical obstruction")
	for edge in manifest.blocked_edges:
		check(original.source.navigation.step(edge.from,edge.to).ok and not a.source.navigation.step(edge.from,edge.to).ok and not a.source.navigation.step(edge.to,edge.from).ok,"building removes an actual symmetric terrain edge")
	# Detached resolver-only fixture: it grants no state/history admission. This
	# tests a real planner-removed edge, rather than geometric distance alone.
	var blocked: Dictionary = manifest.blocked_edges[0]
	var blocked_state: Dictionary = a.state_copy()
	blocked_state.actors.actor_player.hex = blocked.from.duplicate()
	blocked_state.actors.actor_player.inventory = []
	blocked_state.items[Source.ITEM].erase("owner_actor_id")
	blocked_state.items[Source.ITEM].hex = blocked.to.duplicate()
	blocked_state.items[Source.ITEM].scene_id = Source.SCENE
	var blocked_example := Examples.build({"action_id":"detached_fixture","state_version":0,"context_hash":"0".repeat(64),"context":{"facts":PublicProjection.facts(blocked_state),"goal":Examples.goal("pickup_item"),"actor_id":"actor_player"}})
	check(blocked_example.ok and ItemResolver.new(a.source,"pickup_item").freeze(blocked_state,blocked_example.assessment).get("code") == "GENERATED_ITEM_REACH","existing item resolver rejects pickup through an actual village obstruction")
	var road: Array = manifest.roads[0].route_hexes
	check(a.source.navigation.step(road[0],road[1]).ok and a.source.navigation.route_points(road).size() >= 2,"entry road remains a real unobstructed edge")
	var connected := Planner.distances(a.source.navigation.allowed,Planner.key(manifest.origin_hex))
	check(connected.size() == a.source.spawn_component.size() and connected.has(Planner.key(road[0])) and connected.has(Planner.key(road[1])),"original connected dry component and village entry remain reachable")
	var saved: String = C.bytes(a.save_data())
	var catalog: Dictionary = a.state_copy().generated_world.static_entity_catalog
	check(catalog.entries.size() == 5 and StaticCatalog.validate_world(a.state_copy()).ok,"exact fixed settlement, three buildings and road are registered")
	for id in catalog.entries:
		var reference: Dictionary = a.static_reference(id)
		check(not reference.is_empty() and a.attention(reference).ok and a.attention(reference).readonly,"registered static target resolves as read-only selection "+id)
		check(C.bytes(a.save_data()) == saved,"static selection changes no facts, action, RNG or history")
		var resolved := StaticFocus.resolve(reference,a.state_copy())
		if resolved.ok:
			check(StaticFocus.validate_historical(resolved.focus,a.state_copy()).is_empty(),"exact static historical witness validates")
			var forged: Dictionary = resolved.focus.duplicate(true)
			forged.facts.descriptor.name = "伪造对象"
			check(not StaticFocus.validate_historical(forged,a.state_copy()).is_empty(),"changed frozen static descriptor rejected")
		var stale: Dictionary = reference.duplicate(true); stale.catalog_id = "stale"
		check(not a.attention(stale).ok and C.bytes(a.save_data()) == saved,"stale static catalog selection is atomic")
		var focused := ModelView.facts(a.state_copy(),{"npc_secret_allowlist":[],"public_flag_ids":[]},reference)
		check(focused.context_scope.schema_version == PublicProjection.ID and focused.static_entities.has(id) and focused.hexes.size() <= 62,"bounded combined projector includes explicitly selected static descriptor")
		check(not focused.generated_source.has("static_entity_catalog") and not focused.has("placement_manifest") and not focused.has("allowed_neighbors"),"projection excludes full static catalog, placement manifest and navigation graph")
	for field in ["profile","projection_id","static_entity_profile","village_inventory_profile","runtime_hash","inventory_runtime_hash","placement_hash","effective_navigation_hash"]:
		var malformed: Dictionary = a.state_copy(); malformed.generated_world[field] = "stale"
		check(PublicProjection.active(malformed) and ModelView.facts(malformed,{"npc_secret_allowlist":[],"public_flag_ids":[]}).is_empty(),"malformed combined marker fails closed: "+field)
	var broken_metadata: Dictionary = a.state_copy(); broken_metadata.generated_world = []
	check(PublicProjection.active(broken_metadata) and ModelView.facts(broken_metadata,{"npc_secret_allowlist":[],"public_flag_ids":[]}).is_empty(),"world prefix keeps malformed non-object metadata fail-closed")
	var tampered: Dictionary = a.save_data()
	tampered.placement_manifest.buildings[0].position[0] += .25
	tampered.placement_manifest.erase("placement_hash")
	tampered.placement_manifest.placement_hash = C.digest(tampered.placement_manifest)
	tampered.identity.placement_hash = tampered.placement_manifest.placement_hash
	tampered.engine.state.generated_world.placement_hash = tampered.placement_manifest.placement_hash
	var result: Dictionary = a.load_data(tampered)
	check(not result.ok and result.get("code") == "PLACEMENT_REPRODUCE" and C.bytes(a.save_data()) == saved,"rehashed saved placement cannot bypass exact Planner.validate reproduction")
	tampered = a.save_data(); tampered.placement_manifest.origin_hex = manifest.settlements[0].center_hex.duplicate()
	tampered.placement_manifest.erase("placement_hash"); tampered.placement_manifest.placement_hash = C.digest(tampered.placement_manifest)
	reject_load(a,tampered,"rehashed saved placement using another origin")

func static_history_checks(a: RefCounted) -> void:
	if not a.ready().ok: return
	var manifest: Dictionary = a.source.placement_result.manifest
	var target: Array = manifest.settlements[0].center_hex
	var planned: Dictionary = a.source.navigation.plan(a.state_copy(),target,999)
	if not check(planned.ok,"village target has verified route from original spawn"): return
	for i in range(1,planned.route.size()):
		var step: Array = planned.route[i]
		var cost: int = preload("res://core/ai_gm_rebuilt/traversal_policy.gd").COSTS[a.state_copy().hexes[Planner.key(step)].terrain]
		while a.state_copy().actors.actor_player.stamina.current < cost:
			if not check(execute(a,"rest"),"rest before walking to village"): return
		if not check(execute(a,"move",a.tile_reference(step)),"walk verified clear entry route"): return
	var id: String = manifest.buildings[0].id
	var reference: Dictionary = a.static_reference(id)
	var static_before := C.bytes(a.state_copy().generated_world.static_entity_catalog)
	check(a.begin_intent(a.sample_goal("observe",reference),reference).ok,"static observation begins with exact frozen building focus")
	reject_pending_extension(a,"static")
	roundtrip(a,"unassessed static pending")
	check(a.prepare_fixture().ok and a.roll_once().ok and a.stage().ok and a.commit().ok,"static building focus supports existing assessed cell observation")
	check(C.bytes(a.state_copy().generated_world.static_entity_catalog) == static_before,"observation cannot mutate fixed physical object")
	var receipt_id: String = a.last_action
	var frozen: Dictionary = a.engine.save_data().receipts[receipt_id].attention_focus
	check(frozen.kind == "building" and StaticFocus.validate_historical(frozen,a.state_copy()).is_empty(),"committed static focus keeps exact immutable witness")
	roundtrip(a,"committed static observation")
	var tampered: Dictionary = a.save_data()
	var receipt: Dictionary = tampered.engine.receipts[receipt_id]
	receipt.attention_focus.facts.descriptor.name = "伪造村屋"
	var unsigned: Dictionary = receipt.duplicate(true); unsigned.erase("receipt_hash"); receipt.receipt_hash = C.digest(unsigned)
	reject_load(a,tampered,"rehashed historical static witness")
	check(a.begin_intent(a.sample_goal("pickup_item"),reference).ok,"static selection does not invent an item binding")
	var assessment: Dictionary = Examples.build(a.request()).assessment
	assessment.bindings.item_id = id
	assessment.provenance = {"provider":"offline_test","live":false,"kind":"model_reply"}
	var before := C.bytes(a.save_data())
	check(not a.import_reply(assessment).ok and C.bytes(a.save_data()) == before,"static building cannot become pickup or inventory item")
	check(a.cancel().ok,"unsupported static-item assessment remains cancelable")

func request_budget_checks(a: RefCounted, label_: String) -> void:
	var catalog: Dictionary = a.state_copy().generated_world.static_entity_catalog
	var goal_: String = "x".repeat(Adapter.MAX_GOAL_BYTES)
	check(goal_.to_utf8_buffer().size() == 4096,label_+" full 4096-byte goal fixture")
	var maximum := 0
	var maximum_request: Dictionary = {}
	var maximum_focus: Dictionary = {}
	for id in catalog.entries:
		var descriptor: Dictionary = catalog.entries[id]
		var supports: Array = descriptor.supported_hexes if descriptor.kind == "road" else [descriptor.primary_hex]
		for support in supports:
			var reference: Dictionary = a.static_reference(id,support)
			var started: Dictionary = a.begin_intent(goal_,reference)
			if not check(started.ok,label_+" maximum-goal static request admitted "+id+" "+str(support)):
				printerr(started)
				continue
			var request_: Dictionary = a.request()
			var size_: int = C.bytes(request_).to_utf8_buffer().size()
			if size_ > maximum:
				maximum = size_
				maximum_request = request_.duplicate(true)
				maximum_focus = reference.duplicate(true)
			check(size_ <= Adapter.MAX_REQUEST_BYTES and request_.context.facts.hexes.size() <= 62,label_+" complete static request remains within 64KiB and cell bound")
			print("V3 VILLAGE REQUEST_BYTES ",label_," ",descriptor.kind," ",id," support=",support," bytes=",size_)
			check(a.cancel().ok,label_+" budget probe leaves no active action")
	print("V3 VILLAGE MAX_REQUEST_BYTES ",label_," ",maximum)
	if check(not maximum_request.is_empty(),label_+" maximum request is retained for independent context QA"):
		retain_budget_artifacts(a,label_,maximum_request,maximum_focus,maximum)

func reject_pending_extension(a: RefCounted, label_: String) -> void:
	var tampered: Dictionary = a.save_data()
	var action_id: String = a.active_action
	check(tampered.engine.pending.has(action_id),label_+" adversarial fixture has a real saved pending action")
	if not tampered.engine.pending.has(action_id): return
	var action: Dictionary = tampered.engine.pending[action_id]
	# This field is safe JSON and intentionally absent from the public focus
	# projector, so the original context hash remains valid. Only exact frozen
	# catalog focus validation can close the pending-to-history schema gap.
	action.focus["safe_unknown_extension"] = {"note":"not an authorized catalog focus field","revision":1}
	check(C.safe(action.focus),label_+" unknown focus extension is JSON-safe")
	check(C.digest(a.engine._context(action)) == action.context_hash,label_+" extension keeps projected context hash valid and must fail exact focus validation")
	reject_load(a,tampered,"saved pending "+label_+" focus unknown top-level extension")

func real_board_reload_checks() -> void:
	for recipe in ["coastal_range","plateau_hinterland"]:
		var path: String = "res://tests/generated_v3_village/fixtures/history_wire/valid_r12_"+recipe+"_journey.json"
		var original_sha: String = FileAccess.get_sha256(path)
		var original_text: String = FileAccess.get_file_as_string(path)
		var wire: Variant = JSON.parse_string(original_text)
		if not check(wire is Dictionary and wire.get("engine") is Dictionary,recipe+" real radius12 closed board checkpoint is readable"): continue
		var exact: String = C.bytes(wire)
		var restored := Adapter.new()
		var loaded: Dictionary = restored.load_data(wire)
		if not check(loaded.ok,recipe+" real move/rest/entry/drop/pickup checkpoint loads after JSON parse"):
			printerr("BOARD_RELOAD_DIAGNOSTIC ",recipe," ",loaded)
			continue
		check(C.bytes(restored.save_data()) == exact,recipe+" real checkpoint source/catalog/placement/history/RNG stays byte-exact")
		check(restored.source.validate_history(wire.engine).ok,recipe+" raw wire numeric types replay all historical actor and item focuses")
		check(restored.state_copy().turn == wire.engine.state.turn and restored.state_copy().items[Source.ITEM].owner_actor_id == "actor_player" and restored.state_copy().items[Source.ITEM].custody_revision == 2,recipe+" journey resumes with recorded completed bundle roundtrip")
		check(FileAccess.get_sha256(path) == original_sha and C.bytes(wire) == exact,recipe+" real checkpoint and caller-owned wire data remain untouched")

func plain_inventory_actor_rest_reload(raw: Dictionary) -> void:
	var plain := LegacyV3Inventory.new(raw)
	if not check(plain.ready().ok,"plain frozen inventory admits actor-rest regression source"): return
	var start: Array = plain.state_copy().actors.actor_player.hex
	var neighbors: Array = plain.source.navigation.allowed[Planner.key(start)]
	if not check(not neighbors.is_empty(),"plain inventory actor-rest regression has legal move"): return
	var cell: Dictionary = plain.state_copy().hexes[neighbors[0]]
	if not check(execute(plain,"move",plain.tile_reference([cell.q,cell.r])),"plain inventory moves before actor-focused rest"): return
	var state: Dictionary = plain.state_copy()
	var actor_ref := {"world_id":state.world_id,"kind":"actor","id":"actor_player","hex":state.actors.actor_player.hex.duplicate(),"scene_id":Source.SCENE}
	if not check(execute(plain,"rest",actor_ref),"plain inventory commits actor-focused rest after move"): return
	var exact: String = C.bytes(plain.save_data())
	var wire: Dictionary = JSON.parse_string(exact)
	check(plain.source.validate_history(wire.engine).ok,"frozen inventory replay accepts numerically equal JSON actor coordinates")
	var restored := LegacyV3Inventory.new()
	var loaded: Dictionary = restored.load_data(wire)
	if not check(loaded.ok,"plain inventory move then actor-rest survives JSON reload"):
		printerr("PLAIN_INVENTORY_RELOAD_DIAGNOSTIC ",loaded)
		return
	check(C.bytes(restored.save_data()) == exact and C.bytes(wire) == exact and C.bytes(plain.save_data()) == exact,"plain inventory complete save and caller wire remain byte-exact")

func numeric_focus_boundary_checks() -> void:
	# Detached minimal focus fixture only; never offered as an admitted world.
	var snapshot := {"world_id":"numeric_focus_boundary","scenes":{Source.SCENE:{"id":Source.SCENE}},"actors":{"actor_player":{"id":"actor_player","name":"旅人","hex":[2,-1],"scene_id":Source.SCENE,"inventory":[],"health":{"current":12,"max":12},"stamina":{"current":6,"max":8}}},"hexes":{"2,-1":{"id":"hex_2_-1","q":2,"r":-1,"scene_id":Source.SCENE,"terrain":"grass"}}}
	var reference := {"world_id":snapshot.world_id,"kind":"actor","id":"actor_player","hex":[2,-1],"scene_id":Source.SCENE}
	var contract := FocusContract.new()
	var exact_state: PackedByteArray = var_to_bytes(snapshot)
	var float_reference: Dictionary = JSON.parse_string(C.bytes(reference))
	var exact_float_ref: PackedByteArray = var_to_bytes(float_reference)
	check(float_reference.hex[0] is float and snapshot.actors.actor_player.hex[0] is int,"numeric-boundary fixture preserves JSON float versus native integer types")
	var resolved: Dictionary = contract.resolve(float_reference,snapshot)
	check(resolved.ok and C.bytes(resolved.focus.hex) == C.bytes(reference.hex),"integral JSON float actor reference resolves against integer snapshot")
	check(var_to_bytes(snapshot) == exact_state and var_to_bytes(float_reference) == exact_float_ref,"float-reference resolution mutates neither snapshot nor reference")
	var float_snapshot: Dictionary = JSON.parse_string(C.bytes(snapshot))
	var exact_float_state: PackedByteArray = var_to_bytes(float_snapshot)
	var exact_ref: PackedByteArray = var_to_bytes(reference)
	resolved = contract.resolve(reference,float_snapshot)
	check(resolved.ok and C.bytes(resolved.focus.hex) == C.bytes(reference.hex),"integer actor reference resolves against integral JSON float snapshot")
	check(var_to_bytes(float_snapshot) == exact_float_state and var_to_bytes(reference) == exact_ref,"float-snapshot resolution mutates neither snapshot nor reference")
	var invalid: Array = [{"label":"fractional q","hex":[2.5,-1]},{"label":"fractional r","hex":[2,-1.5]},{"label":"NaN","hex":[NAN,-1]},{"label":"positive infinity","hex":[INF,-1]},{"label":"negative infinity","hex":[2,-INF]},{"label":"q beyond 1000","hex":[1001,-1]},{"label":"r beyond 1000","hex":[2,-1001]},{"label":"in-bound coordinate outside map domain","hex":[999,0]}]
	for row in invalid:
		var bad: Dictionary = reference.duplicate(true); bad.hex = row.hex.duplicate()
		var exact_bad: PackedByteArray = var_to_bytes(bad)
		check(not contract.resolve(bad,snapshot).ok,"actor focus rejects "+row.label)
		check(var_to_bytes(snapshot) == exact_state and var_to_bytes(bad) == exact_bad,"rejected "+row.label+" reference leaves all inputs unchanged")
	# An artificial matching cell cannot remove the explicit ±1000 guard.
	var beyond: Dictionary = snapshot.duplicate(true)
	beyond.actors.actor_player.hex = [1001,0]
	beyond.hexes["1001,0"] = {"id":"hex_1001_0","q":1001,"r":0,"scene_id":Source.SCENE,"terrain":"grass"}
	var beyond_ref: Dictionary = reference.duplicate(true); beyond_ref.hex = [1001,0]
	var before_beyond: PackedByteArray = var_to_bytes(beyond)
	check(not contract.resolve(beyond_ref,beyond).ok and var_to_bytes(beyond) == before_beyond,"matching detached out-of-bound cell cannot bypass coordinate bound")

func retain_budget_artifacts(a: RefCounted, label_: String, request_: Dictionary, focus: Dictionary, exact_bytes: int) -> void:
	var directory := "res://artifacts/generated_v3_village/context_budget"
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK,label_+" context QA output directory available"): return
	var request_path: String = directory+"/max_request_"+label_+".json"
	var manifest_path: String = directory+"/placement_manifest_"+label_+".json"
	var metadata_path: String = directory+"/max_request_"+label_+"_metadata.json"
	var manifest: Dictionary = a.source.placement_result.manifest.duplicate(true)
	var encoded_request: String = C.bytes(request_)
	var encoded_manifest: String = C.bytes(manifest)
	if not check(encoded_request.to_utf8_buffer().size() == exact_bytes,label_+" retained request matches measured complete bytes"): return
	var metadata := {"schema_version":"generated_v3_village_context_budget_witness/v1","case":label_,"profile":Source.PROFILE,"board_radius":a.source.data.board_radius,"goal_bytes":request_.context.goal.to_utf8_buffer().size(),"request_bytes":exact_bytes,"request_sha256":encoded_request.sha256_text(),"request_path":request_path,"action_id":request_.action_id,"focus_kind":focus.kind,"focus_id":focus.id,"support_hex":focus.hex.duplicate(),"focus_catalog_hash":focus.catalog_id,"public_cell_count":request_.context.facts.hexes.size(),"static_entity_count":request_.context.facts.static_entities.size(),"content_hash":a.source.identity.content_hash,"geometry_hash":a.source.identity.geometry_hash,"runtime_hash":a.source.identity.runtime_hash,"placement_hash":manifest.placement_hash,"placement_profile":manifest.profile_id,"placement_manifest_sha256":encoded_manifest.sha256_text(),"placement_manifest_bytes":encoded_manifest.to_utf8_buffer().size(),"placement_manifest_path":manifest_path,"encoding":"C.bytes canonical normalized JSON with full precision; no truncation"}
	for output in [{"path":request_path,"text":encoded_request},{"path":manifest_path,"text":encoded_manifest},{"path":metadata_path,"text":C.bytes(metadata)}]:
		var file: FileAccess = FileAccess.open(output.path,FileAccess.WRITE)
		if not check(file != null,label_+" context QA artifact opened "+output.path): return
		file.store_string(output.text); file.flush()
		var error: Error = file.get_error(); file.close()
		if not check(error == OK and FileAccess.get_file_as_string(output.path) == output.text,label_+" complete context QA artifact verified "+output.path): return
	check(FileAccess.get_sha256(request_path) == metadata.request_sha256 and FileAccess.get_sha256(manifest_path) == metadata.placement_manifest_sha256,label_+" retained request and manifest SHA-256 verified")
	print("V3 VILLAGE CONTEXT_BUDGET_WITNESS ",C.bytes(metadata))
