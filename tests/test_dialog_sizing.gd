extends SceneTree
## Regression for wrapped notes measured at zero width before the first popup.
const Main=preload("res://main.tscn")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1180,812)
	var scene=Main.instantiate();root.add_child(scene);await process_frame;await process_frame
	for dialog in [scene.inventory_dialog,scene.effects_dialog,scene.world_dialog,scene.import_dialog]:
		dialog.popup_centered();await process_frame;await process_frame
		print("DIALOG SIZE ",dialog.title," ",dialog.size," minimum ",dialog.get_contents_minimum_size())
		check(dialog.size.x<=root.size.x-40 and dialog.size.y<=root.size.y-60,dialog.title+" fits minimum native window")
		var button:Button=dialog.get_ok_button()
		check(button.visible and button.position.y+button.size.y<=dialog.size.y,dialog.title+" return/apply button is reachable")
		dialog.hide()
	scene.show_inventory();await process_frame
	check(scene.inventory_dialog.size.y<=550,"Inventory reopened at bounded height")
	check(scene.game.state.state_version==0 and scene.active_action.is_empty(),"Opening dialogs never mutates world or creates action")
	scene.queue_free();await process_frame
	if failures.is_empty():print("DIALOG SIZING PASSED: %d assertions"%checks);quit(0)
	else:
		for f in failures:printerr("FAIL: ",f)
		quit(1)
