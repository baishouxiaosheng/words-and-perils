extends Node
## Compatibility-friendly silhouette shell: selected actor only, no post-processing.
## Presentation-only children follow existing model transforms; no physics/selection facts.
const SHELL_NAME="SelectedEdgeGlow"
var selected_id:=""
var tracked:Array[MeshInstance3D]=[]
var material:ShaderMaterial
func _init()->void:
	material=ShaderMaterial.new()
	var shader=Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 edge_color : source_color = vec4(1.0, 0.84, 0.36, 1.0);
uniform float edge_width = 0.035;
void vertex() { VERTEX += NORMAL * edge_width; }
void fragment() { ALBEDO = edge_color.rgb; EMISSION = edge_color.rgb * 0.35; }
"""
	material.shader=shader
func select_actor(id:String,tokens:Dictionary)->void:
	if id==selected_id:return
	for shell in tracked:
		if is_instance_valid(shell):shell.hide()
	tracked.clear();selected_id=id
	if tokens.has(id):_collect(tokens[id])
func _collect(node:Node)->void:
	if node is MeshInstance3D and node.name!=SHELL_NAME and node.mesh!=null:
		var shell=node.get_node_or_null(SHELL_NAME) as MeshInstance3D
		if shell==null:
			shell=MeshInstance3D.new();shell.name=SHELL_NAME;shell.mesh=node.mesh
			shell.material_override=material;shell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(shell)
		shell.show();tracked.append(shell)
	for child in node.get_children():
		if child.name!=SHELL_NAME:_collect(child)
func clear()->void:select_actor("",{})
func report()->Dictionary:return {"selected_actor":selected_id,"active_shells":tracked.size(),"postprocessing":false,"gameplay_effects":false}
