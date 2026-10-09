extends "res://tests/retry_identity/reproduce_legacy.gd"
## Separate Godot invocation: replay existing pre-fix and new-policy files exactly.
func run() -> void:
	if not setup(): quit(1); return
	for version in [1, 2]:
		var prefix := "legacy" if version == 1 else "v2"
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + prefix + "_committed.json"))
		for phase in ["ready_roll", "rolled", "staged"]:
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT + prefix + "_" + phase + ".json"))
			var e := make(version)
			var loaded: Dictionary = e.load_data(saved)
			expect(loaded.ok, prefix + " process reload " + phase + " " + str(loaded))
			if not loaded.ok: continue
			expect(C.bytes(e.save_data()) == C.bytes(saved), prefix + " exact saved phase " + phase)
			var id: String = saved.pending.keys()[0]
			if phase == "ready_roll": expect(e.roll_once(id).ok, prefix + " resumed program roll")
			if phase != "staged": expect(e.stage(id).ok, prefix + " resumed stage")
			var token: String = e.action_copy(id).stage_hash
			expect(e.commit(id, token).ok, prefix + " resumed commit")
			expect(C.bytes(e.save_data()) == C.bytes(expected), prefix + " exact original commit including receipt and RNG " + phase)
			expect(e.commit(id, token).already_committed, prefix + " idempotent process replay")
			if version == 2:
				var a := reply(e, 2)
				expect(e.prepare_assessment(a).get("code") == "REPEAT_ATTEMPT", "v2 baseline persists after process replay " + phase)
	print("RETRY PROCESS RELOAD ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	write_json("process_reload_report.json", {"checks": checks, "passed": checks - failures.size(), "failures": failures, "scope": "separate Godot invocation; legacy files produced by pinned original engine/resolver sources; v2 files by corrected sources"})
	quit(0 if failures.is_empty() else 1)
