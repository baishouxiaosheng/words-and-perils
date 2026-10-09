extends SceneTree
const Adapter = preload("res://view/generated_v3_inventory/adapter.gd")
const Source = preload("res://view/generated_v3_inventory/source.gd")
const PublicProjection = preload("res://view/generated_v3_inventory/projection.gd")
const LegacyV3 = preload("res://view/generated_v3_adventure/adapter.gd")
const LegacyInventory = preload("res://view/generated_inventory/adapter.gd")
const LegacySeeded = preload("res://view/generated_adventure/seeded_adapter.gd")
const SeedContract = preload("res://core/world_generation_contract.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const ItemResolver = preload("res://view/generated_v3_inventory/resolver.gd")
const Examples = preload("res://view/generated_v3_inventory/assessments.gd")
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
	check(a.source.identity.profile == Source.PROFILE and a.source.identity.entity_profile == Source.PROFILE and initial.world_id == Source.WORLD_PREFIX+raw.content_hash,"new explicit source profile and world namespace")
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
	roundtrip(a,"idle")
	check(a.begin_intent("把行礼包放下",item_ref).ok and not a.fixture_available() and not a.roll_once().ok,"ordinary text waits for assessment without keyword execution")
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
	check(C.bytes(a.source.navigation.allowed) == C.bytes(old.source.navigation.allowed) and C.bytes(a.source.navigation.supported) == C.bytes(old.source.navigation.supported) and C.bytes(a.source.spawn_component) == C.bytes(old.source.spawn_component),"inventory preserves exact original dry navigation and connected spawn component")
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
	check(a.default_save_path() == Adapter.INVENTORY_SAVE and a.default_request_path() == Adapter.INVENTORY_REQUEST,"save and request have new independent defaults")
	for path in [LegacyV3.GENERATED_SAVE,LegacyV3.V3_REQUEST,"user://generated_inventory_v1.json","user://generated_adventure_v2.json","user://generated_adventure_request_v1.json"]:
		var hash_before := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(not a.save_file(path).ok and not a.export_request(path).ok and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == hash_before,"protected old namespace untouched "+path)
	check(not a.save_file(a.default_request_path()).ok and not a.export_request(a.default_save_path()).ok,"save/request defaults cannot collide")
	var path := "user://v3_inventory_suite_save.json"
	check(a.save_file(path).ok,"own profile atomic file save")
	var disk := FileAccess.get_file_as_string(path); var loaded := Adapter.new()
	check(loaded.load_file(path).ok and C.bytes(loaded.save_data()) == C.bytes(a.save_data()),"actual save file roundtrip is exact")
	DirAccess.make_dir_absolute(path+".tmp"); before = C.bytes(a.save_data())
	check(not a.save_file(path).ok and FileAccess.get_file_as_string(path) == disk and C.bytes(a.save_data()) == before,"failed temporary write loses neither old file nor item/RNG")
	DirAccess.remove_absolute(path+".tmp")
	var request_path := "user://v3_inventory_suite_request.json"
	check(a.export_request(request_path).ok and a.export_request(request_path).ok,"own valid narration request can be exported repeatedly")
	check(not a.save_file(request_path).ok and not a.export_request(path).ok,"recognized save/request schemas cannot overwrite each other")
	var unrelated := "user://v3_inventory_suite_unrelated.json"
	var file := FileAccess.open(unrelated,FileAccess.WRITE); file.store_string('{"note":"preserve"}'); file.close()
	check(not a.save_file(unrelated).ok and not a.export_request(unrelated).ok and FileAccess.get_file_as_string(unrelated) == '{"note":"preserve"}',"arbitrary existing JSON is never overwritten")
	DirAccess.remove_absolute(unrelated)
	var reset: RefCounted = a.restarted()
	check(reset.ready().ok and reset.state_copy().turn == 0 and reset.state_copy().actors.actor_player.inventory == [Source.ITEM] and C.bytes(reset.source.data) == raw_bytes and C.bytes(reset.source.identity) == C.bytes(a.source.identity),"explicit restart alone recreates one starting bundle and exact source identity")
	check(FileAccess.get_file_as_string(path) == disk,"explicit restart never overwrites saved journey")
	finish()
func finish() -> void:
	print("V3 INVENTORY ADAPTER ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
