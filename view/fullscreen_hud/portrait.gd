extends Control
## Original C fieldbook portrait, authored from the game's own faceted traveler.
const FieldbookArt=preload("res://view/adventure_fieldbook/skin.gd")
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw()->void:
	var texture_:Texture2D=FieldbookArt.texture("portrait_composite")
	var factor:float=minf(size.x/140.0,size.y/160.0)
	var target:=Vector2(140,160)*factor
	draw_texture_rect(texture_,Rect2((size-target)*.5,target),false)
