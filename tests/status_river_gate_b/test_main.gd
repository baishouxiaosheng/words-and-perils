extends "res://tests/status_river_gate_b/harness.gd"
## FULL-resource actual Main gate. Serial native admission only; no tiny renderer.
const MainScene = preload("res://main.tscn")
const HostCustody = preload("res://view/generated_v3_river_entry/host_custody.gd")
var app: Control
var evidence_viewport: SubViewport
var emitted_events: Array = []
var historical_focus_witnesses: Array = []
const HISTORY_SAVE = "user://gate_b_history.json"

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 4) -> void:
	for _i in range(count):
		await process_frame

func run() -> void:
	case_name = argument("--case")
	if not storage_safe() or not check("--status-gameplay" in OS.get_cmdline_user_args(), "actual Main new-world opt-in flag is explicit"):
		finish()
		return
	if not check(case_name in ["main_poison","main_poison_reopen","main_flight","main_flight_reopen","main_antidote"], "recognized explicit Main case"):
		finish()
		return
	var adapter: RefCounted = F.adapter()
	if not verify_adapter(adapter):
		finish()
		return
	if case_name == "main_antidote":
		if not check(F.authored_poison_setup(adapter).ok, "labelled isolated antidote fixture seeds pre-existing poison only before any gameplay"):
			finish()
			return
		report["fixture_provenance"] = "Full pinned source world plus explicitly authored initial poison, not an original source-world fact. Real antidote still requires normal trusted-source assessment and commit."
	# Inject the exact actual Coast adapter before Main._ready; this is a test
	# constructor seam, not a replacement renderer or a direct gameplay state edit.
	# Main then builds its ordinary source Coast scene around this same adapter.
	app = MainScene.instantiate()
	app.coast_adventure = adapter
	if "--visual-1080" in OS.get_cmdline_user_args():
		# Render the unchanged actual Main and guest tree at native1920x1080;
		# independent of the physical desktop size, never resize an old image.
		evidence_viewport=SubViewport.new();evidence_viewport.size=Vector2i(1920,1080);evidence_viewport.gui_embed_subwindows=true;evidence_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(evidence_viewport);evidence_viewport.add_child(app)
		report["render_evidence"]={"width":1920,"height":1080,"actual_main_in_offscreen_viewport":true,"image_upscaled":false,"physical_OS_input_claimed":false}
	else:root.add_child(app)
	await frames(6)
	if not verify_main(adapter):
		await close_app()
		finish()
		return
	app.board.committed_feedback.event_started.connect(func(event: Dictionary): emitted_events.append(event.duplicate(true)))
	if case_name.ends_with("_reopen"):
		await reopen()
	elif case_name == "main_antidote":
		await antidote()
	else:
		await apply_and_visit("poison" if case_name == "main_poison" else "flight")
	report["observed_started_effects"] = emitted_events
	report["fx_report"] = app.board.committed_feedback.report()
	report["method_driven_ui"] = true
	report["pointer_clicks_verified"] = false
	report["screenshots_verified"] = false
	report["visual_appearance_verified"] = false
	await close_app()
	finish()

func close_app() -> void:
	if is_instance_valid(app):
		app.queue_free()
		await frames()

func verify_main(adapter: RefCounted) -> bool:
	var ok := check(app.coast_mode and app.playtest_mode and app.playtest == adapter and app.playtest.status_gameplay_mode, "actual Main uses the same new-mode Coast authority")
	ok = check(F.world_check(app.playtest.state_copy()).ok, "actual Main has pinned1801 world, not startup fallback") and ok
	ok = check(is_instance_valid(app.board) and app.board.get_script().resource_path == "res://view/playable_build/board.gd" and app.board.tiles.size() == 1801 and app.board.load_error.is_empty(), "actual full Coast renderer and all1801 source tiles loaded") and ok
	ok = check(not app.runtime_ai.connection_enabled and not app.runtime_ai.automatic_assessment_enabled() and not app.runtime_ai.client.configured() and not app.runtime_ai.busy(), "actual Main transport stays unconfigured and offline; no key or model call") and ok
	ok = check(is_instance_valid(app.board.committed_feedback), "actual committed effect router compiled and attached") and ok
	report["actual_main_identity"] = F.identity(app.playtest.state_copy())
	return ok

func begin_main(resolver: String, bindings: Dictionary, components: Array) -> Dictionary:
	app.end_turn_requested = false # Advanced phase controls, no automatic completion.
	app.set_player_intent("【Gate B 离线作者测试】" + resolver + " " + C.bytes(bindings))
	app.submit_playtest()
	if not check(app.playtest.phase() == "awaiting_assessment", "actual Main begins an ordinary assessment request"):
		return {}
	var reply := F.assessment(app.playtest.request(),resolver,bindings,components)
	if not check(not reply.is_empty(), "offline reply cites actual frozen source/target facts"):
		return {}
	if resolver == F.Action.ID:
		var budget: Dictionary = F.inspect_request_budget(app.playtest,reply)
		if not check(budget.ok, "actual source-action public<=65536 and complete Codec wrapper<=4MiB, or explicit unsent CONTEXT_BUDGET: " + C.bytes(budget)):
			return {}
	if not check(app.apply_playtest_reply(reply) and app.playtest.phase() == "ready_roll", "actual Main imports labelled offline assessment without executing it"):
		return {}
	return reply

func commit_main() -> Dictionary:
	var before: Dictionary = app.playtest.state_copy()
	var frozen_focus: Dictionary = app.playtest.action_copy().get("focus",{})
	var frozen_status: Dictionary = frozen_focus.get("facts",{}).get("status_details",{}) if frozen_focus.get("kind") == "actor" else {}
	var receipts_before: int = app.board.committed_feedback.accepted_receipts
	app.advance_playtest()
	if not check(app.playtest.phase() == "rolled", "actual Main rolls once"):
		return {}
	app.advance_playtest()
	if not check(app.playtest.phase() == "staged" and C.bytes(app.playtest.state_copy()) == C.bytes(before), "actual Main stage remains a non-authoritative preview"):
		return {}
	if not frozen_status.is_empty():
		check(C.bytes(app.playtest.request().get("context",{}).get("attention_focus",{}).get("facts",{}).get("status_details")) == C.bytes(frozen_status), "staged narration retains actor-focus status_details from the original frozen intention")
	app.advance_playtest()
	if not check(app.playtest.phase() == "idle", "actual Main commits the frozen stage"):
		return {}
	var saved: Dictionary = app.playtest.engine.save_data()
	var receipt: Dictionary = saved.receipts.get(app.playtest.last_action,{})
	if not check(not receipt.is_empty(), "actual Main committed receipt exists"):
		return {}
	if not frozen_status.is_empty():
		check(C.bytes(receipt.get("attention_focus",{}).get("facts",{}).get("status_details")) == C.bytes(frozen_status), "committed historical actor focus retains exact original status_details")
		historical_focus_witnesses.append({"action_id":receipt.action_id,"status_details":frozen_status.duplicate(true)})
		check_history_packets()
	check(app.board.committed_feedback.accepted_receipts == receipts_before+1, "Main sends fresh committed receipt to actual router exactly once")
	var exact := C.digest(saved)
	var duplicate: Dictionary = app.playtest.engine.commit(receipt.action_id,receipt.stage_hash)
	check(duplicate.get("already_committed",false) and C.digest(app.playtest.engine.save_data()) == exact, "duplicate gameplay receipt leaves whole save unchanged")
	var router_before: Dictionary = app.board.committed_feedback.report()
	var duplicate_fx: Dictionary = app.board.present_committed_receipt(receipt,before)
	var router_after: Dictionary = app.board.committed_feedback.report()
	check(not duplicate_fx.get("ok",false) and router_after.accepted_receipts == router_before.accepted_receipts and router_after.ignored_receipts == router_before.ignored_receipts+1 and router_after.emitted_effects == router_before.emitted_effects and router_after.pending_effects == router_before.pending_effects, "actual router rejects repeated receipt without duplicating queued or emitted effects")
	report["last_committed_receipt"] = receipt
	return receipt

func check_details(expected_status: String, remaining: int = -1) -> bool:
	var state: Dictionary = app.playtest.state_copy()
	var prior := C.digest(app.playtest.engine.save_data())
	app._apply_focus(F.player_reference(state))
	app.show_focus_details()
	var actual: Dictionary = F.Details.public_details(state,state.actors.actor_player)
	var expected_lines: Array = F.Details.status_lines({"status_details":actual})
	var labels: Array = []
	for child in app.inventory_box.get_children():
		if child is Label and not child.is_queued_for_deletion():
			labels.append(child.text)
	var ok := check(actual.available and is_instance_valid(app.hero_subtitle) and is_instance_valid(app.focus_details_text), "real status Label and focus RichTextLabel exist")
	if expected_status.is_empty():
		ok = check(expected_lines.is_empty() and "没有持续状态" in labels and app.focus_details_text.text.contains("没有持续状态"), "actual inventory and target details remove ended status") and ok
	else:
		ok = check(not expected_lines.is_empty() and F.status(state,expected_status).get("remaining") == remaining, "committed status duration matches requested UI check") and ok
		for line in expected_lines:
			ok = check(line in labels and app.hero_subtitle.tooltip_text.contains(line), "actual inventory Label and HUD tooltip show exact public status line") and ok
		for line in F.Details.focus_status_lines({"status_details":actual}):
			ok = check(app.focus_details_text.text.contains(line),"focused details show all short read-only status paragraphs") and ok
		check(app.focus_details_text.get_theme_stylebox("normal").get_content_margin(SIDE_LEFT)>=16 and app.focus_details_text.get_theme_stylebox("normal").get_content_margin(SIDE_TOP)>=16,"actual focused body keeps16px paper inset")
		ok = check(C.bytes(app.resolved_focus.get("facts",{}).get("status_details")) == C.bytes(actual), "ModelView focus supplies committed status_details to real Main") and ok
	check(C.digest(app.playtest.engine.save_data()) == prior, "opening actual status details is read-only")
	report["latest_details_ui"] = {"public":actual, "inventory_labels":labels, "hero_subtitle":app.hero_subtitle.text, "hero_tooltip":app.hero_subtitle.tooltip_text, "focus_details":app.focus_details_text.text}
	app.focus_details_dialog.hide() # Visible modal intentionally blocks river entry.
	return ok

func pending_entry_rejected() -> bool:
	app.set_player_intent("【Gate B 离线作者测试】只建立待评估休息请求")
	app.submit_playtest()
	if not check(app.playtest.phase() == "awaiting_assessment", "status-bearing host owns real pending intention"):
		return false
	var exact := C.digest(app.playtest.engine.save_data())
	var action_id: String = app.playtest.active_action
	var before_mode: int = app.process_mode
	app.open_river_experiment()
	var closed: bool = app.river_entry_controller == null or not app.river_entry_controller.session.is_open()
	var ok := check(closed and app.process_mode == before_mode and app.playtest.active_action == action_id and app.playtest.phase() == "awaiting_assessment" and C.digest(app.playtest.engine.save_data()) == exact and app.playtest.status_gameplay_mode, "pending new-status host entry refuses without cancelling, replacing, or altering authority")
	var before: Dictionary = app.playtest.engine.save_data()
	app.cancel_pending()
	var after: Dictionary = app.playtest.engine.save_data()
	ok = check(app.playtest.phase() == "idle" and C.bytes(before.state) == C.bytes(after.state) and C.bytes(before.rng) == C.bytes(after.rng), "explicit Main cancellation preserves committed poison/flight and RNG") and ok
	return ok

func ui_status_snapshot() -> Dictionary:
	var state: Dictionary = app.playtest.state_copy()
	var labels: Array = []
	for child in app.inventory_box.get_children():
		if child is Label and not child.is_queued_for_deletion(): labels.append(child.text)
	return {"main_identity":app._river_entry_ui_snapshot(), "status_details":F.Details.public_details(state,state.actors.actor_player), "resolved_focus":app.resolved_focus.duplicate(true), "hero_subtitle":app.hero_subtitle.text, "hero_tooltip":app.hero_subtitle.tooltip_text, "inventory_labels":labels, "focus_details":app.focus_details_text.text, "route_label":app.route_preview_label.text}

func capture_visual(name_:String) -> void:
	if not "--visual-evidence" in OS.get_cmdline_user_args():return
	await RenderingServer.frame_post_draw
	var pixels:Image=evidence_viewport.get_texture().get_image() if evidence_viewport!=null else root.get_texture().get_image()
	if evidence_viewport!=null:check(pixels.get_size()==Vector2i(1920,1080),"actual native1080 viewport pixels, not post-capture resizing")
	check(pixels!=null and not pixels.is_empty() and pixels.save_png("res://artifacts/status_river_gate/"+case_name+"_"+name_+".png")==OK,"actual rendered screenshot saved: "+name_)

func river_roundtrip(status_id: String) -> bool:
	var host: RefCounted = app.playtest
	var captured: Dictionary = HostCustody.capture(host)
	if not check(captured.ok and captured.kind == "coast_engine_and_narration/v1", "new-status host supports full raw-engine/narration custody"):
		return false
	var custody_hash := C.digest(captured.snapshot)
	var wrapper_hash := C.digest(F.Save.make_envelope(host.engine))
	var ui_hash := C.digest(ui_status_snapshot())
	var board_id: int = app.board.get_instance_id()
	var host_id: int = host.get_instance_id()
	var old_mode: int = app.process_mode
	var old_draw: int = app.viewport.render_target_update_mode
	var old_input: bool = app.viewport.gui_disable_input
	if not check(not F.status(host.state_copy(),status_id).is_empty(), "river host actually carries committed " + status_id):
		return false
	app.on_tool_selected(app.RIVER_EXPERIMENT_MENU_ID)
	await frames(8)
	var entry: Node = app.river_entry_controller
	if not check(entry != null and entry.session.is_open() and entry.view != null, "actual Main menu opens river guest over new-status full1801 host"):
		return false
	await capture_visual("river_idle")
	var guest_turn: int = entry.session.river.state_copy().turn
	var ok := check(app.playtest.get_instance_id() == host_id and app.board.get_instance_id() == board_id and app.board.tiles.size() == 1801 and host.status_gameplay_mode, "same full1801 host adapter/board/new-mode flag remain resident during river visit")
	ok = check(C.digest(HostCustody.capture(host).snapshot) == custody_hash and C.digest(F.Save.make_envelope(host.engine)) == wrapper_hash and C.digest(ui_status_snapshot()) == ui_hash, "raw custody, explicit wrapper, and actual status UI remain exact while parked") and ok
	ok = check(app.process_mode == Node.PROCESS_MODE_DISABLED and app.viewport.gui_disable_input and app.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "status host input/processing/draw parked") and ok
	check(entry.session.river.state_copy().turn == guest_turn, "opening the guest itself does not fabricate an action")
	check(not entry.view.diagnostics_box.visible and entry.view.theme==app.theme,"offline diagnostic UI starts collapsed with the actual C theme")
	entry.view._select_neighbor();entry.view._choose_example("move");entry.view._assess()
	if not check(entry.session.river.phase()=="ready_roll","guest movement uses its real offline assessed pipeline"):
		return false
	for text_node in entry.view.find_children("*","Label",true,false):
		if text_node.is_visible_in_tree():check(not text_node.text.contains("PHYSICAL RIVERS") and not text_node.text.contains("【探索") and not text_node.text.contains("A=3"),"visible river labels omit protocol/technical diagnostics")
	await capture_visual("river_assessed")
	entry.view._apply();await frames(4)
	ok=check(entry.session.river.state_copy().turn==guest_turn+1 and C.digest(HostCustody.capture(host).snapshot)==custody_hash and C.digest(F.Save.make_envelope(host.engine))==wrapper_hash,"guest committed turn does not tick or mutate the poisoned/flying host") and ok
	if "--visual-evidence" in OS.get_cmdline_user_args():await inspect_diagnostic_scroll(entry)
	if not check(entry.close().ok, "explicit return after one independent guest action succeeds"):
		return false
	await frames(6)
	ok = check(entry.metrics.get("guest_adapter_released",false) and entry.metrics.get("guest_view_released",false), "actual guest adapter and view weak references release") and ok
	ok = check(app.playtest == host and app.playtest.get_instance_id() == host_id and app.board.get_instance_id() == board_id and host.status_gameplay_mode, "return retains same host identity and explicit status mode") and ok
	ok = check(C.digest(HostCustody.capture(host).snapshot) == custody_hash and C.digest(F.Save.make_envelope(host.engine)) == wrapper_hash and C.digest(ui_status_snapshot()) == ui_hash, "return leaves whole committed status authority/custody/UI exact") and ok
	ok = check(app.process_mode == old_mode and app.viewport.render_target_update_mode == old_draw and app.viewport.gui_disable_input == old_input, "return restores exact presentation modes") and ok
	app.show_focus_details();await capture_visual("host_status_details")
	if "--visual-evidence" in OS.get_cmdline_user_args():
		app.focus_details_text.scroll_to_line(maxi(0,app.focus_details_text.get_line_count()-1));await frames(4)
		check(app.focus_details_text.get_v_scroll_bar().value>0,"actual detail text scroll reaches calculation parameters below first screen")
		await capture_visual("host_status_calculation_scrolled")
	app.focus_details_dialog.hide()
	report["combined_river_return"] = {"status":status_id, "metrics":entry.metrics.duplicate(true), "host_instance":host_id, "board_instance":board_id, "raw_custody_hash":custody_hash, "wrapper_hash":wrapper_hash, "ui_status_hash":ui_hash, "guest_actions":1}
	return ok

func route_preview() -> Dictionary:
	var exact := C.digest(app.playtest.engine.save_data())
	var chosen: Dictionary = F.first_neighbor_route(app.playtest)
	if not check(chosen.ok, "bounded source-adjacent flight route exists"):
		return {}
	app._apply_focus(F.tile_reference(app.playtest.state_copy(),chosen.target))
	app.update_movement_preview()
	check(app.movement_preview.get("ok",false) and C.bytes(app.movement_preview.get("route")) == C.bytes(chosen.preview.route) and app.route_preview_label.visible and app.route_preview_label.text.begins_with("飞行参考"), "actual Main route Label and route geometry use trusted flight preview")
	check(is_instance_valid(app.board.route_preview) and app.board.route_preview.get_child_count() > 0, "real renderer receives route geometry")
	check(C.digest(app.playtest.engine.save_data()) == exact, "actual route preview is read-only")
	report["source_route"] = chosen
	return chosen

func apply_and_visit(status_id: String) -> void:
	if not check(not FileAccess.file_exists(F.Save.PATH), "fresh isolated actual Main save destination"):
		return
	var source := "item_poison_vial" if status_id == "poison" else "item_feather_vial"
	var initial: Dictionary = app.playtest.state_copy()
	if begin_main(F.Action.ID,F.source_bindings(source),["delivery","effect"]).is_empty(): return
	if not fixed_checks(app.playtest): return
	var receipt := commit_main()
	if receipt.is_empty(): return
	if not check(receipt.outcomes.delivery and receipt.outcomes.effect, "independent seed1 first trusted source succeeds; no retry or reselection"): return
	check(app.playtest.state_copy().actors.actor_player.health == initial.actors.actor_player.health, "new status application has no same-action poison tick")
	await frames()
	if not check_details(status_id,3): return
	if not pending_entry_rejected(): return
	await frames()
	if not check_details(status_id,3): return
	if status_id == "flight" and route_preview().is_empty(): return
	# Freeze focus/details after all intentional UI navigation, before custody.
	var returned: bool = await river_roundtrip(status_id)
	if not returned: return
	app.save_game()
	if not check(app.last_save_result.get("ok",false) and app.playtest.default_save_path() == F.Save.PATH, "actual Main saves the explicit new wrapper via its normal menu method"): return
	if not witness(app.playtest,F.Save.PATH,{"status":status_id,"remaining":3,"main_writer":true}): return
	completed = true

func reopen() -> void:
	var expected := "poison" if case_name == "main_poison_reopen" else "flight"
	var original_hash := FileAccess.get_sha256(F.Save.PATH)
	app.load_game()
	if not check(app.last_load_result.get("ok",false), "new process actual Main load method accepts saved explicit wrapper"): return
	if not verify_reopen(app.playtest,F.Save.PATH): return
	if not verify_main(app.playtest): return
	await frames()
	if not check_details(expected,3): return
	check(app.board.committed_feedback.accepted_receipts == 0 and app.board.committed_feedback.pending.is_empty(), "loading committed history baselines FX instead of replaying receipts")
	if expected == "poison":
		var before_hp: int = app.playtest.state_copy().actors.actor_player.health.current
		var damage: int = 1 + int(float(app.playtest.state_copy().actors.actor_player.health.max)*0.10)
		if begin_main("coast_rest",{"actor_id":F.PLAYER},["rest"]).is_empty(): return
		if commit_main().is_empty(): return
		await frames()
		check(app.playtest.state_copy().actors.actor_player.health.current == before_hp-damage, "actual Main owner action settles fixed poison formula once")
		if not check_details("poison",2): return
	else:
		var chosen := route_preview()
		if chosen.is_empty(): return
		var before: Dictionary = app.playtest.state_copy()
		if begin_main(F.Weighted.ID,{"actor_id":F.PLAYER,"target_hex":chosen.target},["move"]).is_empty(): return
		check(app.playtest.action_copy().checks.size() == 1 and app.playtest.action_copy().checks[0].method == "direct_success", "registered weighted movement policy owns the safe-direct route result")
		check(app.playtest.frozen_movement_preview().get("ok",false), "actual Main retains frozen preview of assessed flight route")
		if commit_main().is_empty(): return
		await frames()
		var after: Dictionary = app.playtest.state_copy()
		check(after.actors.actor_player.hex == chosen.target and after.turn == before.turn+1 and after.actors.actor_player.stamina.current == before.actors.actor_player.stamina.current-chosen.preview.cost and F.status(after,"flight").get("remaining") == 2, "one full weighted route commits destination/cost and ages flight exactly once")
		if not check_details("flight",2): return
		# Land only on an existing supported source-world dry route endpoint.
		if begin_main(F.Action.ID,F.source_bindings("land"),["delivery","effect"]).is_empty(): return
		if not fixed_checks(app.playtest,true): return
		if commit_main().is_empty(): return
		await frames()
		if not check_details(""): return
	check(FileAccess.get_sha256(F.Save.PATH) == original_hash, "reopen verification does not overwrite retained writer artifact")
	if not save_history_witness(): return
	completed = true

func antidote() -> void:
	if not check_details("poison",3): return
	var before: Dictionary = app.playtest.state_copy()
	if begin_main(F.Action.ID,F.source_bindings("item_status_antidote"),["delivery","effect"]).is_empty(): return
	if not fixed_checks(app.playtest): return
	var receipt := commit_main()
	if receipt.is_empty(): return
	if not check(receipt.outcomes.delivery and receipt.outcomes.effect, "independent seed1 first antidote checks succeed; no retry"): return
	await frames()
	var after: Dictionary = app.playtest.state_copy()
	check(F.status(after,"poison").is_empty() and after.actors.actor_player.health == before.actors.actor_player.health and after.items.item_status_antidote.quantity == before.items.item_status_antidote.quantity-1 and after.actors.actor_player.stamina.current == before.actors.actor_player.stamina.current-1, "real antidote removes poison before owner tick and spends exact trusted costs without healing")
	check(receipt.hook_patches.any(func(patch): return patch.get("type") == "status_v2_event" and patch.get("definition_id") == "poison" and patch.get("change") == "removed"), "real antidote receipt carries typed removal evidence")
	if not check_details(""): return
	if not save_history_witness(): return
	completed = true

func check_history_packets() -> bool:
	var ok := true
	for item in historical_focus_witnesses:
		var narrated: Dictionary = app.playtest.engine.narration_request(item.action_id)
		var packet: Variant = narrated.get("context",{}).get("attention_focus",{}).get("facts",{}).get("status_details")
		ok = check(C.bytes(packet) == C.bytes(item.status_details), "historical narration never replaces frozen actor status_details with current changed/removed status") and ok
	return ok

func save_history_witness() -> bool:
	if not check(not historical_focus_witnesses.is_empty(), "changed/removed actual player status has a focused historical receipt to reload"):
		return false
	if not check_history_packets():
		return false
	var state: Dictionary = app.playtest.state_copy()
	var current: Dictionary = F.Details.public_details(state,state.actors.actor_player)
	check(historical_focus_witnesses.any(func(item): return C.bytes(item.status_details) != C.bytes(current)), "at least one frozen actor-focus status genuinely differs from current UI state")
	if not check(not FileAccess.file_exists(HISTORY_SAVE), "new separate history artifact preserves earlier writer save"):
		return false
	if not check(app.playtest.save_file(HISTORY_SAVE).ok, "actual Coast saves changed/removed status plus historical focus"):
		return false
	report["historical_focus_witnesses"] = historical_focus_witnesses
	return witness(app.playtest,HISTORY_SAVE,{"history":historical_focus_witnesses,"current_status_details":current,"main_writer":true})

func inspect_diagnostic_scroll(entry:Node) -> void:
	var view_:Control=entry.view
	var before:String=C.digest(entry.session.river.state_copy())
	var scroll:ScrollContainer=view_.diagnostics_toggle.get_parent().get_parent()
	scroll.ensure_control_visible(view_.save_button);await frames(4)
	check(scroll.get_global_rect().encloses(view_.save_button.get_global_rect()) and scroll.get_global_rect().encloses(view_.load_button.get_global_rect()),"actual scroll brings complete save/load buttons into viewport")
	scroll.ensure_control_visible(view_.diagnostics_toggle);await frames(4)
	check(scroll.get_global_rect().encloses(view_.diagnostics_toggle.get_global_rect()),"actual scroll brings complete diagnostics toggle into viewport")
	await capture_visual("river_controls_scrolled")
	view_.diagnostics_toggle.button_pressed=true;await frames(4)
	check(view_.diagnostics_box.visible,"existing toggle signal opens diagnostics without executing an action")
	scroll.ensure_control_visible(view_.identity_label);await frames(4)
	await capture_visual("river_diagnostics_open")
	view_.diagnostics_toggle.button_pressed=false;scroll.scroll_vertical=0;await frames(4)
	check(not view_.diagnostics_box.visible and C.digest(entry.session.river.state_copy())==before,"opening and closing scrolled diagnostics preserves whole guest world")
