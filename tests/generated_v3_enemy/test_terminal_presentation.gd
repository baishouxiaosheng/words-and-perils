extends SceneTree
## Focused native board gate. All attacks are explicitly assessed offline; no RNG override.
const A=preload("res://view/generated_v3_enemy/adapter.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const E=preload("res://view/generated_v3_enemy/assessments.gd")
const Board=preload("res://view/generated_v3_enemy/board.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const OUT="res://artifacts/generated_v3_enemy/terminal_presentation/"
var a:RefCounted
var board:Node3D
var caption:Label
var checks=0
var failures:Array=[]
var rows:Array=[]
var lethal_staged_seen=false
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("TERMINAL_FAIL ",label_)
	return value
func shot(name_:String,text_:String)->void:
	caption.text=text_
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name_+".png")
func action(kind:String,focus:Dictionary={}) -> bool:
	var begin:Dictionary=a.begin_enemy_response() if kind=="enemy_attack" else a.begin_intent(a.sample_goal(kind,focus),focus)
	if not check(begin.ok,"begin assessed "+kind):return false
	var reply:Dictionary=E.build(a.request()).assessment
	reply.provenance={"provider":"terminal-presentation-offline-mock","kind":"model_reply","live":false}
	if kind in ["attack","enemy_attack"]:
		for component in reply.components:component.parameters={"A":4,"D":0,"P":2} if kind=="attack" else {"A":0,"D":4,"P":-2}
	if not check(a.import_reply(reply).ok,"registered assessment "+kind):return false
	if not check(a.roll_once().ok and a.stage().ok,"lock and stage "+kind):return false
	var before:Dictionary=a.state_copy();var enemy_id:String=a.source.enemy_id
	var staged:Dictionary=a.action_copy().staged
	if staged.actors[enemy_id].health.current==0 and before.actors[enemy_id].health.current>0:
		lethal_staged_seen=true
		board.set_world(a.state_copy(),false)
		check(before.actors[enemy_id].health.current>0 and is_equal_approx(board.token_nodes[enemy_id].scale.y,1.0),"staged lethal result leaves authoritative live standing pawn")
		check(board.committed_effects.accepted_receipts==0 or board.committed_effects.pending.is_empty(),"staging does not create lethal receipt VFX")
		await shot("01_lethal_staged","离线评估已锁定致命结果，尚未提交：敌人仍站立，生命尚未扣除")
	var result:Dictionary=a.commit()
	if not check(result.ok,"commit once "+kind):return false
	board.set_world(a.state_copy(),true,a.authoritative_result().get("public_effects",[]))
	var presented:Dictionary=board.present_committed_receipt(result.receipt,before)
	check(presented.ok,"fresh committed receipt admitted once")
	if a.state_copy().actors[enemy_id].health.current==0:
		check(is_equal_approx(board.token_nodes[enemy_id].scale.y,.38),"committed terminal pawn collapsed vertically")
		check(not a.movement_preview(a.state_copy().actors[enemy_id].hex).ok,"committed downed enemy still blocks cell")
		await shot("02_lethal_committed","致命回合已提交：敌人倒下，原格仍被占据；伤害演出来自已提交回执")
	await create_timer(1.2).timeout
	rows.append({"kind":kind,"turn":a.state_copy().turn,"enemy_hp":a.state_copy().actors[enemy_id].health.current,"player_hp":a.state_copy().actors.actor_player.health.current,"enemy_scale_y":board.token_nodes[enemy_id].scale.y})
	return true
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1280,720)
	a=A.new();a.feature_options={"vegetation":true}
	if not check(a.start_source(G.generate(726381,4,"coastal_range").source).ok,"source-backed vegetation encounter"):finish();return
	board=Board.new(a.source);root.add_child(board);board.set_world(a.state_copy());board.focus_player();board.set_presentation_safe_rect(Rect2(24,100,1232,596))
	var layer=CanvasLayer.new();root.add_child(layer);caption=Label.new();caption.position=Vector2(24,24);caption.size=Vector2(1232,80);caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;caption.add_theme_font_override("font",load("res://assets/NotoSansCJK-Regular.ttc"));caption.add_theme_font_size_override("font_size",24);caption.add_theme_color_override("font_color",Color("182820"));layer.add_child(caption)
	if not check(board.load_error.is_empty(),"native board ready"):finish();return
	var anchor:Array=a.source.enemy_placement_result.attack_anchor_hex
	if not await action("move",a.tile_reference(anchor)):finish();return
	var attempts=0
	while a.state_copy().actors[a.source.enemy_id].health.current>0 and a.state_copy().actors.actor_player.health.current>0 and attempts<16:
		attempts+=1
		var kind:String="enemy_attack" if a.enemy_response_available() else ("attack" if a.state_copy().actors.actor_player.stamina.current>0 else "rest")
		if not await action(kind,a.enemy_reference() if kind=="attack" else {}):finish();return
	if not check(lethal_staged_seen and a.state_copy().actors[a.source.enemy_id].health.current==0,"real assessed encounter reached enemy terminal receipt"):finish();return
	var exact:String=C.bytes(a.save_data())
	if not check(a.save_file("user://terminal_presentation_save.json").ok,"actual disk terminal save"):finish();return
	var loaded=A.new();var result:Dictionary=loaded.load_file("user://terminal_presentation_save.json")
	if not check(result.ok and C.bytes(loaded.save_data())==exact,"actual terminal disk reload exact"):finish();return
	board.admitted_source=loaded.source;board.set_world(loaded.state_copy(),false)
	check(is_equal_approx(board.token_nodes[loaded.source.enemy_id].scale.y,.38),"disk load restores downed pose")
	check(board.committed_effects.pending.is_empty() and board.committed_effects.active_count()==0,"load clears queued/active effects without replay")
	var receipt:Dictionary=loaded.engine.save_data().receipts[loaded.last_action]
	var replay:Dictionary=board.present_committed_receipt(receipt,loaded.state_copy())
	check(not replay.ok and board.committed_effects.pending.is_empty(),"old terminal receipt cannot replay")
	await shot("03_downed_reloaded","真实文件读档后：倒下姿态与占格保留，伤害和中毒演出没有重播")
	finish()
func finish()->void:
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"lethal_staged_seen":lethal_staged_seen,"mock_only":true,"rng_override":false,"network_calls":0,"scope":"native rendered board, explicit assessed callbacks; not a mouse interaction test"}
	FileAccess.open(OUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ENEMY_TERMINAL_PRESENTATION ",checks," ",failures);quit(0 if failures.is_empty() else 1)
