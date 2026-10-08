extends RefCounted
## Authored regression helpers only. NOT parsed or executed in this audit.
## Invoke from the existing admitted, isolated real-Main QA fixture after its
## genuine player -> single enemy -> player round trip. No fabricated receipts,
## source edits, world writes, Engine replacement, RNG override or model call.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Source = preload("res://view/actor_action_profile_v2/source.gd")
const BASE_MAIN_SHA = "05ebbe56e88d2ac7e774527419a60fbfabbb819dd1b52a14748728c38939072f"
const PATCHED_MAIN_SHA = "fcbe64b533f21bbd6e6b21c9c020f11f934ccee4c064078216e0f69cdcb6376b"
const ACTOR_PROFILE_SHA = "084f3c14412ea01fd0d5f4023463232979376e8938a5800325feffa93371cc6e"

static func _check(rows: Array, label: String, value: bool) -> bool:
	rows.append({"label": label, "ok": value})
	return value

static func _result(rows: Array) -> Dictionary:
	var failures: Array = []
	for row in rows:
		if not row.ok: failures.append(row.label)
	return {"ok": failures.is_empty(), "checks": rows, "failures": failures,
		"main_sha256": FileAccess.get_sha256("res://main.gd"), "live_model": false}

static func _scope(app, rows: Array) -> bool:
	if not _check(rows, "real unified actor_actions_v2 Main only",
		app.actor_action_mode and not app.actor_status_mode and app.playtest != null): return false
	if not _check(rows, "exact audited base or exact minimal candidate",
		FileAccess.get_sha256("res://main.gd") in [BASE_MAIN_SHA, PATCHED_MAIN_SHA]): return false
	if not _check(rows, "unchanged frozen actor-v2 authority",
		Source.profile_digest() == ACTOR_PROFILE_SHA and app.playtest.ready().get("ok", false)): return false
	if not _check(rows, "fixture uses offline transport and both automatic calls off",
		not app.runtime_ai.client.provider_info().live and not app.runtime_ai.busy()
		and not app.runtime_ai.automatic_assessment and not app.runtime_ai.automatic_narration): return false
	return _check(rows, "returned live player slot, source-bound board, no modal",
		app.playtest.phase() == "idle" and app.playtest.current_actor_id() == "actor_player"
		and app.actor_render_error.is_empty() and not app._api_settings_open())

static func _display(app) -> Dictionary:
	return {"speaker": app.dialogue_speaker.text, "text": app.latest_dialogue.text,
		"tooltip": app.latest_dialogue.tooltip_text}

static func _manual(app, reply: Dictionary) -> bool:
	# Exercise the same actual JSON modal -> import_decision -> apply_decision
	# -> apply_playtest_reply route as the finite real-Main QA.
	app.show_import()
	app.import_text.text = C.bytes(reply)
	app.import_decision()
	return not app.import_dialog.visible and app.import_error_label.text.is_empty()

static func _reply(app, receipt_id: String, marker: String) -> Dictionary:
	var request: Dictionary = app.playtest.narration_request(receipt_id)
	if request.is_empty(): return {}
	return {"schema_version": "ai_gm_narration/v1", "action_id": receipt_id,
		"state_version": request.state_version, "context_hash": request.context_hash,
		"narration": marker}

static func pending_import(app, receipt_id: String, marker: String) -> Dictionary:
	## Run once with an older committed player receipt and once with the latest
	## committed enemy receipt, on separate fresh admitted round-trip fixtures.
	var rows: Array = []
	if not _scope(app, rows): return _result(rows)
	var receipt: Dictionary = app.playtest.committed(receipt_id)
	if not _check(rows, "actual un-narrated committed receipt", not receipt.is_empty()
		and not app.playtest.has_recorded_narration(receipt_id)): return _result(rows)
	var reply: Dictionary = _reply(app, receipt_id, marker)
	if not _check(rows, "complete bound historical narration request", not reply.is_empty()): return _result(rows)
	app.clear_target()
	app.set_player_intent("MANUAL_RECEIPT_DISPLAY_NEXT: observe the ground here")
	app.submit_button.pressed.emit()
	if not _check(rows, "new real player intention waits without an assessment",
		app.playtest.phase() == "awaiting_assessment" and app.playtest.action_copy().actor_id == "actor_player"):
		return _result(rows)
	var pending_id: String = app.playtest.active_action
	var authority: String = C.bytes(app.playtest.save_data())
	var current_request: String = C.bytes(app.current_request)
	var display: Dictionary = _display(app)
	var latest_field: String = app.playtest.narration
	var effect_count: int = app.board.committed_effects.accepted_receipts
	var invalid: Dictionary = reply.duplicate(true)
	invalid.action_id = "manual_receipt_display_unknown_action"
	var invalid_history: String = app.journal.get_parsed_text()
	var invalid_records: String = C.bytes(app.playtest.narration_entries())
	_check(rows, "uncommitted or unknown receipt import is rejected", not _manual(app, invalid))
	_check(rows, "invalid receipt is inert in display, history and authority",
		_display(app) == display and app.journal.get_parsed_text() == invalid_history
		and C.bytes(app.playtest.narration_entries()) == invalid_records
		and C.bytes(app.playtest.save_data()) == authority and app.playtest.active_action == pending_id)
	app.import_dialog.hide()
	_check(rows, "actual manual JSON route accepts committed receipt prose", _manual(app, reply))
	_check(rows, "pending owns speaker, text and tooltip", _display(app) == display)
	_check(rows, "history contains prose once under immutable receipt turn",
		app.journal.get_parsed_text().count(marker) == 1
		and app.journal.get_parsed_text().contains("叙事记录 · 第%d回合" % int(receipt.turn)))
	_check(rows, "sidecar records actual receipt", app.playtest.has_recorded_narration(receipt_id))
	_check(rows, "latest facade field keeps historical ownership behavior",
		app.playtest.narration == latest_field if receipt_id != app.playtest.last_action else app.playtest.narration == marker)
	_check(rows, "no action, turn, RNG, receipt, assessment or current request changes",
		C.bytes(app.playtest.save_data()) == authority and C.bytes(app.current_request) == current_request
		and app.playtest.active_action == pending_id and app.playtest.phase() == "awaiting_assessment")
	_check(rows, "no receipt presentation replay", app.board.committed_effects.accepted_receipts == effect_count)
	var once: String = app.journal.get_parsed_text()
	_check(rows, "duplicate manual receipt import remains accepted", _manual(app, reply))
	_check(rows, "duplicate cannot append history or steal latest display",
		app.journal.get_parsed_text() == once and _display(app) == display
		and C.bytes(app.playtest.save_data()) == authority and app.playtest.active_action == pending_id)
	return _result(rows)

static func idle_latest_import(app, marker: String) -> Dictionary:
	## Separate fresh round-trip fixture: latest committed enemy receipt is idle.
	var rows: Array = []
	if not _scope(app, rows): return _result(rows)
	var id: String = app.playtest.last_action
	var receipt: Dictionary = app.playtest.committed(id)
	if not _check(rows, "latest actual receipt lacks prose", not receipt.is_empty()
		and not app.playtest.has_recorded_narration(id)): return _result(rows)
	var authority: String = C.bytes(app.playtest.save_data())
	var effect_count: int = app.board.committed_effects.accepted_receipts
	var reply: Dictionary = _reply(app, id, marker)
	_check(rows, "latest idle manual narration imports", _manual(app, reply))
	_check(rows, "latest idle receipt still promotes all three display controls",
		_display(app) == {"speaker": "叙事记录 · 第%d回合" % int(receipt.turn), "text": marker, "tooltip": marker})
	_check(rows, "idle latest prose changes no authority or effects",
		C.bytes(app.playtest.save_data()) == authority and app.playtest.phase() == "idle"
		and app.board.committed_effects.accepted_receipts == effect_count)
	var once: String = app.journal.get_parsed_text()
	_check(rows, "latest idle duplicate remains idempotent", _manual(app, reply)
		and app.journal.get_parsed_text() == once and app.journal.get_parsed_text().count(marker) == 1)
	return _result(rows)
