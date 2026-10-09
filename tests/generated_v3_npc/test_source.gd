extends SceneTree
const Source=preload("res://view/generated_v3_npc/source.gd")
const Generator=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures=[]
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_npc")
	for radius in [4,12]:
		for recipe in ["coastal_range","plateau_hinterland"]:
			var generated=Generator.generate(726381,radius,recipe)
			var source=Source.new();var result=source.admit(generated.source)
			var name_="%s_r%d"%[recipe,radius]
			check(result.ok,name_+" admission "+C.bytes(result))
			if not result.ok:continue
			check(source.validate_state(source.world).ok,name_+" initial valid")
			check(source.data.content_hash==generated.source.content_hash,name_+" source preserved")
			check(source.world.actors[source.npc_id].inventory==[],name_+" common actor shape")
			var out={"admission":result,"placement":source.npc_placement_result,"reservations":source.npc_reservations,"catalog":source.identity.npc_catalog}
			var file=FileAccess.open("res://artifacts/generated_v3_npc/placement_"+name_+".json",FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t"));file.close()
	var report={"checks":checks,"failures":failures,"ok":failures.is_empty()}
	FileAccess.open("res://artifacts/generated_v3_npc/source_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("NPC_SOURCE ",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
