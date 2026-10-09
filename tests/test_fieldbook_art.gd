extends SceneTree
const Main=preload("res://main.gd")
const FieldbookArt=preload("res://view/adventure_fieldbook/skin.gd")
func _initialize()->void:
	var count:=0
	for kind in ["dock","speech","history","status","turn","round","writing","well","panel","button","primary"]:
		for state in ["normal","hover","pressed","disabled"]:
			var box:=FieldbookArt.surface(kind,12,state)
			assert(box.texture!=null);assert(box.texture.get_width()>0);count+=1
	for n in ["quill","bookmark","portrait_composite","minimap_frame"]:assert(FieldbookArt.texture(n)!=null);count+=1
	print("C_ART_CONTRACT ",count,"/",count);quit(0)
