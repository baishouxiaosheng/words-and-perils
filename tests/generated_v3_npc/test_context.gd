extends SceneTree
const Adapter=preload("res://view/generated_v3_npc/adapter.gd")
const Generator=preload("res://core/world_generation_v3/generator.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const ModelView=preload("res://core/ai_gm_rebuilt/model_view.gd")
var checks=0
var failures=[]
var cases=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	DirAccess.make_dir_recursive_absolute("res://artifacts/generated_v3_npc/requests")
	for configuration in [[4,"coastal_range",false],[4,"coastal_range",true],[12,"coastal_range",true],[12,"plateau_hinterland",true]]:
		var radius:int=configuration[0];var recipe:String=configuration[1];var plants:bool=configuration[2]
		var label="r%d_%s_%s"%[radius,recipe,"plants" if plants else "bare"]
		var generated:Dictionary=Generator.generate(726381,radius,recipe)
		var a=Adapter.new();a.feature_options={"vegetation":plants}
		var result:Dictionary=a.start_source(generated.source)
		check(result.ok,label+" source "+str(result))
		if not result.ok:continue
		var state:Dictionary=a.state_copy();var rows:Array=[{"label":"npc","ref":a.npc_reference()},{"label":"item","ref":a.item_reference()}]
		for id in state.generated_world.static_entity_catalog.entries:
			var d:Dictionary=state.generated_world.static_entity_catalog.entries[id]
			for hex in d.supported_hexes:rows.append({"label":d.kind+"_"+str(rows.size()),"ref":a.static_reference(id,hex)})
		if plants:
			var far_id="";var far_distance=-1
			for id in state.generated_world.vegetation_entity_catalog.entries:
				var h:Array=state.generated_world.vegetation_entity_catalog.entries[id].hex
				var q:int=h[0]-state.actors.actor_player.hex[0];var r:int=h[1]-state.actors.actor_player.hex[1]
				var distance=maxi(absi(q),maxi(absi(r),absi(q+r)))
				if distance>far_distance:far_distance=distance;far_id=id
			check(not far_id.is_empty(),label+" vegetation exists")
			if not far_id.is_empty():rows.append({"label":"outer_vegetation","ref":a.vegetation_reference(far_id),"distance":far_distance})
		var maximum=0
		for row in rows:
			var before=C.bytes(a.save_data());check(a.attention(row.ref).ok and C.bytes(a.save_data())==before,label+row.label+" pure selection")
			check(a.begin_intent("x".repeat(4096),row.ref).ok,label+row.label+" full4096-byte goal admitted")
			var request:Dictionary=a.request();var bytes=C.bytes(request).to_utf8_buffer().size();maximum=maxi(maximum,bytes)
			check(not request.is_empty() and bytes<=65536,label+row.label+"64KiB "+str(bytes))
			if request.is_empty():continue
			var facts:Dictionary=request.context.facts;var h:Array=row.ref.hex;var key="%d,%d"%h
			check(facts.hexes.has(key) and facts.scenes[row.ref.scene_id].hex_ids.has(facts.hexes[key].id) and facts.hexes.size()<=62,label+row.label+" exact selected root/support cell")
			check(request.context.goal.to_utf8_buffer().size()==4096,label+row.label+" goal never truncated")
			check(not facts.has("generated_world") and not C.bytes(facts).contains('"allowed_neighbors"') and not C.bytes(facts).contains('"npc_catalog":'),label+row.label+" no whole graph/catalog leak")
			var payload:String=state.generated_world.npc_catalog.entries[a.source.npc_id].facts.values()[0].payload.description
			check(not C.bytes(request).contains(payload),label+row.label+" no unlearned answer")
			FileAccess.open("res://artifacts/generated_v3_npc/requests/"+label+"_"+row.label+".json",FileAccess.WRITE).store_string(C.bytes(request))
			if row.label=="outer_vegetation":
				var bad=a.save_data();bad.engine.pending[a.active_action].focus.extra=true
				var restored=Adapter.new();check(not restored.load_data(bad).ok,label+" malformed typed vegetation pending rejected")
			check(a.cancel().ok,label+row.label+" canceled")
		cases.append({"label":label,"maximum_request_bytes":maximum,"headroom":65536-maximum,"requests":rows.size(),"plants":state.generated_world.get("vegetation_entity_catalog",{}).get("entries",{}).size()})
		var saved=C.bytes(a.save_data());var reload=Adapter.new();var loaded:Dictionary=reload.load_data(JSON.parse_string(saved))
		check(loaded.ok and C.bytes(reload.save_data())==saved,label+" features+catalog exact reload "+str(loaded))
		var restarted=a.restarted();check(restarted.ready().ok and restarted.source.features==a.source.features and restarted.source.identity.runtime_hash==a.source.identity.runtime_hash,label+" restart exact composition")
	FileAccess.open("res://artifacts/generated_v3_npc/context_report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"ok":failures.is_empty()},"\t"))
	print("NPC_CONTEXT ",checks," ",failures);quit(0 if failures.is_empty() else 1)
