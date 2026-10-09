extends SceneTree
const Presentation=preload("res://view/action_presentation.gd")
const Board=preload("res://view/hex_board.gd")
const Game=preload("res://core/game_state.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures.append(text)
func _initialize()->void:call_deferred("run")
func run()->void:
	var helper=Presentation.new();root.add_child(helper)
	var token=Node3D.new();root.add_child(token)
	helper.register_actor("a",token,Vector3.ZERO)
	helper.select_actor("a");helper._process(0.3)
	check(token.position.y>0.15,"Selected token lifts visually")
	var endpoint=Vector3(3,0.4,1)
	helper.move_actor("a",endpoint)
	helper._process(0.5)
	check(token.position.y>0.7,"Resolved move has a lifted hand arc")
	check(token.position!=endpoint,"Position interpolates before landing")
	helper._process(2.0)
	check(token.position.is_equal_approx(endpoint),"Landing is exactly authoritative destination")
	check(token.rotation.is_equal_approx(Vector3.ZERO),"Landing ends perfectly upright")
	helper.move_actor("a",Vector3(4,1,0));helper._process(0.3)
	helper.reset_actor("a",Vector3(1,0,0));helper._process(2.0)
	check(token.position.is_equal_approx(Vector3(1,0,0)),"Reset invalidates stale movement")
	for kind in ["magic","gunfire","melee","hit"]:helper.play_effect(kind,Vector3.ZERO,Vector3(2,0,0),true)
	check(helper.effects.size()==4,"Four distinct showcase effects generated")
	for fx in helper.effects:check(fx.node.get_meta("showcase_only"),"Showcase provenance remains explicit")
	helper._process(2.0)
	check(helper.effects.is_empty(),"Effect lifetimes clear transient resources")
	var board=Board.new();root.add_child(board);await process_frame
	var game=Game.new();board.set_world(game.state)
	var before=board.token_nodes.actor_player
	var state=game.state.duplicate(true);state.actors.actor_player.hex=[1,-1]
	board.set_world(state,true)
	check(before==board.token_nodes.actor_player,"Stable token identity across authoritative refresh")
	check(board.presentation.actors.actor_player.moving,"Commit movement schedules visual-only motion")
	board.presentation._process(3.0)
	check(before.position.is_equal_approx(board.hex_pos(Vector2i(1,-1))+Vector3(0,board.terrain_field.support_height(Vector2i(1,-1)),0)),"Board token lands on current terrain support")
	check(state.actors.actor_player.hex==[1,-1] and state.state_version==0,"Presentation never mutates supplied world state")
	board.focus_player()
	check(absf(board.camera.position.distance_to(board.view_focus)-board.camera_distance)<0.0001,"Focused perspective radius is centered on nonzero encounter focus")
	board.orbit_camera(0.8,-0.1)
	check(absf(board.camera.position.distance_to(board.view_focus)-board.camera_distance)<0.0001,"Orbit preserves nonzero focus and radius")
	var top=board.hex_pos(Vector2i(1,-1));top.y=board.terrain_field.surface_height(top)
	check(board.pick(board.camera.unproject_position(top))==Vector2i(1,-1),"Perspective height-ray picking remains valid after focus and orbit")
	var old_count=board.presentation.effects.size()
	state=state.duplicate(true);state.actors.actor_sentinel.health.current=9
	board.set_world(state,true)
	check(board.presentation.effects.size()==old_count+1,"Health loss produces actual hit presentation")
	board.set_world(game.state,false)
	check(board.presentation.effects.is_empty() and not board.presentation.actors.actor_player.moving,"Load/reset cancels effects and stale motion")
	board.queue_free();helper.queue_free();token.queue_free();await process_frame
	if failures.is_empty():print("ACTION PRESENTATION PASSED: %d assertions"%checks);quit(0)
	else:
		for f in failures:printerr("FAIL: ",f)
		quit(1)
