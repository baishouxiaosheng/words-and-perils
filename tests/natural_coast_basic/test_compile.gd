extends SceneTree
const Adapter = preload("res://view/generated_natural_coast_basic/adapter.gd")
const Controller = preload("res://view/generated_natural_coast_entry/controller.gd")
const View = preload("res://view/generated_natural_coast_entry/view.gd")
const Board = preload("res://view/generated_natural_coast_basic/board.gd")
var checks := 0
var failures: Array = []
func _initialize() -> void:
	var adapter := Adapter.new(); var controller := Controller.new(); var view := View.new(); var board := Board.new()
	checks = 4
	if adapter.ready().get("ok",false): failures.append("blank adapter unexpectedly ready")
	if controller.session.is_open(): failures.append("blank controller unexpectedly admitted")
	if view.adapter != null: failures.append("blank view owns authority before admission")
	if board.admitted_source != null: failures.append("blank board substituted source")
	controller.free(); view.free(); board.free()
	finish()
func finish() -> void:
	var output := OS.get_environment("COAST_PLAY_OUTPUT")
	var result := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"suite":get_script().resource_path,"recipe":OS.get_environment("COAST_PLAY_RECIPE"),"run_id":OS.get_environment("COAST_PLAY_RUN_ID"),"owned_pid":OS.get_process_id(),"script_sha256":FileAccess.get_sha256(get_script().resource_path)}
	if not output.is_empty():
		var encoded := JSON.stringify(result,"\t",true,true)
		FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(encoded)
		FileAccess.open(output.path_join("completed.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":result.run_id,"owned_pid":result.owned_pid,"checks":checks,"result_sha256":encoded.sha256_text(),"script_sha256":result.script_sha256}))
	print("NATURAL_COAST_BASIC ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
