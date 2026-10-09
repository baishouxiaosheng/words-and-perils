extends Node3D
## Small authored shore lantern at the keeper's dry anchor, driven by saved story flag.
## It is a presentation prop, not a new walkable tile or action shortcut.
var lantern:MeshInstance3D
var lens_material:StandardMaterial3D
var title:Label3D
var lit:=false
func _ready()->void:
	var stone:=StandardMaterial3D.new();stone.albedo_color=Color("53665e");stone.roughness=1
	var brass:=StandardMaterial3D.new();brass.albedo_color=Color("92794a");brass.roughness=1
	_cylinder("StoneFoot",0.20,0.25,0.12,0.06,stone)
	_cylinder("LampColumn",0.09,0.13,0.62,0.43,stone)
	_cylinder("LanternBase",0.22,0.22,0.07,0.78,brass)
	lens_material=StandardMaterial3D.new();lens_material.albedo_color=Color("506363");lens_material.roughness=1
	lantern=_cylinder("LanternLens",0.17,0.17,0.28,0.96,lens_material)
	_cylinder("LanternRoof",0.02,0.28,0.22,1.18,brass)
	title=Label3D.new();title.name="LanternState";title.text="旧灯 · 熄灭";title.font_size=28;title.pixel_size=0.005
	title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;title.position.y=1.42;title.modulate=Color.WHITE;add_child(title)
func _cylinder(label_:String,top:float,bottom:float,height:float,y:float,mat:Material)->MeshInstance3D:
	var node=MeshInstance3D.new();node.name=label_;var mesh=CylinderMesh.new();mesh.top_radius=top;mesh.bottom_radius=bottom;mesh.height=height;mesh.radial_segments=6;mesh.rings=1
	node.mesh=mesh;node.material_override=mat;node.position.y=y;add_child(node);return node
func update_state(state:Dictionary,anchor:Vector3,overview:bool)->void:
	position=anchor+Vector3(0.85,0.02,0.06)
	lit=state.flags.get("lamp_restored",false)==true
	if lens_material!=null:
		lens_material.albedo_color=Color("ffe087") if lit else Color("506363")
		lens_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED if lit else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		lens_material.emission_enabled=lit;lens_material.emission=Color("ffd775");lens_material.emission_energy_multiplier=1.0
	if title!=null:
		title.text="旧灯 · 重燃" if lit else "旧灯 · 熄灭"
		title.visible=not overview
