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
var diagnostic_only := false
var path := "user://natural_coast_basic_save_owned_staging.json"
var original := PackedByteArray()
var generated: Dictionary = {}
var a: RefCounted
var b: RefCounted
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label_: String) -> void:
	assertions += 1
	if not ok: failures.append(label_); printerr("FAIL: "+label_)
func snapshot(adapter: RefCounted) -> String:
	return C.bytes({"save":adapter.save_data(),"active_action":adapter.active_action,"last_action":adapter.last_action,"narration":adapter.narration,"feedback":adapter.last_feedback})
func nonce(value: int) -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(32); bytes.fill(value); return bytes
func _run() -> void:
	var expected: String = OS.get_environment("FOGBANK_STAGING_TEST_USER_DIR").replace("\\","/").trim_suffix("/")
	if expected.is_empty() or OS.get_user_data_dir().replace("\\","/").trim_suffix("/") != expected:
		printerr("STAGING_TEST_REFUSED: explicit isolated user directory required"); quit(2); return
	if FileAccess.file_exists(path):
		printerr("STAGING_TEST_REFUSED: fresh isolated test directory required"); quit(2); return
	check(FileAccess.get_sha256("res://view/generated_natural_coast_basic/adapter.gd") == ADAPTER_SHA256,"candidate production source binding")
	check(FileAccess.get_sha256("res://view/generated_natural_coast_basic/engine.gd") == "dba3ca7fe04dc8a4100897250fc19c5c6c2acff2ef687ff120e894beadf6351d","inherited identity Engine unchanged")
	generated = Generator.generate("726381",4,"coastal_range")
	check(generated.get("ok",false),"source generated")
	if not generated.get("ok",false): finish(); return
	a = FakeAdapter.new(generated.source); b = FakeAdapter.new(generated.source)
	check(a.ready().ok and b.ready().ok,"both same-identity production adapters admitted")
	if not a.ready().ok or not b.ready().ok: finish(); return
	check(a.begin_intent("雪岸 é 🌊 — synthetic transaction A").ok,"A has distinct exact pending payload")
	check(C.bytes(a.save_data()) != C.bytes(b.save_data()),"A and B payload bytes differ")
	check(a.save_file(path).ok,"native isolated setup destination")
	original = FileAccess.get_file_as_bytes(path)
	if not failures.is_empty(): finish(); return
	a.use_fake_backend = true; b.use_fake_backend = true
	if diagnostic_only:
		cleanup_diagnostic()
	else:
		collision_group(); legacy_group(); cleanup_group()
	finish()
func collision_group() -> void:
	var before_a: String = snapshot(a); var before_b: String = snapshot(b)
	var expected_a: PackedByteArray = C.bytes(a.save_data()).to_utf8_buffer()
	var expected_b: PackedByteArray = C.bytes(b.save_data()).to_utf8_buffer()
	ProbeIO.reset({"nonce_queue":[nonce(11),nonce(11),nonce(22)]},path,original)
	var observed: Dictionary = {}
	ProbeIO.options["before_rename"] = func() -> void:
		var owned_directory: String = ProbeIO.created[0]
		var payload_path: String = owned_directory.path_join("payload.json")
		var retained: PackedByteArray = ProbeIO.files[payload_path].duplicate()
		var collided: Dictionary = b.save_file(path)
		observed["collision_rejected"] = not collided.ok and collided.get("code") == "SAVE_FAILED"
		observed["collision_did_not_claim"] = ProbeIO.created.size() == 1
		observed["collision_did_not_write"] = ProbeIO.files[payload_path] == retained
		observed["same_first_name"] = ProbeIO.attempted[0] == ProbeIO.attempted[1]
		var second: Dictionary = b.save_file(path)
		observed["b_saved_own_bytes"] = second.ok and ProbeIO.files[path] == expected_b
		observed["a_bytes_survived_b"] = ProbeIO.files[payload_path] == retained
		observed["different_owned_directories"] = ProbeIO.created.size() == 2 and ProbeIO.created[0] != ProbeIO.created[1]
	var result: Dictionary = a.save_file(path)
	for key in observed: check(observed[key],"collision group: "+key)
	check(observed.size() == 7,"all explicit collision interleave observations executed")
	check(result.ok and ProbeIO.files[path] == expected_a,"A promotes only A bytes after B transaction")
	check(ProbeIO.directories.is_empty(),"both successful owners remove only their empty directory")
	check(ProbeIO.counters.opened == 2 and ProbeIO.counters.closed == 2,"collision loser never opens; two writes close once")
	check(ProbeIO.counters.read_opened == 2 and ProbeIO.counters.read_closed == 2,"two stage readbacks close once")
	check(snapshot(a) == before_a and snapshot(b) == before_b,"both live adapters and RNG/state remain unchanged")
	check(FileAccess.get_file_as_bytes(path) == original,"mock interleave cannot alter real setup destination")
	cases.append({"group":"independent_ownership_collision","observed":observed,"kind":"deterministic in-memory interleave; not OS concurrency"})
func legacy_group() -> void:
	for succeeds in [true,false]:
		ProbeIO.reset({} if succeeds else {"stored":false,"write_error":OK},path,original)
		var sentinel: PackedByteArray = ProbeIO.files[path+".tmp"].duplicate()
		var result: Dictionary = a.save_file(path)
		check(result.ok == succeeds,"legacy group: expected result")
		check(ProbeIO.files[path+".tmp"] == sentinel,"legacy shared tmp bytes unchanged on success/failure")
		check(ProbeIO.directories.is_empty(),"legacy group: only owned staging cleaned")
		cases.append({"group":"legacy_tmp_preserved","save_succeeded":succeeds})
func cleanup_group() -> void:
	for settings in [{"open_failed":true},{"stored":false,"write_error":OK},{"readback_corrupt":true}]:
		ProbeIO.reset(settings,path,original)
		var result: Dictionary = a.save_file(path)
		check(not result.ok and result.get("code") == "SAVE_FAILED","pre-rename failure reported")
		check(ProbeIO.counters.renames == 0,"pre-rename failure never promotes")
		check(ProbeIO.files[path] == original and ProbeIO.directories.is_empty(),"pre-rename failure cleans only owned staging")
		check(ProbeIO.files.size() == 2 and ProbeIO.files.has(path+".tmp"),"original destination and legacy sentinel both remain")
		check(ProbeIO.counters.opened == ProbeIO.counters.closed and ProbeIO.counters.read_opened == ProbeIO.counters.read_closed,"all opened handles closed once")
		cases.append({"group":"owned_cleanup","branch":"pre_rename_failure","settings":settings})
	ProbeIO.reset({"rename_error":ERR_CANT_CREATE,"drop_destination_on_rename_failure":true},path,original)
	var failed: Dictionary = a.save_file(path)
	var directory: String = ProbeIO.created[0]; var payload: String = directory.path_join("payload.json")
	check(not failed.ok and failed.get("recovery_path") == payload and failed.get("staging_directory") == directory,"rename failure reports exact owned recovery location")
	check(ProbeIO.directories.has(directory) and ProbeIO.files[payload] == C.bytes(a.save_data()).to_utf8_buffer(),"rename failure keeps full recoverable payload and directory")
	check(not ProbeIO.files.has(path),"simulate destructive rename failure without pretending old memory target survived")
	check(ProbeIO.files[path+".tmp"] == "PREEXISTING_TEST_TMP".to_utf8_buffer(),"rename failure preserves legacy sentinel")
	check(not ProbeIO.staging_calls.any(func(event: Variant) -> bool: return event is Dictionary and event.has("remove")),"no cleanup at all after failed rename")
	cases.append({"group":"owned_cleanup","branch":"rename_failure_payload_retained","kind":"simulated backend removes target; not native Windows proof"})
	ProbeIO.reset({},path,original)
	var saved: Dictionary = a.save_file(path)
	check(saved.ok and not saved.has("cleanup_error") and ProbeIO.directories.is_empty(),"successful rename removes empty owned directory")
	check(ProbeIO.files.size() == 2 and ProbeIO.files[path+".tmp"] == "PREEXISTING_TEST_TMP".to_utf8_buffer(),"successful cleanup leaves no owned payload and never touches legacy tmp")
	cases.append({"group":"owned_cleanup","branch":"successful_commit_cleanup"})
func cleanup_diagnostic() -> void:
	ProbeIO.reset({"directory_remove_failed":true},path,original)
	var saved: Dictionary = a.save_file(path)
	check(saved.ok and saved.get("cleanup_ok",true) == false and saved.get("cleanup_error") == ERR_CANT_CREATE,"cleanup diagnostic preserves committed success and separately reports cleanup error")
	check(ProbeIO.files[path] == C.bytes(a.save_data()).to_utf8_buffer() and ProbeIO.directories.size() == 1,"commit bytes exist; failed empty-directory cleanup retained")
	check(saved.get("cleanup_directory") == ProbeIO.created[0],"cleanup diagnostic points only to own directory")
	cases.append({"group":"owned_cleanup","branch":"cleanup_failure_diagnostic","strict_guard_pass_expected":false,"native_error_must_remain_visible":true})
func finish() -> void:
	print("NATURAL_OWNED_STAGING ",JSON.stringify({"ok":failures.is_empty(),"assertions":assertions,"failures":failures,"cases":cases,"group_count":1 if diagnostic_only else 3,"diagnostic_only":diagnostic_only,"strict_guard_pass_expected":not diagnostic_only,"pid":OS.get_process_id(),"adapter_sha256":ADAPTER_SHA256,"script_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"candidate actual save_file via explicit test I/O seams; in-memory collision/cleanup, no OS concurrency/CAS/Windows/crash claim"}))
	quit(0 if failures.is_empty() else 1)
