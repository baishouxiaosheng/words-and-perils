extends SceneTree
const Reuse=preload("res://view/mesh_landscape_reuse.gd")
class Raw extends RefCounted:
	var calls:=0
	func sample_visual_landscape(p:Vector3)->Dictionary:
		calls+=1;return {"elevation":p.x+p.z,"marker":calls}
class Field extends RefCounted:
	var generated:=true
	var height_field=Raw.new()
	var fail:=false
	func build_meshes()->Dictionary:
		if fail:
			var absent:Dictionary={}
			var bad=absent["intentional_failure"]
			return bad
		var a:Dictionary=height_field.sample_visual_landscape(Vector3(0.125,0,0.75))
		var b:Dictionary=height_field.sample_visual_landscape(Vector3(0.125,7,0.75))
		return {"a":a,"b":b}
var checks:Array=[]
var scope_weak:WeakRef
var proxy_weak:WeakRef
func forced_scope_failure(f)->void:
	var scope:=Reuse.RestoreScope.new(f)
	scope_weak=weakref(scope);proxy_weak=weakref(scope.proxy)
	var absent:Dictionary={}
	var bad=absent["intentional_scope_failure"]
	print(bad)
func check(ok:bool,label_:String)->void:
	checks.append({"passed":ok,"label":label_});if not ok:printerr("LIFECYCLE_FAIL ",label_)
func _initialize()->void:run.call_deferred()
func run()->void:
	var f:=Field.new();var raw=f.height_field
	var result:Dictionary=Reuse.build_meshes(f)
	check(f.height_field==raw,"normal return restores identity")
	check(raw.calls==1 and result.a==result.b,"exact xz ignores y")
	f.fail=true
	var failed:Dictionary=Reuse.build_meshes(f)
	check(f.height_field==raw,"script failure restores identity")
	f.fail=false
	Reuse.build_meshes(f)
	check(f.height_field==raw and raw.calls==2,"rebuild starts fresh and restores identity")
	var proxy=Reuse.ExactSampleProxy.new(raw)
	proxy.sample_visual_landscape(Vector3(0.0,0,1.0));proxy.sample_visual_landscape(Vector3(0.00000001,0,1.0))
	check(raw.calls==4,"no rounded approximate reuse")
	var old_a:Dictionary=proxy.sample_visual_landscape(Vector3(4,0,5))
	var old_copy:Dictionary=old_a.duplicate(true)
	proxy.sample_visual_landscape(Vector3(5,0,6))
	check(old_a==old_copy,"later sample does not mutate retained dictionary")
	forced_scope_failure(f)
	check(f.height_field==raw,"scope unwind fallback restores identity")
	check(scope_weak.get_ref()==null and proxy_weak.get_ref()==null,"scope and proxy released after unwind")
	var scope:=Reuse.RestoreScope.new(f)
	var replacement:=Raw.new();f.height_field=replacement;scope=null
	check(f.height_field==replacement,"fallback preserves newer replacement")
	f.generated=false
	Reuse.build_meshes(f)
	check(f.height_field==replacement and replacement.calls==2,"legacy delegates without installing reuse")
	var file:=FileAccess.open(OS.get_environment("FOGBANK_PERF_OUT")+"/lifecycle.json",FileAccess.WRITE);file.store_string(JSON.stringify(checks,"\t"));file.close()
	print("LIFECYCLE_COMPLETE ",JSON.stringify(checks));quit(0 if checks.all(func(row):return row.passed) else 1)
