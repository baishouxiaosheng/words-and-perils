extends "res://tests/ui_readability/capture_game_ui.gd"
## Actual-game C skin capture and history checks. Isolated candidate, no network.
func capture(label_: String) -> void:
	out="res://artifacts/fieldbook_c/native_final"
	record(scene.coast_mode and scene.board.tiles.size()==1801 and scene.board.load_error.is_empty(),"C capture is actual complete1801-cell coast")
	report["actual_coast_cells"]=scene.board.tiles.size()
	report["actual_coast_mode"]=scene.coast_mode
	report["source_bundle_id"]=preload("res://view/playable_build/world_bundle.gd").bundle_id()
	DirAccess.make_dir_recursive_absolute(out)
	if label_=="ui_long_history":
		for entry in range(8):scene.append_journal("沿岸记录 %d"%(entry+1),"海风掠过石阶，潮水在岸边留下清晰的盐痕。旅人停下脚步，回看此前的记录，再决定下一步如何行动。")
		await settle()
		var before:String=scene.journal.get_parsed_text();var bar:VScrollBar=scene.journal.get_v_scroll_bar()
		record(scene.journal.selection_enabled,"C history remains selectable")
		record(bar.max_value>bar.page,"C history exposes a real long-text scrollbar")
		bar.value=0;await settle();var top:float=bar.value
		bar.value=maxf(0,bar.max_value-bar.page);await settle()
		record(bar.value>top,"C history reaches later paragraphs")
		scene.toggle_journal();await settle();record(not scene.journal_panel.visible,"C history closes")
		scene.toggle_journal();await settle();record(scene.journal.get_parsed_text()==before,"C history reopen keeps exact prose")
		bar.value=0;await settle()
		record(not scene.journal.text.contains("[bgcolor"),"C history has no per-line highlight backgrounds")
	await super.capture(label_)
