extends Control
## Lightweight schematic of authoritative playable cells. No second 3D render.
signal activated
var state: Dictionary = {}
var points: Array[Dictionary] = []
var center_hex := Vector2.ZERO
var extent := 1.0
var overview := false
# One immutable 2D mesh preserves the original hex tessellation, draw order and
# colors while avoiding one canvas draw call per cell. Actors/rim remain dynamic.
var terrain_batch_enabled := true
var terrain_mesh: ArrayMesh
var terrain_mesh_size := Vector2(-1,-1)
var terrain_mesh_dirty := true
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "查看全图 / 返回旅人"
	resized.connect(queue_redraw)
func set_world(value: Dictionary) -> void:
	state = value
	var next_points: Array[Dictionary] = []
	var bounds := Rect2()
	var first := true
	for cell in state.get("hexes",{}).values():
		var p := Vector2(sqrt(3.0)*(float(cell.q)+float(cell.r)*0.5),float(cell.r)*1.5)
		next_points.append({"p":p,"terrain":cell.terrain})
		if first: bounds = Rect2(p,Vector2.ZERO); first = false
		else: bounds = bounds.expand(p)
	if points != next_points:
		points = next_points
		terrain_mesh_dirty = true
	center_hex = bounds.get_center()
	extent = maxf(bounds.size.x,bounds.size.y)*0.57+2.0
	queue_redraw()
func map_point(hex: Array) -> Vector2:
	return size*0.5+(Vector2(sqrt(3.0)*(float(hex[0])+float(hex[1])*0.5),float(hex[1])*1.5)-center_hex)*((minf(size.x,size.y)*0.5-12.0)/extent)
func _draw() -> void:
	var c := size*0.5
	var radius := minf(size.x,size.y)*0.5-3.0
	draw_circle(c+Vector2(0,3),radius+2,Color(0,0,0,0.15))
	draw_circle(c,radius-8,Color("329bb5"))
	if terrain_batch_enabled:
		if terrain_mesh_dirty or terrain_mesh_size != size: _rebuild_terrain_mesh(c,radius)
		if terrain_mesh != null: draw_mesh(terrain_mesh,null)
	else:
		_draw_terrain_unbatched(c,radius)
	for id in state.get("actors",{}):
		var pos := map_point(state.actors[id].hex)
		if pos.distance_to(c)>radius-10: continue
		draw_circle(pos,5.0 if id=="actor_player" else 3.8,Color("162d32"))
		draw_circle(pos,3.1 if id=="actor_player" else 2.2,Color("fff4c7") if id=="actor_player" else Color("cc8664"))
		if id=="actor_player": draw_arc(pos,7.0,0,TAU,24,Color(1,0.96,0.79,0.8),1.2,true)
	var FieldbookArt=preload("res://view/adventure_fieldbook/skin.gd")
	# Map aperture at (142,132), r94; preserve existing c/radius and actor mapping.
	var scale_:float=(radius-8)/94.0
	draw_texture_rect(FieldbookArt.texture("minimap_frame"),Rect2(c-Vector2(142,132)*scale_,Vector2(284,300)*scale_),false)
	var font:Font=get_theme_default_font()
	draw_string(font,Vector2(c.x-4,20),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("4f694f"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		activated.emit(); accept_event()

func _draw_terrain_unbatched(c:Vector2,radius:float)->void:
	var unit := (radius-10)/extent
	var colors := {"grass":Color("a8c95f"),"arid":Color("e0c486"),"forest":Color("5e9854"),"jungle":Color("83ad4f"),"ocean":Color("329bb5"),"main_lake":Color("64c9ca")}
	for row in points:
		var p: Vector2 = c+(row.p-center_hex)*unit
		if p.distance_to(c)>radius-9: continue
		var corners := PackedVector2Array()
		for i in range(6): corners.append(p+Vector2(cos(PI/6+i*TAU/6),sin(PI/6+i*TAU/6))*unit*1.02)
		draw_colored_polygon(corners,colors.get(row.terrain,Color("a8c95f")))

func _rebuild_terrain_mesh(c:Vector2,radius:float)->void:
	var vertices:=PackedVector2Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var unit := (radius-10)/extent
	var palette := {"grass":Color("a8c95f"),"arid":Color("e0c486"),"forest":Color("5e9854"),"jungle":Color("83ad4f"),"ocean":Color("329bb5"),"main_lake":Color("64c9ca")}
	for row in points:
		var p: Vector2 = c+(row.p-center_hex)*unit
		if p.distance_to(c)>radius-9: continue
		var corners := PackedVector2Array()
		for i in range(6): corners.append(p+Vector2(cos(PI/6+i*TAU/6),sin(PI/6+i*TAU/6))*unit*1.02)
		var offset:=vertices.size()
		vertices.append_array(corners)
		for corner in corners: colors.append(palette.get(row.terrain,Color("a8c95f")))
		# Same triangulation used by draw_colored_polygon, including edge overlap.
		for index in Geometry2D.triangulate_polygon(corners): indices.append(offset+index)
	terrain_mesh=null
	if not indices.is_empty():
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
		terrain_mesh=ArrayMesh.new()
		terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	terrain_mesh_size=size;terrain_mesh_dirty=false
