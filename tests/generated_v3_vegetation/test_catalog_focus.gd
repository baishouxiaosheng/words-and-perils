extends SceneTree
## Transport/focus/paging suite; no terrain or renderer launched by this script.
## An optional native-export pass checks artifacts from test_vegetation.gd.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/generated_v3_vegetation/catalog.gd")
const Focus = preload("res://core/generated_v3_vegetation/focus.gd")
const PublicProjection = preload("res://core/generated_v3_vegetation/projection.gd")
const Fixture = preload("res://tests/generated_v3_vegetation/catalog_fixture.gd")
var checks := 0
var failures: Array = []
var timings: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	checks += 1
	if not value: failures.append(label); printerr("VEGETATION_CATALOG_FAIL ",label)
	return value
func fail_build(input: Dictionary, label: String) -> void:
	Fixture.seal(input.manifest,"vegetation_hash")
	check(not Catalog.build(Fixture.PROFILE,input.source,input.manifest,input.assets).ok,label)
func legacy_context(state: Dictionary, focus: Dictionary = {}) -> Dictionary:
	# Frozen pre-optimization algorithm retained as a byte-equivalence and
	# timing oracle. It deliberately performs the old repeated public checks.
	if not Catalog.validate_world(state).ok: return {}
	var actor: Variant = state.get("actors", {}).get("actor_player")
	if not actor is Dictionary or not actor.get("scene_id") is String or not Catalog.valid_hex(actor.get("hex")): return {}
	var selected := ""; var frozen: Dictionary = {}
	if focus.get("kind") == "vegetation":
		if not Focus.validate_historical(focus, state).is_empty(): return {}
		selected = focus.id; frozen = PublicProjection.frozen_focus(focus)
	for limit in [3, 2, 1]:
		var page := PublicProjection.nearby_page(state, actor.scene_id, actor.hex, PublicProjection.RADIUS, selected, {}, limit)
		if not page.ok: return {}
		page.erase("ok")
		if C.bytes({"frozen_focus":frozen, "vegetation":page}).to_utf8_buffer().size() <= PublicProjection.MAX_BYTES: return page
	return {}
func run() -> void:
	var input := Fixture.transport()
	var before_input := C.bytes(input)
	var built := Catalog.build(Fixture.PROFILE,input.source,input.manifest,input.assets)
	if not check(built.ok,"strict synthetic transport builds; not physical admission"):
		printerr(built); finish(); return
	var state := Fixture.world(input,built.catalog)
	if not check(Catalog.validate_world(state).ok,"catalog matches immutable composed world"):
		printerr(Catalog.validate_world(state)); finish(); return
	check(C.bytes(input)==before_input,"catalog build never mutates manifest, assets or upstream identity")
	check(built.catalog.source_identity.source_runtime_hash==input.source.runtime_hash and built.catalog.source_identity.source_runtime_hash!=state.generated_world.runtime_hash,"runtime binding is upstream and noncircular")
	var id: String = input.manifest.plants[0].id
	var before := C.bytes(state)
	var reference := Focus.make_reference(id,state)
	var resolved := Focus.resolve(reference,state)
	if not check(resolved.ok,"root plant resolves exact immutable focus"):
		printerr(resolved); finish(); return
	var focus: Dictionary = resolved.focus
	check(Focus.validate_historical(focus,state).is_empty(),"frozen vegetation history validates")
	check(focus.kind=="vegetation" and focus.entity_revision==0 and focus.catalog_version==Focus.VERSION,"vegetation has own kind, fixed revision and focus version")
	check(C.bytes(focus.facts.descriptor)==C.bytes(built.catalog.entries[id]),"one compact descriptor freezes exact row/asset/biome/transform")
	check(C.bytes(Focus.make_reference(id,state,[int(reference.hex[0])+1,reference.hex[1]]))==C.bytes(reference),"canopy overhang cannot relabel root identity")
	check(Focus.make_reference(id,state,[0.5,0]).is_empty(),"malformed click hint fails closed")
	check(not focus.facts.selection_is_action and not focus.facts.has("custody_witness") and not focus.facts.has("item"),"selection grants no turn, custody, harvest or cover")
	var projected := PublicProjection.frozen_focus(focus)
	var context := PublicProjection.context(state,focus)
	var combined := PublicProjection.resolve_context(reference,state)
	check(combined.ok and C.bytes(combined.focus)==C.bytes(focus) and C.bytes(combined.context)==C.bytes(context),"single-validation combined resolution retains exact full focus and context")
	check(C.bytes(context)==C.bytes(legacy_context(state,focus)),"optimized context is byte-identical to pre-optimization algorithm")
	check(C.bytes(PublicProjection.context(state))==C.bytes(legacy_context(state)),"unselected context remains byte-identical")
	check(not context.is_empty() and context.returned<=3,"selected context contains a bounded nearby summary page")
	check(C.bytes({"frozen_focus":projected,"vegetation":context}).to_utf8_buffer().size()<=2048,"selected-plus-nearby combined vegetation request contribution <=2KiB")
	check(C.bytes(projected.facts.descriptor)==C.bytes(focus.facts.descriptor),"selected compact descriptor appears intact in frozen_focus")
	check(not C.bytes(context).contains("row_hash") and not C.bytes(context).contains(id+"\":") and not C.bytes(projected).contains("root_footprint") and not C.bytes(projected).contains("secret_cell_note"),"context has summaries only and requests have no polygons or private cells")
	for row in context.entries: check(row.id!=id and C.exact_fields(row,["id","hex","asset_id"]),"selected ID is excluded from bounded summaries")
	check(C.bytes(state)==before,"all selection/projection helpers are read-only")
	var wire_state: Dictionary = JSON.parse_string(C.bytes(state))
	var wire_ref: Dictionary = JSON.parse_string(C.bytes(reference))
	var wire_focus: Dictionary = JSON.parse_string(C.bytes(focus))
	check(Catalog.validate_world(wire_state).ok and Focus.resolve(wire_ref,wire_state).ok and Focus.validate_historical(wire_focus,wire_state).is_empty(),"integral JSON floats preserve catalog/reference/history")
	check(C.bytes(PublicProjection.frozen_focus(wire_focus))==C.bytes(projected),"JSON-normalized frozen model facts are exact")
	var wire_combined := PublicProjection.resolve_context(wire_ref,wire_state)
	check(wire_combined.ok and C.bytes(wire_combined)==C.bytes(combined),"combined resolution remains exact across integral JSON transport")
	for field in Focus.REF_FIELDS:
		var bad := reference.duplicate(true)
		bad[field] = [99,99] if field=="hex" else 1 if field=="entity_revision" else "wrong"
		check(not Focus.resolve(bad,state).ok,"reference tamper rejected: "+field)
		check(not PublicProjection.resolve_context(bad,state).ok,"combined path rejects reference tamper: "+field)
	for revision in [-1,0.5,"0",false]:
		var bad := reference.duplicate(true); bad.entity_revision=revision
		check(not Focus.resolve(bad,state).ok,"revision must be integer zero: "+str(revision))
		check(not PublicProjection.resolve_context(bad,state).ok,"combined revision gate remains strict: "+str(revision))
	var extra := reference.duplicate(true); extra["harvest"]=true
	check(not Focus.resolve(extra,state).ok,"unknown reference capability rejected")
	check(not PublicProjection.resolve_context(extra,state).ok,"combined path rejects unknown reference capability")
	for field in Focus.FACT_FIELDS:
		var bad := focus.duplicate(true)
		if field=="selection_is_action": bad.facts[field]=true
		elif field=="scene_id": bad.facts[field]="wrong"
		else: bad.facts[field]["unknown"]=true
		check(not Focus.validate_historical(bad,state).is_empty(),"historical fact exactness: "+field)
		check(PublicProjection.context(state,bad).is_empty(),"optimized context preserves exact historical gate: "+field)
	var changed := state.duplicate(true)
	changed.turn=5; changed.state_version=5; changed.actors.actor_player.hex=[99,99]; changed.flags["note"]="changed"
	check(Focus.validate_historical(focus,changed).is_empty(),"unrelated turn/player/flags never revise vegetation history")
	for field in ["profile","source_contract","content_hash","geometry_hash","placement_hash","effective_navigation_hash","vegetation_base_runtime_hash","vegetation_profile","vegetation_hash","vegetation_catalog_hash"]:
		var bad := state.duplicate(true); bad.generated_world[field]="wrong"
		check(not Catalog.validate_world(bad).ok,"world binding exact: "+field)
		check(PublicProjection.context(bad,focus).is_empty() and not PublicProjection.resolve_context(reference,bad).ok,"operation-local reuse cannot bypass world binding: "+field)
	for field in ["actors","items","scenes"]:
		var bad := state.duplicate(true); bad[field][id]={"id":id}
		check(not Catalog.validate_world(bad).ok,"vegetation identity collision rejected: "+field)
	for invalid_actor in [{}, {"scene_id":"missing_scene","hex":[0,0]}, {"scene_id":"test_scene","hex":[0.5,0]}]:
		var malformed := state.duplicate(true); malformed.actors.actor_player=invalid_actor
		check(PublicProjection.context(malformed,focus).is_empty() and not PublicProjection.resolve_context(reference,malformed).ok,"single-validation context preserves actor/scope gates")
	var bad_state := state.duplicate(true); bad_state.hexes.values()[0]["id"]=id
	check(not Catalog.validate_world(bad_state).ok,"vegetation cannot collide with cell identity")
	bad_state=state.duplicate(true); bad_state.hexes.values()[0]["ocean"]=true
	check(not Catalog.validate_world(bad_state).ok,"world root must remain dry")
	bad_state=state.duplicate(true); bad_state.hexes.values()[0]["biome"]="jungle"
	check(not Catalog.validate_world(bad_state).ok,"declared biome must match exact root cell")
	bad_state=state.duplicate(true); bad_state.scenes[false]={}
	check(not Catalog.validate_world(bad_state).ok,"malformed scene keys fail before typed lookup")
	bad_state=state.duplicate(true); bad_state.hexes["bad"]=[]
	check(not Catalog.validate_world(bad_state).ok,"malformed cell values fail without runtime exception")
	bad_state=state.duplicate(true); bad_state.scenes.other={"id":"other"}; bad_state.scene_hexes={"other":state.hexes.duplicate(true)}
	for row in bad_state.scene_hexes.other.values(): row.scene_id="other"
	check(not Catalog.validate_world(bad_state).ok,"ambiguous scene roots cannot silently choose one")
	var detached := Catalog.descriptor(id,state)
	detached.position[0]+=1
	check(C.bytes(Catalog.descriptor(id,state))==C.bytes(built.catalog.entries[id]),"returned compact descriptor is detached from authority")
	for field in ["biome","asset_id","habit","row_hash","full_sha256","far_sha256"]:
		var bad:Dictionary = built.catalog.duplicate(true); bad.entries[id][field]="wrong"; Fixture.seal(bad,"catalog_hash")
		check(not Catalog.validate(bad).ok,"invalid compact descriptor value rejected: "+field)
	var wrong_support:Dictionary = built.catalog.duplicate(true); wrong_support.entries[id].root_support["unsupported"]=true; Fixture.seal(wrong_support,"catalog_hash")
	check(not Catalog.validate(wrong_support).ok,"unknown compact root support rejected")
	var bad_catalog: Dictionary = built.catalog.duplicate(true); bad_catalog.entries[id].position[0]+=0.125; Fixture.seal(bad_catalog,"catalog_hash")
	bad_state=state.duplicate(true); bad_state.generated_world.vegetation_entity_catalog=bad_catalog
	check(Catalog.validate(bad_catalog).ok and not Catalog.validate_world(bad_state).ok,"self-rehashed transport does not replace the world's admitted catalog binding")
	for field in ["unsupported", "harvestable", "custody"]:
		bad_catalog=built.catalog.duplicate(true); bad_catalog.entries[id][field]=true; Fixture.seal(bad_catalog,"catalog_hash")
		check(not Catalog.validate(bad_catalog).ok,"unknown descriptor field rejected even after rehash: "+field)
	bad_catalog=built.catalog.duplicate(true); bad_catalog["unsupported"]=true; Fixture.seal(bad_catalog,"catalog_hash")
	check(not Catalog.validate(bad_catalog).ok,"unknown catalog field rejected after rehash")
	for field in ["source_identity","vegetation_identity"]:
		bad_catalog=built.catalog.duplicate(true); bad_catalog[field]["unsupported"]=true; Fixture.seal(bad_catalog,"catalog_hash")
		check(not Catalog.validate(bad_catalog).ok,"unknown binding field rejected after rehash: "+field)
	var polluted := focus.duplicate(true); polluted["secret"]="strip"; polluted.facts["secret"]="strip"; polluted.facts.descriptor["secret"]="strip"; polluted.facts.descriptor.root_support["secret"]="strip"
	check(C.bytes(PublicProjection.frozen_focus(polluted))==C.bytes(projected),"nested projection whitelist strips unknown fields")
	for field in ["source_hash","geometry_hash","placement_hash","navigation_hash","asset_catalog_hash"]:
		var bad := input.duplicate(true); bad.manifest[field]=Fixture.digest("changed:"+field); bad.manifest.context_hash=C.digest(Catalog.pick(bad.manifest,Catalog.CONTEXT_FIELDS)); fail_build(bad,"source-bound manifest rejects rehashed "+field)
	var bad_input := input.duplicate(true); bad_input.manifest.plants[0]["unsupported"]=true; Fixture.seal(bad_input.manifest.plants[0],"row_hash"); fail_build(bad_input,"unknown full row rejected after both hashes rebuilt")
	bad_input=input.duplicate(true); bad_input.manifest["unsupported"]=true; fail_build(bad_input,"unknown full manifest field rejected")
	bad_input=input.duplicate(true); bad_input.manifest.plants[0].position[0]+=0.1; Fixture.seal(bad_input.manifest.plants[0],"row_hash"); fail_build(bad_input,"non-q12 transform rejected even after rehash")
	bad_input=input.duplicate(true); bad_input.manifest.plants[0].id=bad_input.manifest.plants[1].id; Fixture.seal(bad_input.manifest.plants[0],"row_hash"); fail_build(bad_input,"duplicate stable plant IDs rejected")
	bad_input=input.duplicate(true); bad_input.assets.assets.shrub.full_sha256=Fixture.digest("wrong_mesh"); Fixture.seal(bad_input.assets,"catalog_hash"); fail_build(bad_input,"rehash asset catalog cannot change admitted native mesh binding")
	var empty := Fixture.transport(0); var empty_built := Catalog.build(Fixture.PROFILE,empty.source,empty.manifest,empty.assets)
	check(empty_built.ok and Catalog.validate_world(Fixture.world(empty,empty_built.catalog)).ok,"empty native-valid vegetation population is permitted")
	test_large()
	test_native_exports()
	finish()
func test_large() -> void:
	var input := Fixture.transport(1024)
	var built := Catalog.build(Fixture.PROFILE,input.source,input.manifest,input.assets)
	if not check(built.ok,"full 1024-record transport accepted within catalog/manifest bounds"):
		printerr(built); return
	var state := Fixture.world(input,built.catalog)
	var before := C.bytes(state)
	var selected: String = input.manifest.plants[0].id
	var started: int = Time.get_ticks_usec()
	var checked := Catalog.validate_world(state)
	timings["validate_world_1024_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	check(checked.ok,"1024-row validation benchmark succeeds")
	started = Time.get_ticks_usec()
	var selected_ref := Focus.make_reference(selected,state)
	timings["make_reference_1024_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var selected_focus := Focus.resolve(selected_ref,state)
	timings["resolve_1024_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	check(selected_focus.ok,"1024-row focus benchmark succeeds")
	started = Time.get_ticks_usec()
	var table := Focus.references_for_admitted_world(state)
	timings["all_references_1024_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	check(table.ok and table.references.size()==1024 and C.bytes(table.references[selected])==C.bytes(selected_ref),"all compact renderer headers need only one full validation")
	for row in input.manifest.plants:
		check(C.exact_fields(table.references[row.id],Focus.REF_FIELDS) and C.bytes(table.references[row.id].hex)==C.bytes(row.hex),"batch reference keeps exact root and complete immutable header")
	var frozen: Dictionary = selected_focus.focus
	started=Time.get_ticks_usec()
	var context := PublicProjection.context(state,frozen)
	timings["context_refresh_1024_ms"]=(Time.get_ticks_usec()-started)/1000.0
	started=Time.get_ticks_usec()
	var baseline := legacy_context(state,frozen)
	timings["legacy_context_1024_ms"]=(Time.get_ticks_usec()-started)/1000.0
	check(C.bytes(context)==C.bytes(baseline),"1024-row optimized context is exactly byte-identical to legacy context")
	started=Time.get_ticks_usec()
	var combined := PublicProjection.resolve_context(table.references[selected],state)
	timings["resolve_context_1024_ms"]=(Time.get_ticks_usec()-started)/1000.0
	check(combined.ok and C.bytes(combined.focus)==C.bytes(frozen) and C.bytes(combined.context)==C.bytes(baseline),"1024-row combined operation is exact and keeps every historical fact")
	check(timings.context_refresh_1024_ms < timings.legacy_context_1024_ms and timings.resolve_context_1024_ms < timings.legacy_context_1024_ms,"one-validation context and complete resolution improve measured legacy latency")
	started=Time.get_ticks_usec()
	var fresh_ref:Dictionary=Focus.make_reference(selected,state)
	var fresh_focus:Dictionary=Focus.resolve(fresh_ref,state)
	var fresh_context:Dictionary=PublicProjection.context(state,fresh_focus.get("focus",{}))
	timings["complete_select_focus_context_1024_ms"]=(Time.get_ticks_usec()-started)/1000.0
	check(fresh_focus.ok and not fresh_context.is_empty(),"complete selected object refresh benchmark succeeds")
	check(not context.is_empty() and context.catalog_total==1024 and context.returned<=3,"1024 catalog contributes at most three nearby summaries")
	check(C.bytes({"frozen_focus":PublicProjection.frozen_focus(frozen),"vegetation":context}).to_utf8_buffer().size()<=2048,"full-1024 selected projection satisfies combined 2KiB cap")
	var seen: Dictionary = {}; var cursor: Dictionary = {}; var total := -1; var pages := 0
	while true:
		var page := PublicProjection.nearby_page(state,"test_scene",[0,0],2,selected,cursor)
		if not check(page.ok,"bounded read-only page resolves"): break
		if total<0: total=page.total
		check(page.catalog_total==1024 and page.total==total and page.returned==page.entries.size() and page.returned<=3 and page.omitted==total-page.returned,"truthful per-page total/returned/omitted at 1024 cap")
		for row in page.entries:
			check(not seen.has(row.id) and row.id!=selected,"pagination returns each scoped root once")
			seen[row.id]=true
		pages+=1
		if page.next_cursor==null: break
		cursor=page.next_cursor
		if pages>342: check(false,"pagination must terminate"); break
	check(seen.size()==total and pages>1,"cursor exhausts the entire nearby root scope without claiming distant absence")
	var first := PublicProjection.nearby_page(state,"test_scene",[0,0],2,selected)
	var next: Dictionary = first.next_cursor
	check(not PublicProjection.nearby_page(state,"test_scene",[1,0],2,selected,next).ok,"cursor cannot change center scope")
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],1,selected,next).ok,"cursor cannot change radius scope")
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],2,"",next).ok,"cursor cannot change excluded selection")
	var altered: Dictionary = next.duplicate(true); altered["unsupported"]=true
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],2,selected,altered).ok,"cursor rejects unknown fields")
	altered=next.duplicate(true); altered.after_id="vegetation:v3:missing"
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],2,selected,altered).ok,"cursor after_id must belong to the exact scope")
	altered=next.duplicate(true); altered.binding=Fixture.digest("other catalog")
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],2,selected,altered).ok,"cursor cannot replace catalog binding")
	var other_state := state.duplicate(true)
	other_state.generated_world.vegetation_entity_catalog.entries[selected].tint=1.125
	Fixture.seal(other_state.generated_world.vegetation_entity_catalog,"catalog_hash")
	other_state.generated_world.vegetation_catalog_hash=other_state.generated_world.vegetation_entity_catalog.catalog_hash
	check(not PublicProjection.nearby_page(other_state,"test_scene",[0,0],2,selected,next).ok,"old cursor rejects another internally self-consistent catalog hash")
	check(not PublicProjection.nearby_page(state,"test_scene",[0,0],3).ok and not PublicProjection.nearby_page(state,"test_scene",[0,0],2,"",{},4).ok,"caller cannot unbound radius or page size")
	check(C.bytes(state)==before,"full-catalog pagination is read-only")
	var extra: Dictionary = built.catalog.entries.values()[0].duplicate(true); extra.id="vegetation:v3:"+input.manifest.context_hash.substr(0,16)+":999_999:0"; extra.hex=[999,999]
	built.catalog.entries[extra.id]=extra; Fixture.seal(built.catalog,"catalog_hash")
	check(not Catalog.validate(built.catalog).ok,"1025th record is rejected even with recomputed catalog digest")
func test_native_exports() -> void:
	var dir := DirAccess.open("res://artifacts/generated_v3_vegetation")
	if dir==null or not FileAccess.file_exists("res://artifacts/generated_v3_vegetation/native_assets.json"):
		print("VEGETATION_NATIVE_EXPORTS not available; native admission integration remains pending")
		return
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/generated_v3_vegetation/native_assets.json"))
	var count := 0
	for file in dir.get_files():
		if not file.begins_with("vegetation_726381_") or not file.ends_with(".json"): continue
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/generated_v3_vegetation/"+file))
		var source := {"source_contract":"native_export_test/v1","content_hash":manifest.source_hash,"geometry_hash":manifest.geometry_hash,"placement_hash":manifest.placement_hash,"effective_navigation_hash":manifest.navigation_hash,"runtime_hash":Fixture.digest("native export runtime")}
		var result := Catalog.build(Fixture.PROFILE,source,manifest,native.catalog)
		check(result.ok,"native admitted manifest/assets compact catalog: "+file)
		if not result.ok: printerr(result)
		count+=1
	print("VEGETATION_NATIVE_EXPORTS checked ",count," prior physical artifacts")
func finish() -> void:
	print("VEGETATION_CATALOG_RESULT ",C.bytes({"checks":checks,"failures":failures,"timings":timings}))
	quit(0 if failures.is_empty() else 1)
