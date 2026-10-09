extends SceneTree
## Headless mode conditions. Native cleanup coverage is recorded separately.
const Main = preload("res://main.tscn")
var checks := 0
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func has_sky(board: Node) -> bool:
	for node in board.get_children():
		if node is WorldEnvironment and node.environment != null and node.environment.sky != null: return true
	return false
func run() -> void:
	var explicit := "--explicit-property" in OS.get_cmdline_user_args()
	var legacy := explicit or OS.has_environment("FOGBANK_LEGACY_START") or "--legacy-start" in OS.get_cmdline_user_args()
	var app = Main.instantiate(); app.startup_legacy = explicit; root.add_child(app)
	await process_frame
	check(app.coast_mode == not legacy, "requested startup mode is preserved")
	if legacy:
		check(has_sky(app.board), "explicit legacy startup retains reflected Sky")
		check(not app.board.get_meta("diagnosis_skip_startup_sky",false), "explicit legacy start never receives skip flag")
	else:
		check(not has_sky(app.board), "default coast uses its plain-color environment")
		check(app.board.tiles.size() == 1801, "default coast still has complete map")
	app.switch_playtest(false)
	check(not app.coast_mode and not app.playtest_mode, "later legacy preview remains available")
	check(has_sky(app.board), "later legacy preview retains reflected Sky")
	check(not app.board.get_meta("diagnosis_skip_startup_sky",false), "later preview is not marked temporary")
	var label := "property" if explicit else ("environment" if OS.has_environment("FOGBANK_LEGACY_START") else ("argument" if "--legacy-start" in OS.get_cmdline_user_args() else "default"))
	var f := FileAccess.open("res://artifacts/sky_cleanup_20261003/startup_"+label+".json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":checks-failures.size(),"total":checks,"failures":failures,"case":label,"native_render":false},"\t")); f.close()
	print("SKY_STARTUP_",label.to_upper()," ",checks-failures.size(),"/",checks," ",JSON.stringify(failures))
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
