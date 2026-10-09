extends SceneTree
const Style=preload("res://view/world_name_style.gd")
const Board=preload("res://view/hex_board.gd")
const Game=preload("res://core/game_state.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	checks+=1
	if not ok:failures.append(note)
func run()->void:
	var source=Image.create(25,25,false,Image.FORMAT_RGBA8);source.fill(Color.TRANSPARENT)
	for y in range(9,16):
		for x in range(9,16):source.set_pixel(x,y,Color.WHITE)
	var blur=Style.blur_alpha(source)
	check(blur.get_width()==source.get_width() and blur.get_height()==source.get_height(),"Blur retains bounded quad size")
	check(blur.get_pixel(7,12).a>0.01 and source.get_pixel(7,12).a==0.0,"True convolution creates soft alpha beyond original glyph")
	check(blur.get_pixel(12,12).a<0.78 and blur.get_pixel(12,12).a>0.35,"Blur core is stronger but never an opaque black outline")
	check(blur.get_pixel(6,12).a<blur.get_pixel(8,12).a and blur.get_pixel(8,12).a<blur.get_pixel(10,12).a,"Blur alpha has a graded edge")
	check(blur.get_pixel(0,0).a==0.0,"Padded external edge remains transparent")
	var viewport=SubViewport.new();viewport.size=Vector2i(1128,642);viewport.own_world_3d=true;root.add_child(viewport)
	var board=Board.new();viewport.add_child(board);await process_frame
	var game=Game.new();var before=game.state.duplicate(true);board.set_world(game.state);await process_frame
	for id in board.token_nodes:
		var label:Label3D=board.token_nodes[id].get_node("Nameplate")
		check(label.font_size==32 and is_equal_approx(label.pixel_size,0.007),"Original world-name physical size remains unchanged: "+id)
		check(label.modulate==Color.WHITE and label.outline_size==0,"Bold name stays pure white with no outline: "+id)
		check(label.font is FontVariation and label.font.variation_face_index==2 and is_equal_approx(label.font.variation_embolden,Style.EMBOLDEN),"Name uses same SCface with real synthetic bold: "+id)
		var shadow:Sprite3D=label.get_node_or_null("SoftNameShadow")
		check(shadow!=null and shadow.billboard==BaseMaterial3D.BILLBOARD_ENABLED and is_equal_approx(shadow.pixel_size,label.pixel_size),"One shadowquad has matching billboard scale: "+id)
		check(not shadow.no_depth_test and shadow.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Shadow respects occlusion and never casts physical world shadows: "+id)
		var count=label.get_children().filter(func(node):return node is Sprite3D).size()
		board.set_world(game.state)
		check(count==1 and label.get_children().filter(func(node):return node is Sprite3D).size()==1,"Repeated state refresh does not stack text shadows: "+id)
	check(game.state==before,"Name styling never changes state or pick identity")
	viewport.queue_free();await process_frame
	if failures.is_empty():print("WORLD NAME STYLE PASSED: %d assertions"%checks);quit()
	else:
		for failure in failures:printerr("FAIL: ",failure)
		quit(1)
