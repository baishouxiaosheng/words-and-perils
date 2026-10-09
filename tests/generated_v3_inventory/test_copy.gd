extends SceneTree
const Main=preload("res://main.gd")
func _initialize() -> void:
	var app=Main.new();app.generated_v3_inventory_mode=true
	assert(app._assessment_error_text({"code":"GENERATED_ITEM_REACH","errors":["English detail"]}).begins_with("离行礼包太远"))
	assert(app._assessment_error_text({"code":"ITEM_DUPLICATE","errors":["English detail"]}).contains("已经在你身上"))
	assert(app._assessment_error_text({"code":"ITEM_OWNERSHIP","errors":["English detail"]}).contains("其他角色"))
	app.generated_v3_inventory_mode=false
	assert(app._assessment_error_text({"code":"ITEM_RANGE","errors":["Original old-mode text"]})=="Original old-mode text")
	app.build_v3_setup_dialog()
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:assert(app.v3_inventory_choice.get_theme_color(state)==Main.INK)
	assert(Main.focus_details_extent(Vector2i(1280,720),true)==Vector2i(540,420))
	assert(Main.focus_details_extent(Vector2i(1280,720),false)==Vector2i(540,340))
	assert(Main.focus_details_extent(Vector2i(640,360),true).y<=280)
	app.free();print("V3_INVENTORY_COPY 12/12");quit(0)
