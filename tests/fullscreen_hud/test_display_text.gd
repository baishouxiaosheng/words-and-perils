extends SceneTree
## Bounded presentation regression. Run serially with isolated XDG user data.
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const DisplayText=preload("res://view/playable_build/display_text.gd")
const OUT="res://artifacts/fullscreen_hud_20261002/presentation_cleanup/"
var scene
var checks:=0
var failures:Array[String]=[]
var wrapping:Array=[]
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);printerr("FAIL: "+title)
func _initialize()->void:call_deferred("run")
func settle()->void:
	for i in range(8):await process_frame
func capture(name_:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settle();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1920,1080)
	scene=Main.instantiate();root.add_child(scene);await settle()
	var raw:String=scene.playtest.sample_goal("observe",{})
	var clean:=DisplayText.player_intent(raw)
	scene.fill_coast_sample("observe");await settle()
	check(not raw==clean and scene.goal.text==clean,"chosen sample shows natural input")
	check(scene.submitted_player_intent()==raw,"unchanged chosen sample retains exact signed goal")
	var before:=C.bytes(scene.playtest.state_copy())
	scene.submit_action();await settle()
	check(scene.playtest.action_copy().goal==raw,"engine receives unchanged raw signed goal")
	check(scene.playtest.fixture_available(),"chosen sample still matches signed assessment")
	check(not scene.journal.get_parsed_text().contains(DisplayText.SAMPLE_PREFIX) and scene.latest_dialogue.text==clean,"live history and preview hide protocol prefix")
	check(C.bytes(scene.playtest.state_copy())==before,"presentation and pending intent do not commit facts")
	var pending:=C.bytes(scene.playtest.action_copy())
	scene.save_game();scene.load_game();await settle()
	check(C.bytes(scene.playtest.action_copy())==pending,"saved pending action is byte-identical after restore")
	check(scene.goal.text==clean and not scene.journal.get_parsed_text().contains(DisplayText.SAMPLE_PREFIX),"restored pending input and history use natural intent")
	await capture("01_clean_pending_1920")
	scene.end_turn_requested=false
	scene.playtest_fixture();await settle()
	check(not scene.journal.get_parsed_text().contains("手写夹具") and not scene.journal.get_parsed_text().contains("评估预览"),"technical fixture preview stays outside normal history")
	check(scene.status_label.text.contains("手写演示") and scene.status_label.text.contains("未调用模型"),"advanced status retains honest sample provenance")
	scene.end_turn();await settle()
	check(scene.playtest.phase()=="idle" and scene.playtest.state_copy().turn==1,"primary action still completes accepted result once")
	scene.save_game();scene.load_game();await settle()
	if not scene.journal_open:scene.toggle_journal()
	scene.journal.scroll_following=false;scene.journal.scroll_to_line(0);await settle()
	await capture("03_real_restored_history_1920")
	scene.journal.scroll_following=true
	scene.toggle_journal()
	var signed_rest:String=scene.playtest.sample_goal("rest",{})
	scene.fill_coast_sample("rest");await settle()
	var natural_rest:String=scene.goal.text
	scene.goal.set_caret_column(scene.goal.get_line(0).length())
	scene.goal.insert_text_at_caret("再看看海面");await settle()
	check(scene.submitted_player_intent()==scene.goal.text and not scene.submitted_player_intent().begins_with(DisplayText.SAMPLE_PREFIX),"editing a sample immediately loses signed draft token")
	scene.goal.undo();await settle()
	check(scene.goal.text==natural_rest and scene.submitted_player_intent()!=signed_rest,"undo to original wording does not silently regain sample provenance")
	scene.submit_action();await settle()
	check(not scene.playtest.fixture_available() and scene.playtest.action_copy().goal==natural_rest,"edited draft uses ordinary offline assessment even after undo")
	scene.cancel_pending();scene.goal.text=""
	var long_outcome:="旧灯重新亮起，桐岸确认岸线恢复了引航信号。旧灯重燃：本段冒险完成。船队去向仍待后续调查（尚未制作）。体力减少两点，桐岸继续沿岸巡视。你记下断绳、潮痕与新亮起的灯火，准备在下一段旅程里继续调查。"
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle();scene.apply_responsive_layout();await settle()
		scene.journal.clear()
		for i in range(3):scene.append_journal("回合结束 · 第 %d 回合"%(i+1),long_outcome)
		if not scene.journal_open:scene.toggle_journal()
		await settle()
		var parsed:String=scene.journal.get_parsed_text()
		check(parsed.count(long_outcome)==3,"all long outcome text retained "+str(resolution))
		var box:StyleBox=scene.journal.get_theme_stylebox("normal")
		var available:float=scene.journal.size.x-box.get_margin(SIDE_LEFT)-box.get_margin(SIDE_RIGHT)
		var scrollbar:VScrollBar=scene.journal.get_v_scroll_bar()
		if scrollbar.visible:available-=scrollbar.size.x
		var widest:=0.0
		for line in range(scene.journal.get_line_count()):widest=maxf(widest,scene.journal.get_line_width(line))
		check(widest<=available+1.0,"every history line fits inner text width "+str(resolution))
		check(scene.journal.get_line_count()>scene.journal.get_paragraph_count(),"long paragraphs really wrap "+str(resolution))
		check(scrollbar.visible and scrollbar.max_value>scrollbar.page,"overflow remains accessible by vertical scrolling "+str(resolution))
		wrapping.append({"resolution":[resolution.x,resolution.y],"text_width":available,"widest_line":widest,"line_count":scene.journal.get_line_count(),"paragraph_count":scene.journal.get_paragraph_count(),"scrollbar_visible":scrollbar.visible})
		scene.journal.scroll_to_line(0);await settle()
		await capture("02_history_wrap_"+str(resolution.x))
	var report={"passed":checks-failures.size(),"total":checks,"failures":failures,"wrapping":wrapping,"display":DisplayServer.get_name()}
	var f:=FileAccess.open(OUT+"verification.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("DISPLAY_PRESENTATION ",checks-failures.size(),"/",checks," ",JSON.stringify(wrapping))
	scene.free();quit(0 if failures.is_empty() else 1)
