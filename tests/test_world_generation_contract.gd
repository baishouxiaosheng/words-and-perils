extends SceneTree
const Contract = preload("res://core/world_generation_contract.gd")
const Validation = preload("res://core/world_generation_validation.gd")
const Generator = preload("res://core/world_generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array = []
var rows: Array = []
var producer_calls := 0

func _initialize() -> void:
	_run()
	var evidence := {"engine": Engine.get_version_info().string, "assertions": checks, "failures": failures, "measurements": rows, "scope": "Seed normalization, preset/source invariants, deterministic retry/fail-closed behavior, metadata roundtrip, representative/extreme seeds; exact renderer navigation only where explicitly marked, no visual or target-hardware certification."}
	var file := FileAccess.open("res://tests/seeded_world/report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(evidence, "\t", true, true)); file.close()
	for failure in failures: printerr("FAIL: " + str(failure))
	print("SEEDED WORLD CONTRACT: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	for value in [0, 1, -1, 726381, -2147483647, 2147483647]:
		var normalized := Contract.normalize_seed(value)
		_check(normalized.ok and normalized.normalized_seed == value and normalized.normalization_mode == "preserved_integer", "adapter-safe integer preserved: " + str(value))
		_check(Contract.normalize_seed(str(value)) == normalized, "integer and canonical decimal text agree")
	for value in [-2147483648, 2147483648, -9223372036854775807, 9223372036854775807, "922337203685477580812345", "雾岸-任意种子", "001", "-0"]:
		var normalized := Contract.normalize_seed(value)
		_check(normalized.ok and normalized.normalization_mode == "hashed_text" and normalized.normalized_seed >= 0 and normalized.normalized_seed < Contract.SEED_LIMIT, "large/extreme/text seed explicitly hashed: " + str(value))
		_check(Contract.normalize_seed(value) == normalized, "normalization repeatable")
		_check(Contract.normalize_seed(normalized.seed_token) == normalized, "seed token roundtrips exactly without JSON precision loss")
	_check(Contract.normalize_seed("  726381\n").normalized_seed == 726381, "edge whitespace is explicit normalization")
	for value in [null, true, 1.0, NAN, INF, {}, [], "", "  ", "x".repeat(257)]:
		_check(not Contract.normalize_seed(value).ok, "unsafe seed input rejected: " + str(value))
	_check(not Contract.make_request(1, "future_preset").ok, "unknown preset rejected")
	_check(not Contract.make_request(1, "compact_coast", 3).ok and not Contract.make_request(1, "compact_coast", 25).ok, "radius never silently clamped")
	for preset in Contract.PRESETS:
		_check(Contract.make_request(1, preset).request.board_radius == Contract.PRESETS[preset].radius, "preset default extent")
	var specimens: Array = []
	for radius in [4, 10, 24]:
		for seed_value in [0, 1, -91, 726381, -2147483648, 2147483647, "9223372036854775807", "雾岸-任意种子"]:
			specimens.append([seed_value, radius])
	# Fixed-domain property representatives are independent of global RNG/time.
	for index in range(8): specimens.append(["property_" + str(index), 4 + index * 2])
	var showcase: Dictionary = {}
	for specimen in specimens:
		var started := Time.get_ticks_usec()
		var result := Contract.generate(specimen[0], "coast_exploration", specimen[1])
		var milliseconds := (Time.get_ticks_usec() - started) / 1000.0
		_check(result.ok, "representative generation accepted: " + str(specimen) + " " + str(result.get("attempts", [])))
		if not result.ok: continue
		_check(result.metadata.attempts.size() <= 3 and result.metadata.attempts[-1].accepted, "accepted candidate carries bounded explicit attempt trail")
		_check(Contract.validate_envelope(result).ok, "source and persistable metadata validate together")
		_check(result.source.seed == result.metadata.effective_seed and result.source.board_radius == specimen[1], "effective seed/extent never concealed")
		_check(not result.metadata.diagnostics.renderer_navigation_checked and not result.metadata.diagnostics.visual_quality_checked, "structural gate does not claim visual/mesh authority")
		_check(not result.source.has("generation_metadata") and result.source.keys().size() == Validation.SOURCE_FIELDS.size(), "source schema stays unchanged")
		rows.append({"requested_seed": str(specimen[0]), "radius": specimen[1], "effective_seed": result.source.seed, "attempts": result.metadata.attempts, "source_hash": result.source.content_hash, "milliseconds": milliseconds, "diagnostics": result.metadata.diagnostics})
		if specimen[0] is int and specimen[0] == 726381 and specimen[1] == 4: showcase = result
		print("seed=%s radius=%d effective=%d attempts=%d ms=%.1f" % [str(specimen[0]), specimen[1], result.source.seed, result.metadata.attempts.size(), milliseconds])
	_check(not showcase.is_empty(), "canonical compact specimen available")
	if showcase.is_empty(): return
	var repeated := Contract.generate(726381, "coast_exploration", 4)
	_check(C.bytes(showcase) == C.bytes(repeated), "same version/seed/preset/config yields byte-identical envelope")
	var parser := JSON.new(); parser.parse(C.bytes(showcase))
	_check(Contract.validate_envelope(parser.data).ok and C.bytes(parser.data) == C.bytes(showcase), "complete source/metadata JSON roundtrip exact")
	var request: Dictionary = Contract.make_request(726381, "compact_coast").request
	producer_calls = 0
	var recovered := Contract._generate_request(request, _reject_first)
	_check(recovered.ok and recovered.metadata.retry_used and recovered.metadata.selected_attempt >= 1 and producer_calls <= 3, "failed original candidate uses bounded explicit derived retry")
	if recovered.ok:
		_check(recovered.source.seed != request.normalized_seed, "retry changes effective seed and retains original token")
		producer_calls = 0
		_check(C.bytes(Contract._generate_request(request, _reject_first)) == C.bytes(recovered), "retry trail and output repeat exactly")
	producer_calls = 0
	var rejected := Contract._generate_request(request, _reject_all)
	_check(not rejected.ok and producer_calls == 3 and rejected.attempts.size() == 3 and rejected.source.is_empty() and rejected.fallback == "preserve_existing_world", "total failure ends after exactly three attempts with safe nonreplacement")
	_check(Contract.attempt_seed(request, 0) == request.normalized_seed and Contract.attempt_seed(request, 1) != Contract.attempt_seed(request, 2), "retry derivation uses stable indexed domains")
	var child := Contract.derive_child_seed(showcase.metadata, "local_map", "harbor/warehouse_01", "room_graph/v1")
	_check(child.ok and not child.implemented_content, "future local-map seed has an explicit unimplemented-content marker")
	_check(child == Contract.derive_child_seed(showcase.metadata, "local_map", "harbor/warehouse_01", "room_graph/v1"), "local-map identity regenerates independent of visitation order")
	_check(child.seed != Contract.derive_child_seed(showcase.metadata, "npc_placement", "harbor/warehouse_01", "room_graph/v1").seed, "NPC placement has a separate future seed domain")
	_check(child.seed != Contract.derive_child_seed(showcase.metadata, "local_map", "harbor/warehouse_02", "room_graph/v1").seed, "stable location identity changes child seed")
	_check(child.seed != Contract.derive_child_seed(showcase.metadata, "local_map", "harbor/warehouse_01", "room_graph/v2").seed, "content version changes child seed explicitly")
	_check(not Contract.derive_child_seed(showcase.metadata, "anything", "id", "v1").ok, "unregistered child domain rejected")
	_test_tampering(showcase)
	_test_navigation(showcase)
	_check(checks >= 220, "full intended contract test matrix completed")

func _reject_first(seed_value: int, radius: int) -> Dictionary:
	producer_calls += 1
	return {} if producer_calls == 1 else Generator.generate(seed_value, radius, {"generator_version": Generator.BIOMES_VERSION})

func _reject_all(_seed_value: int, _radius: int) -> Dictionary:
	producer_calls += 1
	return {}

func _test_tampering(original: Dictionary) -> void:
	for field in ["contract_version", "metadata_hash", "source_content_hash", "engine_version", "generator_file_sha256"]:
		var bad: Dictionary = original.duplicate(true); bad.metadata[field] = "changed"
		_check(not Contract.validate_envelope(bad).ok, "metadata tampering rejected: " + field)
	var bad: Dictionary = original.duplicate(true); bad.source.hexes["0,0"].q = 10000
	var unsigned: Dictionary = bad.source.duplicate(true); unsigned.erase("content_hash"); bad.source.content_hash = C.digest(unsigned)
	_check(not Validation.validate_source(bad.source).ok, "re-signing out-of-world cells does not bypass reproduction")
	bad = original.duplicate(true); bad.source.seed += 1
	unsigned = bad.source.duplicate(true); unsigned.erase("content_hash"); bad.source.content_hash = C.digest(unsigned)
	_check(not Validation.validate_source(bad.source).ok, "swapped seed cannot masquerade as reproducible geography")
	for value in [null, {}, {"hexes": []}, "world", true]: _check(not Validation.validate_source(value).ok, "malformed source fails without mutation")
	for mutation in ["diagnostics", "attempts", "request"]:
		bad = original.duplicate(true); bad.metadata[mutation] = {}
		unsigned = bad.metadata.duplicate(true); unsigned.erase("metadata_hash"); bad.metadata.metadata_hash = C.digest(unsigned)
		_check(not Contract.validate_envelope(bad).ok, "re-signed malformed metadata rejected: " + mutation)
	_check(Contract.validate_envelope(original).ok, "failure paths leave original candidate unchanged")

func _test_navigation(specimen: Dictionary) -> void:
	# The one exact renderer-navigation admission is radius4, no mesh bake or
	# frame-time test. Larger source specimens remain structural evidence only.
	var started := Time.get_ticks_usec()
	var admitted := Contract.admit_gameplay(specimen)
	_check(admitted.ok, "compact source passes actual renderer-derived navigation gate: " + str(admitted))
	rows.append({"exact_navigation_radius": 4, "source_hash": specimen.source.content_hash, "result": admitted, "milliseconds": (Time.get_ticks_usec() - started) / 1000.0})
	var graph := {}; var supported := {}
	for key in specimen.source.hexes: graph[key] = []; supported[key] = true
	_check(not Validation.validate_navigation(specimen.source, graph, supported, [0, 0]).ok, "isolated starting cell rejected")
	graph["0,0"] = ["999,999"]
	_check(not Validation.validate_navigation(specimen.source, graph, supported, [0, 0]).ok, "out-of-world graph edge rejected")
	graph["0,0"] = ["1,0"]
	_check(not Validation.validate_navigation(specimen.source, graph, supported, [0, 0]).ok, "asymmetric graph edge rejected")
	graph["1,0"] = ["0,0"]; supported["1,0"] = false
	_check(not Validation.validate_navigation(specimen.source, graph, supported, [0, 0]).ok, "wet graph destination rejected")
