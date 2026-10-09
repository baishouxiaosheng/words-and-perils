extends SceneTree
const Adapter = preload("res://view/generated_v3_adventure/adapter.gd")
const Source = preload("res://view/generated_v3_adventure/source.gd")
const PublicProjection = preload("res://view/generated_v3_adventure/projection.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy = preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const ModelView = preload("res://core/ai_gm_rebuilt/model_view.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL "+message)
func roundtrip(adapter: RefCounted, label_: String) -> void:
	var saved: Dictionary = adapter.save_data(); var exact := C.bytes(saved)
	var loaded := Adapter.new(); var result := loaded.load_data(JSON.parse_string(exact))
	check(result.ok,"exact "+label_+" reload admitted")
	if result.ok:
		check(C.bytes(loaded.save_data()) == exact,"exact "+label_+" reload retains source, geometry, state, plan, focus, receipts and RNG")
		check(loaded.phase() == adapter.phase(),label_+" phase retained")
func complete(adapter: RefCounted, kind: String, focus: Dictionary = {}) -> bool:
	return adapter.begin_intent(adapter.sample_goal(kind,focus),focus).ok and adapter.prepare_fixture().ok and adapter.roll_once().ok and adapter.stage().ok and adapter.commit().ok
func reject_load(adapter: RefCounted, corrupt: Dictionary, label_: String) -> void:
	var before := C.bytes(adapter.save_data())
	check(not adapter.load_data(corrupt).ok and C.bytes(adapter.save_data()) == before,label_+" rejects atomically")
func run() -> void:
	var started := Time.get_ticks_msec()
	var generated := Generator.generate(726381,4,"coastal_range")
	check(generated.ok,"frozen V3 generator fixture available")
	if not generated.ok: finish(); return
	var raw: Dictionary = generated.source; var exact_source := C.bytes(raw)
	var adapter := Adapter.new(raw)
	check(adapter.ready().ok,"V3 exact geometry admits playable authority")
	if not adapter.ready().ok: printerr(adapter.ready()); finish(); return
	var state := adapter.state_copy(); var start: Array = state.actors.actor_player.hex
	var start_key: String = "%d,%d" % start
	check(adapter.engine.rule_id() == "generated_v3_exploration_release/v1","new explicit rule identity")
	check(C.bytes(adapter.source.data) == exact_source and raw.scope.gameplay_admitted == false,"admission preserves raw source and prototype provenance exactly")
	check(state.generated_world.source_contract == Source.ID and state.generated_world.source_schema == Generator.ID and state.generated_world.renderer_profile == "structured_v1","V3 identity never masquerades as V2")
	check(state.actors.keys() == ["actor_player"] and state.items.is_empty() and not state.has("physical_catalog"),"one generic traveler, no unsupported objects or effects")
	check(adapter.source.spawn_component.size() >= 7 and adapter.source.navigation.allowed[start_key].size() >= 2,"spawn has sufficiently connected dry support")
	var restart: RefCounted = adapter.restarted()
	check(restart.ready().ok and restart.state_copy().actors.actor_player.hex == start and C.bytes(restart.source.identity) == C.bytes(adapter.source.identity),"same V3 source rebuilds deterministic spawn and full identity")
	restart = null
	check(Source.BIOME_TERRAIN.dry_steppe == "grass" and Policy.COSTS[Source.BIOME_TERRAIN.dry_steppe] == 1,"dry_steppe uses explicit versioned legal terrain mapping")
	var key: String = adapter.source.navigation.allowed[start_key][0]
	var cell: Dictionary = state.hexes[key]; var target: Array = [cell.q,cell.r]
	var focus := adapter.tile_reference(target)
	var before := C.bytes(adapter.save_data())
	for i in range(3):
		var selected := adapter.attention(focus)
		check(selected.ok and selected.readonly,"tile selection is read only")
		for field in Source.DESCRIPTORS: check(selected.focus.facts[field] == raw.cells[key][field],"focus retains exact V3 "+field)
		adapter.movement_preview(target); adapter.render_state(); adapter.authority_text(); adapter.journal_entries()
	check(C.bytes(adapter.save_data()) == before,"repeated views, selection, previews do not change any facts, counters or RNG")
	check(not adapter.attention({"world_id":"other","kind":"tile","id":cell.id,"hex":target}).ok,"foreign map selection rejected")
	check(not adapter.attention({"world_id":state.world_id,"kind":"tree","id":"tree","hex":target}).ok,"unsupported objects cannot gain an action by selection")
	var projected := ModelView.facts(state,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]},focus)
	check(PublicProjection.active(state) and projected.context_scope.schema_version == PublicProjection.ID and projected.hexes.size() <= 62,"V3 routes explicitly to bounded projection")
	check(not projected.has("rng") and not projected.has("generated_world") and not projected.has("generated_v3_source") and not projected.has("receipts"),"model view excludes raw source, RNG and private history")
	var bad_projection := state.duplicate(true); bad_projection.generated_world.projection_id = "invalid"
	check(PublicProjection.active(bad_projection) and ModelView.facts(bad_projection,{"npc_secret_allowlist":[],"public_flag_ids":[]}).is_empty(),"malformed V3 identity fails closed instead of general unbounded context")
	check(adapter.begin_intent("看看附近，能走就走吧",focus).ok,"free text creates pending intent")
	check(adapter.phase() == "awaiting_assessment" and not adapter.fixture_available() and not adapter.prepare_fixture().ok and not adapter.roll_once().ok,"free text never guesses move, target or authored assessment")
	check(C.bytes(adapter.state_copy()) == C.bytes(state),"unassessed free text cannot mutate facts")
	roundtrip(adapter,"free pending")
	check(adapter.cancel().ok,"unassessed free text may cancel")
	roundtrip(adapter,"canceled")
	var preview := adapter.movement_preview(target)
	check(preview.ok and preview.cost == Policy.COSTS[cell.terrain],"dry edge uses unchanged destination terrain cost")
	check(adapter.begin_intent(adapter.sample_goal("move",focus),focus).ok,"explicit move starts")
	var request := adapter.request()
	check(C.bytes(request).to_utf8_buffer().size() <= Adapter.MAX_REQUEST_BYTES and request.context.facts.hexes.size() <= 62,"V3 model request respects byte and cell bounds")
	check(request.contract.resolver_ids == ["generated_v3_move_v1","generated_v3_observe_v1","generated_v3_rest_v1"],"exact closed three-action resolver registry")
	check(not adapter.import_reply({"phase":"resolution","state_patch":{"actors":{}}}).ok,"arbitrary model patch rejected")
	roundtrip(adapter,"pending")
	check(adapter.prepare_fixture().ok and adapter.phase() == "ready_roll","exact authored fixture admitted with honest provenance")
	check(adapter.action_copy().assessment.provenance.provider == Adapter.AUTHOR and not adapter.action_copy().assessment.provenance.live,"fixture never claims model or external call")
	roundtrip(adapter,"ready")
	check(adapter.roll_once().ok and adapter.phase() == "rolled","assessed move locks once")
	before = C.bytes(adapter.save_data())
	check(adapter.roll_once().ok and C.bytes(adapter.save_data()) == before,"repeated lock has no reroll or RNG changes")
	check(not adapter.cancel().ok,"locked action cannot be canceled")
	roundtrip(adapter,"locked")
	check(adapter.stage().ok and C.bytes(adapter.state_copy()) == C.bytes(state),"stage remains a preview")
	roundtrip(adapter,"staged")
	check(adapter.commit().ok,"staged move commits")
	var moved := adapter.state_copy()
	check(moved.actors.actor_player.hex == target and moved.actors.actor_player.stamina.current == 8-preview.cost and moved.turn == 1 and moved.state_version == 1,"move commits exact route charge and one turn")
	check(adapter.last_feedback == "已走到（%d，%d），消耗%d点体力。" % [target[0],target[1],preview.cost],"move feedback reports only actual committed position and charge")
	before = C.bytes(adapter.save_data())
	check(adapter.commit().get("already_committed",false) and C.bytes(adapter.save_data()) == before,"adapter duplicate commit is exactly once")
	roundtrip(adapter,"committed move")
	check(complete(adapter,"observe",adapter.tile_reference(target)),"assessed observe commits")
	check(adapter.state_copy().flags.observations == 1 and adapter.state_copy().flags.last_observed_cell == key,"observe persists exact target")
	var biome_labels := {"grassland":"草原","dry_steppe":"干旱草原","desert":"荒漠","temperate_forest":"温带森林","jungle":"密林","alpine":"高山带","wetland":"湿地","ocean":"海域"}
	check(adapter.last_feedback == "已观察（%d，%d）：%s。观察记录已保存。" % [target[0],target[1],biome_labels[raw.cells[key].biome]],"observe feedback reports exact committed source biome")
	var missing_stamina: int = 8-int(adapter.state_copy().actors.actor_player.stamina.current)
	check(complete(adapter,"rest"),"assessed rest commits")
	check(adapter.state_copy().actors.actor_player.stamina.current == 8-maxi(0,missing_stamina-2),"rest recovery bounded by two and max stamina")
	check(adapter.last_feedback == "休息后恢复%d点体力，当前%d/%d。" % [mini(2,missing_stamina),adapter.state_copy().actors.actor_player.stamina.current,8],"rest feedback reports actual restored amount and current pool")
	roundtrip(adapter,"committed observations/rest")
	var historical: Dictionary = adapter.engine.save_data().receipts.values()[0].attention_focus
	var view := ModelView.focus_view(historical,projected)
	check(view.facts.source_cell_version == Source.CELL_VERSION and view.facts.biome == raw.cells[key].biome and view.facts.elevation == raw.cells[key].elevation,"historical focus preserves V3 descriptor whitelist")
	# Explicit manual assessment of free text is allowed, only after correct facts.
	var current_focus := adapter.tile_reference(target)
	check(adapter.begin_intent("我想仔细看看这里的地形。",current_focus).ok,"new free-text observation waits")
	var outgoing := adapter.request(); var facts: Dictionary = outgoing.context.facts
	var reply := {"schema_version":"ai_gm_assessment/v1","action_id":outgoing.action_id,"state_version":outgoing.state_version,"context_hash":outgoing.context_hash,"narration":"观察当前地格。","interpretation":"根据用户完整意图评估当前位置的观察。","resolver_id":"generated_v3_observe_v1","bindings":{"actor_id":"actor_player","target_hex":target},"components":[{"id":"observe","parameters":{"A":3,"D":1,"P":0},"disposition":"possible","fact_ref_ids":["actor","target"]}],"fact_refs":[{"id":"actor","path":"/actors/actor_player","expected":facts.actors.actor_player},{"id":"target","path":"/hexes/"+key,"expected":facts.hexes[key]}],"provenance":{"provider":"test_manual_reply","live":false,"kind":"model_reply"}}
	check(adapter.import_reply(reply).ok and adapter.phase() == "ready_roll","free text proceeds only with valid bounded assessment")
	check(adapter.cancel().ok,"ready assessment may legally cancel")
	# Cheap malformed admission probes fail before building renderer data.
	for field in ["schema_version","recipe_version","content_hash"]:
		var bad := raw.duplicate(true); bad[field] = "invalid"
		check(not Source.validate_source(bad).ok,"invalid "+field+" rejected")
	var altered := raw.duplicate(true); altered.cells[start_key].elevation += 1.0/4096.0
	check(not Source.validate_source(altered).ok,"stale content hash rejected")
	var unsigned := altered.duplicate(true); unsigned.erase("content_hash"); altered.content_hash = C.digest(unsigned)
	check(not Source.validate_source(altered).ok,"resigned source edit fails exact reproduction")
	altered = raw.duplicate(true); altered.board_radius = 24
	check(not Source.validate_source(altered).ok,"radius24 rejected instead of clamped")
	var invalid_profile := Adapter.new(raw,"alternative_b")
	check(not invalid_profile.ready().ok and invalid_profile.state_copy().is_empty(),"unsupported profile has no fallback or inherited world")
	var corrupt := adapter.save_data(); corrupt.geometry_hash = "0".repeat(64); reject_load(adapter,corrupt,"changed geometry")
	corrupt = adapter.save_data(); corrupt.renderer_profile = "alternative_b"; reject_load(adapter,corrupt,"changed renderer profile")
	corrupt = adapter.save_data(); corrupt.identity.runtime_hash = "different"; reject_load(adapter,corrupt,"changed runtime identity")
	corrupt = adapter.save_data(); corrupt.engine.state.hexes[start_key].terrain = "road"; reject_load(adapter,corrupt,"cheaper forged terrain")
	corrupt = adapter.save_data(); corrupt.engine.rule_id = "coast_release/v1"; reject_load(adapter,corrupt,"legacy rule selection")
	corrupt = adapter.save_data(); corrupt.schema_version = "generated_adventure_save/v2"; reject_load(adapter,corrupt,"legacy namespace envelope")
	check(not adapter.load_data(adapter.engine.save_data()).ok,"raw engine save is never migrated")
	check(adapter.default_save_path() == "user://generated_v3_adventure_v1.json" and adapter.default_request_path() == "user://generated_v3_adventure_request_v1.json","new default save/request namespaces")
	for path in ["user://generated_adventure_v1.json","user://generated_adventure_v2.json","user://generated_inventory_v1.json","user://r24_coast_adventure_save.json"]:
		var hash_before := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(not adapter.save_file(path).ok and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == hash_before,"legacy destination preserved "+path)
	for path in ["user://r24_coast_adventure_request.json","user://generated_adventure_request_v1.json"]:
		var hash_before := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(not adapter.export_request(path).ok and (FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent") == hash_before,"legacy request destination preserved "+path)
	var arbitrary_path := "user://generated_v3_test_arbitrary.json"
	var arbitrary := FileAccess.open(arbitrary_path,FileAccess.WRITE); arbitrary.store_string('{"note":"keep this unrelated JSON"}'); arbitrary.close()
	var arbitrary_hash := FileAccess.get_sha256(arbitrary_path)
	check(not adapter.export_request(arbitrary_path).ok and FileAccess.get_sha256(arbitrary_path) == arbitrary_hash,"export never overwrites arbitrary existing JSON")
	DirAccess.remove_absolute(arbitrary_path)
	var request_path := "user://generated_v3_test_request.json"
	check(adapter.export_request(request_path).ok and adapter.export_request(request_path).ok,"recognized V3 narration request may be exported repeatedly")
	check(not adapter.save_file(adapter.default_request_path()).ok and not adapter.export_request(adapter.default_save_path()).ok,"save and request destinations cannot collide")
	check(adapter.save_file("user://generated_v3_test_committed.json").ok,"atomic V3 save writes own namespace")
	var loaded := Adapter.new()
	check(loaded.load_file("user://generated_v3_test_committed.json").ok and C.bytes(loaded.save_data()) == C.bytes(adapter.save_data()),"actual file roundtrip retains exact committed/canceled state")
	if loaded.ready().ok:
		var frozen: Dictionary = loaded.engine.save_data().receipts.values()[0].attention_focus
		var history_view := ModelView.historical_focus(frozen,{"npc_secret_allowlist":[],"public_flag_ids":["observations","last_observed_cell"]})
		check(history_view.facts.source_cell_version == Source.CELL_VERSION,"fresh reload dispatches historical V3 cell version")
		for field in Source.DESCRIPTORS: check(history_view.facts[field] == raw.cells[key][field],"fresh reload historical focus retains exact "+field)

	print("V3_ADAPTER_METRICS ",JSON.stringify({"elapsed_ms":Time.get_ticks_msec()-started,"source_bytes":exact_source.to_utf8_buffer().size(),"request_bytes":C.bytes(request).to_utf8_buffer().size(),"start":start,"component_size":adapter.source.spawn_component.size(),"geometry_hash":adapter.source.identity.geometry_hash}))
	finish()
func finish() -> void:
	print("V3 ADAPTER ",checks-failures.size(),"/",checks)
	quit(0 if failures.is_empty() else 1)
