extends "res://view/generated_adventure/adapter.gd"
## New seeded starts keep detached provenance. Legacy v1 remains an exact v1 save.
const Legacy = preload("res://view/generated_adventure/adapter.gd")
const SeedContract = preload("res://core/world_generation_contract.gd")
const SeedValidation = preload("res://core/world_generation_validation.gd")
const SEEDED_SAVE_SCHEMA := "generated_adventure_save/v2"
const SEEDED_SAVE := "user://generated_adventure_v2.json"
var generation_metadata: Dictionary = {}
var gameplay_admission: Dictionary = {}

func start_seeded(envelope: Variant) -> Dictionary:
	if source != null or engine != null:
		return C.fail("SEEDED_ALREADY_STARTED", "Create a separate candidate; an existing adventure cannot be replaced by a new seed.")
	var checked := SeedContract.validate_envelope(envelope)
	if not checked.ok: admission = checked; return checked
	var candidate := Legacy.new(envelope.source)
	checked = candidate.ready()
	if checked.ok: checked = _check_gameplay(candidate)
	if not checked.ok: admission = checked; return checked
	_publish(candidate, envelope.metadata, checked)
	return {"ok": true, "admission": gameplay_admission.duplicate(true)}

func _check_gameplay(candidate: RefCounted) -> Dictionary:
	# Same exact-geometry gate as SeedContract.admit_gameplay, reusing the newly
	# admitted source instead of baking its terrain a second time. Never accept a
	# caller-provided navigation graph as clearance evidence.
	return SeedValidation.validate_navigation(candidate.source.data, candidate.source.navigation.allowed, candidate.source.navigation.supported, candidate.source.world.actors.actor_player.hex)

func _publish(candidate: RefCounted, metadata: Dictionary, checked: Dictionary) -> void:
	source = candidate.source; engine = candidate.engine
	active_action = candidate.active_action; last_action = candidate.last_action
	narration = candidate.narration; last_feedback = candidate.last_feedback
	generation_metadata = metadata.duplicate(true)
	gameplay_admission = {"admission_status": "exact_renderer_navigation_validated", "source_metadata_hash": metadata.metadata_hash, "identity": source.identity.duplicate(true), "start": source.world.actors.actor_player.hex.duplicate(), "navigation": checked.duplicate(true), "visual_quality_checked": false}
	admission = {"ok": true}

func generation_envelope() -> Dictionary:
	return {"source": source.data.duplicate(true), "metadata": generation_metadata.duplicate(true)} if source != null and not generation_metadata.is_empty() else {}

func restarted() -> RefCounted:
	var candidate = get_script().new()
	if generation_metadata.is_empty(): candidate.admission = candidate._install(source.data)
	else: candidate.start_seeded(generation_envelope())
	return candidate

func save_data() -> Dictionary:
	var result := super.save_data()
	if result.is_empty() or generation_metadata.is_empty(): return result
	result.schema_version = SEEDED_SAVE_SCHEMA
	result["generation_metadata"] = generation_metadata.duplicate(true)
	return result

func save_file(path: String = "") -> Dictionary:
	return super.save_file(default_save_path() if path.is_empty() else path)

func default_save_path() -> String:
	return GENERATED_SAVE if generation_metadata.is_empty() else SEEDED_SAVE

func load_file(path: String = "") -> Dictionary:
	if path.is_empty():
		# Existing adventures keep their own namespace. A fresh Continue prefers
		# v2 if present, but a corrupt v2 never silently falls back to older progress.
		path = default_save_path() if source != null else (SEEDED_SAVE if FileAccess.file_exists(SEEDED_SAVE) else GENERATED_SAVE)
	return super.load_file(path)

func load_data(value: Variant) -> Dictionary:
	if value is Dictionary and value.get("schema_version") == SAVE_SCHEMA:
		if not generation_metadata.is_empty(): return C.fail("SEEDED_SAVE_LINEAGE", "A seeded adventure cannot silently discard its generation metadata for a v1 save.")
		return super.load_data(value)
	if not C.exact_fields(value, ["schema_version", "source", "generation_metadata", "engine"]) or value.schema_version != SEEDED_SAVE_SCHEMA or not value.source is Dictionary or not value.generation_metadata is Dictionary or not value.engine is Dictionary or not C.safe(value):
		return C.fail("SEEDED_SAVE_SCHEMA", "Expected an exact generated_adventure_save/v2 envelope, or an unchanged legacy v1 save.")
	if C.bytes(value).to_utf8_buffer().size() > MAX_SAVE_BYTES: return C.fail("GENERATED_SAVE_BUDGET", "Save exceeds the bounded format; current adventure is preserved.")
	if source != null and (generation_metadata.is_empty() or value.source.get("content_hash") != source.identity.content_hash or C.bytes(value.generation_metadata) != C.bytes(generation_metadata)):
		return C.fail("SEEDED_SAVE_LINEAGE", "Load a different source or seed lineage as a separate adventure; no implicit migration is allowed.")
	var checked := SeedContract.validate_envelope({"source": value.source, "metadata": value.generation_metadata})
	if not checked.ok: return checked
	var candidate := Legacy.new()
	checked = candidate.load_data({"schema_version": SAVE_SCHEMA, "source": value.source, "engine": value.engine})
	if not checked.ok: return checked
	checked = _check_gameplay(candidate)
	if not checked.ok: return checked
	# Publication happens only after provenance, exact navigation, immutable
	# world and every pending context/plan/RNG/stage have all passed validation.
	_publish(candidate, value.generation_metadata, checked)
	return {"ok": true, "exact_pending": not active_action.is_empty()}
