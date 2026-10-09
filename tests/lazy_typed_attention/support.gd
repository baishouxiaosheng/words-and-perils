extends RefCounted
## Test-only harness: real source admission, exact engine snapshots, no authority cache.
const Adapter = preload("res://view/generated_v3_npc/adapter.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const OldEngine = preload("res://tests/lazy_typed_attention/generated/old_engine.gd")
const NewEngine = preload("res://tests/lazy_typed_attention/generated/new_engine.gd")
const TYPED = ["source-npc-focus/v1", "source-vegetation-focus/v1", "source-static-focus/v1", "source-entity-focus/v1"]
var checks: int = 0
var failures: Array = []
var rows: Array = []
var pair: Dictionary = {}
var authoritative_engine: RefCounted

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("LAZY_ATTENTION_FAIL ", label)
	return ok

func admit() -> RefCounted:
	var generated: Dictionary = Generator.generate(726381, 12, "coastal_range")
	if not check(generated.get("ok", false), "real r12 coastal generator succeeded"): return null
	var adapter = Adapter.new()
	adapter.feature_options = {"vegetation": true}
	var result: Dictionary = adapter.start_source(generated.source)
	if not check(result.ok, "real NPC + vegetation Source/Adapter admission: " + str(result.get("errors", []))): return null
	return adapter

func engines_for(adapter: RefCounted) -> bool:
	# Capture exact production bytes, including RNG, pending context and receipt identities.
	authoritative_engine = adapter.engine
	var saved: Dictionary = authoritative_engine.save_data()
	pair = {}
	for variant in ["old", "new"]:
		var script = OldEngine if variant == "old" else NewEngine
		var engine = script.new(authoritative_engine._state, authoritative_engine._calculator, authoritative_engine._resolvers, authoritative_engine._policy)
		if not check(engine.ready().ok, variant + " engine constructed from admitted state"): return false
		var loaded: Dictionary = engine.load_data(saved.duplicate(true))
		if not check(loaded.ok and C.bytes(engine.save_data()) == C.bytes(saved), variant + " exact engine save + RNG load"): return false
		pair[variant] = engine
	return true

func restore(adapter: RefCounted) -> void:
	adapter.engine = authoritative_engine

static func identity(adapter: RefCounted) -> Dictionary:
	var saved: Dictionary = adapter.save_data()
	return {
		"save": C.bytes(saved),
		"rng": C.bytes(saved.engine.rng),
		"world": C.bytes(saved.engine.state),
		"request": C.bytes(adapter.request()),
		"pending_target": C.bytes(adapter.action_copy().get("focus", {})),
		"active_action": adapter.active_action,
		"last_action": adapter.last_action,
		"phase": adapter.phase(),
	}

func parity(adapter: RefCounted, reference: Dictionary, label: String, expected_ok: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var outputs: Dictionary = {}
	var calls: Dictionary = {}
	var baselines: Dictionary = {}
	var reference_bytes: String = C.bytes(reference)
	for variant in ["old", "new"]:
		adapter.engine = pair[variant]
		baselines[variant] = identity(adapter)
		adapter.engine.facts_calls = 0
		result = adapter.attention(reference)
		calls[variant] = adapter.engine.facts_calls
		outputs[variant] = C.bytes(result)
		check(identity(adapter) == baselines[variant], label + " " + variant + " save/RNG/request/pending target read-only")
		check(C.bytes(reference) == reference_bytes, label + " " + variant + " caller reference unmodified")
		check(result.get("ok", false) == expected_ok, label + " " + variant + " expected acceptance")
		var expected_calls: int = 0
		if result.get("ok", false):
			expected_calls = 0 if variant == "new" and result.get("focus", {}).get("catalog_version", "") in TYPED else 1
		check(calls[variant] == expected_calls, label + " " + variant + " actual full-facts calls " + str(calls[variant]))
	check(outputs.old == outputs.new, label + " byte-exact old/new attention output")
	check(baselines.old == baselines.new, label + " identical old/new authoritative input and request identity")
	rows.append({"label": label, "ok": result.get("ok", false), "catalog_version": reference.get("catalog_version", "legacy"), "facts_calls": calls, "output_sha256": outputs.new.sha256_text(), "save_sha256": baselines.new.save.sha256_text(), "request_sha256": baselines.new.request.sha256_text()})
	restore(adapter)
	return result

static func references(adapter: RefCounted) -> Array:
	var state: Dictionary = adapter.state_copy()
	var result: Array = [
		{"label": "npc", "reference": adapter.npc_reference()},
		{"label": "item", "reference": adapter.item_reference()},
	]
	var seen: Dictionary = {}
	for id in state.generated_world.static_entity_catalog.entries:
		var descriptor: Dictionary = state.generated_world.static_entity_catalog.entries[id]
		if not seen.has(descriptor.kind):
			result.append({"label": "static_" + descriptor.kind, "reference": adapter.static_reference(id)})
			seen[descriptor.kind] = true
	var plants: Array = state.generated_world.vegetation_entity_catalog.entries.keys()
	plants.sort()
	if not plants.is_empty(): result.append({"label": "vegetation", "reference": adapter.vegetation_reference(plants[0])})
	var actor: Dictionary = state.actors.actor_player
	result.append({"label": "legacy_actor", "reference": {"world_id": state.world_id, "kind": "actor", "id": actor.id, "hex": actor.hex.duplicate(), "scene_id": actor.scene_id}})
	result.append({"label": "legacy_tile", "reference": adapter.tile_reference(actor.hex)})
	result.append({"label": "empty", "reference": {}})
	return result

func execute(adapter: RefCounted, kind: String, reference: Dictionary = {}) -> bool:
	var begun: Dictionary = adapter.begin_intent(adapter.sample_goal(kind, reference), reference)
	if not check(begun.ok, "real assessed " + kind + " begins: " + str(begun.get("errors", []))): return false
	for step in ["prepare_fixture", "roll_once", "stage", "commit"]:
		var result: Dictionary = adapter.call(step)
		if not check(result.ok, "real assessed " + kind + " " + step + ": " + str(result.get("errors", []))): return false
	return true

func write_report(path: String, extra: Dictionary = {}) -> void:
	var report: Dictionary = {"schema": "lazy_typed_attention_test/v1", "ok": failures.is_empty(), "checks": checks, "failures": failures, "cases": rows}
	report.merge(extra)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "report output open: " + path)
		return
	file.store_string(JSON.stringify(report, "\t")); file.close()
