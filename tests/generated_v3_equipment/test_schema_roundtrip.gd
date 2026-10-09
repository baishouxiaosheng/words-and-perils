extends SceneTree
## First gate for this profile: real serialized/disk witness equality, every recipe/size.
const A=preload("res://view/generated_v3_equipment/adapter.gd")
const G=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures:Array=[]
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("SCHEMA_FAIL ",label_)
	return value
func run()->void:
	for radius in [4,12]:
		for recipe in ["coastal_range","plateau_hinterland"]:
			var raw:Dictionary=G.generate(726381,radius,recipe)
			var a=A.new();a.feature_options={"vegetation":true}
			var admitted:Dictionary=a.start_source(raw.source)
			if not check(admitted.ok,"admit "+str(radius)+" "+recipe+" "+str(admitted.get("code",""))):continue
			var encoded:String=C.bytes(a.save_data());var parsed:Variant=JSON.parse_string(encoded)
			check(parsed is Dictionary and C.bytes(parsed)==encoded,"complete exact JSON roundtrip "+str(radius)+recipe)
			var b=A.new();var loaded:Dictionary=b.load_data(parsed)
			check(loaded.ok,"serialized source/witness admission "+str(radius)+recipe+" "+str(loaded))
			check(loaded.ok and C.bytes(b.save_data())==encoded,"entire admitted identity and world exact after JSON")
			var path:String="user://equipment_schema_%d_%s.json"%[radius,recipe]
			check(a.save_file(path).ok,"write actual disk save")
			var disk=A.new();var read:Dictionary=disk.load_file(path)
			check(read.ok and C.bytes(disk.save_data())==encoded,"actual disk read exact "+str(read))
			var bad:Dictionary=parsed.duplicate(true);bad.enemy_placement.support_witness.raw_full_footprint.bytes_hex="00"+str(bad.enemy_placement.support_witness.raw_full_footprint.bytes_hex).substr(2)
			if C.bytes(bad.enemy_placement)==C.bytes(parsed.enemy_placement):bad.enemy_placement.support_witness.raw_full_footprint.bytes_hex="ff"+str(bad.enemy_placement.support_witness.raw_full_footprint.bytes_hex).substr(2)
			check(not A.new().load_data(bad).ok,"changed raw-byte witness rejected exactly")
			rows.append({"radius":radius,"recipe":recipe,"vegetation":true,"save_bytes":encoded.to_utf8_buffer().size(),"native_float32_encoding":a.source.enemy_placement_result.placement_witness.support_witness.raw_full_footprint.encoding,"disk_exact":read.ok})
			a=null;b=null;disk=null;await process_frame
	var report={"ok":failures.is_empty(),"checks":checks,"failures":failures,"cases":rows,"source_seed":726381,"scope":"full identity, all placement/vegetation witnesses, initial world via real JSON and actual disk; no epsilon/hash weakening"}
	FileAccess.open("res://artifacts/generated_v3_equipment/schema_roundtrip_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("EQUIPMENT_SCHEMA_ROUNDTRIP ",checks," ",failures);quit(0 if failures.is_empty() else 1)
