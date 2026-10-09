extends RefCounted
const INK:=Color("374438")
const MUTED:=Color("677460")
const STRAW:=Color("efe2b9")
const LIGHT:=Color("f7edcb")
const SHADE:=Color("d7c28e")
static func surface(kind:String,pad:float=12.0,state:String="normal")->StyleBoxTexture:
	return preload("res://view/adventure_fieldbook/skin.gd").surface(kind,pad,state)
static func focus()->StyleBoxFlat:
	return preload("res://view/adventure_fieldbook/skin.gd").focus()
