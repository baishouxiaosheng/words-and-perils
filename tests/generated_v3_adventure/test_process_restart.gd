extends SceneTree
const Adapter = preload("res://view/generated_v3_adventure/adapter.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const PREFIX := "user://generated_v3_process_"
var failed := false
func _initialize() -> void: run.call_deferred()
func verify(ok: bool, label_: String) -> void:
	if not ok: failed = true; printerr("FAIL "+label_)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if not args.is_empty() else "write"
	var phase_ := String(args[1]) if args.size() > 1 else "locked"
	var path := PREFIX+phase_+".json"
	if mode == "write":
		var generated := Generator.generate("v3 restart text seed",4,"plateau_hinterland")
		verify(generated.ok,"source generated")
		if not generated.ok: quit(1); return
		var adapter := Adapter.new(generated.source)
		verify(adapter.ready().ok,"new V3 admitted")
		if not adapter.ready().ok: printerr(adapter.ready()); quit(1); return
		var actor: Dictionary = adapter.state_copy().actors.actor_player
		var focus := adapter.tile_reference(actor.hex)
		if phase_ != "idle": verify(adapter.begin_intent(adapter.sample_goal("observe",focus),focus).ok,"pending")
		if phase_ == "canceled": verify(adapter.cancel().ok,"canceled")
		if phase_ in ["ready","locked","staged","committed"]: verify(adapter.prepare_fixture().ok,"ready")
		if phase_ in ["locked","staged","committed"]: verify(adapter.roll_once().ok,"locked")
		if phase_ in ["staged","committed"]: verify(adapter.stage().ok,"staged")
		if phase_ == "committed": verify(adapter.commit().ok,"committed")
		verify(adapter.save_file(path).ok,"saved")
		var witness := FileAccess.open(path+".sha256",FileAccess.WRITE); witness.store_string(C.digest(adapter.save_data())); witness.close()
	else:
		var adapter := Adapter.new(); var checked := adapter.load_file(path)
		verify(checked.ok,"fresh process loaded "+phase_)
		if not checked.ok: printerr(checked); quit(1); return
		var witness := FileAccess.open(path+".sha256",FileAccess.READ)
		verify(witness != null and witness.get_as_text() == C.digest(adapter.save_data()),"complete exact JSON and RNG retained across process exit")
		if witness != null: witness.close()
		if phase_ in ["locked","staged"]:
			var before := C.bytes(adapter.save_data())
			verify(not adapter.cancel().ok and C.bytes(adapter.save_data()) == before,"locked restart cannot cancel")
			if phase_ == "locked": verify(adapter.stage().ok,"resumed stage")
			verify(adapter.commit().ok,"resumed commit")
			verify(adapter.state_copy().flags.observations == 1 and adapter.state_copy().turn == 1,"one exact observation consequence")
	print("V3 PROCESS ",mode," ",phase_," ","PASS" if not failed else "FAIL")
	quit(1 if failed else 0)
