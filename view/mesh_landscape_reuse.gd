extends RefCounted
## Mesh-build-only reuse beneath the existing rounded landscape cache.
## Exact input equality preserves first-hit representatives and sampling order.
class ExactSampleProxy extends RefCounted:
	var source
	var has_sample:=false
	var last_x:=0.0
	var last_z:=0.0
	var last_sample:Dictionary={}
	func _init(original)->void:source=original
	func sample_visual_landscape(point:Vector3)->Dictionary:
		if has_sample and point.x==last_x and point.z==last_z:return last_sample
		last_sample=source.sample_visual_landscape(point)
		last_x=point.x;last_z=point.z;has_sample=true
		return last_sample
class RestoreScope extends RefCounted:
	var field
	var original
	var proxy
	func _init(target)->void:
		field=target;original=field.height_field
		proxy=ExactSampleProxy.new(original);field.height_field=proxy
	func restore()->void:
		if field!=null and field.height_field==proxy:field.height_field=original
		field=null;original=null;proxy=null
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE:
			# PREDELETE cannot safely call another method on this dying instance.
			if field!=null and field.height_field==proxy:field.height_field=original
static func build_meshes(field)->Dictionary:
	if not field.generated:return field.build_meshes()
	var scope:=RestoreScope.new(field)
	var meshes:Dictionary=field.build_meshes()
	scope.restore()
	return meshes
