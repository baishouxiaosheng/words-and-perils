extends SceneTree
const Adapter=preload("res://view/playable_build/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Story=preload("res://view/playable_build/story.gd")
const DisplayText=preload("res://view/playable_build/display_text.gd")
const OUT="res://artifacts/full_journey_20261002/"
var failures:Array[String]=[]
var rows:Array=[]
var checks:=0
func check(ok:bool,label_:String)->void:
	checks+=1
	if not ok:failures.append(label_);printerr("JOURNEY_FAIL "+label_)
func _initialize()->void:call_deferred("run")
func act(a:RefCounted,kind:String)->bool:
	var before:Dictionary=a.state_copy()
	check(a.begin_intent(a.sample_goal(kind)).ok,kind+" intent accepted")
	var prep:Dictionary=a.prepare_fixture();check(prep.ok,kind+" assessment accepted "+str(prep))
	if not prep.ok:return false
	check(a.state_copy()==before,kind+" assessment has no side effects")
	check(a.roll_once().ok,kind+" locked outcome")
	var locked:Dictionary=a.action_copy()
	check(not a.cancel().ok,kind+" cannot cancel locked")
	a.roll_once();check(a.action_copy()==locked,kind+" repeated roll unchanged")
	check(a.stage().ok,kind+" staged")
	check(a.commit().ok,kind+" committed")
	check(a.state_copy().turn==before.turn+1,kind+" one turn")
	check(a.state_copy().actors.actor_scout.patrol.index==(before.actors.actor_scout.patrol.index+1)%3,kind+" exactly one patrol step")
	rows.append({"kind":kind,"turn":a.state_copy().turn,"position":a.state_copy().actors.actor_player.hex,"stamina":a.state_copy().actors.actor_player.stamina.current,"wine":a.state_copy().items.item_wine.quantity,"flags":a.state_copy().flags,"feedback":a.last_feedback,"goal":a.story_goal(),"result":a.authoritative_result()})
	return true
func run()->void:
	check(DisplayText.player_intent("【署名样例】观察岸线。")=="观察岸线。","presentation removes leading authoring tag")
	check(DisplayText.player_intent("我念出【署名样例】这几个字。 ")=="我念出【署名样例】这几个字。 ","presentation preserves ordinary wording and interior tags")
	var a=Adapter.new(17)
	var before:Dictionary=a.state_copy()
	a.begin_intent(a.sample_goal("repair"));var fail_:Dictionary=a.prepare_fixture()
	check(not fail_.ok and fail_.get("code")=="CLUE_REQUIRED","cannot repair without clue")
	check(a.state_copy()==before,"rejected repair preserves all facts");a.cancel()
	for kind in ["move","observe","talk","rest","repair"]:
		if not act(a,kind):break
	check(a.story_complete(),"meaningful restored-lamp endpoint reached")
	check(a.last_feedback.contains("本段冒险完成") and a.last_feedback.contains("体力"),"resolution and cost visible")
	check(a.story_goal().contains("尚未制作"),"unbuilt continuation is explicitly bounded")
	before=a.state_copy();a.begin_intent(a.sample_goal("repair"));fail_=a.prepare_fixture()
	check(not fail_.ok and fail_.get("code")=="CHAPTER_COMPLETE","repeat repair rejected")
	check(a.state_copy()==before,"repeat repair no resource cost");a.cancel()
	check(a.save_file("user://full_journey_new.json").ok,"completed chapter saved")
	var restored=Adapter.new(90);check(restored.load_file("user://full_journey_new.json").ok,"completed chapter restored")
	check(restored.state_copy()==before and restored.story_complete(),"completion, resources, location, patrol survive load")
	check(not restored.last_feedback.is_empty(),"last readable result survives load")
	var frozen_history:String=C.bytes(restored.engine.save_data())
	var visible_history:Array=restored.journal_entries()
	check(not String(visible_history[0].text).contains("【署名样例】"),"restored player history displays natural intent")
	check(C.bytes(restored.engine.save_data())==frozen_history,"display-only history never rewrites signed goals, state or dice")
	check(restored.journal_entries().size()==10 and restored.journal_entries()[-1].text.contains("本段冒险完成"),"verified five-turn player history can be restored")
	check(restored.journal_entries()[3].text.contains("受潮") and not restored.journal_entries()[3].text.contains("旧灯仍在发光"),"later completion never rewrites earlier observed clue")
	# Historical source saves must not be reinterpreted under a changed physical bundle.
	var legacy=Adapter.new(90)
	var existing:Dictionary=legacy.engine.save_data()
	var legacy_path:String=OUT+"legacy_locked_save.json"
	var old_bytes:String=FileAccess.get_file_as_string(legacy_path)
	var old=JSON.parse_string(old_bytes)
	var load_old:Dictionary=legacy.load_file(legacy_path)
	if old.state.generated_world.get("catalog_sha256") != legacy.state_copy().generated_world.get("catalog_sha256"):
		check(not load_old.ok and load_old.get("code")=="BUNDLE_MISMATCH","cross-source locked save explicitly refused")
		check(legacy.engine.save_data()==existing,"refused old save leaves current world/RNG intact")
		check(FileAccess.get_file_as_string(legacy_path)==old_bytes,"refused old save remains byte-exact on disk")
	else:
		check(load_old.ok,"same-source old locked save still loads")
		check(C.bytes(legacy.engine.save_data())==C.bytes(old),"old pending dice/state/context remain byte-exact")
		legacy.roll_once();check(C.bytes(legacy.engine.save_data())==C.bytes(old),"legacy save cannot reroll")
		check(legacy.stage().ok and legacy.commit().ok,"old locked turn completes")
		var preserved=legacy.engine.save_data();var resumed:Dictionary=legacy.begin_intent(legacy.sample_goal("observe"));check(resumed.ok,"next legacy intent safely upgrades idle state")
		check(legacy.state_copy().flags.has("lamp_restored"),"new story available after old pending ends")
		check(legacy.engine.save_data().rng==preserved.rng and legacy.engine.save_data().receipts==preserved.receipts,"upgrade keeps RNG and receipts exact")
		legacy.cancel()
	check(legacy.prepare_fixture().get("code")=="FIXTURE_SCOPE","no fixture auto-inference without pending exact intent")
	var broken:=FileAccess.open("user://malformed_save.json",FileAccess.WRITE);broken.store_string('{"state": {"flags": null}}');broken.close()
	check(not legacy.load_file("user://malformed_save.json").ok,"malformed flags rejected without script crash")
	# Bypass persuasion entirely: running out of wine never deadlocks the chapter.
	var independent=Adapter.new(9)
	check(act(independent,"observe") and act(independent,"repair") and independent.story_complete(),"observed clue permits self-repair without trust")
	check(independent.state_copy().actors.actor_player.stamina.current==6 and independent.state_copy().items.item_wine.quantity==3,"self-repair costs two stamina, no wine")
	var f=FileAccess.open(OUT+"story_journey.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"kind":"programmatic fixed-rule story journey; no model called","checks":checks,"failures":failures,"turns":rows,"active_bundle":a.state_copy().generated_world},"\t"));f.close()
	print("STORY_JOURNEY ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
