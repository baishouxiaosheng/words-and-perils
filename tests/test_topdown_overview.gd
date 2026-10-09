extends SceneTree
const Board=preload("res://view/hex_board.gd")
const Before=preload("res://tests/fixtures/v7_renderer/hex_board.gd")
const Generator=preload("res://core/world_generator.gd")
const Game=preload("res://core/game_state.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func _initialize()->void:call_deferred("run")
func settle()->void:
	for i in range(3):await process_frame
func run()->void:
	var vp=SubViewport.new();vp.size=Vector2i(1128,642);vp.own_world_3d=true;root.add_child(vp)
	var board=Board.new();var before=Before.new();vp.add_child(board);vp.add_child(before);await settle()
	var game=Game.new();board.set_world(game.state);before.set_world(game.state);board.focus_player();before.focus_player()
	check(board.camera.transform==before.camera.transform and board.camera.projection==before.camera.projection,"Original61 launch close camera exact v7")
	var world=Generator.generate(726381,12,{"generator_version":Generator.BIOMES_VERSION})
	game.state.hexes=world.hexes.duplicate(true);game.state.generated_world=world.duplicate(true);game.state.board_radius=12
	for id in game.state.actors:game.state.actors[id].hex=world.actor_spawn_hexes[id].duplicate()
	board.set_world(game.state);board.focus_player();await settle();var close=board.camera.transform;var near_water=board.water_near_material;var near_roughness=near_water.roughness;var near_specular=near_water.metallic_specular;var exact=game.state.duplicate(true)
	var labels={}
	for label in board.find_children("*","Label3D",true,false):labels[label.get_instance_id()]={"position":label.position,"scale":label.scale,"font_size":label.font_size,"pixel_size":label.pixel_size}
	for size_ in [Vector2i(1128,642),Vector2i(1128,822),Vector2i(1608,822),Vector2i(600,820)]:
		vp.size=size_;board.reset_camera();await settle()
		check(board.overview_mode and board.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"Large fullmap is orthographic")
		check((-board.camera.global_basis.z).dot(Vector3.DOWN)>0.999999,"True vertical ray direction, no oblique approximation")
		check(board.camera.global_basis.determinant()>0.9999 and board.camera.global_basis.is_finite(),"Stable orthonormal camera at pole")
		check(board.water_near_material==near_water and near_water.roughness==near_roughness and near_water.metallic_specular==near_specular,"Overview does not mutate shared near water material")
		check(board.water_overview_material!=near_water and board.water_layers.all(func(node):return node.material_override==board.water_overview_material),"Overview-only duplicate applied to all water layers")
		check(board.water_overview_material.albedo_color==near_water.albedo_color and board.water_overview_material.transparency==near_water.transparency and board.water_overview_material.depth_draw_mode==near_water.depth_draw_mode and board.water_overview_material.metallic==near_water.metallic,"Water color/transparency/depth/metallic identity preserved")
		check(not board.chunk_mode,"Fullmap uses whole terrain, no extra near-submission penalty")
		var bounds=Rect2(Vector2.ZERO,Vector2(size_))
		for tile in board.tiles.values():
			for i in range(6):
				var point=board.hex_pos(tile.hex)+board.terrain_field.corner(i)
				point.y=board.terrain_field.surface_height(point)
				check(bounds.has_point(board.camera.unproject_position(point)),"Every actualtilecorner fits aspect "+str(size_))
		for h in [Vector2i(-2,4),Vector2i(2,5),Vector2i(0,0),Vector2i(12,0),Vector2i(-12,0)]:
			var point=board.hex_pos(h);point.y=board.terrain_field.surface_height(point)
			check(board.pick(board.camera.unproject_position(point))==h,"Topdown terrain/bridge/coast point picks same hex "+str(h))
		var rectangles:Array=[]
		for label in board.find_children("*","Label3D",true,false):
			check(label.font_size==32 and label.modulate==Color.WHITE and label.outline_size==0,"Overview keeps actual typography32/white/nooutline")
			check(float(label.get_meta("overview_nominal_px",0))>=13.999,"Overview user-approved minimum readable size")
			var rect:Rect2=label.get_meta("overview_screen_rect")
			check(bounds.encloses(rect),"Name rectangle remains within boardviewport")
			check(not rectangles.any(func(other):return other.intersects(rect)),"Names separated rather than overlapping")
			rectangles.append(rect)
		check(game.state==exact,"Camera/label view never changes worldfacts")
	board.reset_camera();board.orbit_camera(0.61,0.3);await settle()
	check((-board.camera.global_basis.z).dot(Vector3.DOWN)>0.999999,"Map rotation stays vertical")
	board.focus_player();await settle()
	check(board.water_layers.all(func(node):return node.material_override==near_water),"Exact original water resource restored onclose")
	check(board.camera.transform==close and board.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Near camera restores exact saved orientation/projection")
	for label in board.find_children("*","Label3D",true,false):
		var original:Dictionary=labels[label.get_instance_id()]
		check(label.position==original.position and label.scale==original.scale and label.font_size==original.font_size and label.pixel_size==original.pixel_size,"All close anchors/scales/pixels restored exactly")
	var original=Game.new();board.set_world(original.state);board.focus_player();await settle()
	check(not board.overview_mode and board.camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Returning original61 leaves topdown mode")
	vp.queue_free();await settle()
	for failure in failures:printerr("FAIL: ",failure)
	print("TOPDOWN OVERVIEW: %d/%d passed"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
