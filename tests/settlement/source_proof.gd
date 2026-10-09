extends RefCounted
## Read-only test evidence: only project source and authored runtime content.
static func collect(path:String,result:Dictionary)->void:
	var directory:=DirAccess.open(path)
	if directory==null:return
	directory.list_dir_begin()
	var name_:String=directory.get_next()
	while not name_.is_empty():
		if not name_.begins_with(".") and name_!="source" and name_!="previews":
			var child:=path+"/"+name_
			if directory.current_is_dir():collect(child,result)
			elif name_.get_extension() in ["gd","gdshader","tscn","tres","glb"]:result[child]=FileAccess.get_sha256(child)
		name_=directory.get_next()
	directory.list_dir_end()
static func snapshot()->Dictionary:
	var result:Dictionary={}
	for path in ["res://core","res://view","res://shared","res://relay","res://tests/settlement","res://assets/city_districts"]:collect(path,result)
	for path in ["res://main.gd","res://main.tscn","res://project.godot","res://artifacts/world_bundle_20261002/manifest.json","res://artifacts/settlement_20261003/content_v1.json","res://assets/city_districts/manifest.json"]:result[path]=FileAccess.get_sha256(path)
	return result
