extends SceneTree
const Generator=preload("res://core/world_generation_v3/generator.gd")
const Adapter=preload("res://view/generated_v3_enemy/adapter.gd")
const Board=preload("res://view/generated_v3_enemy/board.gd")
const Main=preload("res://main.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	print("ENEMY_PROBE_PARSE_OK")
	var generated:Dictionary=Generator.generate(726381,4,"coastal_range")
	print("ENEMY_GENERATE ",JSON.stringify({"ok":generated.get("ok"),"code":generated.get("code","")}))
	var adapter=Adapter.new();var started:Dictionary=adapter.start_source(generated.source)
	print("ENEMY_ADMISSION ",JSON.stringify({"ok":started.get("ok"),"code":started.get("code", ""),"errors":started.get("errors",[])}))
	if not started.ok:quit(2);return
	var source=adapter.source
	print("ENEMY_GEOMETRY ",JSON.stringify({"enemy_hex":source.world.actors[source.enemy_id].hex,"anchor":source.enemy_placement_result.attack_anchor_hex}))
	var submitted:Dictionary=adapter.begin_intent(adapter.sample_goal("observe"),adapter.tile_reference(adapter.state_copy().actors.actor_player.hex))
	print("ENEMY_SUBMIT ",JSON.stringify({"ok":submitted.get("ok"),"code":submitted.get("code", ""),"request_bytes":JSON.stringify(adapter.request()).to_utf8_buffer().size()}))
	if not submitted.ok:print(submitted);quit(3);return
	for step in ["prepare_fixture","roll_once","stage","commit"]:
		var result:Dictionary=adapter.call(step);print("ENEMY_STEP ",step," ",JSON.stringify({"ok":result.get("ok"),"code":result.get("code", ""),"errors":result.get("errors",[])}))
		if not result.ok:quit(4);return
	var loaded=Adapter.new();var restored:Dictionary=loaded.load_data(adapter.save_data());print("ENEMY_RESTORE ",JSON.stringify(restored))
	quit(0 if restored.ok else 5)
