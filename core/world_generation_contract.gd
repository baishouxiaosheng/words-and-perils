extends RefCounted
## Opt-in seed/preset contract. The accepted coast and legacy source remain intact.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator = preload("res://core/world_generator.gd")
const Validation = preload("res://core/world_generation_validation.gd")
const ID := "seed_preset_contract/v1"
const PRESET_VERSION := "macro_coast_presets/v1"
const NORMALIZATION := "utf8_trim_sha256_adapter32/v1"
const DERIVATION := "canonical_domain_sha256/v1"
const MAX_ATTEMPTS := 3
const MAX_SEED_BYTES := 256
const SEED_LIMIT := 2147483647
const PRESETS := {
	"compact_coast": {"radius": 4, "label": "紧凑海岸"},
	"coast_exploration": {"radius": 10, "label": "海岸探索"},
	"wide_coast": {"radius": 24, "label": "广域海岸"}
}

static func normalize_seed(value: Variant) -> Dictionary:
	if not (value is int or value is String): return C.fail("SEED_TYPE", "Seed must be an integer or nonempty text; floating-point seeds are rejected.")
	var token := str(value).strip_edges()
	if token.is_empty() or token.to_utf8_buffer().size() > MAX_SEED_BYTES: return C.fail("SEED_LENGTH", "Seed text must contain 1–256 UTF-8 bytes after trimming.")
	# Preserve canonical integers already admitted by the existing source.
	# Decimal strings avoid JSON rounding for full int64/long user seeds.
	var parsed := token.to_int() if token.length() <= 11 and token.is_valid_int() else 0
	var direct := token.is_valid_int() and str(parsed) == token and parsed >= -SEED_LIMIT and parsed <= SEED_LIMIT
	var normalized := parsed if direct else _digest_seed([NORMALIZATION, token])
	return {"ok": true, "seed_token": token, "normalized_seed": normalized, "normalization_version": NORMALIZATION, "normalization_mode": "preserved_integer" if direct else "hashed_text"}

static func make_request(seed_value: Variant, preset_id: String = "coast_exploration", radius: int = 0) -> Dictionary:
	if not PRESETS.has(preset_id): return C.fail("SEED_PRESET", "Unknown preset; a supported versioned preset is required.")
	var normalized := normalize_seed(seed_value)
	if not normalized.ok: return normalized
	var actual_radius := int(PRESETS[preset_id].radius) if radius == 0 else radius
	if actual_radius < Generator.MIN_RADIUS or actual_radius > Generator.MAX_RADIUS: return C.fail("SEED_RADIUS", "Radius must be from 4 through 24; out-of-range input is never silently clamped.")
	return {"ok": true, "request": {"contract_version": ID, "preset_version": PRESET_VERSION, "preset_id": preset_id, "generator_version": Generator.BIOMES_VERSION, "seed_token": normalized.seed_token, "normalized_seed": normalized.normalized_seed, "normalization_version": NORMALIZATION, "normalization_mode": normalized.normalization_mode, "board_radius": actual_radius, "recipe_options": {"generator_version": Generator.BIOMES_VERSION}, "max_attempts": MAX_ATTEMPTS, "failure_policy": "reject_candidate_preserve_existing_world"}}

static func generate(seed_value: Variant, preset_id: String = "coast_exploration", radius: int = 0) -> Dictionary:
	var prepared := make_request(seed_value, preset_id, radius)
	if not prepared.ok: return prepared
	return _generate_request(prepared.request, func(seed: int, extent: int) -> Dictionary: return Generator.generate(seed, extent, {"generator_version": Generator.BIOMES_VERSION}))

static func _generate_request(request: Dictionary, producer: Callable) -> Dictionary:
	# Internal producer seam is only for deterministic failure/retry tests.
	# Validation reproduces source, so a custom producer cannot authorize edits.
	var attempts: Array = []
	for index in range(MAX_ATTEMPTS):
		var effective := attempt_seed(request, index)
		var source: Variant = producer.call(effective, int(request.board_radius))
		var checked := Validation.validate_source(source)
		if checked.ok and (source.seed != effective or source.board_radius != request.board_radius): checked = C.fail("SEED_RECIPE_IDENTITY", "Producer returned a different seed or radius.")
		attempts.append({"attempt": index, "effective_seed": effective, "accepted": checked.ok, "code": checked.get("code", "OK"), "errors": checked.get("errors", [])})
		if not checked.ok: continue
		var metadata := {"contract_version": ID, "request": request.duplicate(true), "attempts": attempts, "selected_attempt": index, "effective_seed": effective, "retry_used": index > 0, "source_content_hash": source.content_hash, "generator_file_sha256": FileAccess.get_sha256("res://core/world_generator.gd"), "validation_file_sha256": FileAccess.get_sha256("res://core/world_generation_validation.gd"), "contract_file_sha256": FileAccess.get_sha256("res://core/world_generation_contract.gd"), "engine_version": Engine.get_version_info().string, "derivation_version": DERIVATION, "diagnostics": checked.diagnostics, "admission_status": "source_validated_gameplay_pending"}
		metadata["metadata_hash"] = C.digest(metadata)
		return {"ok": true, "source": source.duplicate(true), "metadata": metadata, "notice": "原始种子已通过校验" if index == 0 else "原始候选未通过，已使用明确记录的派生重试种子 %d" % effective}
	return {"ok": false, "code": "SEED_ATTEMPTS_EXHAUSTED", "errors": ["All three deterministic candidates failed; preserve the existing world and report the attempt log."], "request": request.duplicate(true), "attempts": attempts, "fallback": "preserve_existing_world", "source": {}}

static func attempt_seed(request: Dictionary, index: int) -> int:
	if index == 0: return int(request.normalized_seed)
	return _digest_seed([DERIVATION, "world_retry", request.contract_version, request.preset_version, request.preset_id, request.normalized_seed, request.board_radius, index])

static func derive_child_seed(metadata: Dictionary, domain: String, stable_location_id: String, content_version: String) -> Dictionary:
	if not domain in ["local_map", "npc_placement"] or stable_location_id.is_empty() or stable_location_id.to_utf8_buffer().size() > 192 or content_version.is_empty() or content_version.to_utf8_buffer().size() > 96:
		return C.fail("SEED_CHILD_DOMAIN", "Use local_map or npc_placement with a stable location ID and explicit content version.")
	var checked := validate_metadata(metadata)
	if not checked.ok: return checked
	var identity := {"derivation_version": DERIVATION, "world_source_hash": metadata.source_content_hash, "effective_world_seed": metadata.effective_seed, "world_generator_version": metadata.request.generator_version, "world_preset_version": metadata.request.preset_version, "domain": domain, "location_id": stable_location_id, "content_version": content_version}
	return {"ok": true, "seed": _digest_seed(identity), "identity": identity, "implemented_content": false}

static func validate_metadata(value: Variant) -> Dictionary:
	var fields := ["contract_version", "request", "attempts", "selected_attempt", "effective_seed", "retry_used", "source_content_hash", "generator_file_sha256", "validation_file_sha256", "contract_file_sha256", "engine_version", "derivation_version", "diagnostics", "admission_status", "metadata_hash"]
	if not C.exact_fields(value, fields) or not C.safe(value): return C.fail("SEED_METADATA_SCHEMA", "Generation metadata is incomplete or unsafe.")
	var unsigned: Dictionary = value.duplicate(true); unsigned.erase("metadata_hash")
	if value.metadata_hash != C.digest(unsigned) or value.contract_version != ID or value.derivation_version != DERIVATION or value.admission_status != "source_validated_gameplay_pending": return C.fail("SEED_METADATA_HASH", "Generation metadata version/hash is unsupported.")
	if not value.request is Dictionary or not value.request.get("seed_token") is String or not value.request.get("preset_id") is String or not C.integer(value.request.get("board_radius")): return C.fail("SEED_METADATA_REQUEST", "Generation metadata request is malformed.")
	var rebuilt := make_request(value.request.seed_token, value.request.preset_id, int(value.request.board_radius))
	if not rebuilt.ok or C.bytes(rebuilt.request) != C.bytes(value.request): return C.fail("SEED_METADATA_REQUEST", "Request does not reproduce under the declared seed/preset contract.")
	if not C.integer(value.selected_attempt) or value.selected_attempt < 0 or value.selected_attempt >= MAX_ATTEMPTS or not value.attempts is Array or value.attempts.size() != int(value.selected_attempt) + 1 or value.effective_seed != attempt_seed(value.request, int(value.selected_attempt)) or not value.retry_used is bool or value.retry_used != (value.selected_attempt > 0): return C.fail("SEED_METADATA_RETRY", "Attempt lineage is inconsistent.")
	for index in range(value.attempts.size()):
		var row: Variant = value.attempts[index]
		if not C.exact_fields(row, ["attempt", "effective_seed", "accepted", "code", "errors"]) or row.attempt != index or row.effective_seed != attempt_seed(value.request, index) or not row.accepted is bool or row.accepted != (index == value.selected_attempt) or not row.code is String or not row.errors is Array: return C.fail("SEED_METADATA_RETRY", "Attempt record is malformed.")
	for field in ["source_content_hash", "generator_file_sha256", "validation_file_sha256", "contract_file_sha256"]:
		if not _hash(value[field]): return C.fail("SEED_METADATA_HASH", "Expected an exact SHA256 identity.")
	if value.engine_version != Engine.get_version_info().string or value.generator_file_sha256 != FileAccess.get_sha256("res://core/world_generator.gd") or value.validation_file_sha256 != FileAccess.get_sha256("res://core/world_generation_validation.gd") or value.contract_file_sha256 != FileAccess.get_sha256("res://core/world_generation_contract.gd"): return C.fail("SEED_METADATA_PIPELINE", "Use the original engine and pipeline package to reproduce this metadata.")
	return {"ok": true}

static func validate_envelope(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("source") is Dictionary or not value.get("metadata") is Dictionary: return C.fail("SEED_ENVELOPE", "Expected detached source and generation metadata.")
	var checked := validate_metadata(value.metadata)
	if not checked.ok: return checked
	if value.source.get("content_hash") != value.metadata.source_content_hash or value.source.get("seed") != value.metadata.effective_seed or value.source.get("board_radius") != value.metadata.request.board_radius: return C.fail("SEED_ENVELOPE_IDENTITY", "Source and metadata identify different worlds.")
	var source_check := Validation.validate_source(value.source)
	if not source_check.ok: return source_check
	if C.bytes(value.metadata.diagnostics) != C.bytes(source_check.diagnostics): return C.fail("SEED_ENVELOPE_DIAGNOSTICS", "Persisted diagnostics do not match independent validation.")
	return source_check

static func admit_gameplay(value: Variant) -> Dictionary:
	# Opt-in second gate, intentionally absent from cheap preview generation.
	# Existing adapter owns renderer triangles, water clearance, and rules.
	var checked := validate_envelope(value)
	if not checked.ok: return checked
	var adapter_script = load("res://view/generated_adventure/source.gd")
	var adapter = adapter_script.new()
	var admitted: Dictionary = adapter.admit(value.source)
	if not admitted.ok: return admitted
	var graph_check := Validation.validate_navigation(value.source, adapter.navigation.allowed, adapter.navigation.supported, adapter.world.actors.actor_player.hex)
	if not graph_check.ok: return graph_check
	return {"ok": true, "identity": adapter.identity.duplicate(true), "start": adapter.world.actors.actor_player.hex.duplicate(), "navigation": graph_check, "source_metadata_hash": value.metadata.metadata_hash, "admission_status": "exact_renderer_navigation_validated", "visual_quality_checked": false}

static func _digest_seed(value: Variant) -> int:
	# First 32 SHA256 bits fit exactly in int64; modulo is explicitly versioned.
	return int(C.digest(value).substr(0, 8).hex_to_int() % SEED_LIMIT)

static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
