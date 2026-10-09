extends SceneTree
const Adapter=preload("res://view/generated_inventory/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_pack_selection/"
var phase_:="pending"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase_=arg.trim_prefix("--phase=")
	run.call_deferred()
func run() -> void:
	var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"native_checkpoints.json"))[phase_]
	var adapter:=Adapter.new();assert(adapter.load_file(OUT+"native_"+phase_+".json").ok)
	assert(C.digest(adapter.save_data())==expected.digest)
	assert(adapter.phase()==expected.phase and C.bytes(adapter.engine.save_data().rng)==C.bytes(expected.rng))
	assert(adapter.attention(adapter.item_reference()).ok)
	if phase_=="pending":assert(adapter.cancel().ok and C.bytes(adapter.state_copy())==C.bytes(expected.state))
	elif phase_=="locked":
		assert(adapter.roll_once().ok and C.digest(adapter.save_data())==expected.digest)
		assert(adapter.stage().ok and adapter.commit().ok and adapter.state_copy().items.item_travel_bundle.custody_revision==1)
	else:assert(adapter.state_copy().items.item_travel_bundle.custody_revision==1 and not adapter.state_copy().items.item_travel_bundle.has("owner_actor_id"))
	print("PACK_RESTART_PASS ",phase_," exact fresh-process source/focus/custody/RNG")
	quit(0)
