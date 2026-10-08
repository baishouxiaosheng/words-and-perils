extends SceneTree
const Adapter = preload("res://view/generated_natural_coast_basic/adapter.gd")
const Source = preload("res://view/generated_natural_coast_basic/source.gd")
const PublicProjection = preload("res://view/generated_natural_coast_basic/projection.gd")
const LegacyV3 = preload("res://view/generated_v3_adventure/adapter.gd")
const LegacyInventory = preload("res://view/generated_inventory/adapter.gd")
const LegacySeeded = preload("res://view/generated_adventure/seeded_adapter.gd")
const SeedContract = preload("res://core/world_generation_contract.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const ItemResolver = preload("res://view/generated_natural_coast_basic/item_resolver.gd")
const Examples = preload("res://view/generated_natural_coast_basic/assessments.gd")
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
func t03_overwrite_guard(adapter: RefCounted, recipe: String) -> void:
	# Dedicated synthetic fixtures only; run with isolated user:// under the
	# existing native guard. These are not actual public/native player saves.
	var path := "user://natural_coast_basic_save_t03_%s.json" % recipe
	var raw_path := "user://natural_coast_basic_save_t03_raw_%s.json" % recipe
	for fixture_path in [path,raw_path,path+".tmp",raw_path+".tmp"]:
		if FileAccess.file_exists(fixture_path): DirAccess.remove_absolute(fixture_path)
	var before := C.bytes(adapter.save_data())
	check(adapter.save_file(path).ok and adapter.save_file(path).ok,"T03 exact distribution envelope saves repeatedly")
	var independent := Adapter.new(adapter.source.data)
	check(independent.ready().ok and C.bytes(independent.source.identity) == C.bytes(adapter.source.identity) and independent.save_file(path).ok,"T03 independent same-distribution entry can save")
	var same_envelope_bytes := FileAccess.get_file_as_string(path)
	check(not adapter.engine.save_file(path).ok and FileAccess.get_file_as_string(path) == same_envelope_bytes,"T03 direct raw API preserves even its own adapter envelope")
	var existing: Dictionary = adapter.save_data()
	existing.identity.inventory_profile_hash = "0".repeat(64)
	existing.identity.runtime_hash = "0".repeat(64)
	existing.engine.state.generated_world = existing.identity.duplicate(true)
	existing.engine.state.world_id = Source.WORLD_PREFIX+existing.identity.runtime_hash
	var encoded := C.bytes(existing)
	FileAccess.open(path,FileAccess.WRITE).store_string(encoded)
	FileAccess.open(path+".tmp",FileAccess.WRITE).store_string("T03 temporary sentinel")
	check(existing.source.content_hash == adapter.source.identity.content_hash,"T03 foreign-identity fixture preserves generator content hash")
	check(not adapter.save_file(path).ok and not independent.save_file(path).ok and FileAccess.get_file_as_string(path) == encoded,"T03 same-terrain foreign runtime envelope is preserved by both entries")
	check(not adapter.engine.save_file(path).ok and FileAccess.get_file_as_string(path) == encoded and FileAccess.get_file_as_string(path+".tmp") == "T03 temporary sentinel","T03 direct raw API preserves foreign envelope and temp sentinel")
	existing = adapter.save_data(); existing.engine.state.world_id = "other_distribution_world"
	encoded = C.bytes(existing); FileAccess.open(path,FileAccess.WRITE).store_string(encoded)
	check(not adapter.save_file(path).ok and FileAccess.get_file_as_string(path) == encoded,"T03 exact envelope identity cannot hide a different engine world")
	existing = adapter.save_data(); existing.source = []
	encoded = C.bytes(existing); FileAccess.open(path,FileAccess.WRITE).store_string(encoded)
	check(not adapter.save_file(path).ok and FileAccess.get_file_as_string(path) == encoded,"T03 malformed typed source refuses without a script exception")
	DirAccess.remove_absolute(path+".tmp")
	check(adapter.engine.save_file(raw_path).ok and adapter.engine.save_file(raw_path).ok,"T03 direct raw API retains same-distribution saves")
	var raw: Dictionary = adapter.engine.save_data(); raw.state.generated_world.inventory_profile_hash = "0".repeat(64)
	encoded = C.bytes(raw); FileAccess.open(raw_path,FileAccess.WRITE).store_string(encoded)
	FileAccess.open(raw_path+".tmp",FileAccess.WRITE).store_string("T03 raw temporary sentinel")
	check(not adapter.engine.save_file(raw_path).ok and FileAccess.get_file_as_string(raw_path) == encoded and FileAccess.get_file_as_string(raw_path+".tmp") == "T03 raw temporary sentinel","T03 direct raw API preserves foreign authority signature before any write")
	FileAccess.open(raw_path,FileAccess.WRITE).store_string("{invalid")
	check(not adapter.engine.save_file(raw_path).ok and FileAccess.get_file_as_string(raw_path) == "{invalid","T03 malformed raw JSON is preserved")
	var independent_before := C.bytes(independent.engine.save_data())
	var foreign_raw: Dictionary = independent.engine.save_data()
	foreign_raw.state.world_id = Source.WORLD_PREFIX+"0".repeat(64)
	foreign_raw.state.generated_world.runtime_hash = "0".repeat(64)
	foreign_raw.campaign_memory.world_id = foreign_raw.state.world_id
	var foreign_encoded := C.bytes(foreign_raw)
	FileAccess.open(raw_path,FileAccess.WRITE).store_string(foreign_encoded)
	var raw_load: Dictionary = independent.engine.load_data(foreign_raw)
	check((not raw_load.ok and C.bytes(independent.engine.save_data()) == independent_before) or (raw_load.ok and not independent.engine.save_file(raw_path).ok and FileAccess.get_file_as_string(raw_path) == foreign_encoded and FileAccess.get_file_as_string(raw_path+".tmp") == "T03 raw temporary sentinel"),"T03 direct raw load cannot redefine constructor-bound save authority")
	check(C.bytes(adapter.save_data()) == before,"T03 allowed and refused writes preserve live state, RNG, pending and receipts")
	for fixture_path in [path,raw_path,path+".tmp",raw_path+".tmp"]:
		DirAccess.remove_absolute(fixture_path)

func run() -> void:
	var recipe := OS.get_environment("COAST_PLAY_RECIPE")
	if recipe.is_empty(): recipe = "coastal_range"
	var generated := Generator.generate(726381,4,recipe)
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
	var initial_save: Dictionary = a.save_data()
	check(C.bytes(a.source.data) == raw_bytes and C.bytes(raw) == raw_bytes,"raw caller/source JSON never changes")
	check(a.source.identity.profile == Source.PROFILE and a.source.identity.entity_profile == Source.PROFILE and initial.world_id == Source.WORLD_PREFIX+a.source.identity.runtime_hash,"new explicit source profile and world namespace")
	check(initial.items.keys() == [Source.ITEM] and initial.items[Source.ITEM].quantity == 1 and initial.items[Source.ITEM].owner_actor_id == "actor_player" and initial.actors.actor_player.inventory == [Source.ITEM],"exactly one initial registered carried bundle")
	check(not a.start_source(raw).ok and C.bytes(a.state_copy()) == C.bytes(initial),"second admission cannot inject or reset supply")
	var item_ref := a.item_reference(); var before := C.bytes(a.save_data())
	check(not item_ref.is_empty() and a.attention(item_ref).ok,"source-independent catalog item focus resolves")
	check(a.attention(item_ref).readonly and C.bytes(a.save_data()) == before,"repeated item selection is read only")
	for field in ["id","world_id","catalog_id"]:
		var bad_ref := item_ref.duplicate(true); bad_ref[field] = "stale"
		check(not a.attention(bad_ref).ok and C.bytes(a.save_data()) == before,"stale item "+field+" fails without mutation")
	var projected := PublicProjection.facts(initial,item_ref)
	check(projected.context_scope.schema_version == PublicProjection.ID and projected.items[Source.ITEM] == initial.items[Source.ITEM] and projected.hexes.size() <= 62,"new bounded model projector includes exact public item facts")
	check(not projected.has("generated_world") and not projected.has("generated_v3_source") and not projected.has("rng") and not projected.has("receipts"),"projection excludes raw source, RNG and private history")
	var broken := initial.duplicate(true); broken.generated_world.projection_id = "stale"
	check(PublicProjection.active(broken) and PublicProjection.facts(broken).is_empty(),"malformed profile remains closed, never falls back")
	roundtrip(a,"idle")
	var invalid_before := C.bytes(a.state_copy()); var invalid_rng := C.bytes(a.engine.save_data().rng)
	check(a.begin_intent(a.sample_goal("rest")).ok and not a.prepare_fixture().ok and a.cancel().ok,"full-stamina rest rejects before lock")
	var wet_target: Array = []; var far_observation: Array = []
	for test_cell in initial.hexes.values():
		var test_key: String = "%d,%d" % [test_cell.q,test_cell.r]
		if wet_target.is_empty() and not a.source.navigation.supported[test_key]: wet_target = [test_cell.q,test_cell.r]
		var dq: int = test_cell.q-start[0]; var dr: int = test_cell.r-start[1]
		if far_observation.is_empty() and maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) > 1: far_observation = [test_cell.q,test_cell.r]
	check(not wet_target.is_empty() and a.begin_intent(a.sample_goal("move",a.tile_reference(wet_target)),a.tile_reference(wet_target)).ok and not a.prepare_fixture().ok and a.cancel().ok,"wet movement rejects before lock")
	check(not far_observation.is_empty() and a.begin_intent(a.sample_goal("observe",a.tile_reference(far_observation)),a.tile_reference(far_observation)).ok and not a.prepare_fixture().ok and a.cancel().ok,"distant observation rejects before lock")
	var budget_neighbor: String = a.source.navigation.allowed["%d,%d" % start][0]
	var budget_cell: Dictionary = initial.hexes[budget_neighbor]
	check(not a.source.navigation.plan(initial,[budget_cell.q,budget_cell.r],0).ok,"over-budget dry navigation refuses a route")
	check(C.bytes(a.state_copy()) == invalid_before and C.bytes(a.engine.save_data().rng) == invalid_rng,"all failed preconditions preserve state and RNG")

	check(a.begin_intent("把行礼包放下",item_ref).ok and not a.fixture_available() and not a.roll_once().ok,"ordinary text waits for assessment without keyword execution")
	roundtrip(a,"unassessed pending")
	var pending_exact := C.bytes(a.save_data())
	check(a.load_data(initial_save).get("code") == "COAST_PENDING_LOAD" and C.bytes(a.save_data()) == pending_exact,"load cannot discard unassessed action")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(initial) and C.bytes(a.engine.save_data().rng) == initial_rng,"pending cancel preserves item and RNG")
	before = C.bytes(a.save_data()); check(not a.cancel().ok and C.bytes(a.save_data()) == before,"duplicate cancel cannot consume an ID or alter state")
	roundtrip(a,"canceled")
	check(a.begin_intent(a.sample_goal("drop_item"),item_ref).ok,"exact authored drop starts")
	var request := a.request()
	check(request.contract.resolver_ids == ["natural_coast_drop_item_v1","natural_coast_move_v1","natural_coast_observe_v1","natural_coast_pickup_item_v1","natural_coast_rest_v1"],"five-action closed registry, no equip/use/transfer/NPC/creation")
	check(C.bytes(request).to_utf8_buffer().size() <= Adapter.MAX_REQUEST_BYTES,"request retains original 64 KiB bound")
	var manual: Dictionary = Examples.build(request).assessment
	manual.provenance = {"provider":"offline_test","live":false,"kind":"model_reply"}
	manual.resolver_id = "natural_coast_equip_item_v1"; before = C.bytes(a.save_data())
	check(not a.import_reply(manual).ok and C.bytes(a.save_data()) == before,"unregistered equipment resolver cannot gain authority")
	manual.resolver_id = "natural_coast_drop_item_v1"; manual.bindings.item_id = "invented_loot"
	check(not a.import_reply(manual).ok and C.bytes(a.save_data()) == before,"unregistered item binding cannot create or move loot")
	check(a.prepare_fixture().ok and a.action_copy().checks[0].method == "direct_success","shared ownership policy creates direct success after assessment")
	roundtrip(a,"ready")
	for corrupt_kind in ["branch","plan","rng","snapshot"]:
		var corrupt_pending := a.save_data(); var pending_action: Dictionary = corrupt_pending.engine.pending.values()[0]
		if corrupt_kind == "branch":
			for branch in pending_action.branches:
				if not branch.patches.is_empty(): branch.patches = []; break
			check(C.bytes(corrupt_pending) != C.bytes(a.save_data()),"branch negative actually changes the pending save")
		elif corrupt_kind == "plan": pending_action.plan_hash = "0".repeat(64)
		elif corrupt_kind == "rng": corrupt_pending.engine.rng.state = "1" if corrupt_pending.engine.rng.state != "1" else "2"
		else: pending_action.snapshot.actors.actor_player.stamina.current -= 1
		var rejected_pending := Adapter.new()
		check(not rejected_pending.load_data(corrupt_pending).ok and rejected_pending.state_copy().is_empty(),"tampered prepared "+corrupt_kind+" fails closed on blank restore")

	pending_exact = C.bytes(a.save_data())
	check(a.load_data(initial_save).get("code") == "COAST_PENDING_LOAD" and C.bytes(a.save_data()) == pending_exact,"load cannot discard ready action")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(initial),"ready drop cancels without loss")
	check(a.begin_intent(a.sample_goal("drop_item"),item_ref).ok and a.prepare_fixture().ok and a.roll_once().ok,"new assessed drop locks")
	before = C.bytes(a.save_data())
	check(a.roll_once().ok and not a.cancel().ok and C.bytes(a.save_data()) == before,"locked drop never rerolls or cancels")
	check(C.bytes(a.engine.save_data().rng) == initial_rng and C.bytes(a.state_copy()) == C.bytes(initial),"direct lock consumes no entropy and moves no item")
	roundtrip(a,"locked")
	pending_exact = C.bytes(a.save_data())
	check(a.load_data(initial_save).get("code") == "COAST_PENDING_LOAD" and C.bytes(a.save_data()) == pending_exact,"load cannot discard locked action or erase RNG lineage")
	check(a.stage().ok and C.bytes(a.state_copy()) == C.bytes(initial),"staged drop is preview only")
	roundtrip(a,"staged")
	pending_exact = C.bytes(a.save_data())
	check(a.load_data(initial_save).get("code") == "COAST_PENDING_LOAD" and C.bytes(a.save_data()) == pending_exact,"load cannot discard staged action")
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
	check(C.bytes(a.source.data) == C.bytes(old.source.data) and a.source.identity.geometry_hash != old.source.identity.geometry_hash and a.source.identity.source_contract == "natural_coast_source/v1","raw source remains exact but natural physical authority is independently identified")
	var physical: Dictionary = a.source.physical_base.custody.snapshot()
	check(not physical.is_empty() and C.bytes(physical.identity) == C.bytes(a.source.identity.physical_custody),"new gameplay binds exact verified source, geometry, water and navigation custody")
	check(a.source.identity.navigation_content_hash == C.digest({"supported":a.source.navigation.supported,"support_heights":a.source.navigation.support_heights,"allowed":a.source.navigation.allowed}),"gameplay uses exact independently validated natural-coast navigation")
	var inventory_mesh: Array = a.source.renderer_bundle.ground_mesh.surface_get_arrays(0)
	var physical_mesh: Array = a.source.physical_base.custody.renderer_bundle.ground_mesh.surface_get_arrays(0)
	check(inventory_mesh[Mesh.ARRAY_VERTEX].to_byte_array() == physical_mesh[Mesh.ARRAY_VERTEX].to_byte_array() and inventory_mesh[Mesh.ARRAY_INDEX].to_byte_array() == physical_mesh[Mesh.ARRAY_INDEX].to_byte_array(),"rendered vertices and indices are the verified natural physical bundle")
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
	check(a.default_save_path() == "user://natural_coast_basic_v1_%s.json" % recipe and a.default_request_path() == "user://natural_coast_basic_request_v1_%s.json" % recipe,"save and request have new independent defaults")
	for path in [LegacyV3.GENERATED_SAVE,LegacyV3.V3_REQUEST,"user://generated_inventory_v1.json","user://generated_adventure_v2.json","user://generated_adventure_request_v1.json"]:
		var hash_before := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(not a.save_file(path).ok and not a.export_request(path).ok and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == hash_before,"protected old namespace untouched "+path)
	check(not a.save_file(a.default_request_path()).ok and not a.export_request(a.default_save_path()).ok,"save/request defaults cannot collide")
	var path := "user://natural_coast_basic_save_suite_%s.json" % recipe
	check(a.save_file(path).ok,"own profile atomic file save")
	var disk := FileAccess.get_file_as_string(path); var loaded := Adapter.new()
	check(loaded.load_file(path).ok and C.bytes(loaded.save_data()) == C.bytes(a.save_data()),"actual save file roundtrip is exact")
	DirAccess.make_dir_absolute(path+".tmp"); before = C.bytes(a.save_data())
	check(not a.save_file(path).ok and FileAccess.get_file_as_string(path) == disk and C.bytes(a.save_data()) == before,"failed temporary write loses neither old file nor item/RNG")
	DirAccess.remove_absolute(path+".tmp")
	var request_path := "user://natural_coast_basic_request_suite_%s.json" % recipe
	check(a.export_request(request_path).ok and a.export_request(request_path).ok,"own valid narration request can be exported repeatedly")
	check(not a.save_file(request_path).ok and not a.export_request(path).ok,"recognized save/request schemas cannot overwrite each other")
	var unrelated := "user://v3_inventory_suite_unrelated.json"
	var file := FileAccess.open(unrelated,FileAccess.WRITE); file.store_string('{"note":"preserve"}'); file.close()
	check(not a.save_file(unrelated).ok and not a.export_request(unrelated).ok and FileAccess.get_file_as_string(unrelated) == '{"note":"preserve"}',"arbitrary existing JSON is never overwritten")
	DirAccess.remove_absolute(unrelated)
	var reset: RefCounted = a.restarted()
	check(reset.ready().ok and reset.state_copy().turn == 0 and reset.state_copy().actors.actor_player.inventory == [Source.ITEM] and C.bytes(reset.source.data) == raw_bytes and C.bytes(reset.source.identity) == C.bytes(a.source.identity),"explicit restart alone recreates one starting bundle and exact source identity")
	check(FileAccess.get_file_as_string(path) == disk,"explicit restart never overwrites saved journey")
	t03_overwrite_guard(a,recipe)
	# Cross-recipe, forged physical identity, producer identity and exact source data fail closed.
	var alternate_recipe := "plateau_hinterland" if recipe == "coastal_range" else "coastal_range"
	var alternate := Adapter.new(Generator.generate("726381",4,alternate_recipe).source)
	check(alternate.ready().ok and alternate.source.identity.geometry_hash != a.source.identity.geometry_hash,"other verified recipe has a distinct admitted physical world")
	reject_load(a,alternate.save_data(),"cross-recipe save")
	corrupt = a.save_data(); corrupt.source.cells[corrupt.source.cells.keys()[0]].moisture += 1.0/4096.0
	reject_load(a,corrupt,"source payload tamper")
	corrupt = a.save_data(); corrupt.identity.water_hash = "0".repeat(64)
	reject_load(a,corrupt,"water identity tamper")
	corrupt = a.save_data(); corrupt.identity.physical_custody.pipeline_sha256 = "0".repeat(64)
	reject_load(a,corrupt,"frozen physical pipeline tamper")
	corrupt = a.save_data(); corrupt.engine.state.generated_world.source_contract = "generated_v3_source/v1"
	reject_load(a,corrupt,"forged old source authority")
	corrupt = a.save_data(); corrupt.identity.inventory_profile_hash = "0".repeat(64)
	reject_load(a,corrupt,"gameplay pipeline tamper")
	var clean_source: Dictionary = a.source.data.duplicate(true)
	a.source.data.cells[a.source.data.cells.keys()[0]].moisture += 1.0/4096.0
	check(not a.source.validate_state(a.state_copy()).ok,"live detached source mutation is rejected")
	a.source.data.clear(); a.source.data.merge(clean_source,true)
	check(a.source.validate_state(a.state_copy()).ok,"restoring exact source restores custody without rewriting authority")
	for old_name in ["generated_v3_village_equipment_v1.json","generated_v3_village_equipment_request_v1.json","generated_v3_rivers_v1.json","generated_v3_rivers_request_v1.json","GENERATED_V3_VILLAGE_EQUIPMENT_V1.JSON"]:
		check(not a._check_destination("user://"+old_name).ok and not a._check_destination("user://"+old_name,true).ok,"all old default namespaces remain protected: "+old_name)
	check(a.engine.get_script().resource_path == "res://view/generated_natural_coast_basic/engine.gd" and a.engine.get_script().get_base_script().resource_path == "res://core/ai_gm_rebuilt/engine.gd","real new Engine subclass inherits the unchanged transaction core")
	var capabilities: Dictionary = a.engine.capability_catalog()
	check(capabilities.get("schema_version") == "action_capability_catalog/v1" and capabilities.get("readonly",false) and capabilities.get("entries",[]).size() == 5 and capabilities.get("target_refs",[]).any(func(row): return row.get("kind") == "item" and row.get("id") == Source.ITEM),"capability discovery uses the new public projector")
	var cancel_probe := Adapter.new(raw)
	check(cancel_probe.begin_intent(cancel_probe.sample_goal("observe",cancel_probe.tile_reference(initial.actors.actor_player.hex))).ok,"cancel-load probe begins intent")
	var late_reply: Dictionary = Examples.build(cancel_probe.request()).assessment
	check(cancel_probe.cancel().ok and cancel_probe.load_data(initial_save).ok,"explicit pre-lock cancel permits load")
	var cancel_loaded := C.bytes(cancel_probe.save_data())
	check(not cancel_probe.engine.prepare_assessment(late_reply).ok and C.bytes(cancel_probe.save_data()) == cancel_loaded,"late reply after cancel/load cannot recreate discarded action")
	# Permanent semantic-save counterexamples: fully rehashed receipt and matching
	# final state, with optional campaign memory omitted as the base core allows.
	var probe := Adapter.new(raw)
	var probe_start: Array = probe.state_copy().actors.actor_player.hex
	var probe_neighbor: String = probe.source.navigation.allowed["%d,%d" % probe_start][0]
	var probe_cell: Dictionary = probe.state_copy().hexes[probe_neighbor]
	check(execute(probe,"move",probe.tile_reference([probe_cell.q,probe_cell.r])),"real move establishes forged-history baseline")
	for malformed_patch in [7,{"type":"actor_move","hex":7}]:
		var malformed_receipt_save := probe.save_data()
		var bad_receipt: Dictionary = malformed_receipt_save.engine.receipts.values()[0]
		bad_receipt.patches = [malformed_patch]; rehash_receipt(bad_receipt); malformed_receipt_save.engine.erase("campaign_memory")
		var malformed_probe := Adapter.new()
		check(not malformed_probe.load_data(malformed_receipt_save).ok and malformed_probe.state_copy().is_empty(),"rehashed malformed patch rejects without exception or partial admission")
	var forged := probe.save_data()
	var movement_receipt: Dictionary = forged.engine.receipts.values()[0]
	var free_patches: Array = []
	for patch in movement_receipt.patches:
		if patch.type != "actor_pool_delta": free_patches.append(patch)
	movement_receipt.patches = free_patches
	forged.engine.state.actors.actor_player.stamina.current = 8
	forged.engine.erase("campaign_memory")
	rehash_receipt(movement_receipt)
	check(probe.source.validate_state(forged.engine.state).ok,"cost-free forged state passes structural state checks")
	var valid_before_forge := C.bytes(probe.save_data())
	var denied: Dictionary = probe.load_data(forged)
	check(denied.get("code") == "COAST_HISTORY_SEMANTICS" and C.bytes(probe.save_data()) == valid_before_forge,"rehashed cost-free move is rejected by new semantic replay atomically")
	var remote := Adapter.new(raw)
	check(execute(remote,"drop_item",remote.item_reference()),"real drop establishes remote-pickup baseline")
	var remote_target: Array = []
	for candidate_cell in remote.state_copy().hexes.values():
		var dq: int = candidate_cell.q-probe_start[0]; var dr: int = candidate_cell.r-probe_start[1]
		if maxi(absi(dq),maxi(absi(dr),absi(dq+dr))) > 1 and remote.movement_preview([candidate_cell.q,candidate_cell.r]).ok:
			remote_target = [candidate_cell.q,candidate_cell.r]; break
	check(not remote_target.is_empty() and execute(remote,"move",remote.tile_reference(remote_target)),"traveler reaches real distant dry cell")
	check(execute(remote,"observe",remote.tile_reference(remote_target)),"real third receipt provides otherwise valid save structure")
	forged = remote.save_data()
	var pickup_receipt: Dictionary = {}
	for receipt_ in forged.engine.receipts.values():
		if receipt_.turn == 3: pickup_receipt = receipt_
	pickup_receipt.branch_id = "pickup_item_success"; pickup_receipt.outcomes = {"interact":true}; pickup_receipt.goal = remote.sample_goal("pickup_item")
	pickup_receipt.patches = [{"type":"item_relocate","item_id":Source.ITEM,"expected_owner_id":"","expected_hex":probe_start.duplicate(),"owner_actor_id":"actor_player","scene_id":"","hex":[]}]
	forged.engine.state.flags = {"observations":0,"last_observed_cell":""}
	var forged_item: Dictionary = forged.engine.state.items[Source.ITEM]
	forged_item.erase("hex"); forged_item.erase("scene_id"); forged_item.owner_actor_id = "actor_player"; forged_item.custody_revision = 2
	forged.engine.state.actors.actor_player.inventory = [Source.ITEM]
	forged.engine.erase("campaign_memory"); rehash_receipt(pickup_receipt)
	check(remote.source.validate_state(forged.engine.state).ok,"remote-pickup forged state passes structural state checks")
	valid_before_forge = C.bytes(remote.save_data()); denied = remote.load_data(forged)
	check(denied.get("code") == "COAST_HISTORY_SEMANTICS" and C.bytes(remote.save_data()) == valid_before_forge,"rehashed remote pickup is rejected by exact source reach semantics")
	# Mutate only this isolated test project's code bytes, then restore before
	# asserting. Canonical v27 is never opened for write by the test.
	var policy_path := "res://core/ai_gm_rebuilt/traversal_policy.gd"
	var old_policy := FileAccess.get_file_as_string(policy_path)
	var changed_policy := old_policy.replace('"grass":1','"grass":2')
	var exact_save := a.save_data(); var old_profile_hash: String = a.source.identity.inventory_profile_hash
	FileAccess.open(policy_path,FileAccess.WRITE).store_string(changed_policy)
	var new_profile_hash := Source.profile_digest()
	var policy_denied: Dictionary = Adapter.new().load_data(exact_save)
	FileAccess.open(policy_path,FileAccess.WRITE).store_string(old_policy)
	check(old_policy != changed_policy and old_profile_hash != new_profile_hash and not policy_denied.ok,"changed traversal cost dependency invalidates new save identity")
	check(Source.profile_digest() == old_profile_hash and FileAccess.get_file_as_string(policy_path) == old_policy,"exact authority code restored after dependency counterexample")
	finish()
func rehash_receipt(receipt: Dictionary) -> void:
	var payload: Dictionary = receipt.duplicate(true); payload.erase("receipt_hash")
	receipt.receipt_hash = C.digest(payload)
func finish() -> void:
	var output := OS.get_environment("COAST_PLAY_OUTPUT")
	var result := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"suite":get_script().resource_path,"recipe":OS.get_environment("COAST_PLAY_RECIPE"),"run_id":OS.get_environment("COAST_PLAY_RUN_ID"),"owned_pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path)}
	if not output.is_empty():
		var encoded := JSON.stringify(result,"\t",true,true)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(encoded)
		FileAccess.open(output.path_join("completed.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":result.run_id,"owned_pid":result.owned_pid,"checks":checks,"result_sha256":encoded.sha256_text(),"script_sha256":result.script_sha256}))
	print("NATURAL_COAST_BASIC ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
