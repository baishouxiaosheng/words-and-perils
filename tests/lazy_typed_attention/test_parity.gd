extends SceneTree
## Focused regression only. This script never modifies production scripts or save files.
const Support = preload("res://tests/lazy_typed_attention/support.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var suite = Support.new()
var started_us: int

func _initialize() -> void: call_deferred("run")

func finish() -> void:
	suite.write_report("res://artifacts/lazy_typed_attention/parity_report.json", {"elapsed_us": Time.get_ticks_usec() - started_us, "fixture": {"seed": 726381, "radius": 12, "recipe": "coastal_range", "vegetation": true}, "source_admissions": 1})
	print("LAZY_ATTENTION_PARITY ", suite.checks, " ", suite.failures)
	quit(0 if suite.failures.is_empty() else 1)

func valid_batch(adapter: RefCounted, prefix: String) -> void:
	var references: Array = Support.references(adapter)
	var kinds: Dictionary = {}
	for row in references:
		suite.parity(adapter, row.reference, prefix + "/" + row.label)
		kinds[row.reference.get("catalog_version", "legacy")] = true
	for typed in Support.TYPED: suite.check(kinds.has(typed), prefix + " covers " + typed)

func malformed_batch(adapter: RefCounted) -> void:
	# A building cannot silently fall through the older legacy settlement contract.
	for row in Support.references(adapter):
		if row.label not in ["npc", "item", "static_building", "vegetation"]: continue
		var reference: Dictionary = row.reference
		for field in reference.keys():
			var missing: Dictionary = reference.duplicate(true); missing.erase(field)
			suite.parity(adapter, missing, row.label + "/missing_" + field, false)
		for variant in ["extra", "world", "scene", "id", "catalog", "revision", "hex"]:
			var bad: Dictionary = reference.duplicate(true)
			match variant:
				"extra": bad["untrusted_extension"] = true
				"world": bad.world_id += "_foreign"
				"scene": bad.scene_id += "_foreign"
				"id": bad.id += "_missing"
				"catalog": bad.catalog_id = "0".repeat(64)
				"revision":
					if bad.has("entity_revision"): bad.entity_revision += 1
					else: bad.contact_revision += 1
				"hex": bad.hex = [999, 999]
			suite.parity(adapter, bad, row.label + "/invalid_" + variant, false)
		var unsupported: Dictionary = reference.duplicate(true)
		unsupported.catalog_version += "/unrecognized"
		suite.parity(adapter, unsupported, row.label + "/unrecognized_exact_catalog_version", false)
	var npc: Dictionary = adapter.npc_reference()
	var bare: Dictionary = {"world_id": npc.world_id, "kind": "actor", "id": npc.id, "hex": npc.hex, "scene_id": npc.scene_id}
	suite.parity(adapter, bare, "registered_NPC_cannot_bypass_typed_header", false)

func scene_guard_fault_injection(adapter: RefCounted) -> void:
	# Deliberately corrupt ONLY a private test engine's acting scene. This is not
	# an admitted alternate world, a save fixture, or evidence of supported travel.
	var reference: Dictionary = {}
	for row in Support.references(adapter):
		if row.label == "static_building": reference = row.reference; break
	if not suite.check(not reference.is_empty(), "typed static reference for scene guard fault test"): return
	var outputs: Dictionary = {}
	for variant in ["old", "new"]:
		adapter.engine = suite.pair[variant]
		var before: Dictionary = Support.identity(adapter)
		var original: String = adapter.engine._state.actors.actor_player.scene_id
		adapter.engine._state.actors.actor_player.scene_id = "scene_fault_injection_not_admitted"
		var faulted_bytes: String = C.bytes(adapter.engine.save_data())
		adapter.engine.facts_calls = 0
		var result: Dictionary = adapter.attention(reference)
		outputs[variant] = C.bytes(result)
		suite.check(not result.ok and result.get("code") == "FOCUS_SCENE", variant + " unchanged scene guard rejects resolved typed focus")
		suite.check(adapter.engine.facts_calls == 0 and C.bytes(adapter.engine.save_data()) == faulted_bytes, variant + " scene guard returns before facts and has no side effects")
		adapter.engine._state.actors.actor_player.scene_id = original
		suite.check(Support.identity(adapter) == before, variant + " private negative-test fault restored immediately")
	suite.check(outputs.old == outputs.new, "FOCUS_SCENE error byte-exact old/new parity")
	suite.restore(adapter)

func run() -> void:
	started_us = Time.get_ticks_usec()
	var adapter = suite.admit()
	if adapter == null or not suite.engines_for(adapter): finish(); return
	valid_batch(adapter, "initial")
	malformed_batch(adapter)
	scene_guard_fault_injection(adapter)
	var carried_before_move: Dictionary = adapter.item_reference()
	var start: Array = adapter.state_copy().actors.actor_player.hex
	var neighbors: Array = adapter.source.navigation.allowed["%d,%d" % start]
	var destination: Array = []
	for key in neighbors:
		var parts: PackedStringArray = String(key).split(",")
		var hex: Array = [int(parts[0]), int(parts[1])]
		if adapter.movement_preview(hex).ok: destination = hex; break
	if not suite.check(not destination.is_empty(), "a legitimate affordable move exists"): finish(); return
	if not suite.execute(adapter, "move", adapter.tile_reference(destination)): finish(); return
	if not suite.engines_for(adapter): finish(); return
	suite.parity(adapter, carried_before_move, "post_move/old_carried_location_rejected", false)
	suite.parity(adapter, adapter.item_reference(), "post_move/current_carried_item")
	suite.parity(adapter, adapter.tile_reference(destination), "post_move/legacy_destination")
	var carried_before_drop: Dictionary = adapter.item_reference()
	if adapter.state_copy().actors.actor_player.stamina.current < 1:
		if not suite.execute(adapter, "rest"): finish(); return
	if not suite.execute(adapter, "drop_item", adapter.item_reference()): finish(); return
	if not suite.engines_for(adapter): finish(); return
	suite.parity(adapter, carried_before_drop, "post_drop/stale_custody_rejected", false)
	var ground: Dictionary = suite.parity(adapter, adapter.item_reference(), "post_drop/current_ground_item")
	suite.check(ground.get("focus", {}).get("facts", {}).get("custody_witness", {}).get("kind") == "ground", "current item exposes real ground custody witness")
	# Real pending intent freezes the NPC target. Later attention never redirects it.
	var begun: Dictionary = adapter.begin_intent("查看守路村民，暂不执行任何行动。", adapter.npc_reference())
	if not suite.check(begun.ok and adapter.phase() == "awaiting_assessment", "real pending NPC intent exists"): finish(); return
	var original_request: String = C.bytes(adapter.request())
	var original_target: String = C.bytes(adapter.action_copy().focus)
	if not suite.engines_for(adapter): finish(); return
	valid_batch(adapter, "pending_after_move_drop")
	for variant in ["old", "new"]:
		adapter.engine = suite.pair[variant]
		var before: Dictionary = Support.identity(adapter)
		var roundtrip: Variant = JSON.parse_string(C.bytes(adapter.engine.save_data()))
		var loaded: Dictionary = adapter.engine.load_data(roundtrip)
		suite.check(loaded.ok and Support.identity(adapter) == before, variant + " pending engine JSON save/load byte-exact")
		suite.check(C.bytes(adapter.request()) == original_request and C.bytes(adapter.action_copy().focus) == original_target, variant + " pending request/context hash and frozen NPC target preserved")
	suite.restore(adapter)
	valid_batch(adapter, "after_pending_load")
	suite.check(adapter.cancel().ok, "pending intent canceled without commit")
	finish()
