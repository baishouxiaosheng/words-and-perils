extends "res://tests/status_river_gate_b/harness.gd"
## Full source resources required. This is not part of the already-passed 240 assertions.
const LEGACY_COMMITTED = "user://gate_b_legacy_committed.json"
const LEGACY_PENDING = "user://gate_b_legacy_pending.json"
const POISON = "user://gate_b_poison.json"
const PREPARED = "user://gate_b_prepared.json"
const STAGED = "user://gate_b_staged.json"

func _initialize() -> void:
	case_name = argument("--case")
	if not storage_safe():
		finish()
		return
	match case_name:
		"adapter_poison": poison_write()
		"adapter_poison_reopen": poison_reopen()
		"adapter_pending": pending_write()
		"adapter_prepared_reopen": prepared_reopen()
		"adapter_staged_reopen": staged_reopen()
		"adapter_legacy": legacy_write()
		"adapter_legacy_reopen": legacy_reopen()
		"adapter_reject_legacy": reject_legacy()
		"adapter_history_reopen": history_reopen()
		_: check(false, "recognized explicit adapter case")
	finish()

func poison_write() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(not FileAccess.file_exists(POISON), "new isolated poison artifact destination"): return
	var initial: Dictionary = adapter.state_copy()
	if not check(F.prepare_source(adapter, "item_poison_vial").ok, "real poison-vial assessment prepares"): return
	if not fixed_checks(adapter): return
	check(C.bytes(adapter.state_copy()) == C.bytes(initial), "prepare cannot publish a status, spend source, or tick")
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok, "poison action rolls once, stages, and commits"): return
	report["poison_receipt"] = result.receipt
	if not check(result.receipt.outcomes.delivery and result.receipt.outcomes.effect, "fixed independent seed1 first source succeeds; stop on failure, never reroll"): return
	var state: Dictionary = adapter.state_copy()
	check(state.actors.actor_player.health == initial.actors.actor_player.health and F.status(state,"poison").get("remaining") == 3, "poison starts with three owner actions and no same-action damage")
	check(state.items.item_poison_vial.quantity == initial.items.item_poison_vial.quantity - 1 and state.actors.actor_player.stamina.current == initial.actors.actor_player.stamina.current - 1, "trusted source units/stamina are spent exactly once")
	var exact := C.digest(adapter.engine.save_data())
	var duplicate: Dictionary = adapter.engine.commit(result.receipt.action_id, result.receipt.stage_hash)
	check(duplicate.get("already_committed",false) and C.digest(adapter.engine.save_data()) == exact, "duplicate real commit cannot spend, roll, tick or change history")
	check(not F.Save.unwrap(adapter.engine.save_data()).ok, "raw engine custody payload cannot masquerade as explicit new-mode save")
	if not check(adapter.save_file(POISON).ok, "real Coast saves explicit wrapper"): return
	if not witness(adapter,POISON): return
	var wrapped := read_json(POISON)
	check(wrapped.get("schema_version") == F.Save.SCHEMA and F.Save.unwrap(wrapped).ok, "saved file has explicit compatible status wrapper")
	# A private temporary directory obstruction is enough to exercise safe I/O
	# failure. Never fill a disk, chmod a system path, or overwrite a player save.
	var original_hash := FileAccess.get_sha256(POISON)
	if not check(DirAccess.make_dir_absolute(POISON + ".tmp") == OK, "test-only temp-path obstruction created"): return
	var failed: Dictionary = adapter.save_file(POISON)
	check(not failed.ok and failed.get("code") == "STATUS_SAVE_IO", "blocked temporary path returns an I/O failure")
	check(FileAccess.get_sha256(POISON) == original_hash, "failed write preserves previously valid destination bytes")
	report["save_fault_scope"] = "Owned .tmp directory obstructs open; real flush/disk-full remains untested and must not be inferred"
	completed = true

func poison_reopen() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(adapter.load_file(POISON).ok, "real bundle-aware Coast reloads explicit new save"): return
	if not verify_reopen(adapter,POISON): return
	var state: Dictionary = adapter.state_copy()
	var before_hp: int = state.actors.actor_player.health.current
	var damage: int = 1 + int(float(state.actors.actor_player.health.max) * 0.10)
	check(F.status(state,"poison").get("remaining") == 3, "reopened committed poison retains remaining-three")
	var begun: Dictionary = F.begin(adapter,"coast_rest",{"actor_id":F.PLAYER},["rest"])
	if not check(begun.ok and adapter.import_reply(begun.get("reply",{})).ok, "ordinary owner rest uses offline assessment pipeline"): return
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok, "ordinary owner rest commits"): return
	state = adapter.state_copy()
	check(state.actors.actor_player.health.current == maxi(0,before_hp-damage) and F.status(state,"poison").get("remaining") == 2, "source-world max-health formula ticks once on next owner action")
	check(F.Details.public_details(state,state.actors.actor_player).available, "committed reopened details remain valid")
	completed = true

func pending_write() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(not FileAccess.file_exists(PREPARED) and not FileAccess.file_exists(STAGED), "fresh pending fixture destinations"): return
	var before := C.digest(adapter.state_copy())
	if not check(F.prepare_source(adapter,"item_feather_vial").ok, "prepare real feather source"): return
	if not fixed_checks(adapter): return
	if not check(adapter.save_file(PREPARED).ok and witness(adapter,PREPARED), "prepared source saved with whole plan/RNG witness"): return
	if not check(adapter.roll_once().ok, "pending source rolls once"): return
	var rolled_digest := C.digest(adapter.engine.save_data())
	check(adapter.roll_once().ok and C.digest(adapter.engine.save_data()) == rolled_digest, "duplicate roll reuses the locked outcome without new RNG")
	check(not adapter.cancel().ok and C.digest(adapter.engine.save_data()) == rolled_digest, "rolled action cannot be cancelled to choose a new outcome")
	if not check(adapter.stage().ok, "locked pending source stages"): return
	check(C.digest(adapter.state_copy()) == before, "staged effects have not changed authoritative player facts")
	if not check(adapter.save_file(STAGED).ok and witness(adapter,STAGED), "staged source saved without committing"): return
	completed = true

func prepared_reopen() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(adapter.load_file(PREPARED).ok, "bundle-aware prepared save reload"): return
	if not verify_reopen(adapter,PREPARED): return
	var reply: Dictionary = adapter.action_copy().assessment
	var old: Dictionary = adapter.engine.save_data()
	check(adapter.cancel().ok and adapter.phase() == "idle", "explicit pre-roll cancellation is permitted after restart")
	var now: Dictionary = adapter.engine.save_data()
	check(C.bytes(now.state) == C.bytes(old.state) and C.bytes(now.rng) == C.bytes(old.rng) and C.bytes(now.receipts) == C.bytes(old.receipts) and C.bytes(now.attempt_ledger) == C.bytes(old.attempt_ledger), "cancellation preserves player facts RNG receipts and retry history")
	var exact := C.digest(now)
	check(not adapter.import_reply(reply).ok and C.digest(adapter.engine.save_data()) == exact, "late assessment for cancelled action cannot revive or reinterpret it")
	completed = true

func staged_reopen() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(adapter.load_file(STAGED).ok, "bundle-aware staged save reload"): return
	if not verify_reopen(adapter,STAGED): return
	var exact := C.digest(adapter.engine.save_data())
	check(not adapter.cancel().ok and C.digest(adapter.engine.save_data()) == exact, "reopened staged action cannot cancel/reseed")
	var result: Dictionary = adapter.commit()
	if not check(result.ok, "fresh process commits the existing frozen stage"): return
	check(result.receipt.outcomes.delivery and result.receipt.outcomes.effect and F.status(adapter.state_copy(),"flight").get("remaining") == 3, "saved first-roll feather outcome produces flight without reinterpretation")
	exact = C.digest(adapter.engine.save_data())
	check(adapter.engine.commit(result.receipt.action_id,result.receipt.stage_hash).get("already_committed",false) and C.digest(adapter.engine.save_data()) == exact, "reopened real receipt remains idempotent")
	# Detached invalid candidate for a pure bridge rejection test. This is not a
	# gameplay resolver and never reaches engine state or save files.
	var before: Dictionary = adapter.state_copy()
	var invalid: Dictionary = before.duplicate(true)
	invalid.status_foundation.world_clock.sequence += 2
	invalid.status_foundation.world_clock.event_id = "offline_gate_b_multi_step_rejection"
	var rejected: Dictionary = F.Foundation.freeze(before,invalid,F.PLAYER)
	check(not rejected.ok and rejected.get("code") == "STATUS_MULTI_WORLD_STEP_UNSUPPORTED" and C.digest(adapter.engine.save_data()) == exact, "multiple world steps stay explicitly unsupported, no silent elapsed-time loss")
	completed = true

func legacy_write() -> void:
	# Real source-world legacy v1 API, never the new status source resolver.
	var adapter: RefCounted = F.Coast.new(1,false,false)
	if not check(adapter.engine.ready().ok and F.world_check(adapter.state_copy()).ok, "legacy source Coast loads with original identity"): return
	if not check(not FileAccess.file_exists(LEGACY_COMMITTED) and not FileAccess.file_exists(LEGACY_PENDING), "fresh authored legacy compatibility artifacts"): return
	check(not adapter.status_gameplay_mode and not adapter.state_copy().has("status_foundation"), "legacy new-game fixture contains no new ruleset")
	if not check(adapter.begin_intent(adapter.sample_goal("poison")).ok and adapter.prepare_fixture().ok, "explicit historical signed poison example prepares original v1 source"): return
	check(adapter.action_copy().assessment.resolver_id == "coast_apply_condition_v1", "old calculator and resolver identity stay explicitly v1")
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok, "old poison commits through historical action pipeline"): return
	check(adapter.state_copy().actors.actor_player.statuses.get("condition_poison",{}).get("remaining_turns") == 2, "actual legacy poison representation retained")
	if not check(adapter.save_file(LEGACY_COMMITTED).ok and witness(adapter,LEGACY_COMMITTED), "legacy committed raw save retained"): return
	if not check(adapter.begin_intent(adapter.sample_goal("rest")).ok and adapter.prepare_fixture().ok, "old poison owner rest is pending under original calculator"): return
	if not check(adapter.save_file(LEGACY_PENDING).ok and witness(adapter,LEGACY_PENDING), "legacy pending raw save retained exactly"): return
	report["provenance"] = "New offline compatibility fixture using original v1 source-world pipeline; not an historical player's original save"
	completed = true

func legacy_reopen() -> void:
	var adapter: RefCounted = F.Coast.new(1,false,false)
	if not check(adapter.load_file(LEGACY_PENDING).ok, "historical registry accepts legacy pending poison save"): return
	if not verify_reopen(adapter,LEGACY_PENDING): return
	var state: Dictionary = adapter.state_copy()
	var hp: int = state.actors.actor_player.health.current
	check(not state.has("status_gameplay") and not state.has("status_foundation"), "legacy load remains free of new-mode store")
	var result: Dictionary = F.commit_prepared(adapter)
	if not check(result.ok, "rest from old pending save commits under old policy"): return
	state = adapter.state_copy()
	check(state.actors.actor_player.health.current == hp-1 and state.actors.actor_player.statuses.condition_poison.remaining_turns == 1, "legacy poison retains original flat-one damage and legacy turn duration")
	check(F.Details.public_details(state,state.actors.actor_player).rows[0].duration.clock == "legacy_turn", "old poison details explicitly retain legacy clock")
	completed = true

func reject_legacy() -> void:
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	for path in [LEGACY_COMMITTED,LEGACY_PENDING]:
		if not check(FileAccess.file_exists(path), "raw old fixture exists for rejection"): return
		var original_hash := FileAccess.get_sha256(path)
		var exact := C.digest(adapter.engine.save_data())
		var loaded: Dictionary = adapter.load_file(path)
		check(not loaded.ok and loaded.get("code") == "STATUS_SAVE_VERSION", "new mode rejects old raw committed/pending save instead of reinterpreting")
		check(C.digest(adapter.engine.save_data()) == exact and FileAccess.get_sha256(path) == original_hash, "failed old-save import preserves new authority and original old bytes")
		var saved: Dictionary = adapter.save_file(path)
		check(not saved.ok and saved.get("code") == "STATUS_SAVE_PROTECTED" and FileAccess.get_sha256(path) == original_hash, "explicit status save cannot overwrite legacy raw destination")
	completed = true

func history_reopen() -> void:
	var path := "user://gate_b_history.json"
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter): return
	if not check(adapter.load_file(path).ok, "actual Coast loads Main-produced historical actor-focus save in a separate process"): return
	if not verify_reopen(adapter,path): return
	var prior: Dictionary = report.reopen_witness
	var history: Array = prior.get("extra",{}).get("history",[])
	if not check(not history.is_empty(), "persisted focused historical status witnesses exist"): return
	var state: Dictionary = adapter.state_copy()
	var current: Dictionary = F.Details.public_details(state,state.actors.actor_player)
	check(C.bytes(current) == C.bytes(prior.extra.current_status_details), "current changed/removed status details reopen exactly")
	for item in history:
		var narrated: Dictionary = adapter.engine.narration_request(item.action_id)
		var packet: Variant = narrated.get("context",{}).get("attention_focus",{}).get("facts",{}).get("status_details")
		var receipt: Dictionary = adapter.engine.save_data().receipts.get(item.action_id,{})
		check(C.bytes(packet) == C.bytes(item.status_details) and C.bytes(receipt.get("attention_focus",{}).get("facts",{}).get("status_details")) == C.bytes(item.status_details), "reloaded historical actor-focus packet remains identical in receipt and narration")
	check(history.any(func(item): return C.bytes(item.status_details) != C.bytes(current)), "load does not rewrite old status history to today's changed/removed state")
	completed = true
