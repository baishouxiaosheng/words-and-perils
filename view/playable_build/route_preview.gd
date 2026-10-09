extends Node3D
## Read-only route illustration. Receiving coordinates cannot schedule movement.
var signature:=""
func show_route(points:Array)->void:
	var next_signature:=str(points)
	if next_signature==signature:return
	signature=next_signature
	for child in get_children():remove_child(child);child.queue_free()
	if points.size()<2:return
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color("e5c98c");mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(1,points.size()):
		var a:Vector3=points[i-1]+Vector3(0,0.10,0);var b:Vector3=points[i]+Vector3(0,0.10,0)
		var line:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.028;mesh.bottom_radius=.028;mesh.height=a.distance_to(b);mesh.radial_segments=6
		line.mesh=mesh;line.material_override=mat;line.position=(a+b)*.5
		if a.distance_to(b)>.001:line.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
		line.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(line)
		var marker:=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=.17;ring.outer_radius=.22;ring.rings=16;ring.ring_segments=4
		marker.mesh=ring;marker.material_override=mat;marker.position=b;marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(marker)
