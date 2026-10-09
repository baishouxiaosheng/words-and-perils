extends SceneTree
## Seeded real release calculation, explicit test-only identity; no provider calls.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const World = preload("res://view/playable_build/world.gd")
const CoreWorld = preload("res://core/ai_gm_rebuilt/world.gd")
const Actions = preload("res://core/ai_gm_rebuilt/generic_actions.gd")
const TestRule = preload("res://tests/core_gameplay/test_release_rule.gd")
const Catalog = preload("res://view/playable_build/entity_catalog.gd")
const Traversal = preload("res://core/ai_gm_rebuilt/traversal.gd")
const Coast = preload("res://view/playable_build/resolver.gd")
const Basic = preload("res://core/ai_gm_rebuilt/basic_actions.gd")
const OUT := "res://artifacts/retry_identity_20261003/"
var base: Dictionary = {}
var chosen: Dictionary = {}
var failures: Array = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func setup() -> bool:
	base = World.world()
	for actor in base.actors.values(): actor.hooks = []
	for row in range(12000):
		var id := Catalog.tree_id(row)
		if id.is_empty(): continue
		var entity := Catalog.entity(id, base)
		var cell: Dictionary = base.hexes[Traversal.key(entity.hex)]
		if not cell.ground_blocked and not cell.all_blocked:
			chosen = entity; break
	if chosen.is_empty(): return false
	base.actors.actor_player.hex = chosen.hex.duplicate()
	base.actors.actor_player.stamina.current = 6
	base.actors.actor_player.health.current = base.actors.actor_player.health.max
	return CoreWorld.validate(base).ok
func registry(version := 1) -> Dictionary:
	var r := {}
	for kind in ["manipulate_environment", "apply_condition"]:
		var a: RefCounted = Actions.new(kind) if version == 1 else load("res://core/ai_gm_rebuilt/generic_actions_v2.gd").new(kind)
		r[a.resolver_id()] = a
	for kind in ["observe", "rest"]:
		var a := Coast.new(kind); r[a.resolver_id()] = a
	for kind in Basic.KINDS:
		var a := Basic.new(kind); r[a.resolver_id()] = a
	return r
func make(version := 1, initial: Dictionary = {}, seed_ := 1) -> RefCounted:
	var r := registry(version)
	return GMEngine.new(base if initial.is_empty() else initial, TestRule.new(r), r, {"npc_secret_allowlist": [], "public_flag_ids": ["coast_observed", "keeper_trust", "lamp_restored"]}, seed_)
func reply(e: RefCounted, version := 1, kind := "fell", goal := "Try to fell this standing tree.") -> Dictionary:
	var state: Dictionary = e.state_copy()
	var start: Dictionary = e.begin_intent(goal, Catalog.make_reference(chosen.id, state) if kind == "fell" else {})
	if not start.ok: return start
	var req: Dictionary = start.request; var facts: Dictionary = req.context.facts
	var refs: Array = [{"id": "actor", "path": "/actors/actor_player", "expected": facts.actors.actor_player}]
	var b := {"actor_id": "actor_player"}; var components: Array = []
	var ids: Array = ["actor"]
	var resolver := "coast_manipulate_environment_v" + str(version)
	if kind == "fell":
		b.target_entity_id = chosen.id; b.operation = "fell"
		refs.append({"id": "tree", "path": "/attention_focus/facts/entity", "expected": req.context.attention_focus.facts.entity})
		refs.append({"id": "cell", "path": "/hexes/" + Traversal.key(chosen.hex), "expected": facts.hexes[Traversal.key(chosen.hex)]})
		ids.append_array(["tree", "cell"])
		for id in ["control", "force"]: components.append({"id": id, "parameters": {"A": 2, "D": 2, "P": 0}, "disposition": "possible", "fact_ref_ids": ids.duplicate()})
	elif kind == "condition":
		resolver = "coast_apply_condition_v" + str(version)
		b.target_actor_id = "actor_player"; b.source_item_id = "item_poison_vial"
		refs.append({"id": "source", "path": "/items/item_poison_vial", "expected": facts.items.item_poison_vial}); ids.append("source")
		for id in ["delivery", "effect"]:
			var p := {"A": 2, "D": 2, "P": 0}
			if id == "effect": p.duration = 1; p.magnitude = 1
			components.append({"id": id, "parameters": p, "disposition": "possible", "fact_ref_ids": ids.duplicate()})
	elif kind in ["rest", "observe"]:
		resolver = "coast_" + kind
		components.append({"id": kind, "parameters": {"A": 2, "D": 2, "P": 0}, "disposition": "certain", "fact_ref_ids": ids.duplicate()})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": req.action_id, "state_version": req.state_version, "context_hash": req.context_hash, "narration": "Explicit offline manual test assessment; not a model execution.", "interpretation": "Test exact existing bindings and real fixed release calculation.", "resolver_id": resolver, "bindings": b, "components": components, "fact_refs": refs, "provenance": {"provider": "retry_identity_offline_test", "live": false, "kind": "model_reply"}}
func finish(e: RefCounted, a: Dictionary) -> Dictionary:
	var p: Dictionary = e.prepare_assessment(a)
	if not p.ok: return p
	var r: Dictionary = e.roll_once(a.action_id)
	if not r.ok: return r
	var s: Dictionary = e.stage(a.action_id)
	if not s.ok: return s
	return e.commit(a.action_id, s.stage_hash)
func write_json(name_: String, value: Variant) -> void:
	var f := FileAccess.open(OUT + name_, FileAccess.WRITE); f.store_string(JSON.stringify(value, "\t", true, true)); f.close()
func run() -> void:
	if not setup(): push_error("No genuine standing-tree test world"); quit(1); return
	var e := make(); var a := reply(e)
	expect(e.ready().ok, "legacy release-test engine ready")
	var before: Dictionary = e.state_copy()
	var p: Dictionary = e.prepare_assessment(a); expect(p.ok, "legacy assessment accepted")
	if not p.ok: print(p); quit(1); return
	var pre: Dictionary = e.action_copy(a.action_id)
	write_json("legacy_ready_roll.json", e.save_data())
	var r: Dictionary = e.roll_once(a.action_id)
	expect(r.ok and not (r.outcomes.control and r.outcomes.force), "actual program dice yield failed felling")
	if not r.ok or (r.outcomes.control and r.outcomes.force): print(r); quit(1); return
	write_json("legacy_rolled.json", e.save_data())
	var s: Dictionary = e.stage(a.action_id); expect(s.ok, "legacy stage")
	write_json("legacy_staged.json", e.save_data())
	var committed: Dictionary = e.commit(a.action_id, s.stage_hash); expect(committed.ok, "legacy commit")
	write_json("legacy_committed.json", e.save_data())
	var after: Dictionary = e.state_copy()
	var again := reply(e); var p2: Dictionary = e.prepare_assessment(again)
	var post: Dictionary = e.action_copy(again.action_id)
	expect(before.actors.actor_player.stamina.current == 6 and after.actors.actor_player.stamina.current == 4, "actual cost 6 to 4")
	expect(C.bytes(before.hexes) == C.bytes(after.hexes) and C.bytes(before.environment_entities) == C.bytes(after.environment_entities), "tree and blocking unchanged")
	expect(p.checks[0].derived_facts.F == 0 and p2.get("checks", [{}])[0].get("derived_facts", {}).get("F") == 0, "real F unchanged at zero")
	expect(pre.attempt_key == post.attempt_key and pre.attempt_fingerprint != post.attempt_fingerprint, "same semantic key but changed whole-actor fingerprint")
	expect(p2.ok and post.status == "ready_roll", "REPRODUCED: legacy fresh identical assessment admits another roll")
	var report := {"scope": "seeded release-calculation test, not production/live provider", "seed": 1, "rule_id": e.rule_id(), "checks": checks, "failures": failures, "tree_id": chosen.id, "actor_hex": chosen.hex, "dice": r.rolls, "outcomes": r.outcomes, "stamina_before": 6, "stamina_after": after.actors.actor_player.stamina.current, "F_before": p.checks[0].derived_facts.F, "F_after": p2.get("checks", [{}])[0].get("derived_facts", {}).get("F"), "key_before": pre.attempt_key, "key_after": post.attempt_key, "fingerprint_before": pre.attempt_fingerprint, "fingerprint_after": post.attempt_fingerprint, "repeat_preparation": p2, "tree_unchanged": C.bytes(before.environment_entities) == C.bytes(after.environment_entities)}
	write_json("legacy_reproduction.json", report)
	print("LEGACY RETRY REPRODUCTION ", checks - failures.size(), "/", checks, " ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
