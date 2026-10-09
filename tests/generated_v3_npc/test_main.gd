extends SceneTree
const Main=preload("res://main.tscn")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const OldVillage=preload("res://view/generated_v3_village/adapter.gd")
const NPCAdapter=preload("res://view/generated_v3_npc/adapter.gd")
const Placement=preload("res://view/generated_v3_npc/placement.gd")
const OUT="res://artifacts/generated_v3_npc_ui/"
var app
var checks=0
var failures=[]
var shots=[]
var memory_checkpoints=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);printerr("NPC_UI_FAIL ",label)
	return ok
func frames(n=4):
	for i in range(n):await process_frame
func capture(name_:String):
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image();var path=OUT+name_+".png"
	check(img.save_png(path)==OK,"PNG "+name_)
	var decoded=Image.load_from_file(path)
	check(decoded.get_size()==root.size and app.viewport.size==root.size,"actual root/world/PNG "+name_)
	shots.append({"name":name_,"width":decoded.get_width(),"height":decoded.get_height(),"world":[app.viewport.size.x,app.viewport.size.y]})
func sample(kind:String)->bool:
	var turn:int=app.playtest.state_copy().turn
	app.fill_generated_sample(kind);app.end_turn()
	if not check(app.playtest.phase()=="awaiting_assessment",kind+" waits assessment"):return false
	app.playtest_fixture()
	return check(app.playtest.phase()=="idle" and app.playtest.state_copy().turn==turn+1,kind+" commits once")
func motion():
	var begun=Time.get_ticks_msec()
	while app.board.presentation.actors.actor_player.moving and Time.get_ticks_msec()-begun<15000:await process_frame
	check(not app.board.presentation.actors.actor_player.moving,"motion complete")
func walk(target:Array)->bool:
	for _i in range(40):
		var state:Dictionary=app.playtest.state_copy();var current=Planner.key(state.actors.actor_player.hex)
		if current==Planner.key(target):return true
		var distances:Dictionary=Planner.distances(app.playtest.source.navigation.allowed,Planner.key(target))
		var next=""
		for n in app.playtest.source.navigation.allowed[current]:
			if distances.has(n) and distances[n]<distances[current]:next=n;break
		if next.is_empty():return false
		var h:Array=Planner.hex_(next)
		if not app.playtest.movement_preview(h).ok:
			if not sample("rest"):return false
			continue
		app._apply_focus(app.playtest.tile_reference(h))
		if not sample("move"):return false
		await motion()
	return false
func close_camera(h:Array):
	app.board.view_focus=app.playtest.source.navigation.cell_center(h)
	app.board.camera_distance=7.5;app.board.overview_mode=false;app.board.orbit_camera(0,0)
func npc_hit()->Dictionary:
	var token:Node3D=app.board.token_nodes[app.playtest.source.npc_id]
	var center:Vector3=token.global_position+Vector3(0,.16,0)
	for offset in [Vector3.ZERO,Vector3(0,-.05,0),Vector3(0,.06,0)]:
		var screen:Vector2=app.board.camera.unproject_position(center+offset)
		for hit in app.board.pick_focus(screen):
			if hit.reference.get("id")==app.playtest.source.npc_id:return {"hit":hit,"screen":screen}
	return {}
static func system_text(path:String) -> String:
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return ""
	var result=""
	for _i in range(1024):
		if file.eof_reached():break
		result+=file.get_line()+"\n"
	file.close();return result
func memory_checkpoint(label:String):
	var rss=0;var high=0
	for line in system_text("/proc/self/status").split("\n"):
		if line.begins_with("VmRSS:"):rss=int(line.trim_prefix("VmRSS:").strip_edges().split(" ",false)[0])*1024
		if line.begins_with("VmHWM:"):high=int(line.trim_prefix("VmHWM:").strip_edges().split(" ",false)[0])*1024
	var stats={}
	for line in system_text("/sys/fs/cgroup/memory.stat").split("\n"):
		var fields=line.split(" ",false)
		if fields.size()==2 and fields[0] in ["file","anon","kernel","shmem"]:stats[fields[0]]=int(fields[1])
	var bundles=[]
	for adapter in [app.generated_v3_adventure,app.generated_v3_inventory_adventure,app.generated_v3_village_adventure,app.generated_v3_npc_adventure]:
		if adapter!=null and adapter.ready().ok:bundles.append({"profile":adapter.source.identity.profile,"renderer_resident":not adapter.source.renderer_bundle.is_empty(),"turn":adapter.state_copy().turn})
	var row={"label":label,"utc_epoch":Time.get_unix_time_from_system(),"monotonic_us":Time.get_ticks_usec(),"owned_pid":OS.get_process_id(),"rss_bytes":rss,"peak_rss_bytes":high,"cgroup_current":int(system_text("/sys/fs/cgroup/memory.current")),"cgroup_stat":stats,"nodes":get_node_count(),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"bundles":bundles}
	check(rss>0 and row.cgroup_current>0 and stats.has("file") and stats.has("anon"),"real nonzero native memory sample "+label)
	memory_checkpoints.append(row)
	FileAccess.open(OUT+"memory_progress.json",FileAccess.WRITE).store_string(JSON.stringify({"completed":false,"checkpoints":memory_checkpoints},"\t"))
	print("NPC_MEMORY ",JSON.stringify(row))
func run():
	DirAccess.make_dir_recursive_absolute(OUT);root.size=Vector2i(1280,720)
	app=Main.instantiate();app.startup_legacy=true;root.add_child(app);await frames();memory_checkpoint("legacy_start")
	check(app.v3_adventure_style.get_item_text(0)=="探索" and app.v3_adventure_style.get_item_text(1)=="村庄冒险","simple primary choices")
	check(app.advanced_menu.get_item_index(17)>=0 and app.advanced_menu.get_item_index(18)>=0 and app.advanced_menu.get_item_index(19)>=0,"old progress discoverable in advanced")
	app.v3_village_choice.button_pressed=true;await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_village_mode and not app.generated_v3_npc_mode,"old village still explicit"):finish();return
	memory_checkpoint("old_village")
	var old:RefCounted=app.playtest;var old_bytes=C.bytes(old.save_data());app.set_player_intent("旧村落草稿",false)
	app.v3_adventure_style.select(1);app.v3_vegetation_choice.button_pressed=false
	app.show_v3_setup();await capture("setup");app.v3_setup_dialog.hide()
	await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_npc_mode and app.playtest.ready().ok and app.board.load_error.is_empty(),"NPC scene enters Main "+app.board.load_error):finish();return
	memory_checkpoint("npc_start")
	check(app.playtest.save_data().schema_version==NPCAdapter.NPC_SAVE_SCHEMA and app.generated_v3_village_adventure==old,"separate new profile preserves old slot")
	var source:RefCounted=app.playtest.source;var id:String=source.npc_id;var hex:Array=app.playtest.state_copy().actors[id].hex
	check(app.board.token_nodes.size()==2,"two real visible actor nodes")
	check(app.board.token_nodes[id].scale==Vector3.ONE*Placement.SCALE,"fixed native pawn scale")
	check(app.board.token_nodes[id].position.is_equal_approx(Placement.position(source.npc_placement_result.placement_witness)),"NPC fixed source-bound pose")
	close_camera(hex);app.set_map_dialogue_hidden(true);await capture("roadside_npc")
	var hit=npc_hit();check(not hit.is_empty(),"raw visible NPC hit")
	if not hit.is_empty():
		var before=C.bytes(app.playtest.save_data());app.on_focus_candidates([hit.hit],hit.screen)
		check(app.selected_focus.get("catalog_version")=="source-npc-focus/v1" and C.bytes(app.playtest.save_data())==before,"world click typed and read-only")
		app.show_focus_details();await capture("npc_details");app.focus_details_dialog.hide();app.clear_target()
	if not check(await walk(hex),"assessed route reaches NPC"):finish();return
	close_camera(hex);app._apply_focus(app.playtest.npc_reference());app.show_focus_details();await capture("npc_nearby_details");app.focus_details_dialog.hide()
	var state_before=C.bytes(app.playtest.state_copy());app.fill_generated_sample("talk");app.end_turn()
	var frozen=C.bytes(app.playtest.action_copy().focus);var pending_request=C.bytes(app.playtest.request())
	app._apply_focus(app.playtest.item_reference())
	check(C.bytes(app.playtest.action_copy().focus)==frozen and C.bytes(app.playtest.request())==pending_request,"pending NPC target frozen across item click")
	app.save_game();var saved=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==saved,"pending NPC save/load exact")
	app.playtest_fixture();await frames()
	check(app.playtest.phase()=="idle" and app.playtest.state_copy().npc_state.contacts[id].conversation_count==1,"first UI conversation commits")
	check(not app.playtest.state_copy().npc_state.learned_facts.actor_player.is_empty(),"learned information persists")
	var notes_before:String=C.bytes(app.playtest.save_data());app.show_npc_notes();await capture("travel_notes");app.npc_notes_dialog.hide()
	check(C.bytes(app.playtest.save_data())==notes_before and app.playtest.learned_notes().contains("首次获知"),"travel notes readable and read-only")
	app._apply_focus(app.playtest.npc_reference());check(app.selected_focus.contact_revision==1,"current selected NPC revision refreshed")
	# Co-located player may obscure this tiny roadside pawn from one view; rotate
	# to an honest view instead of picking through the player or moving the NPC.
	app.board.orbit_camera(1.2,0);await frames()
	hit=npc_hit();check(not hit.is_empty(),"visible NPC can be clicked after talk")
	if not hit.is_empty():app.on_focus_candidates([hit.hit],hit.screen);check(app.selected_focus.contact_revision==1,"repeat world click uses latest contact header")
	var first_facts=C.bytes(app.playtest.state_copy().npc_state.learned_facts)
	if app.playtest.state_copy().actors.actor_player.stamina.current<1:sample("rest")
	check(sample("talk"),"second UI conversation")
	check(C.bytes(app.playtest.state_copy().npc_state.learned_facts)==first_facts and app.playtest.state_copy().npc_state.contacts[id].conversation_count==2,"repeat preserves first information proof")
	app.show_focus_details();await capture("npc_after_repeat");app.focus_details_dialog.hide()
	app.set_player_intent("你还知道什么别的事？",false);app.end_turn()
	check(app.playtest.phase()=="awaiting_assessment" and not app.playtest.fixture_available(),"free conversation waits, never pretends live AI")
	app.cancel_pending();app.save_game();saved=C.bytes(app.playtest.save_data());app.load_game()
	check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==saved,"committed NPC history reload")
	memory_checkpoint("npc_after_talk_reload")
	app.playtest.save_file(OUT+"committed.json")
	app.set_player_intent("村庄新草稿",false);app.continue_v3_village_adventure();await frames()
	memory_checkpoint("return_old_village")
	check(not app.generated_v3_npc_mode and app.playtest==old and C.bytes(old.save_data())==old_bytes and app.goal.text=="旧村落草稿","old village session and draft exact")
	var parked:RefCounted=app.generated_v3_npc_adventure
	check(parked.source.renderer_bundle.is_empty() and C.bytes(parked.save_data())==saved,"inactive NPC renderer released with authority intact")
	parked.source.renderer_bundle.merge({"ok":true,"geometry_hash":"corrupt"},true)
	var old_board=app.board
	app.continue_v3_npc_adventure();await frames()
	check(app.board==old_board and app.playtest==old and C.bytes(old.save_data())==old_bytes,"corrupt parked renderer keeps current board/session")
	parked.source.renderer_bundle.clear()
	app.continue_v3_npc_adventure();await frames()
	check(app.generated_v3_npc_mode and C.bytes(app.playtest.save_data())==saved and app.goal.text=="村庄新草稿","new village session and draft exact")
	parked=null
	app.reset_playtest();await frames()
	check(app.playtest.state_copy().turn==0 and app.playtest.state_copy().npc_state.contacts[id].conversation_count==0 and app.board.load_error.is_empty(),"restart same profile and pose without learned facts")
	check(C.bytes(old.save_data())==old_bytes,"restart never alters old village")
	source=null
	memory_checkpoint("npc_restart")
	# Real enabled-forest branch, separate from the older saved profile.
	app.v3_radius_choice.select(1);app.v3_vegetation_choice.button_pressed=true
	await app.start_v3_from_dialog();await frames()
	if not check(app.generated_v3_npc_mode and app.playtest.source.features.vegetation and app.board.load_error.is_empty(),"enabled forest enters actual Main "+app.board.load_error):finish();return
	memory_checkpoint("forest_start")
	check(is_instance_valid(app.board.vegetation_view) and not app.board.vegetation_references.is_empty(),"instanced plants have exact selection headers")
	var forest_source:RefCounted=app.playtest.source
	var distances:Dictionary=Planner.distances(forest_source.navigation.allowed,Planner.key(app.playtest.state_copy().actors.actor_player.hex))
	var target:Array=[];var best:int=10000
	for plant in forest_source.vegetation_result.manifest.plants:
		var key:String=Planner.key(plant.hex)
		if plant.asset_id in ["temperate","tropical","sapling"] and distances.has(key) and int(distances[key])<best:target=plant.hex.duplicate();best=int(distances[key])
	check(not target.is_empty(),"reachable forest cell exists")
	if not target.is_empty():
		check(await walk(target),"legitimate travel to forest")
		close_camera(target);app.set_map_dialogue_hidden(true);await capture("forest_arrival")
		app._apply_focus(app.playtest.item_reference())
		if app.playtest.state_copy().actors.actor_player.stamina.current<1:sample("rest")
		check(sample("drop_item"),"real forest drop")
		var pose:Dictionary=app.board.inventory_pack.ground_pose
		memory_checkpoint("forest_drop")
		check(pose.get("footprint_verified",false) and not app.board.inventory_pack.overlaps_static_prop(pose),"ground bag clear of actual plant visual bounds and fixed NPC")
		var nexts:Array=forest_source.navigation.allowed[Planner.key(target)]
		if not nexts.is_empty():check(await walk(Planner.hex_(nexts[0])),"walk away from forest bag")
		close_camera(target);await capture("forest_ground_pack")
		check(C.bytes(app.playtest.state_copy().items.item_travel_bundle.hex)==C.bytes(target),"forest movement leaves ground custody exact")
		var forest_hit:Dictionary={}
		for plant in forest_source.vegetation_result.manifest.plants:
			var p:Array=plant.position;var point_:Vector3=Vector3(p[0],p[1]+plant.height*.55,p[2]);var screen_:Vector2=app.board.camera.unproject_position(point_)
			if screen_.x<0 or screen_.y<0 or screen_.x>=app.viewport.size.x or screen_.y>=app.viewport.size.y:continue
			for candidate_ in app.board.pick_focus(screen_):
				if candidate_.reference.get("kind")=="vegetation":forest_hit={"hit":candidate_,"screen":screen_};break
			if not forest_hit.is_empty():break
		check(not forest_hit.is_empty(),"real visible raw plant pick")
		if not forest_hit.is_empty():
			var pure:String=C.bytes(app.playtest.save_data());var begun:int=Time.get_ticks_usec();app.on_focus_candidates([forest_hit.hit],forest_hit.screen)
			print("NPC_PLANT_COMPLETE_SELECT_US ",Time.get_ticks_usec()-begun)
			check(app.selected_focus.catalog_version=="source-vegetation-focus/v1" and C.bytes(app.playtest.save_data())==pure,"plant click is typed and read-only")
			app.show_focus_details();await capture("plant_details");app.focus_details_dialog.hide()
		app.save_game();var forest_saved:String=C.bytes(app.playtest.save_data());app.load_game()
		check(app.last_load_result.ok and C.bytes(app.playtest.save_data())==forest_saved and app.board.load_error.is_empty(),"forest ground pack and source-bound catalog reload exact")
		app.playtest.save_file(OUT+"forest_committed.json")
		forest_source=null
		memory_checkpoint("forest_reloaded")
		app.continue_v3_village_adventure();await frames()
		check(app.playtest==old and C.bytes(old.save_data())==old_bytes and app.goal.text=="旧村落草稿","continuous forest-to-old session recovery")
		memory_checkpoint("forest_return_old")
		app.continue_v3_npc_adventure();await frames()
		check(app.generated_v3_npc_mode and C.bytes(app.playtest.save_data())==forest_saved and app.board.load_error.is_empty(),"parked forest renderer rebuild preserves authority")
		memory_checkpoint("forest_resumed")
	finish()
func finish():
	FileAccess.open(OUT+"memory_progress.json",FileAccess.WRITE).store_string(JSON.stringify({"completed":true,"checkpoints":memory_checkpoints},"\t"))
	FileAccess.open(OUT+"main_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots,"memory_checkpoints":memory_checkpoints,"ok":failures.is_empty()},"\t"))
	print("NPC_MAIN ",checks," ",failures);quit(0 if failures.is_empty() else 1)
