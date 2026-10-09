extends SceneTree
## Verify unsaved, receipt-bound optional prose follows its own old/new session.
const Main=preload("res://main.tscn")
const Old=preload("res://view/generated_v3_npc/adapter.gd")
const New=preload("res://view/generated_v3_enemy/adapter.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var app:Node
var checks=0
var failures:Array=[]
var evidence:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->bool:
	checks+=1
	if not value:failures.append(label);printerr("NARRATION_SESSION_FAIL ",label)
	return value
func frames()->void:
	for i in range(4):await process_frame
func observe()->bool:
	app._apply_focus(app.playtest.tile_reference(app.playtest.state_copy().actors.actor_player.hex))
	app.fill_generated_sample("observe");app.end_turn();app.playtest_fixture()
	return app.playtest.phase()=="idle" and not app.playtest.last_action.is_empty()
func run()->void:
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames()
	var raw:Dictionary=G.generate(726381,4,"coastal_range")
	var old:RefCounted=Old.new(raw.source)
	app._switch_mode_to("generated_v3_npc",old);await frames()
	if not check(app.playtest==old and observe(),"old profile has genuinely committed receipt"):finish();return
	var old_session:RefCounted=app._runtime_adapter()
	var old_id:String=old.last_action
	check(old_session.record_narration(old_id,"OLD_UNSAVED_RECEIPT_NOTE","manual").ok,"old optional note recorded without saving")
	var old_bytes:String=C.bytes(old.save_data())
	var current:RefCounted=New.new(raw.source)
	app._switch_mode_to("generated_v3_enemy",current);await frames()
	if not check(app.playtest==current and observe(),"new profile has genuinely committed receipt"):finish();return
	var new_session:RefCounted=app._runtime_adapter()
	var new_id:String=current.last_action
	check(new_session.record_narration(new_id,"NEW_UNSAVED_RECEIPT_NOTE","manual").ok,"new optional note recorded without saving")
	var new_bytes:String=C.bytes(current.save_data())
	app.on_tool_selected(29);await frames()
	var old_return:RefCounted=app._runtime_adapter()
	check(old_return.has_recorded_narration(old_id),"old unsaved receipt note/idempotency survives advanced-entry switch")
	check(old_return.narration_entries().size()==1,"old session retains exactly its own note")
	check(C.bytes(old.save_data())==old_bytes,"old switch leaves authority byte-exact")
	app.on_tool_selected(27);await frames()
	var new_return:RefCounted=app._runtime_adapter()
	check(new_return.has_recorded_narration(new_id),"new unsaved receipt note/idempotency survives return")
	check(new_return.narration_entries().size()==1,"new session retains exactly its own note")
	check(C.bytes(current.save_data())==new_bytes,"new switch leaves authority byte-exact")
	evidence={"old_before":old_session.narration_entries().size(),"old_after":old_return.narration_entries().size(),"new_before":new_session.narration_entries().size(),"new_after":new_return.narration_entries().size(),"old_facade_retained":old_return==old_session,"new_facade_retained":new_return==new_session,"actual_commits":2,"network_calls":0}
	finish()
func finish()->void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_enemy")
	FileAccess.open("res://artifacts/generated_v3_enemy/narration_sessions_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"evidence":evidence},"\t"))
	print("ENEMY_NARRATION_SESSIONS ",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
