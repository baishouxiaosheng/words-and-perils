extends SceneTree
const Adapter = preload("res://view/playable_build/adapter.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks := 0
var failures: Array = []
func expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var runtime := Adapter.new()
	expect(runtime.engine.ready().ok and runtime.engine.rule_id() == "coast_release/v1", "runtime uses release rule")
	expect(runtime.state_copy().actors.has("actor_raider") and runtime.state_copy().items.has("item_coast_staff"), "only new production game installs authored optional encounter")
	var seeded := Adapter.new(33, true)
	expect(seeded.engine.ready().ok and seeded.engine.rule_id() == "ai_gm_test_coast_release/v1", "explicit deterministic release fixture honestly test-labelled")
	var plain := Adapter.new(33)
	expect(plain.engine.rule_id() == "ai_gm_test_coast_actions/v1" and not plain.state_copy().actors.has("actor_raider"), "historical seeded fixture preserved")
	for kind in ["pickup", "equip", "drop", "pickup", "equip_bow", "equip_wand", "observe"]:
		var goal: String = runtime.sample_goal(kind)
		var begun: Dictionary = runtime.begin_intent(goal)
		expect(begun.ok and runtime.fixture_available(), "exact authored basic goal available " + kind)
		var prepared: Dictionary = runtime.prepare_fixture()
		expect(prepared.ok, "release strict authored assessment accepted " + kind)
		if not prepared.ok: print(prepared); quit(1); return
		var path := "user://release_phase.json"
		for phase in ["ready_roll", "rolled", "staged"]:
			expect(runtime.save_file(path).ok, "save " + phase)
			var reload := Adapter.new()
			expect(reload.load_file(path).ok and C.bytes(reload.engine.save_data()) == C.bytes(runtime.engine.save_data()), "reload exact " + phase)
			if phase == "ready_roll": runtime.roll_once()
			elif phase == "rolled": runtime.stage()
		expect(runtime.commit().ok, "commit basic " + kind)
	var tamper := Adapter.new()
	tamper.begin_intent(tamper.sample_goal("pickup"))
	var built: Dictionary = preload("res://view/playable_build/authored_assessments.gd").build(tamper.request())
	built.assessment.components[0].parameters.A = 4
	expect(not tamper.engine.prepare_assessment(built.assessment).ok, "forged fixture parameters rejected under production")
	var historical := Adapter.new()
	historical.engine = historical._make_engine(null, false, true, true, false, false)
	# Start through base engine so upgrade is not requested before this old save exists.
	var began: Dictionary = historical.engine.begin_intent(historical.sample_goal("observe"))
	historical.active_action = began.request.action_id
	expect(historical.prepare_fixture().ok, "historical registered fixture freeze")
	historical.roll_once(); historical.stage()
	var old_items: Array = historical.state_copy().items.keys(); var old_actors: Array = historical.state_copy().actors.keys()
	expect(historical.save_file("user://old_pending.json").ok, "save old pending")
	var restored := Adapter.new()
	expect(restored.load_file("user://old_pending.json").ok, "load old pending exact rule registry")
	expect(restored.engine.rule_id() == "ai_gm_test_coast_actions/v1" and restored.phase() == "staged", "pending not reinterpreted")
	expect(restored.commit().ok, "old pending completes with original result")
	var next: Dictionary = restored.begin_intent(restored.sample_goal("observe"))
	expect(next.ok and restored.engine.rule_id() == "coast_release/v1", "idle old runtime upgrades for subsequent intent")
	expect(C.bytes(old_items) == C.bytes(restored.state_copy().items.keys()) and C.bytes(old_actors) == C.bytes(restored.state_copy().actors.keys()), "upgrade grants no items or NPCs")
	print("RELEASE ADAPTER ", checks - failures.size(), "/", checks, " ", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
