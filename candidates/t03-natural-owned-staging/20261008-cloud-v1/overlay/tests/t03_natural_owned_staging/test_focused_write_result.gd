extends SceneTree
const Adapter = preload("res://view/generated_natural_coast_basic/adapter.gd")
const FakeAdapter = preload("res://tests/t03_natural_owned_staging/fake_adapter.gd")
const ProbeIO = preload("res://tests/t03_natural_owned_staging/io_probe.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const ADAPTER_SHA256 := "7e11cf5a3679fdc3bee4aa4264a11ed49cdadb2744136c0ffb4bae2ee47fe345"
var assertions := 0
var failures: Array = []
var cases: Array = []
var setup_assertions := 0
func _initialize() -> void:
	var expected: String = OS.get_environment("FOGBANK_STAGING_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/") != expected:
		printerr("STAGING_TEST_REFUSED: explicit isolated user directory required"); quit(2); return
	if FileAccess.file_exists("user://natural_coast_basic_save_write_result.json"):
		printerr("STAGING_TEST_REFUSED: fresh isolated test directory required"); quit(2); return
	_run.call_deferred()
func check(ok: bool, label_: String) -> void:
	assertions += 1
	if not ok: failures.append(label_); printerr("FAIL: "+label_)
func snapshot(adapter: RefCounted) -> String:
	return C.bytes({"save":adapter.save_data(),"active_action":adapter.active_action,"last_action":adapter.last_action,"narration":adapter.narration,"feedback":adapter.last_feedback})
func _run() -> void:
	check(FileAccess.get_sha256("res://view/generated_natural_coast_basic/adapter.gd") == ADAPTER_SHA256,"exact changed production adapter source binding")
	check(FileAccess.get_sha256("res://view/generated_natural_coast_basic/engine.gd") == "dba3ca7fe04dc8a4100897250fc19c5c6c2acff2ef687ff120e894beadf6351d","inherited Natural identity Engine unchanged")
	var generated: Dictionary = Generator.generate("726381",4,"coastal_range")
	check(generated.ok,"deterministic source generated")
	if not generated.ok: finish(); return
	var adapter := FakeAdapter.new(generated.source)
	check(adapter.ready().ok,"Natural fixture admitted")
	if not adapter.ready().ok: finish(); return
	var focus := adapter.tile_reference(adapter.state_copy().actors.actor_player.hex)
	check(adapter.begin_intent(adapter.sample_goal("observe",focus),focus).ok,"create valid current-cell observation fixture")
	check(adapter.prepare_fixture().ok,"prepare deterministic assessment")
	check(adapter.roll_once().ok,"populate RNG fixture")
	check(adapter.stage().ok,"stage prior action")
	check(adapter.commit().ok,"populate receipt fixture")
	check(adapter.begin_intent("雪岸 é 🌊 — synthetic pending save").ok,"populate Unicode pending action")
	var saved: Dictionary = adapter.save_data()
	check(not saved.engine.pending.is_empty() and not saved.engine.receipts.is_empty(),"pending and receipt fixtures both populated")
	var path := "user://natural_coast_basic_save_write_result.json"
	check(adapter.save_file(path).ok,"native setup writes isolated valid same-identity destination")
	var original := FileAccess.get_file_as_bytes(path)
	check(original == C.bytes(saved).to_utf8_buffer(),"setup destination exact UTF-8")
	setup_assertions = assertions
	if not failures.is_empty(): finish(); return
	run_case(adapter,path,original,"store_false_error_OK",{"stored":false,"write_error":OK},false,["open","store","flush","get_error","close"])
	run_case(adapter,path,original,"store_false_error_non_OK",{"stored":false,"write_error":ERR_FILE_CANT_WRITE},false,["open","store","flush","get_error","close"])
	run_case(adapter,path,original,"store_true_flush_observable_error",{"stored":true,"write_error":OK,"flush_error":ERR_FILE_CANT_WRITE},false,["open","store","flush","get_error","close"])
	run_case(adapter,path,original,"open_failure",{"open_failed":true},false,["open"])
	run_case(adapter,path,original,"Unicode_UTF8_success",{},true,["open","store","flush","get_error","close","rename"])
	finish()
func run_case(adapter: RefCounted, path: String, original: PackedByteArray, label_: String, options: Dictionary, expect_ok: bool, expected_calls: Array) -> void:
	var start_assertions := assertions
	var start_failures := failures.size()
	var before := snapshot(adapter)
	var saved: Dictionary = adapter.save_data()
	var encoded := C.bytes(saved)
	ProbeIO.reset(options,path,original)
	adapter.use_fake_backend = true
	# Inherited production save_file includes actual identity/state validation.
	# Allocation, staging readback and fixed cleanup are additional explicit I/O seams.
	var result: Dictionary = adapter.save_file(path)
	check(result.get("ok",false) == expect_ok,label_+": exact result")
	if not expect_ok: check(result.get("code") == "SAVE_FAILED",label_+": SAVE_FAILED returned")
	check(ProbeIO.calls == expected_calls,label_+": exact operation order")
	check(ProbeIO.counters.renames == (1 if expect_ok else 0),label_+": rename count")
	check(ProbeIO.counters.opened == (0 if options.get("open_failed",false) else 1),label_+": opened handle count")
	check(ProbeIO.counters.closed == ProbeIO.counters.opened,label_+": each opened handle closed exactly once")
	check(snapshot(adapter) == before,label_+": complete live adapter snapshot unchanged")
	var after: Dictionary = adapter.save_data()
	for field in ["state","rng","pending","receipts"]:
		check(C.bytes(after.engine[field]) == C.bytes(saved.engine[field]),label_+": "+field+" byte-exact")
	check(FileAccess.get_file_as_bytes(path) == original,label_+": real old destination byte-exact")
	if expect_ok:
		check(ProbeIO.files[path] == encoded.to_utf8_buffer() and ProbeIO.files[path+".tmp"] == "PREEXISTING_TEST_TMP".to_utf8_buffer(),label_+": memory success exact UTF-8")
		check(encoded.contains("雪岸") and encoded.to_utf8_buffer().size() > encoded.length(),label_+": actual multibyte Unicode serialization")
		var memory_reader := Adapter.new()
		check(memory_reader.load_data(JSON.parse_string(ProbeIO.files[path].get_string_from_utf8())).ok and C.bytes(memory_reader.save_data()) == encoded,label_+": existing strict loader memory roundtrip")
		adapter.use_fake_backend = false
		var native_path := "user://natural_coast_basic_save_write_result_unicode.json"
		check(adapter.save_file(native_path).ok,label_+": real isolated native save succeeds")
		check(FileAccess.get_file_as_bytes(native_path) == encoded.to_utf8_buffer(),label_+": real native UTF-8 byte-exact")
		var disk_reader := Adapter.new()
		check(disk_reader.load_file(native_path).ok and C.bytes(disk_reader.save_data()) == encoded,label_+": existing load_file real roundtrip")
		check(snapshot(adapter) == before,label_+": native save preserves state/RNG/pending/receipts")
	else:
		check(ProbeIO.files[path] == original,label_+": memory old destination byte-exact")
		if options.get("open_failed",false):
			check(ProbeIO.files[path+".tmp"] == "PREEXISTING_TEST_TMP".to_utf8_buffer(),label_+": no temp/store/flush on open failure")
		else:
			check(ProbeIO.files[path+".tmp"] == "PREEXISTING_TEST_TMP".to_utf8_buffer() and ProbeIO.directories.is_empty(),label_+": old temp unchanged; own failed staging removed")
			check(ProbeIO.counters.error_reads.size() == 1 and ProbeIO.counters.error_reads[0].after_flush,label_+": observable error checked after flush")
	adapter.use_fake_backend = false
	var outcome := {"case":label_,"passed":failures.size()==start_failures,"assertions":assertions-start_assertions,"calls":ProbeIO.calls.duplicate(),"counters":ProbeIO.counters.duplicate(true),"failure_code":result.get("code",""),"failure_simulation":"in-memory backend only","native_success":expect_ok}
	cases.append(outcome)
	print("FOCUSED_CASE ",JSON.stringify(outcome))
func finish() -> void:
	print("NATURAL_WRITE_RESULT ",JSON.stringify({"ok":failures.is_empty(),"assertions":assertions,"setup_assertions":setup_assertions,"cases":cases,"failures":failures,"owned_pid":OS.get_process_id(),"adapter_sha256":ADAPTER_SHA256,"script_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"adapted original five stimuli through candidate production save_file; staging seams explicit; not the old script hash or OS short-write/crash acceptance"}))
	quit(0 if failures.is_empty() else 1)

