extends SceneTree
## Four actual admitted starts for independent mesh/source/spawn audit.
const Source = preload("res://view/generated_v3_adventure/source.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const OUT := "res://artifacts/generated_v3_adventure/"
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures.append(label_); printerr("FAIL "+label_)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var index: Array = []
	for radius in [4,12]:
		for recipe in ["coastal_range","plateau_hinterland"]:
			var label_ := "726381_r%d_%s" % [radius,recipe]
			var generated := Generator.generate(726381,radius,recipe)
			check(generated.ok,label_+" generated")
			if not generated.ok: continue
			var source := Source.new(); var admitted := source.admit(generated.source)
			check(admitted.ok,label_+" admitted")
			if not admitted.ok: printerr(admitted); continue
			var spawn: Array = source.world.actors.actor_player.hex
			var component: Array = source.spawn_component.keys(); component.sort()
			var spawn_key: String = "%d,%d" % spawn
			check(C.bytes(source.data) == C.bytes(generated.source),label_+" raw source retained")
			check(source.navigation.supported[spawn_key] and source.navigation.allowed[spawn_key].size() >= 2,label_+" dry connected start")
			check(component.size() >= (7 if radius == 4 else 19),label_+" component threshold")
			var report := {"schema_version":"generated_v3_admission_audit/v1","case":label_,"source":source.data.duplicate(true),"identity":source.identity.duplicate(true),"spawn":spawn.duplicate(),"spawn_component":component,"navigation":source.navigation.export_data(spawn),"policy":{"id":Source.SPAWN_POLICY,"minimum_component_size":7 if radius == 4 else 19,"component_choice":"maximum connected supported symmetric dry graph size; ties use component smallest lexical key","spawn_choice":"maximum legal-neighbor degree within chosen component; then minimum axial distance to origin; then lexical key","terrain_mapping_id":Source.TERRAIN_MAPPING_ID,"biome_to_terrain":Source.BIOME_TERRAIN,"terrain_policy_id":Policy.ID,"terrain_costs":Policy.COSTS,"rng_used_for_spawn":false}}
			var path := OUT+"admission_"+label_+".json"
			var file := FileAccess.open(path,FileAccess.WRITE)
			check(file != null,label_+" report opened")
			if file == null: continue
			file.store_string(C.bytes(report)); file.flush(); var error := file.get_error(); file.close()
			check(error == OK,label_+" report written")
			index.append({"case":label_,"path":path,"content_hash":source.identity.content_hash,"geometry_hash":source.identity.geometry_hash,"runtime_hash":source.identity.runtime_hash,"spawn":spawn,"component_size":component.size(),"source_bytes":C.bytes(source.data).to_utf8_buffer().size()})
			print("V3_ADMISSION_CASE ",JSON.stringify(index[-1]))
	var file := FileAccess.open(OUT+"admission_index.json",FileAccess.WRITE)
	if file != null: file.store_string(C.bytes({"schema_version":"generated_v3_admission_audit_index/v1","cases":index,"checks":checks,"failures":failures})); file.close()
	print("V3 ADMISSION AUDIT ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() and index.size() == 4 else 1)
