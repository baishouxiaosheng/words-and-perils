extends RefCounted
## TEST SOURCE ONLY. Authored offline replies; all successes use the frozen real
## Engine, scheduler ticket, random roll, stage token and core.commit path.
const View = preload("res://view/actor_status_entry_v1/view_adapter.gd")
const Core = preload("res://view/actor_status_profile_v1/adapter.gd")
const Source = preload("res://view/actor_status_profile_v1/source.gd")
const OldSource = preload("res://view/actor_action_profile_v2/source.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const PLAYER = "actor_player"
const ENEMY = "actor_village_hostile"
const FROZEN_PROFILE = "9988155d5baf8e840c8d6063c2bc415c08bd0d7b1cd70157f9400bff40698994"
const FROZEN_V2_PROFILE = "084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e"
var checks := 0
var failures: Array = []
var source_data: Dictionary = {}
var admitted_source: RefCounted
var last_transaction: Dictionary = {}
var last_sequence: Array = []
var observed_phases: Array = []
var phase_witnesses: Array = []
const SAVE_ROOT = "user://actor_status_entry_tests"
var attempts: Array = []
func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("STATUS_ENTRY_FAIL ", label)
	return value
func admit() -> bool:
	var generated: Dictionary = Generator.generate(726381, 4, "coastal_range")
	if not expect(generated.get("ok", false), "canonical generated test source"): return false
	source_data = generated.source
	var first = View.new(source_data)
	if not expect(first.ready().get("ok", false), "real facade admits independent status source"): return false
	admitted_source = first.core.source
	var status_ok: bool = expect(admitted_source.identity.profile_hash == FROZEN_PROFILE, "status authority matches independently frozen public source identity")
	var v2_ok: bool = expect(OldSource.profile_digest() == FROZEN_V2_PROFILE, "old-v2 authority matches independently frozen public source identity")
	return status_ok and v2_ok
func fresh() -> RefCounted:
	if admitted_source == null:
		var direct = View.new(source_data)
		expect(direct.ready().get("ok", false), "fresh direct real facade admission")
		return direct
	# Same admitted immutable source, a genuinely new production Engine/RNG.
	# This is not a fabricated state, forced outcome, reroll or reseeded action.
	var core = Core.new()
	var checked: Dictionary = core._publish(admitted_source, Core.make_engine(admitted_source), [])
	expect(checked.get("ok", false), "fresh independent production-rule lineage")
	var view = View.new(); view._publish(core)
	return view
static func status(world: Dictionary, actor_id: String, definition: String) -> Dictionary:
	for instance in world.get("status_foundation", {}).get("instances", {}).values():
		if instance.owner_kind == "actor" and instance.owner_id == actor_id and instance.definition_id == definition: return instance
	return {}
static func applied(receipt: Dictionary) -> bool:
	return not receipt.is_empty() and receipt.get("outcomes", {}).get("delivery", false) and receipt.get("outcomes", {}).get("effect", false)
func assessment(request: Dictionary, kind: String, extra: Dictionary = {}) -> Dictionary:
	var actor_id: String = request.context.actor_id
	var bindings: Dictionary = {"actor_id": actor_id}; bindings.merge(extra)
	var paths: Array = ["/actors/" + actor_id]
	for key in ["target_actor_id", "source_id", "weapon_item_id", "item_id"]:
		if not bindings.has(key): continue
		var path: String
		if key == "target_actor_id": path = "/actors/" + str(bindings[key])
		elif key == "source_id" and bindings[key] == "land": path = "/actors/" + actor_id + "/status_actions/land"
		else: path = "/items/" + str(bindings[key])
		if not path in paths: paths.append(path)
	if bindings.has("target_hex"): paths.append("/hexes/" + "%d,%d" % bindings.target_hex)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found: Dictionary = C.pointer(request.context.facts, path)
		if not found.ok: continue
		var id := "fact_" + str(refs.size()); ids.append(id)
		refs.append({"id": id, "path": path, "expected": found.value})
	var components: Array = []
	var names: Array = ["delivery", "effect"] if kind == "status_source" else (["accuracy", "impact"] if kind == "basic_attack" else (["interact"] if kind in ["drop_item", "pickup_item", "equip_item"] else [kind]))
	for id in names: components.append({"id": id, "parameters": {"A": 4, "D": 0, "P": 2}, "disposition": "certain", "fact_ref_ids": ids.duplicate()})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "Explicit offline authored entry-contract test data.", "interpretation": "Source-bound intention, never an invented effect", "resolver_id": "actor_status_" + kind + "_v1", "bindings": bindings, "components": components, "fact_refs": refs, "provenance": {"provider": "offline_status_entry_test", "live": false, "kind": "model_reply"}}
func proposal(grant: Dictionary, goal: String = "Observe my own current location") -> Dictionary:
	var result: Dictionary = {}
	for key in ["schema_version", "proposal_id", "actor_id", "state_version", "context_hash"]: result[key] = grant[key]
	result.goal = goal; result.focus = {}
	return result
func begin(view: RefCounted, kind: String, extra: Dictionary = {}, focus: Dictionary = {}) -> Dictionary:
	var begun: Dictionary
	if view.current_actor_id() == PLAYER: begun = view.begin_intent("Explicit offline intention: " + kind, focus)
	else:
		var grant: Dictionary = view.decision_request()
		if not expect(grant.get("ok", false), "ordinary current-actor proposal grant"): return {}
		var answer := proposal(grant.request, "Explicit offline actor intention: " + kind); answer.focus = focus
		begun = view.accept_decision(answer)
	if not expect(begun.get("ok", false), "ordinary intention " + kind + " " + str(begun)): return {}
	return assessment(begun.request, kind, extra)
func roundtrip(view: RefCounted, label: String) -> void:
	var saved: Dictionary = JSON.parse_string(C.bytes(view.save_data()))
	var restored = View.new(); var loaded: Dictionary = restored.load_data(saved)
	if not expect(loaded.get("ok", false), "facade save reopens at " + label + " " + str(loaded)): return
	expect(C.bytes(saved) == C.bytes(restored.save_data()), "exact authority bytes at " + label)
	expect(restored.phase() == view.phase() and restored.active_action == view.active_action and restored.current_actor_id() == view.current_actor_id(), "actor and pending phase survive " + label)
	expect(not restored.decision_pending() and restored.narration_entries().is_empty(), "transport grants/prose are not required authority save at " + label)
	if label in ["awaiting_assessment", "ready_roll", "rolled", "staged", "committed"] and not label in observed_phases:
		observed_phases.append(label)
		var directory: String = SAVE_ROOT + "/" + label
		expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated phase fixture directory " + label)
		var path: String = directory + "/actor_status_v1.json"
		if expect(view.save_file(path).get("ok", false), "facade persists isolated phase fixture " + label):
			phase_witnesses.append({"label": label, "path": path, "save_sha256": FileAccess.get_sha256(path), "canonical_sha256": C.digest(saved), "phase": view.phase(), "active_action": view.active_action, "actor_id": view.current_actor_id(), "turn": view.state_copy().turn, "record_count": view.core.public_records.size(), "profile_hash": view.core.source.identity.profile_hash})
func finish_action(view: RefCounted, reply: Dictionary, save_phases: bool = false) -> Dictionary:
	last_transaction = {}
	if reply.is_empty(): return {}
	var before: Dictionary = view.state_copy()
	var count: int = view.core.public_records.size()
	if save_phases: roundtrip(view, "awaiting_assessment")
	var issued: Dictionary = view.issue_assessment_ticket()
	if not expect(issued.get("ok", false), "real scheduler assessment ticket"): return {}
	var accepted: Dictionary = view.accept_assessment(reply, issued.ticket)
	if not expect(accepted.get("ok", false), "ticket admits authored offline assessment " + str(accepted)): return {}
	if save_phases: roundtrip(view, "ready_roll")
	if not expect(view.roll_once().get("ok", false), "real scheduler roll_once"): return {}
	var rng: String = C.bytes(view.engine.save_data().rng)
	expect(view.roll_once().get("ok", false) and C.bytes(view.engine.save_data().rng) == rng, "duplicate roll uses exactly the same draw")
	if save_phases: roundtrip(view, "rolled")
	if not expect(view.stage().get("ok", false), "real scheduler atomic stage"): return {}
	if save_phases: roundtrip(view, "staged")
	expect(C.bytes(view.state_copy()) == C.bytes(before) and view.core.public_records.size() == count, "assessment/roll/stage publish neither world nor public record")
	var id: String = view.active_action; var token: String = view.action_copy().stage_hash
	var journals: int = view.core.journal.size()
	var result: Dictionary = view.commit()
	if not expect(result.get("ok", false), "facade core.commit exact frozen token " + str(result)): return {}
	var receipt: Dictionary = result.receipt
	expect(receipt.action_id == id and receipt.stage_hash == token, "commit owns the exact action/stage")
	expect(view.core.journal.size() == journals + 1 and view.core.public_records.size() == count + 1, "core.commit atomically publishes required journal and public record")
	var record: Dictionary = view.public_receipt_record(id)
	expect(record.get("receipt_hash") == receipt.receipt_hash, "required public record keeps original immutable receipt hash")
	var saved: String = C.bytes(view.save_data()); var again: Dictionary = view.commit()
	expect(again.get("already_committed", false) and C.bytes(view.save_data()) == saved, "duplicate facade commit cannot retick, repay or duplicate history")
	if save_phases: roundtrip(view, "committed")
	last_transaction = {"before": before, "after": view.state_copy(), "receipt": receipt.duplicate(true), "record": record}
	return receipt
func perform(view: RefCounted, kind: String, extra: Dictionary = {}, save_phases: bool = false) -> Dictionary:
	return finish_action(view, begin(view, kind, extra), save_phases)
func use(view: RefCounted, source_id: String, save_phases: bool = false) -> Dictionary:
	return perform(view, "status_source", {"actor_id": view.current_actor_id(), "target_actor_id": view.current_actor_id(), "source_id": source_id}, save_phases)
func observe(view: RefCounted) -> Dictionary:
	return perform(view, "observe", {"target_hex": view.state_copy().actors[view.current_actor_id()].hex})
func successful_sequence(sources: Array) -> RefCounted:
	last_sequence = []
	for attempt in range(1, 33):
		var view = fresh(); var transactions: Array = []; var success := true
		for source_id in sources:
			var receipt: Dictionary = use(view, source_id)
			var row: Dictionary = {"sources": sources.duplicate(), "attempt": attempt, "source_id": source_id, "receipt_hash": receipt.get("receipt_hash", ""), "outcomes": receipt.get("outcomes", {}).duplicate(true)}
			attempts.append(row); print("STATUS_ENTRY_ACTUAL_ATTEMPT ", JSON.stringify(row))
			if receipt.is_empty(): return null
			transactions.append(last_transaction.duplicate(true))
			if not applied(receipt): success = false; break
		if success: last_sequence = transactions; return view
	expect(false, "bounded independent production lineages require actual success: " + str(sources))
	return null
func successful_self(source_id: String) -> RefCounted:
	return successful_sequence([source_id])
func engage(view: RefCounted) -> void:
	var anchor: Array = view.core.source.base.enemy_placement_result.attack_anchor_hex
	var route: Dictionary = view.source.navigation.plan(view.state_copy(), anchor, 32)
	if not expect(route.get("ok", false), "admitted dry route toward encounter"): return
	for index in range(1, route.route.size()):
		if view.current_actor_id() != PLAYER: break
		if perform(view, "move", {"target_hex": route.route[index]}).is_empty(): return
	expect(view.current_actor_id() == ENEMY, "registered contact schedules actual enemy")
