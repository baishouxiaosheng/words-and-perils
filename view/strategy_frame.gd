extends Control
## Restrained original brass inset and cut-corner motifs, rendered at native scale.
var frame_color := Color("a48b5b")
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	if size.x < 30 or size.y < 30: return
	var inset := 5.0
	var rect := Rect2(Vector2.ONE*inset, size-Vector2.ONE*inset*2.0)
	draw_rect(rect, Color(frame_color,0.28), false, 1.0)
	for corner in [Vector2(inset,inset),Vector2(size.x-inset,inset),Vector2(inset,size.y-inset),size-Vector2.ONE*inset]:
		var sx := 1.0 if corner.x < size.x*0.5 else -1.0
		var sy := 1.0 if corner.y < size.y*0.5 else -1.0
		draw_line(corner,corner+Vector2(15*sx,0),frame_color,1.0)
		draw_line(corner,corner+Vector2(0,15*sy),frame_color,1.0)
		var p: Vector2 = corner+Vector2(4*sx,4*sy)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-2),p+Vector2(2,0),p+Vector2(0,2),p+Vector2(-2,0)]),frame_color)
