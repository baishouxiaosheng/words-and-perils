extends SceneTree
## Pass actual frozen V21 save paths after --. Inputs are read only and are not
## bundled as duplicate raw saves in the release; report hashes prove the input.
const Old=preload("res://view/generated_v3_enemy/adapter.gd")
const New=preload("res://view/generated_v3_equipment/adapter.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
var checks=0
var failures:Array=[]
var rows:Array=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label_:String)->bool:
	checks+=1
	if not value:failures.append(label_);printerr("V21_COMPATIBILITY_FAIL ",label_)
	return value
func run()->void:
	var paths:PackedStringArray=OS.get_cmdline_user_args()
	if not check(paths.size()>=2,"explicit actual frozen V21 input files supplied"):finish();return
	for path in paths:
		if not check(FileAccess.file_exists(path),"frozen V21 input exists"):continue
		var hash_:String=FileAccess.get_sha256(path)
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not check(value is Dictionary and value.get("profile")=="generated_v3_village_enemy/v1","input is actual V21 profile"):continue
		var old=Old.new();var loaded:Dictionary=old.load_file(path)
		if not check(loaded.ok,"frozen V21 save admitted by preserved adapter "+str(loaded)):continue
		check(C.bytes(old.save_data())==C.bytes(value),"entire historic V21 save stays exact")
		check(old.state_copy().turn>0,"actual committed pre-slice history present")
		var gear=New.new();var rejected:Dictionary=gear.load_data(value)
		check(not rejected.ok and not gear.ready().ok,"equipment adapter never silently upgrades V21 progress")
		check(FileAccess.get_sha256(path)==hash_,"historic save bytes untouched after both admissions")
		rows.append({"filename":path.get_file(),"input_sha256":hash_,"bytes":FileAccess.get_file_as_bytes(path).size(),"turn":old.state_copy().turn,"profile":old.source.identity.profile,"exact":true})
	finish()
func finish()->void:
	FileAccess.open("res://artifacts/generated_v3_equipment/preserved_v21_report.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":rows,"scope":"read-only actual frozen pre-slice V21 files through current preserved adapter; no automatic migration","network_calls":0},"\t"))
	print("PRESERVED_V21_FILES ",checks," ",failures);quit(0 if failures.is_empty() else 1)
