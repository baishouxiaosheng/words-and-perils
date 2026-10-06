extends SceneTree
## Real frozen v2 Engine facade tests. Offline typed replies are explicit test
## data, never live-model evidence. This suite must run in the composed runtime.
const View = preload("res://view/actor_action_entry/view_adapter.gd")
const Source = preload("res://view/actor_action_profile_v2/source.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const StaticFocus = preload("res://core/source_entities/static_focus.gd")
var checks := 0
var failures: Array = []
var source_data: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func expect(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("VIEW_FACADE_FAIL ", label)
	return value
func fresh() -> RefCounted:
	var view = View.new(source_data)
	expect(view.ready().get("ok", false), "real v2 source admission")
	return view
func assessment(request: Dictionary, kind: String, extra: Dictionary = {}) -> Dictionary:
	var actor_id: String = request.context.actor_id
	var bindings: Dictionary = {"actor_id": actor_id}; bindings.merge(extra)
	var paths: Array = ["/actors/" + actor_id]
	for key in ["target_actor_id", "weapon_item_id", "item_id"]:
		if bindings.has(key): paths.append(("/actors/" if key == "target_actor_id" else "/items/") + str(bindings[key]))
	if bindings.has("target_hex"): paths.append("/hexes/" + "%d,%d" % bindings.target_hex)
	var refs: Array = []; var ids: Array = []
	for path in paths:
		var found: Dictionary = C.pointer(request.context.facts, path)
		if not found.ok: continue
		var id := "fact_" + str(refs.size()); ids.append(id)
		refs.append({"id": id, "path": path, "expected": found.value})
	var components: Array = []
	var component_ids: Array = ["accuracy", "impact"] if kind == "basic_attack" else (["interact"] if kind in ["drop_item", "pickup_item", "equip_item"] else [kind])
	for id in component_ids: components.append({"id": id, "parameters": {"A": 4, "D": 0, "P": 2}, "disposition": "certain", "fact_ref_ids": ids.duplicate()})
	return {"schema_version": "ai_gm_assessment/v1", "action_id": request.action_id, "state_version": request.state_version, "context_hash": request.context_hash, "narration": "Explicit offline facade test data.", "interpretation": "Independently supplied actor intention", "resolver_id": "actor_" + kind + "_v2", "bindings": bindings, "components": components, "fact_refs": refs, "provenance": {"provider": "offline_facade_test", "live": false, "kind": "model_reply"}}
func proposal(grant: Dictionary, goal: String) -> Dictionary:
	var reply: Dictionary = {}
	for key in ["schema_version", "proposal_id", "actor_id", "state_version", "context_hash"]: reply[key] = grant[key]
	reply["goal"] = goal; reply["focus"] = {}
	return reply
func roundtrip(view: RefCounted, label: String) -> void:
	var saved: Dictionary = JSON.parse_string(C.bytes(view.save_data()))
	var restored = View.new()
	var result: Dictionary = restored.load_data(saved)
	expect(result.get("ok", false), "admitted save at " + label + " " + str(result))
	if not result.get("ok", false): return
	expect(C.bytes(restored.save_data()) == C.bytes(saved), "byte-exact authority save at " + label)
	expect(restored.phase() == view.phase() and restored.active_action == view.active_action and restored.current_actor_id() == view.current_actor_id(), "phase and actor restored at " + label)
	expect(not restored.decision_pending(), "transport grants never persist at " + label)
func finish_action(view: RefCounted, reply: Dictionary, save_phases: bool = false) -> Dictionary:
	if save_phases: roundtrip(view, "awaiting_assessment")
	var before := C.bytes(view.state_copy())
	var prepared: Dictionary = view.import_reply(reply)
	if not expect(prepared.get("ok", false), "scheduler manual assessment " + str(prepared)): return {}
	expect(view.action_copy().assessment.provenance == {"provider": "manual_offline_assessment", "live": false, "kind": "model_reply"}, "manual import cannot claim live provenance")
	if save_phases: roundtrip(view, "ready_roll")
	if not expect(view.roll_once().get("ok", false), "real Engine roll through scheduler"): return {}
	var rng := C.bytes(view.engine.save_data().rng)
	expect(view.roll_once().get("ok", false) and C.bytes(view.engine.save_data().rng) == rng, "duplicate roll cannot draw again")
	if save_phases: roundtrip(view, "rolled")
	if not expect(view.stage().get("ok", false), "real Engine stage through scheduler"): return {}
	if save_phases: roundtrip(view, "staged")
	expect(C.bytes(view.state_copy()) == before, "staging is not authority mutation")
	var id: String = view.active_action
	var hash: String = view.action_copy().stage_hash
	var journal_before: int = view.core.journal.size()
	var result: Dictionary = view.commit()
	if not expect(result.get("ok", false), "core commit exact stage hash " + str(result)): return {}
	expect(result.receipt.action_id == id and result.receipt.stage_hash == hash, "receipt uses actual exact staged identity")
	expect(view.core.journal.size() == journal_before + 1, "facade never bypasses frozen assessment journal")
	var saved := C.bytes(view.save_data())
	var again: Dictionary = view.commit()
	expect(again.get("ok", false) and again.get("already_committed", false) and C.bytes(view.save_data()) == saved, "duplicate no-arg commit is idempotent")
	if save_phases: roundtrip(view, "committed")
	return result.receipt
func perform(view: RefCounted, kind: String, extra: Dictionary = {}, save_phases: bool = false) -> Dictionary:
	var begun: Dictionary
	if view.current_actor_id() == "actor_player": begun = view.begin_intent("Explicit offline player intention: " + kind)
	else:
		var granted: Dictionary = view.decision_request()
		if not expect(granted.get("ok", false), "external actor decision grant"): return {}
		begun = view.accept_decision(proposal(granted.request, "Explicit offline enemy intention: " + kind))
	if not expect(begun.get("ok", false), "ordinary intention " + kind + " " + str(begun)): return {}
	return finish_action(view, assessment(begun.request, kind, extra), save_phases)
func engage(view: RefCounted) -> void:
	var anchor: Array = view.core.source.base.enemy_placement_result.attack_anchor_hex
	var route: Dictionary = view.source.navigation.plan(view.state_copy(), anchor, 32)
	if not expect(route.get("ok", false), "admitted source route to contact"): return
	for i in range(1, route.route.size()):
		if view.current_actor_id() != "actor_player": break
		if perform(view, "move", {"target_hex": route.route[i]}).is_empty(): return
	expect(view.current_actor_id() == Source.ACTORS[1], "existing registered contact grants enemy slot")
func run() -> void:
	var generated: Dictionary = Generator.generate(726381, 4, "coastal_range")
	if not expect(generated.get("ok", false), "canonical generated test source"): report(); return
	source_data = generated.source
	var view = fresh()
	if not view.ready().get("ok", false): report(); return
	for method in ["ready", "state_copy", "action_copy", "phase", "current_actor_id", "begin_intent", "decision_request", "accept_decision", "import_reply", "roll_once", "stage", "commit", "cancel", "request", "export_request", "save_file", "load_file", "restarted", "movement_preview", "frozen_movement_preview", "journal_entries", "status_details"]:
		expect(view.has_method(method), "Main facade method " + method)
	var original := C.bytes(view.save_data())
	expect(view.profile_id() == Source.PROFILE and view.source.profile_id() == Source.PROFILE, "explicit v2 authority profile")
	expect(view.source.world.world_id == view.state_copy().world_id and view.source.world.world_id != view.core.source.base.world.world_id, "render bridge keeps true v2 world ID")
	expect(view.source.navigation == view.core.source.navigation and view.source.render_owner() == view.core.source.base, "geometry and dynamic source graph reuse real owner")
	var bridge_identity: Dictionary = view.source.renderer_identity; bridge_identity.clear()
	expect(not view.source.renderer_identity.is_empty(), "read-only identity copy cannot alter authority")
	for id in view.state_copy().generated_world.static_entity_catalog.entries:
		var reference: Dictionary = view.source.static_reference(id)
		expect(reference.world_id == view.state_copy().world_id and StaticFocus.resolve(reference, view.state_copy()).get("ok", false), "static reference bound to v2 " + str(id))
	expect(C.bytes(view.save_data()) == original, "renderer lookups never mutate authority")
	expect(view.item_reference("item_coast_staff").is_empty(), "unregistered weapon focus is never fabricated")
	expect(not view.item_reference().is_empty(), "source-backed bundle focus remains available")
	expect(not view.fixture_available() and not view.prepare_fixture().ok and view.sample_goal("enemy_attack").is_empty(), "no scripted attack or default offline fixture")
	var grant: Dictionary = view.decision_request(100, 30)
	expect(grant.ok and view.decision_pending() and view.phase() == "idle", "decision wait is presentation only, real Engine idle")
	expect(view.request().schema_version == "actor_intent_proposal/v1" and view.default_request_path().ends_with("actor_actions_v2_intent_request.json"), "separate proposal export contract")
	var pending := proposal(grant.request, "Observe this place")
	expect(view.cancel().ok and not view.decision_pending() and C.bytes(view.save_data()) == original, "cancel decision costs no tick or RNG")
	expect(not view.accept_decision(pending, 101).ok, "cancelled proposal cannot create an action")
	view.decision_request(200)
	view.invalidate_transport()
	expect(view.cancel().ok and C.bytes(view.save_data()) == original, "Main transport invalidation followed by cancel remains idempotent")
	perform(view, "observe", {"target_hex": view.state_copy().actors.actor_player.hex}, true)
	if not failures.is_empty(): report(); return
	var receipt_id: String = view.last_action
	var binding: Dictionary = view.receipt_binding(receipt_id)
	expect(C.safe(binding) and binding.view_instance is String and not C.bytes(binding).is_empty(), "receipt binding preserves native instance ID as exact JSON-safe string")
	var prose_request: Dictionary = view.narration_request(receipt_id)
	var begun: Dictionary = view.begin_intent("Explicit next player observation")
	if not expect(begun.ok, "newer pending intent coexists with committed receipt"): report(); return
	var new_action: String = view.active_action
	var exact_pending := C.bytes(view.save_data())
	var previous: Dictionary = view.committed(receipt_id)
	var late_commit: Dictionary = view.core.commit(receipt_id, previous.stage_hash)
	view.refresh_runtime_state()
	expect(late_commit.get("already_committed", false) and view.active_action == new_action and C.bytes(view.save_data()) == exact_pending, "duplicate historical commit callback cannot clear newer action")
	var prose: Dictionary = {"schema_version": "ai_gm_narration/v1", "action_id": receipt_id, "state_version": prose_request.state_version, "context_hash": prose_request.context_hash, "narration": "The earlier recorded action is complete."}
	for invalid_epoch in [1.5, true, INF, C.LIMIT + 1]:
		var malformed:Dictionary=binding.duplicate(true);malformed.epoch=invalid_epoch
		expect(not view.accept_narration(prose,malformed,"manual").ok and C.bytes(view.save_data())==exact_pending,"noninteger or unsafe binding epoch rejects without mutation")
	var unsafe_id:Dictionary=binding.duplicate(true);unsafe_id.view_instance=9223372036854775807
	expect(C.bytes(unsafe_id).is_empty() and not view.accept_narration(prose,unsafe_id,"manual").ok,"unsafe instance numeric encoding cannot collide with a valid binding")
	expect(not view.accept_narration(prose).ok,"provider callback cannot omit its receipt binding")
	expect(view.accept_narration(prose, binding, "manual").ok and view.has_recorded_narration(receipt_id), "historical narration admitted while newer intent pending")
	expect(view.accept_narration(prose, binding, "manual").get("already_recorded", false), "duplicate receipt narration records once")
	expect(C.bytes(view.save_data()) == exact_pending and view.active_action == new_action, "narration cannot mutate pending action or authority save")
	var next_reply: Dictionary = assessment(begun.request, "observe", {"target_hex": view.state_copy().actors.actor_player.hex})
	var claimed_live: Dictionary = next_reply.duplicate(true); claimed_live.provenance.live = true
	expect(not view.import_reply(claimed_live).ok and C.bytes(view.save_data()) == exact_pending, "manual import cannot claim provider-live assessment")
	var ticket: Dictionary = view.issue_assessment_ticket(100)
	expect(view.import_reply(next_reply).ok, "manual import wins transport ownership")
	expect(not view.accept_assessment(next_reply, ticket.ticket, 101).ok, "late old assessment callback is stale")
	expect(view.cancel().ok, "ready assessment can cancel without rolling")
	var before_failed_load := C.bytes(view.save_data())
	var fresh_before_load:Dictionary=view.receipt_binding(receipt_id)
	expect(view.accept_narration(prose,fresh_before_load,"manual").get("ok",false),"fresh callback binding is valid immediately before rejected load")
	var bad: Dictionary = view.save_data(); bad.schema_version = "generated_v3_actor_actions_save/v1"
	expect(not view.load_data(bad).ok and C.bytes(view.save_data()) == before_failed_load, "v1 schema rejects transactionally")
	expect(not view.accept_narration(prose, fresh_before_load).ok, "load attempt invalidates old callback binding")
	expect(view.receipt_binding(receipt_id).epoch==fresh_before_load.epoch+1 and C.bytes(view.save_data())==before_failed_load,"rejected load alone increments callback epoch once and preserves authority")
	var restarted: RefCounted = view.restarted()
	expect(restarted.ready().ok and restarted.state_copy().turn == 0 and restarted.profile_id() == Source.PROFILE, "restart fresh same-source v2 without migration")
	var enemy_view = fresh(); engage(enemy_view)
	if not failures.is_empty(): report(); return
	var state: Dictionary = enemy_view.state_copy()
	var world_before := C.bytes(enemy_view.save_data())
	expect(not enemy_view.begin_intent("Do not submit player as enemy").ok and C.bytes(enemy_view.save_data()) == world_before, "player HUD method cannot impersonate enemy")
	var enemy: String = enemy_view.current_actor_id()
	perform(enemy_view, "observe", {"target_hex": state.actors[enemy].hex})
	expect(enemy_view.state_copy().flags[Source.observation_key(enemy)] == 1 and enemy_view.last_action != "", "same facade commits actor-owned enemy observation")
	perform(enemy_view, "observe", {"target_hex": enemy_view.state_copy().actors.actor_player.hex})
	var move_target: Array = []
	for cell in enemy_view.public_facts().hexes.values():
		var target: Array = [cell.q, cell.r]
		if enemy_view.movement_preview(target).get("ok", false): move_target = target; break
	if expect(not move_target.is_empty(), "actual enemy has a legal visible preview target"):
		var request: Dictionary = enemy_view.decision_request()
		var accepted: Dictionary = enemy_view.accept_decision(proposal(request.request, "Move to the explicitly selected visible cell"))
		var reply: Dictionary = assessment(accepted.request, "move", {"target_hex": move_target})
		expect(enemy_view.import_reply(reply).ok, "enemy move uses ordinary assessment")
		var preview: Dictionary = enemy_view.frozen_movement_preview()
		expect(preview.actor_id == enemy and preview.route[0] == enemy_view.state_copy().actors[enemy].hex and preview.route.back() == move_target, "frozen movement starts at actual enemy, never player")
		expect(enemy_view.roll_once().ok and enemy_view.stage().ok and enemy_view.commit().ok, "enemy move through all no-arg HUD stages")
		expect(enemy_view.state_copy().actors[enemy].hex == move_target, "enemy committed position persists")
		roundtrip(enemy_view, "enemy moved")
	var weak_view: WeakRef = weakref(enemy_view)
	enemy_view = null
	expect(weak_view.get_ref() == null, "facade/source/decision have no strong ownership cycle")
	var unarmed = fresh(); engage(unarmed)
	if not failures.is_empty(): report(); return
	perform(unarmed, "basic_attack", {"target_actor_id": "actor_player", "weapon_item_id": "item_raider_blade"})
	perform(unarmed, "drop_item", {"item_id": "item_coast_staff"})
	perform(unarmed, "pickup_item", {"item_id": "item_coast_staff"})
	perform(unarmed, "observe", {"target_hex": unarmed.state_copy().actors.actor_player.hex})
	perform(unarmed, "equip_item", {"item_id": "item_coast_staff"})
	perform(unarmed, "observe", {"target_hex": unarmed.state_copy().actors.actor_player.hex})
	perform(unarmed, "drop_item", {"item_id": "item_coast_staff"})
	perform(unarmed, "pickup_item", {"item_id": "item_coast_staff"})
	var checkpoint: Dictionary = unarmed.save_data()
	expect(unarmed.current_actor_id() == Source.ACTORS[1] and unarmed.state_copy().actors[Source.ACTORS[1]].equipment.is_empty(), "unarmed ordinary enemy remains scheduled")
	for kind in ["observe", "rest", "equip_item"]:
		var branch = View.new()
		if not expect(branch.load_data(checkpoint).ok, "reload unarmed checkpoint " + kind): continue
		var extra: Dictionary = {"target_hex": branch.state_copy().actors[Source.ACTORS[1]].hex} if kind == "observe" else ({"item_id": "item_raider_blade"} if kind == "equip_item" else {})
		var receipt: Dictionary = perform(branch, kind, extra)
		if receipt.is_empty(): continue
		expect(receipt.actor_id == Source.ACTORS[1] and not receipt.patches.any(func(p): return p.type == "combat_event"), "explicit unarmed choice has no fallback attack " + kind)
		expect(branch.state_copy().turn == checkpoint.engine.state.turn + 1 and branch.current_actor_id() == "actor_player", "unarmed choice commits one ordinary action " + kind)
		roundtrip(branch, "unarmed " + kind)
	expect(not view.save_file("user://generated_v3_village_enemy_v1.json").ok, "legacy save filename never overwritten")
	expect(not View._is_public_request({"context": {"facts": 1}, "context_hash": C.digest({"facts": 1})}, true), "malformed public export is rejected without unsafe field access")
	report()
func report() -> void:
	print("VIEW_FACADE_RESULT ", JSON.stringify({"ok": failures.is_empty(), "checks": checks, "failures": failures, "engine": "real frozen actor_actions_v2", "network_calls": 0, "assessment_source": "explicit manual offline test data"}))
	quit(0 if failures.is_empty() else 1)
