extends "res://view/generated_adventure/seeded_adapter.gd"
## Explicit new-start profile. Never upgrades or downgrades an existing save.
const InventorySource = preload("res://view/generated_inventory/source.gd")
const InventoryResolver = preload("res://view/generated_inventory/resolver.gd")
const InventoryRule = preload("res://view/generated_inventory/rule.gd")
const InventoryExamples = preload("res://view/generated_inventory/assessments.gd")
const INVENTORY_SAVE_SCHEMA := "generated_inventory_save/v1"
const INVENTORY_SAVE := "user://generated_inventory_v1.json"
func _install(_generated: Dictionary) -> Dictionary:
	return C.fail("INVENTORY_PROVENANCE_REQUIRED", "Start this profile with an exact seed/preset envelope.")
func _engine_for(candidate: RefCounted) -> RefCounted:
	var registry := {}
	for kind in ["move", "observe", "rest"]:
		var resolver := GeneratedResolver.new(candidate, kind); registry[resolver.resolver_id()] = resolver
	for kind in ["drop_item", "pickup_item"]:
		var resolver := InventoryResolver.new(candidate, kind); registry[resolver.resolver_id()] = resolver
	return GMEngine.new(candidate.world, InventoryRule.new(registry), registry, {"npc_secret_allowlist": [], "public_flag_ids": ["observations", "last_observed_cell"]})
func start_seeded(envelope: Variant) -> Dictionary:
	if source != null or engine != null: return C.fail("SEEDED_ALREADY_STARTED", "Create a separate candidate for a new inventory adventure.")
	var checked := SeedContract.validate_envelope(envelope)
	if not checked.ok: admission = checked; return checked
	var candidate := InventorySource.new()
	checked = candidate.admit(envelope.source)
	if checked.ok: checked = SeedValidation.validate_navigation(candidate.data, candidate.navigation.allowed, candidate.navigation.supported, candidate.world.actors.actor_player.hex)
	if not checked.ok: admission = checked; return checked
	var next_engine := _engine_for(candidate)
	var engine_check: Dictionary = next_engine.ready()
	if not engine_check.ok: admission = engine_check; return engine_check
	_publish_inventory(candidate, next_engine, envelope.metadata, checked)
	return {"ok": true, "admission": gameplay_admission.duplicate(true)}
func _publish_inventory(candidate: RefCounted, next_engine: RefCounted, metadata: Dictionary, checked: Dictionary) -> void:
	source = candidate; engine = next_engine; generation_metadata = metadata.duplicate(true)
	gameplay_admission = {"admission_status": "exact_renderer_navigation_validated", "source_metadata_hash": metadata.metadata_hash, "identity": source.identity.duplicate(true), "start": source.world.actors.actor_player.hex.duplicate(), "navigation": checked.duplicate(true), "visual_quality_checked": false}
	admission = {"ok": true}; active_action = ""; last_action = ""; narration = ""; last_feedback = ""
	var saved: Dictionary = engine.save_data()
	for id in saved.pending: active_action = id
	var latest := -1
	for id in saved.receipts:
		if int(saved.receipts[id].turn) > latest: latest = int(saved.receipts[id].turn); last_action = id
func default_save_path() -> String: return INVENTORY_SAVE
func save_data() -> Dictionary:
	return {"schema_version": INVENTORY_SAVE_SCHEMA, "profile": InventorySource.PROFILE, "source": source.data.duplicate(true), "generation_metadata": generation_metadata.duplicate(true), "engine": engine.save_data()} if ready().ok else {}
func load_file(path: String = "") -> Dictionary:
	return super.load_file(INVENTORY_SAVE if path.is_empty() else path)
func load_data(value: Variant) -> Dictionary:
	if not C.exact_fields(value, ["schema_version", "profile", "source", "generation_metadata", "engine"]) or value.schema_version != INVENTORY_SAVE_SCHEMA or value.profile != InventorySource.PROFILE or not value.source is Dictionary or not value.generation_metadata is Dictionary or not value.engine is Dictionary or not C.safe(value):
		return C.fail("INVENTORY_SAVE_SCHEMA", "Use the matching inventory profile; old v1/v2 saves keep their original profiles.")
	if C.bytes(value).to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("GENERATED_SAVE_BUDGET", "Save exceeds the bounded format; current adventure is preserved.")
	if source != null and (value.source.get("content_hash") != source.identity.content_hash or C.bytes(value.generation_metadata) != C.bytes(generation_metadata)):
		return C.fail("SEEDED_SAVE_LINEAGE", "A different source or seed lineage requires a separate adventure.")
	var checked := SeedContract.validate_envelope({"source": value.source, "metadata": value.generation_metadata})
	if not checked.ok: return checked
	var candidate := InventorySource.new()
	checked = candidate.admit(value.source)
	if checked.ok: checked = candidate.validate_state(value.engine.get("state"))
	if not checked.ok: return checked
	var navigation_check := SeedValidation.validate_navigation(candidate.data, candidate.navigation.allowed, candidate.navigation.supported, candidate.world.actors.actor_player.hex)
	if not navigation_check.ok: return navigation_check
	var next_engine := _engine_for(candidate)
	checked = next_engine.load_data(value.engine)
	if not checked.ok: return checked
	_publish_inventory(candidate, next_engine, value.generation_metadata, navigation_check)
	return {"ok": true, "exact_pending": not active_action.is_empty()}
func sample_goal(kind: String, focus: Dictionary = {}) -> String:
	return InventoryExamples.goal(kind, focus.get("hex", state_copy().get("actors", {}).get("actor_player", {}).get("hex", [])))
func fixture_available() -> bool: return phase() == "awaiting_assessment" and InventoryExamples.build(request()).ok
func prepare_fixture() -> Dictionary:
	if phase() != "awaiting_assessment": return C.fail("FIXTURE_SCOPE", "Submit a complete signed example first.")
	var built := InventoryExamples.build(request())
	return engine.prepare_assessment(built.assessment) if built.ok else built
func commit() -> Dictionary:
	var result: Dictionary = super.commit()
	if result.ok: last_feedback = "行动已由固定程序提交；位置、体力、观察与行礼包归属按本次结果保留。"
	return result
func authority_text() -> String:
	var text := super.authority_text()
	if not ready().ok: return text
	var item: Dictionary = state_copy().items.item_travel_bundle
	return text + ("\n行礼包 ×1 · 随身携带" if item.has("owner_actor_id") else "\n行礼包 ×1 · 地上（%d，%d）" % item.hex)

func supported_focus_kinds() -> Array: return ["tile","actor","item"]
func item_reference(id: String = "item_travel_bundle") -> Dictionary:
	return preload("res://view/generated_inventory/item_focus.gd").make_reference(id,state_copy())
