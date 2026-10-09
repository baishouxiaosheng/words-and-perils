extends SceneTree
## Static transport/focus tests use a frozen admitted manifest, not a terrain build.
## No placement generation, renderer, terrain adapter or credential is loaded.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/source_entities/static_catalog.gd")
const Focus = preload("res://core/source_entities/static_focus.gd")
const PublicProjection = preload("res://core/source_entities/static_projection.gd")
const MANIFEST_PATH := "res://tests/source_entities/fixtures/static_placement_v1.json"
const PROFILE := "unit_static_village/v1"
const CELL_FIELDS := ["id", "scene_id", "q", "r", "terrain", "biome", "source_cell_version", "ground_blocked", "air_blocked", "all_blocked"]
var checks := 0
var failures: Array = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("STATIC_ENTITY_FAIL ", label)

func manifest_fixture() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return parsed if parsed is Dictionary else {}

func inventory_identity(manifest: Dictionary) -> Dictionary:
	return {"source_contract":"unit_source/v1","content_hash":manifest.source_hash,"geometry_hash":manifest.geometry_hash,"runtime_hash":"3".repeat(64),"entity_catalog":{"entries":{"item_travel_bundle":{"id":"item_travel_bundle","kind":"item"}}}}

func fixture(manifest: Dictionary) -> Dictionary:
	var base := inventory_identity(manifest)
	var built := Catalog.build(PROFILE, base, manifest)
	if not built.get("ok", false):
		printerr("STATIC_BUILD_DIAGNOSTIC ", C.bytes(built))
		var digest_payload: Dictionary = manifest.duplicate(true); digest_payload.erase("placement_hash")
		printerr("STATIC_SHAPE_DIAGNOSTIC ", C.bytes({"shape":Catalog._manifest_shape(manifest, base),"context_match":C.digest(Catalog.pick(manifest, Catalog.CONTEXT_FIELDS)) == manifest.context_hash,"placement_match":C.digest(digest_payload) == manifest.placement_hash,"plaza":Catalog._plaza(manifest.plaza),"base_graph":Catalog._graph(manifest.base_allowed_neighbors),"effective_graph":Catalog._graph(manifest.allowed_neighbors)}))
	check(built.get("ok", false), "exact admitted physical manifest builds static catalog")
	if not built.get("ok", false): return {}
	var state := {"world_id":"unit_static_world","turn":5,"state_version":5,"actors":{"actor_player":{"id":"actor_player","hex":[99,99],"scene_id":"unit_scene","inventory":["item_travel_bundle"]}},"items":{"item_travel_bundle":{"id":"item_travel_bundle","owner_actor_id":"actor_player","custody_revision":2}},"scenes":{"unit_scene":{"id":"unit_scene"}},"hexes":{},"flags":{},"generated_world":{"source_contract":base.source_contract,"content_hash":base.content_hash,"geometry_hash":base.geometry_hash,"base_runtime_hash":"2".repeat(64),"inventory_runtime_hash":base.runtime_hash,"runtime_hash":"4".repeat(64),"static_entity_profile":PROFILE,"static_entity_catalog_hash":built.catalog.catalog_hash,"static_entity_catalog":built.catalog,"placement_profile":manifest.profile_id,"placement_hash":manifest.placement_hash,"placement_context_hash":manifest.context_hash,"entity_catalog":base.entity_catalog}}
	var keys: Array = manifest.allowed_neighbors.keys(); keys.append("99,99")
	for key in keys:
		var parts: PackedStringArray = key.split(",")
		state.hexes[key] = {"id":"hex_" + key.replace(",", "_"),"scene_id":"unit_scene","q":int(parts[0]),"r":int(parts[1]),"terrain":"grass","biome":"dry_steppe","source_cell_version":"generated_v3_cell/v1","ground_blocked":false,"air_blocked":false,"all_blocked":false,"secret_cell_note":"not public"}
	return C.normalized(state)

func rehash_manifest(manifest: Dictionary) -> void:
	manifest.erase("placement_hash")
	manifest.placement_hash = C.digest(manifest)

func rehash_catalog(catalog: Dictionary) -> void:
	catalog.erase("catalog_hash")
	catalog.catalog_hash = C.digest(catalog)

func changed_build_fails(manifest: Dictionary, label: String) -> void:
	rehash_manifest(manifest)
	check(not Catalog.build(PROFILE, inventory_identity(manifest), manifest).ok, label)

func run() -> void:
	check(FileAccess.get_sha256(MANIFEST_PATH) == "5a6fb99fa7b02afdd0e14e17ad984e8c2ef036e5b6f1b677f68930bf7b6b5d2e", "self-contained accepted fixture retains exact source bytes")
	var manifest := manifest_fixture()
	check(not manifest.is_empty(), "frozen final placement artifact is readable")
	if manifest.is_empty(): finish(); return
	var original_manifest := C.bytes(manifest)
	var state := fixture(manifest)
	if state.is_empty(): finish(); return
	var before := C.bytes(state)
	check(Catalog.validate_world(state).ok, "catalog validates without a source renderer or terrain adapter")
	check(state.generated_world.static_entity_catalog.entries.size() == 5, "one settlement, three buildings and one road are distinct static identities")
	check(state.generated_world.static_entity_catalog.source_identity.source_runtime_hash == state.generated_world.inventory_runtime_hash, "static binding names exact inventory runtime rather than terrain runtime")
	check(C.bytes(manifest) == original_manifest, "catalog admission does not alter the placement manifest")
	var site_id: String = manifest.settlements[0].id
	var building_id: String = manifest.buildings[0].id
	var road_id: String = manifest.roads[0].id
	var primary: Array = manifest.roads[0].route_hexes[0]
	var entry: Array = manifest.roads[0].route_hexes[1]
	var frozen: Dictionary = {}
	for id in [site_id, building_id, road_id]:
		var reference := Focus.make_reference(id, state)
		check(not reference.is_empty() and reference.entity_revision == 0 and reference.catalog_version == Focus.VERSION, "static reference has independent revision/version " + id)
		var resolved := Focus.resolve(reference, state)
		check(resolved.ok, "each supported static kind resolves " + id)
		if not resolved.ok: continue
		var focus: Dictionary = resolved.focus
		check(Focus.validate_historical(focus, state).is_empty(), "exact static history validates " + id)
		check(C.bytes(Focus.reference_for(focus)) == C.bytes(reference), "reference retains exact header " + id)
		check(not focus.facts.has("item") and not focus.facts.has("custody_witness") and not focus.facts.selection_is_action, "static entity is not an item, custody target or action " + id)
		check(C.bytes(focus.facts.descriptor) == C.bytes(Catalog.descriptor(id, state)), "frozen descriptor equals immutable catalog " + id)
		check(C.bytes(PublicProjection.public_descriptor(focus.facts.descriptor)) == C.bytes(focus.facts.descriptor), "public descriptor preserves all admitted bounded witness facts " + id)
		check(C.bytes(focus).to_utf8_buffer().size() < 16384 and not C.bytes(focus).contains("allowed_neighbors") and not C.bytes(focus).contains("origin_component"), "far focused evidence includes one cell and bounded witness " + id)
		check(focus.hex != state.actors.actor_player.hex, "far entity focus does not follow player location " + id)
		frozen[id] = focus
	var road_ref := Focus.make_reference(road_id, state, entry)
	check(C.bytes(road_ref.hex) == C.bytes(entry) and C.bytes(Focus.make_reference(road_id, state).hex) == C.bytes(primary), "road preserves selected declared support; default uses primary")
	check(Focus.make_reference(site_id, state, entry).is_empty() and Focus.make_reference(building_id, state, entry).is_empty(), "external road endpoint cannot impersonate settlement/building support")
	check(Focus.make_reference(road_id, state, [99,99]).is_empty() and Focus.make_reference(road_id, state, [0.5,0]).is_empty(), "unsupported and fractional road support is rejected")
	check(Focus.make_reference("item_travel_bundle", state).is_empty(), "item catalog does not become static selection")
	check(C.bytes(state) == before, "selection, resolution and projection leave world unchanged")
	var wire_reference: Dictionary = JSON.parse_string(C.bytes(road_ref))
	check(Focus.resolve(wire_reference, state).ok, "JSON float transport roundtrip preserves exact selected road support")
	var wire_state: Dictionary = JSON.parse_string(C.bytes(state))
	var wire_catalog_result := Catalog.validate_world(wire_state)
	var wire_focus_result := Focus.resolve(wire_reference, wire_state)
	if not wire_catalog_result.ok or not wire_focus_result.ok: printerr("STATIC_WIRE_DIAGNOSTIC ", C.bytes({"catalog":wire_catalog_result,"focus":wire_focus_result}))
	check(wire_catalog_result.ok and wire_focus_result.ok, "JSON transport catalog/world/reference roundtrip retains static identity")
	var wire_before := C.bytes(wire_state)
	for support in [primary, entry]:
		var wire_selected: Dictionary = JSON.parse_string(C.bytes(Focus.make_reference(road_id, state, support)))
		var wire_selected_result := Focus.resolve(wire_selected, wire_state)
		check(wire_selected_result.ok, "both declared road endpoints survive live JSON transport: " + str(support))
		if wire_selected_result.ok:
			var wire_frozen: Dictionary = JSON.parse_string(C.bytes(wire_selected_result.focus))
			check(Focus.validate_historical(wire_frozen, wire_state).is_empty(), "both road endpoints survive historical JSON transport: " + str(support))
			check(C.bytes(PublicProjection.frozen_focus(wire_frozen, CELL_FIELDS)) == C.bytes(PublicProjection.frozen_focus(wire_selected_result.focus, CELL_FIELDS)), "frozen JSON road projection is exact at endpoint: " + str(support))
	check(C.bytes(wire_state) == wire_before, "wire catalog and focus normalization never mutates caller world")
	var road_focus: Dictionary = Focus.resolve(road_ref, state).focus
	var public_before := C.bytes(PublicProjection.frozen_focus(road_focus, CELL_FIELDS))
	check(not PublicProjection.frozen_focus(road_focus, CELL_FIELDS).facts.supporting_cell.has("secret_cell_note"), "supporting cell projection uses explicit public whitelist")
	state.actors.actor_player.hex = primary.duplicate()
	state.actors.actor_player.inventory = []
	state.items.item_travel_bundle = {"id":"item_travel_bundle","hex":entry.duplicate(),"scene_id":"unit_scene","custody_revision":3}
	state.turn += 1; state.state_version += 1; state.flags["mutable_note"] = "changed"
	check(Focus.validate_historical(road_focus, state).is_empty() and Focus.resolve(road_ref, state).ok, "actor, inventory, item and turn changes never revise static identities")
	check(C.bytes(PublicProjection.frozen_focus(road_focus, CELL_FIELDS)) == public_before, "history projection is an exact frozen copy after unrelated live changes")
	var detached: Dictionary = Catalog.descriptor(road_id, state); detached.name = "changed copy"
	check(state.generated_world.static_entity_catalog.entries[road_id].name != detached.name, "descriptor lookup cannot mutate catalog")
	for field in ["world_id", "catalog_id", "catalog_version", "id", "scene_id", "kind"]:
		var bad_ref := road_ref.duplicate(true); bad_ref[field] = "wrong"
		check(not Focus.resolve(bad_ref, state).ok, "invalid or stale reference rejected: " + field)
	for revision in [-1, 1, 0.5, "0", false]:
		var bad_ref := road_ref.duplicate(true); bad_ref.entity_revision = revision
		check(not Focus.resolve(bad_ref, state).ok, "static revision must remain integer zero: " + str(revision))
	for hex in [[], [entry[0]], [entry[0],entry[1],0], [0.5,0], [99,99], [1001,0], ["0",0]]:
		var bad_ref := road_ref.duplicate(true); bad_ref.hex = hex
		check(not Focus.resolve(bad_ref, state).ok, "malformed or unsupported clicked hex fails closed: " + str(hex))
	var bad_ref := road_ref.duplicate(true); bad_ref["owner_actor_id"] = "actor_player"
	check(not Focus.resolve(bad_ref, state).ok, "unsupported reference field cannot add custody")
	bad_ref = road_ref.duplicate(true); bad_ref.erase("scene_id")
	check(not Focus.resolve(bad_ref, state).ok, "incomplete static reference fails closed")
	for field in ["source_contract", "content_hash", "geometry_hash", "inventory_runtime_hash", "placement_hash", "placement_profile", "placement_context_hash", "static_entity_catalog_hash", "static_entity_profile"]:
		var bad_state := state.duplicate(true); bad_state.generated_world[field] = "wrong"
		check(not Catalog.validate_world(bad_state).ok and Focus.make_reference(road_id, bad_state).is_empty(), "exact frozen world binding rejects: " + field)
	for field in ["items", "actors", "scenes"]:
		var bad_state := state.duplicate(true); bad_state[field][road_id] = {"id":road_id}
		check(not Catalog.validate_world(bad_state).ok, "static ID cannot collide with " + field)
	var bad_state := state.duplicate(true); bad_state.scenes[false] = {}
	check(not Catalog.validate_world(bad_state).ok, "non-string scene key fails before typed cell helpers")
	bad_state = state.duplicate(true); bad_state.hexes["99,99"].id = road_id
	check(not Catalog.validate_world(bad_state).ok, "static ID cannot collide with a cell identity")
	bad_state = state.duplicate(true); bad_state.hexes["99,99"] = []
	check(not Catalog.validate_world(bad_state).ok, "invalid cell container fails without typed lookup error")
	bad_state = state.duplicate(true); bad_state.scenes.other_scene = {"id":"other_scene"}; bad_state.scene_hexes = {"other_scene":{}}
	for key in state.hexes:
		bad_state.scene_hexes.other_scene[key] = state.hexes[key].duplicate(true)
		bad_state.scene_hexes.other_scene[key].scene_id = "other_scene"
	check(not Catalog.validate_world(bad_state).ok, "ambiguous scene support cannot silently pick a scene")
	for field in ["world_id", "catalog_id", "catalog_version", "scene_id", "id", "kind", "entity_revision", "hex"]:
		var changed := road_focus.duplicate(true)
		changed[field] = [99,99] if field == "hex" else (1 if field == "entity_revision" else "wrong")
		check(not Focus.validate_historical(changed, state).is_empty(), "historical identity rejects: " + field)
	for field in ["source_identity", "catalog_identity", "placement_identity", "descriptor", "supporting_cell", "location_witness"]:
		var changed := road_focus.duplicate(true); changed.facts[field]["unsupported"] = true
		check(not Focus.validate_historical(changed, state).is_empty(), "historical frozen facts are exact: " + field)
	var changed := road_focus.duplicate(true); changed.facts.selection_is_action = true
	check(not Focus.validate_historical(changed, state).is_empty(), "historical selection cannot grant action authority")
	changed = road_focus.duplicate(true); changed.facts.location_witness.hex = primary.duplicate()
	check(not Focus.validate_historical(changed, state).is_empty(), "road history cannot switch the selected supporting endpoint")
	var polluted := road_focus.duplicate(true)
	polluted["secret"] = "strip"
	polluted.facts["item"] = {"owner_actor_id":"hidden"}
	for field in ["source_identity", "catalog_identity", "placement_identity", "descriptor", "location_witness"]: polluted.facts[field]["secret"] = "strip"
	polluted.facts.descriptor.physical_witness["secret"] = "strip"
	polluted.facts.descriptor.physical_witness.support["secret"] = "strip"
	polluted.facts.descriptor.physical_witness.support_limits["secret"] = "strip"
	check(C.bytes(PublicProjection.frozen_focus(polluted, CELL_FIELDS)) == public_before, "nested public whitelists drop unsupported descriptor, witness and identity secrets")
	for id in ["building/a", "building~a", "building a", "building\na", "", "建筑"]:
		var altered := manifest.duplicate(true); altered.buildings[0].id = id
		changed_build_fails(altered, "path-unsafe or unsupported ASCII identity rejected: " + id)
	var altered := manifest.duplicate(true); altered.buildings[1].id = altered.buildings[0].id
	changed_build_fails(altered, "duplicate building IDs rejected before dictionary insertion")
	altered = manifest.duplicate(true); altered.buildings[0].id = site_id
	changed_build_fails(altered, "cross-kind duplicate IDs rejected before insertion")
	altered = manifest.duplicate(true); altered.buildings[0].id = "item_travel_bundle"
	changed_build_fails(altered, "static/item catalog ID collision rejected at build")
	altered = manifest.duplicate(true); altered["unsupported"] = true
	changed_build_fails(altered, "unsupported top-level placement field rejected")
	altered = manifest.duplicate(true); altered.buildings[0]["owner_actor_id"] = "actor_player"
	changed_build_fails(altered, "unsupported building custody field rejected")
	altered = manifest.duplicate(true); altered.settlements[0].name = false
	changed_build_fails(altered, "invalid settlement name fails before typed descriptor creation")
	altered = manifest.duplicate(true); altered.buildings[0].position = [0,0]
	changed_build_fails(altered, "invalid physical transform dimensions rejected")
	altered = manifest.duplicate(true); altered.buildings[0].footprint = [[0,0],[1,1],[1,0],[0,1]]
	changed_build_fails(altered, "self-intersecting collision footprint rejected")
	altered = manifest.duplicate(true); altered.buildings[0].clearance_envelope = [[0,0],[1,0],[1,0]]
	changed_build_fails(altered, "duplicate/degenerate collision envelope rejected")
	altered = manifest.duplicate(true); altered.buildings[0].support.ok = false
	changed_build_fails(altered, "failed physical support cannot become static witness")
	altered = manifest.duplicate(true); altered.roads[0].route_hexes = [primary,primary]
	changed_build_fails(altered, "road requires two unique declared supports")
	altered = manifest.duplicate(true); altered.roads[0].route_hexes = [primary,[99,99]]
	changed_build_fails(altered, "nonadjacent road support rejected")
	altered = manifest.duplicate(true); altered.roads[0].centerline_q40[0] = [0.5,0,0]
	changed_build_fails(altered, "exact physical centerline rejects fractional integer encoding")
	altered = manifest.duplicate(true); altered.roads[0].centerline_q40.resize(65)
	changed_build_fails(altered, "unbounded centerline witness rejected")
	altered = manifest.duplicate(true); altered.settlements[0].building_ids.append(building_id)
	changed_build_fails(altered, "duplicate relationship identities rejected")
	altered = manifest.duplicate(true); altered.settlements[0].road_ids = [building_id]
	changed_build_fails(altered, "relationship cannot cross static kind")
	altered = manifest.duplicate(true); altered.entry_anchors[0].hex = [99,99]
	changed_build_fails(altered, "placement anchor must match static supported identity")
	altered = manifest.duplicate(true); altered.blocked_edges[0].building_ids = [road_id]
	changed_build_fails(altered, "collision edge cannot name a road as building blocker")
	altered = manifest.duplicate(true); altered.allowed_neighbors[altered.allowed_neighbors.keys()[0]] = {}
	changed_build_fails(altered, "malformed graph transport fails closed")
	altered = manifest.duplicate(true); altered.context_hash = "a".repeat(64)
	changed_build_fails(altered, "placement context hash must match exact context fields")
	altered = manifest.duplicate(true); altered.placement_hash = "a".repeat(64)
	check(not Catalog.build(PROFILE, inventory_identity(altered), altered).ok, "stale placement digest rejected")
	var catalog: Dictionary = state.generated_world.static_entity_catalog.duplicate(true)
	catalog.entries[road_id].kind = "item"; rehash_catalog(catalog)
	check(not Catalog.validate(catalog).ok, "rehashed catalog cannot make static road a custody item")
	catalog = state.generated_world.static_entity_catalog.duplicate(true)
	catalog.entries[road_id].physical_witness["allowed_neighbors"] = manifest.allowed_neighbors; rehash_catalog(catalog)
	check(not Catalog.validate(catalog).ok, "rehashed descriptor cannot smuggle whole placement graph")
	check(Catalog.valid_id("building:v3:abc_01-test") and not Catalog.valid_id("building/v3"), "static IDs share explicit item-catalog safe ASCII alphabet")
	finish()

func finish() -> void:
	var report := {"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Immutable static catalog/focus/projection transport, binding and adversarial tests over a frozen admitted placement; no terrain or renderer generation"}
	print("SOURCE_STATIC_ENTITY_CATALOG ", C.bytes(report))
	quit(0 if failures.is_empty() else 1)
