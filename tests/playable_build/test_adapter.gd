extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var n := 0
var failed: Array[String] = []
func check(value: bool, title: String) -> void:
	n+=1
	if not value: failed.append(title); printerr("FAIL: "+title)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var a := Adapter.new(17)
	check(a.engine.ready().ok,"accepted real source creates valid engine")
	check(a.state_copy().hexes.size()==1801,"all playable real cells, no halo")
	var before := a.state_copy()
	check(a.begin_intent("飞过大海并杀死所有人").ok,"free text creates assessment request")
	check(not a.fixture_available() and not a.prepare_fixture().ok,"arbitrary text cannot use samples")
	check(a.state_copy()==before,"text and rejected fixture cannot mutate facts")
	check(a.cancel().ok,"pre-evaluation cancellation")
	for kind in ["move","observe","talk","rest"]:
		check(a.begin_intent(a.sample_goal(kind)).ok,kind+" begins")
		var prep := a.prepare_fixture()
		check(prep.ok,kind+" prepares "+str(prep))
		if not prep.ok: break
		before = a.state_copy()
		check(a.roll_once().ok,kind+" resolves once")
		var locked := C.bytes(a.action_copy())
		a.roll_once()
		check(C.bytes(a.action_copy())==locked,kind+" reroll is stable")
		check(not a.cancel().ok,kind+" cannot cancel resolved")
		check(a.stage().ok and a.state_copy()==before,kind+" staging preserves facts")
		check(a.save_file("user://coast_test_save.json").ok,kind+" saves staged")
		var restored := Adapter.new(98)
		check(restored.load_file("user://coast_test_save.json").ok,kind+" loads staged")
		check(C.bytes(restored.action_copy())==C.bytes(a.action_copy()),kind+" save preserves dice and stage")
		check(a.commit().ok,kind+" commits")
		check(a.state_copy().turn==before.turn+1,kind+" increments exactly one turn")
		check(a.state_copy().actors.actor_scout.hex!=before.actors.actor_scout.hex,kind+" configured patrol advances")
	print("PLAYABLE ADAPTER ",n-failed.size(),"/",n)
	quit(0 if failed.is_empty() else 1)
