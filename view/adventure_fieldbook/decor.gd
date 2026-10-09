extends Control
## Presentation-only overlay. Drawing never intercepts hit testing or input.
const FieldbookArt=preload("res://view/adventure_fieldbook/skin.gd")
var scene:Control
var previous:Array=[]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(_delta:float)->void:
	if not is_instance_valid(scene):return
	var next:Array=[scene.action_base.get_global_rect(),scene.speech_panel.get_global_rect(),scene.action_panel.visible,scene.hero_panel.get_global_rect(),scene.get_meta(&"responsive_hud_scale",1.0)]
	if next!=previous:previous=next;queue_redraw()
func _draw()->void:
	if not is_instance_valid(scene) or not scene.action_panel.visible:return
	var factor:float=scene.get_meta(&"responsive_hud_scale",1.0)
	var r:Rect2=scene.action_base.get_global_rect();var h:float=minf(132*factor,r.size.y+9*factor)
	var qx:float=r.position.x-25*factor
	var qrect:=Rect2(Vector2(qx,r.end.y-h+3*factor),Vector2(h*76/162,h))
	if qrect.intersects(scene.hero_panel.get_global_rect().grow(4*factor)):
		h=minf(h,100*factor);qx=r.position.x-10*factor
	if scene.action_base.is_visible_in_tree():draw_texture_rect(FieldbookArt.texture("quill"),Rect2(Vector2(qx,r.end.y-h+3*factor),Vector2(h*76/162,h)),false)
	# Bookmark lies outside the text lane, tucked into the dialogue's right edge.
	var s:Rect2=scene.speech_panel.get_global_rect()
	draw_texture_rect(FieldbookArt.texture("bookmark"),Rect2(Vector2(s.end.x-26*factor,s.position.y+7*factor),Vector2(21,36)*factor),false)
