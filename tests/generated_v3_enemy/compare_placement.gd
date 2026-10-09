extends SceneTree
const Base=preload("res://view/generated_v3_npc/source.gd")
const Place=preload("res://view/generated_v3_enemy/placement.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var differences:Array=[]
func _initialize()->void:call_deferred("run")
func compare(a:Variant,b:Variant,path:String)->void:
	if C.bytes(a)==C.bytes(b):return
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):differences.append({"path":path+"/"+str(key),"missing":"new"})
			else:compare(a[key],b[key],path+"/"+str(key))
		for key in b:
			if not a.has(key):differences.append({"path":path+"/"+str(key),"missing":"saved"})
	elif a is Array and b is Array and a.size()==b.size():
		for i in a.size():compare(a[i],b[i],path+"/"+str(i))
	else:differences.append({"path":path,"saved":a,"new":b})
func run()->void:
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/generated_v3_enemy/native_mouse/actual_saved_core.json"))
	var base=Base.new();var result:Dictionary=base.admit(saved.source,saved.renderer_profile,saved.placement_manifest,{"vegetation":false});print("BASE ",result.get("ok")," ",result.get("code",""))
	if not result.ok:print(result);quit(1);return
	var placed:Dictionary=Place.build(base,"actor_village_hostile")
	compare(saved.enemy_placement,placed.placement_witness,"witness")
	FileAccess.open("res://artifacts/generated_v3_enemy/placement_difference.json",FileAccess.WRITE).store_string(JSON.stringify(differences,"\t"))
	print("PLACEMENT_DIFF ",JSON.stringify(differences));quit(0)
