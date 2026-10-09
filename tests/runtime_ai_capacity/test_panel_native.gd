extends "res://tests/runtime_ai_capacity/test_native_journey.gd"
## Visual QA of the new controls in the actual main settings dialog.
func run()->void:
	source_start=SourceProof.snapshot()
	scene=Main.instantiate();root.add_child(scene);await frames(12)
	configure_budget_ui();long_intent_probe()
	var panel:Control=scene.runtime_connection_panel
	scene.show_ai_connection();await frames()
	scene.advanced_scroll.scroll_vertical=int(panel.position.y+panel.budget_profile_input.get_parent().position.y)-16
	await capture("native_budget_controls")
	check(panel.budget_profile_input.selected==1 and panel.budget_usage_label.text.contains("98304"),"actual native city96 controls and measured bytes")
	check(scene.advanced_scroll.get_global_rect().intersects(panel.budget_profile_input.get_global_rect()),"budget selector visibly inside scroll viewport")
	panel.budget_profile_input.select(2);panel.budget_profile_input.item_selected.emit(2);panel.budget_bytes_input.text="70001";panel.budget_bytes_input.text_changed.emit("70001")
	panel.key_input.text="synthetic-native-capacity-marker";panel._apply()
	check(scene.runtime_ai.client.public_configuration().public_request_budget_bytes==70001 and panel.budget_bytes_input.text=="70001","native custom exact bytes applied")
	await capture("native_budget_custom")
	panel.budget_bytes_input.text="131073";panel.budget_bytes_input.text_changed.emit("131073");panel.key_input.text="synthetic-native-capacity-marker";panel._apply()
	check(not scene.runtime_ai.client.configured() and panel.status_label.text.contains("1至131072"),"native invalid cap reports no clamping or connection")
	await capture("native_budget_invalid")
	check(mock.sent.size()==1,"UI choices and Apply generate no extra sends")
	check(C.bytes(source_start)==C.bytes(SourceProof.snapshot()),"native UI source unchanged")
	var report:={"checks":count,"failures":failures,"passed":failures.is_empty(),"live_api":false,"mock_sends":mock.sent.size(),"actual_viewport":[root.size.x,root.size.y]}
	var f:=FileAccess.open(OUT+"panel_report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print("NATIVE_BUDGET_PANEL ",count," checks; failures=",failures)
	scene.queue_free();await frames(3);quit(0 if failures.is_empty() else 1)
