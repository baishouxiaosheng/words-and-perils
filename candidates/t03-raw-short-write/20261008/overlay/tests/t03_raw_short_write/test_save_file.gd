extends SceneTree
## Prepared only. Run in an exact disposable project after the native memory gate is restored.
const GMEngine = preload("res://core/ai_gm_rebuilt/engine.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Story = preload("res://tests/experimental/ai_gm_rebuilt/story_fixture.gd")
const IOProbe = preload("res://tests/t03_raw_short_write/io_probe.gd")
const ENGINE_PATH := "res://core/ai_gm_rebuilt/engine.gd"
const ENGINE_SHA256 := "cb707722b1d28534615257cb9873d1c66ce9924ac2ee5ebdc2d1d2a46b09fdc3"
const METHOD_SHA256 := "a67af61429e9d9caef0b16b182682319389eb52600a1de5c85f74564051d811c"
var assertions := 0
var failures: Array = []
var cases: Array = []
var case_start := 0

func _init() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label); printerr("FAIL: " + label)
func start_case(label: String) -> void:
	cases.append({"case": label, "passed": false}); case_start = failures.size()
func end_case() -> void: cases[-1].passed = failures.size() == case_start

func _run() -> void:
	var source := FileAccess.get_file_as_string(ENGINE_PATH)
	check(source.sha256_text() == ENGINE_SHA256, "exact candidate Engine source hash")
	var first := source.find("func save_file(")
	var last := source.find("\nfunc load_file(", first)
	check(first >= 0 and last > first, "extract complete save_file method")
	if source.sha256_text() != ENGINE_SHA256 or first < 0 or last <= first:
		finish(); return
	var method := source.substr(first, last - first)
	check(method.sha256_text() == METHOD_SHA256, "exact production method hash before backend substitution")
	if method.sha256_text() != METHOD_SHA256: finish(); return
	# Only the two backend identifiers change. All production control flow, bytes,
	# return dictionaries, close/error ordering and rename decisions remain exact.
	var transformed := method.replace("FileAccess.", "ProbeIO.").replace("DirAccess.", "ProbeIO.")
	var harness_source := "extends RefCounted\nconst C = preload(\"res://core/ai_gm_rebuilt/canonical.gd\")\nconst ProbeIO = preload(\"res://tests/t03_raw_short_write/io_probe.gd\")\nvar _initial_error: Dictionary = {}\nvar payload: Dictionary = {}\nfunc ready() -> Dictionary: return _initial_error.duplicate(true)\nfunc save_data() -> Dictionary: return payload.duplicate(true)\n" + transformed + "\n"
	var harness := GDScript.new()
	harness.source_code = harness_source
	var parsed: Error = harness.reload()
	check(parsed == OK, "source-bound fault harness parses")
	if parsed != OK: finish(); return
	probe_case(harness, "short write returns false with no reported error", {"stored": false, "write_error": OK}, false, ["open", "store", "flush", "get_error", "close"])
	probe_case(harness, "short write returns false with write error", {"stored": false, "write_error": ERR_FILE_CANT_WRITE}, false, ["open", "store", "flush", "get_error", "close"])
	probe_case(harness, "reported write error despite stored true", {"stored": true, "write_error": ERR_FILE_CANT_WRITE}, false, ["open", "store", "flush", "get_error", "close"])
	probe_case(harness, "temporary open failure", {"open_failed": true}, false, ["open"])
	probe_case(harness, "rename failure after successful write", {"rename_error": ERR_CANT_CREATE}, false, ["open", "store", "flush", "get_error", "close", "rename"])
	probe_case(harness, "successful source-bound write", {}, true, ["open", "store", "flush", "get_error", "close", "rename"])
	start_case("invalid Engine refuses before any I/O")
	var refused: RefCounted = harness.new()
	refused._initial_error = C.fail("INVALID_WORLD", "test-only invalid Engine")
	IOProbe.reset({}, "probe://save.json", "ORIGINAL_DESTINATION")
	check(refused.save_file("probe://save.json").get("code") == "INVALID_WORLD", "initial readiness error preserved")
	check(IOProbe.calls.is_empty(), "no I/O for unready Engine")
	check(IOProbe.files["probe://save.json"] == "ORIGINAL_DESTINATION" and IOProbe.files["probe://save.json.tmp"] == "PREEXISTING_TMP", "unready destination and temporary sentinel unchanged")
	end_case()
	native_cases()
	finish()

func probe_case(harness: GDScript, label: String, options: Dictionary, expect_ok: bool, expected_calls: Array) -> void:
	start_case(label)
	var instance: RefCounted = harness.new()
	instance.payload = {"schema_version": "probe/v1", "text": "中文字与é", "rng": {"seed": "1", "state": "2"}, "pending": {"action": 1}, "receipts": {"receipt": 2}}
	var before: String = C.bytes(instance.payload)
	var path := "probe://save.json"
	IOProbe.reset(options, path, "ORIGINAL_DESTINATION")
	var result: Dictionary = instance.save_file(path)
	check(result.get("ok", false) == expect_ok, label + ": exact success/failure")
	check(expect_ok or result.get("code") == "SAVE_FAILED", label + ": failure code")
	check(IOProbe.calls == expected_calls, label + ": exact operation order and rename decision")
	check(C.bytes(instance.payload) == before, label + ": payload unchanged")
	if expect_ok:
		check(IOProbe.files[path] == before and not IOProbe.files.has(path + ".tmp"), label + ": exact canonical destination bytes")
	else:
		check(IOProbe.files[path] == "ORIGINAL_DESTINATION", label + ": destination preserved")
		if options.get("open_failed", false):
			check(IOProbe.files[path + ".tmp"] == "PREEXISTING_TMP", label + ": temporary untouched before open")
		else:
			check(IOProbe.files.has(path + ".tmp"), label + ": failed temporary retained, never deleted or promoted")
	end_case()

func native_cases() -> void:
	var root := "user://t03_raw_short_write_%s_%s" % [str(Time.get_unix_time_from_system()).replace(".", "_"), str(Time.get_ticks_usec())]
	start_case("native canonical save and load roundtrip")
	var made: Error = DirAccess.make_dir_recursive_absolute(root)
	check(made == OK, "create isolated native test directory")
	if made != OK: end_case(); return
	var engine: RefCounted = GMEngine.new(Story.world())
	check(engine.ready().ok, "native Engine fixture ready")
	var before: String = C.bytes(engine.save_data())
	var path := root + "/save.json"
	check(engine.save_file(path).ok, "native first save succeeds")
	check(FileAccess.get_file_as_bytes(path) == before.to_utf8_buffer(), "native save exact canonical UTF-8 bytes")
	check(C.bytes(engine.save_data()) == before, "native save preserves complete live state/RNG/pending/receipts")
	var reader: RefCounted = GMEngine.new(Story.world())
	check(reader.load_file(path).ok and C.bytes(reader.save_data()) == before, "native strict reload exact full payload")
	end_case()
	start_case("native repeated pending save")
	check(engine.begin_intent("test-only pending save, no assessment").ok, "native unassessed action begins")
	before = C.bytes(engine.save_data())
	check(engine.save_file(path).ok and engine.save_file(path).ok, "native repeated saves succeed")
	check(FileAccess.get_file_as_bytes(path) == before.to_utf8_buffer() and C.bytes(engine.save_data()) == before, "native repeated saves preserve exact pending/RNG/state")
	check(not FileAccess.file_exists(path + ".tmp"), "successful native rename consumes temporary")
	end_case()
	start_case("native temporary open failure preserves destination and state")
	var protected := root + "/protected.json"
	var sentinel := FileAccess.open(protected, FileAccess.WRITE)
	check(sentinel != null, "create test-only protected destination")
	if sentinel == null: end_case(); return
	var stored: bool = sentinel.store_string("ORIGINAL_NATIVE_DESTINATION")
	sentinel.close()
	check(stored and DirAccess.make_dir_absolute(protected + ".tmp") == OK, "test-only directory blocks temporary file open")
	var failed: Dictionary = engine.save_file(protected)
	check(not failed.ok and failed.get("code") == "SAVE_FAILED", "native temporary open failure is returned")
	check(FileAccess.get_file_as_bytes(protected) == "ORIGINAL_NATIVE_DESTINATION".to_utf8_buffer() and DirAccess.dir_exists_absolute(protected + ".tmp"), "native failure preserves destination and temporary directory")
	check(C.bytes(engine.save_data()) == before, "native failure preserves complete live state")
	end_case()
	# Retain isolated test artifacts for inspection. No live save is read or removed.

func finish() -> void:
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "assertions": assertions, "failures": failures, "cases": cases, "engine_sha256": ENGINE_SHA256, "method_sha256": METHOD_SHA256, "fault_scope": "source-extracted in-memory I/O decisions; not actual OS short writes"}))
	quit(0 if failures.is_empty() else 1)
