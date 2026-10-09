extends SceneTree
const Adapter = preload("res://view/generated_inventory/adapter.gd")
const Legacy = preload("res://view/generated_adventure/adapter.gd")
const Seeded = preload("res://view/generated_adventure/seeded_adapter.gd")
const Contract = preload("res://core/world_generation_contract.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ItemResolver = preload("res://view/generated_inventory/resolver.gd")
const Examples = preload("res://view/generated_inventory/assessments.gd")
var checks := 0
var failures: Array = []
var envelope: Dictionary
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
	return ok
func roundtrip(adapter: RefCounted, label: String) -> void:
	var exact: String = C.bytes(adapter.save_data())
	var restored := Adapter.new()
	check(restored.load_data(JSON.parse_string(exact)).ok, label + " restores through exact JSON")
	check(C.bytes(restored.save_data()) == exact, label + " preserves source/metadata/profile/transaction/RNG/history exactly")
func execute(adapter: RefCounted, kind: String, focus: Dictionary = {}) -> bool:
	return adapter.begin_intent(adapter.sample_goal(kind, focus), focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok
func unchanged_rejection(adapter: RefCounted, corrupt: Dictionary, label: String) -> void:
	var exact: String = C.bytes(adapter.save_data())
	check(not adapter.load_data(corrupt).ok and C.bytes(adapter.save_data()) == exact, label)
func run() -> void:
	envelope = Contract.generate("雪岸-行囊", "compact_coast", 4)
	var a := Adapter.new()
	if not check(a.start_seeded(envelope).ok, "seeded inventory profile admits a real generated map"): finish(); return
	var state: Dictionary = a.state_copy()
	var item: Dictionary = state.items.item_travel_bundle
	var initial_rng: String = C.bytes(a.engine.save_data().rng)
	var original_source := C.bytes(envelope.source)
	check(C.bytes(a.source.data) == original_source and a.source.identity.content_hash == envelope.source.content_hash, "profile does not modify generator bytes/hash")
	check(state.items.size() == 1 and item.quantity == 1 and item.owner_actor_id == "actor_player" and state.actors.actor_player.inventory == [item.id], "one explicit whole-stack supply, exact ownership and no generated loot")
	check(a.default_save_path() != Seeded.SEEDED_SAVE and a.default_save_path() != Legacy.GENERATED_SAVE, "new profile never defaults to old save paths")
	check(not Adapter.new(envelope.source).ready().ok, "raw source cannot skip seed/preset provenance")
	roundtrip(a, "idle")
	var before: String = C.bytes(a.save_data())
	var focus := a.tile_reference(state.actors.actor_player.hex)
	check(a.attention(focus).ok and C.bytes(a.save_data()) == before, "attention selects only, never changes supply, turn or RNG")
	check(not a.attention({"world_id": state.world_id, "kind": "item", "id": item.id}).ok and C.bytes(a.save_data()) == before, "unsupported item focus does not invent clickable object support")
	check(a.begin_intent("放下行礼包").ok and not a.fixture_available(), "ordinary free text awaits a real external assessment, not inferred fixture")
	check(not a.roll_once().ok and C.bytes(a.state_copy()) == C.bytes(state), "unassessed free text cannot relocate or roll")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(state) and C.bytes(a.engine.save_data().rng) == initial_rng, "cancel before assessment preserves exact custody and RNG")
	check(a.begin_intent(a.sample_goal("drop_item"), focus).ok, "signed drop creates assessment request")
	var req: Dictionary = a.request()
	check(req.contract.resolver_ids == ["generated_drop_item_v1", "generated_move_v1", "generated_observe_v1", "generated_pickup_item_v1", "generated_rest_v1"], "closed five-action registry excludes combat/equip/transfer/use")
	check(req.context.facts.items.item_travel_bundle == item and req.context.facts.hexes.size() <= 62 and C.bytes(req).to_utf8_buffer().size() <= 65536, "known supply public facts remain bounded")
	check(not req.context.facts.has("generated_world") and not req.context.facts.has("rng") and not req.context.facts.has("receipts") and not req.context.facts.has("pending"), "public context excludes raw source/RNG/receipts/pending")
	roundtrip(a, "awaiting")
	check(a.prepare_fixture().ok and a.action_copy().checks[0].method == "direct_success", "existing ownership/range rules decide direct result after assessment")
	check(a.cancel().ok and C.bytes(a.state_copy()) == C.bytes(state), "cancel assessed unrolled drop loses no item")
	check(a.begin_intent(a.sample_goal("drop_item")).ok and a.prepare_fixture().ok, "retry cancelled drop obtains fresh assessment")
	roundtrip(a, "ready")
	check(a.roll_once().ok, "assessed drop locks")
	var locked: String = C.bytes(a.save_data())
	check(a.roll_once().ok and C.bytes(a.save_data()) == locked and not a.cancel().ok, "locked result cannot reroll or cancel")
	check(C.bytes(a.state_copy()) == C.bytes(state) and C.bytes(a.engine.save_data().rng) == initial_rng, "direct lock does not relocate or consume RNG")
	roundtrip(a, "locked")
	check(a.save_file("user://inventory_locked.json").ok, "locked item transaction saves atomically")
	var loaded := Adapter.new()
	check(loaded.load_file("user://inventory_locked.json").ok and C.bytes(loaded.save_data()) == locked, "locked file reload is byte-exact")
	check(loaded.stage().ok and C.bytes(loaded.state_copy()) == C.bytes(state), "staging drop changes no live facts")
	roundtrip(loaded, "staged")
	check(loaded.commit().ok, "one atomic drop commit")
	var dropped: Dictionary = loaded.state_copy()
	check(dropped.items.size() == 1 and dropped.items.item_travel_bundle.quantity == 1 and not dropped.items.item_travel_bundle.has("owner_actor_id") and dropped.items.item_travel_bundle.hex == state.actors.actor_player.hex and dropped.actors.actor_player.inventory.is_empty(), "drop preserves one ID/quantity and relocates whole stack to exact feet")
	check(dropped.turn == 1 and dropped.state_version == 1 and dropped.items.item_travel_bundle.custody_revision == 1 and loaded.source.validate_state(dropped).ok, "drop advances turn/version/custody once and preserves source invariants")
	var receipt: Dictionary = loaded.engine.save_data().receipts[loaded.last_action]
	before = C.bytes(loaded.save_data())
	check(loaded.engine.commit(loaded.last_action, receipt.stage_hash).already_committed and C.bytes(loaded.save_data()) == before, "duplicate commit cannot duplicate or lose supply")
	check(loaded.begin_intent(loaded.sample_goal("drop_item")).ok and not loaded.prepare_fixture().ok and C.bytes(loaded.state_copy()) == C.bytes(dropped), "repeated drop of ground supply rejects without mutation")
	check(loaded.cancel().ok, "failed assessment remains cancellable")
	check(execute(loaded, "pickup_item"), "assessed pickup reuses existing custody rules")
	check(loaded.state_copy().items.item_travel_bundle.owner_actor_id == "actor_player" and loaded.state_copy().actors.actor_player.inventory == [item.id] and loaded.state_copy().items.item_travel_bundle.custody_revision == 2, "pickup restores one item with monotonic custody revision")
	check(execute(loaded, "drop_item") and execute(loaded, "pickup_item"), "material custody revisions permit later genuine drop/pickup, no prose retry bypass")
	check(loaded.state_copy().turn == 4 and C.bytes(loaded.engine.save_data().rng) == initial_rng, "four assessed direct actions consume four turns and zero random draws")
	roundtrip(loaded, "committed")
	# Move away after dropping. Public recorded custody is retained but out-of-reach pickup fails.
	check(execute(loaded, "drop_item"), "drop supply before departure")
	var from_key: String = "%d,%d" % loaded.state_copy().actors.actor_player.hex
	var neighbor: String = loaded.source.navigation.allowed[from_key][0]
	var target_cell: Dictionary = loaded.state_copy().hexes[neighbor]
	var target := [target_cell.q, target_cell.r]
	check(execute(loaded, "move", loaded.tile_reference(target)), "existing assessed movement works while supply is on ground")
	check(execute(loaded, "pickup_item"), "verified adjacent dry pickup succeeds")
	check(execute(loaded, "observe", loaded.tile_reference(target)) and execute(loaded, "rest"), "existing observation/rest still assessed in new profile")
	check(loaded.source.validate_state(loaded.state_copy()).ok and C.bytes(loaded.source.data) == original_source, "all five actions preserve admitted source and runtime invariants")
	# Adversarial manual assessments cannot invent verbs/entities or bypass custody.
	check(loaded.begin_intent("把行礼包拆成两件").ok, "unsupported intent can request assessment but has no fabricated response")
	var bad: Dictionary = Examples.build({"action_id": loaded.request().action_id, "state_version": loaded.request().state_version, "context_hash": loaded.request().context_hash, "context": {"actor_id": "actor_player", "goal": Examples.goal("drop_item"), "facts": loaded.request().context.facts}}).assessment
	bad.provenance = {"provider": "manual", "live": false, "kind": "model_reply"}; bad.resolver_id = "generated_equip_item_v1"
	before = C.bytes(loaded.save_data())
	check(not loaded.import_reply(bad).ok and C.bytes(loaded.save_data()) == before, "unregistered equip resolver rejected atomically")
	bad.resolver_id = "generated_drop_item_v1"; bad.bindings.item_id = "invented_loot"
	check(not loaded.import_reply(bad).ok and C.bytes(loaded.save_data()) == before, "invented item rejected atomically")
	check(loaded.cancel().ok, "unsupported assessment cancellation retains supply")
	# Arbitrary text remains display-only; authoritative custody stays recorded beside it.
	var narration_request: Dictionary = loaded.request()
	before = C.bytes(loaded.save_data())
	var narrative := {"schema_version": "ai_gm_narration/v1", "action_id": narration_request.action_id, "state_version": narration_request.state_version, "context_hash": narration_request.context_hash, "narration": "这只是一段显示文字。"}
	check(loaded.import_reply(narrative).ok and C.bytes(loaded.save_data()) == before, "optional narrative cannot mutate custody, receipts or RNG")
	narrative["patches"] = [{"type": "item_quantity_delta", "item_id": item.id, "delta": 1}]
	check(not loaded.import_reply(narrative).ok and C.bytes(loaded.save_data()) == before, "narrative arbitrary patches are rejected")
	# Real public distant ground item; moving farther than one cell cannot silently pick it up.
	check(execute(loaded, "drop_item"), "drop before distant reach test")
	var departure: Array = loaded.state_copy().actors.actor_player.hex.duplicate()
	var distant: Array = []
	for cell in loaded.state_copy().hexes.values():
		var dq: int = cell.q - departure[0]; var dr: int = cell.r - departure[1]
		if maxi(absi(dq), maxi(absi(dr), absi(dq + dr))) < 2: continue
		if loaded.movement_preview([cell.q, cell.r]).ok: distant = [cell.q, cell.r]; break
	check(not distant.is_empty() and execute(loaded, "move", loaded.tile_reference(distant)), "real admitted route reaches a distant cell")
	var far_state: String = C.bytes(loaded.state_copy()); var far_rng: String = C.bytes(loaded.engine.save_data().rng)
	check(loaded.begin_intent(loaded.sample_goal("pickup_item")).ok and not loaded.prepare_fixture().ok and C.bytes(loaded.state_copy()) == far_state and C.bytes(loaded.engine.save_data().rng) == far_rng, "out-of-reach pickup cannot teleport supply or consume RNG")
	check(loaded.cancel().ok, "rejected distant pickup cancels without loss")
	# Materially different assessment branches cannot alter a saved locked relocation.
	if loaded.state_copy().actors.actor_player.stamina.current < 8: check(execute(loaded, "rest"), "rest before returning to supply")
	check(execute(loaded, "move", loaded.tile_reference(departure)), "return by admitted dry route")
	check(loaded.begin_intent(loaded.sample_goal("pickup_item")).ok and loaded.prepare_fixture().ok and loaded.roll_once().ok, "pickup lock before adversarial pending load")
	var forged := loaded.save_data()
	for branch in forged.engine.pending[loaded.active_action].branches:
		if not branch.patches.is_empty(): branch.patches[0].item_id = "invented"
	unchanged_rejection(loaded, forged, "forged frozen relocation rejects before publishing")
	check(loaded.stage().ok and loaded.commit().ok, "valid original locked pickup still commits after rejected load")
	# Corruption rejects before publishing; supply capability/quantity never rewritten by a save.
	var corrupt := loaded.save_data(); corrupt.engine.state.items.item_travel_bundle.quantity = 2
	unchanged_rejection(loaded, corrupt, "forged quantity rejects with old world intact")
	corrupt = loaded.save_data(); corrupt.engine.state.items.item_travel_bundle.interaction_profile.equip_slot = "weapon"
	unchanged_rejection(loaded, corrupt, "forged item ability rejects")
	corrupt = loaded.save_data(); corrupt.engine.state.actors.actor_player.inventory.append(item.id)
	unchanged_rejection(loaded, corrupt, "duplicate inventory reference rejects")
	corrupt = loaded.save_data(); corrupt.engine.state.items.item_travel_bundle.custody_revision += 1
	unchanged_rejection(loaded, corrupt, "inconsistent custody revision rejects")
	corrupt = loaded.save_data(); corrupt.engine.state.generated_world.inventory_profile_hash = "changed"
	unchanged_rejection(loaded, corrupt, "changed runtime inventory implementation rejects")
	corrupt = loaded.save_data(); corrupt.source.seed += 1
	unchanged_rejection(loaded, corrupt, "altered source seed rejects")
	corrupt = loaded.save_data(); corrupt.generation_metadata.request.seed_token = "changed"
	unchanged_rejection(loaded, corrupt, "altered seed provenance rejects")
	corrupt = loaded.save_data(); corrupt.profile = "generated_inventory/v2"
	unchanged_rejection(loaded, corrupt, "unknown profile cannot silently migrate")
	# Failed file operation must preserve an existing valid file and in-memory transaction.
	check(loaded.save_file("user://inventory_preserved.json").ok, "baseline save before induced file failure")
	var disk := FileAccess.get_file_as_string("user://inventory_preserved.json")
	DirAccess.make_dir_absolute("user://inventory_preserved.json.tmp")
	before = C.bytes(loaded.save_data())
	check(not loaded.save_file("user://inventory_preserved.json").ok and C.bytes(loaded.save_data()) == before and FileAccess.get_file_as_string("user://inventory_preserved.json") == disk, "failed temporary save loses no item, old file or RNG")
	DirAccess.remove_absolute("user://inventory_preserved.json.tmp")
	# Legacy protocols remain byte-exact, never gain supplies or inventory resolvers.
	var old := Seeded.new(); check(old.start_seeded(envelope).ok, "old v2 still admits source")
	var old_exact := C.bytes(old.save_data())
	check(not old.load_data(loaded.save_data()).ok and C.bytes(old.save_data()) == old_exact, "old adapter refuses inventory save without mutation")
	unchanged_rejection(loaded, old.save_data(), "inventory adapter refuses v2 instead of granting supplies")
	check(old.state_copy().items.is_empty() and old.state_copy().actors.actor_player.inventory.is_empty(), "existing v2 profile receives no automatic supply")
	var old_focus := old.tile_reference(old.state_copy().actors.actor_player.hex)
	check(old.begin_intent(old.sample_goal("observe", old_focus), old_focus).ok and old.prepare_fixture().ok and old.roll_once().ok, "old v2 locked action remains supported")
	var old_pending := C.bytes(old.save_data()); var old_restored := Seeded.new()
	check(old_restored.load_data(JSON.parse_string(old_pending)).ok and C.bytes(old_restored.save_data()) == old_pending, "old v2 pending source/context/RNG survives new code exactly")
	var reset: RefCounted = loaded.restarted()
	check(reset.ready().ok and reset.state_copy().turn == 0 and reset.state_copy().actors.actor_player.inventory == [item.id] and C.bytes(reset.generation_envelope()) == C.bytes(loaded.generation_envelope()), "explicit reset keeps profile/source and restores only one starting item")
	check(FileAccess.get_file_as_string("user://inventory_preserved.json") == disk, "reset never overwrites saved progress")
	finish()
func finish() -> void:
	var report := {"checks": checks, "failures": failures, "scope": "One explicit starting travel bundle, assessed whole-stack drop/pickup with source dry reach; exact profile/save/RNG and old v2 compatibility. No live model or generated society."}
	var file := FileAccess.open("res://artifacts/generated_inventory_20261004/adapter_report.json", FileAccess.WRITE); file.store_string(JSON.stringify(report, "\t")); file.close()
	print("GENERATED INVENTORY ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
