extends RefCounted
## Immutable authored miniature objects and two real, source-supported apertures.
## No save migration or model text may author these facts. Source geometry is
## baked from the pinned terrain triangles; render transforms are presentation.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Cells = preload("res://core/ai_gm_rebuilt/scene_cells.gd")
const Bundle = preload("res://view/playable_build/world_bundle.gd")
const VERSION := "creative_physical_catalog/v1"
const FOCUS_VERSION := "creative-scene-focus/v1"
const CATALOG_ID := "coast_creative_bracing/v1"
const SCENE := "scene_coast"
const WORLD_UNITS_PER_MM := 0.0005
const EXTENSION_FIELDS := ["physical_catalog", "passage_targets", "creative_relations", "creative_placements"]
const PUBLIC_ITEM_FIELDS := ["id","name","description","quantity","hex","scene_id","owner_actor_id","condition_source","weapon_profile","interaction_profile","custody_revision","physical_traits"]
const PUBLIC_CELL_FIELDS := ["id","q","r","scene_id","terrain","ground_blocked","air_blocked","all_blocked"]
const ITEM_IDS := ["item_brace_plank", "item_brace_oar", "item_brace_bar"]
const DATA := '''{"schema_version":"creative_authored_content/v1","catalog_id":"coast_creative_bracing/v1","bundle_id":"natural-shore-v03-2f6a1a215a0d44a374f01c4a","source_mesh_sha256":"68931983818b291b07022477029d4ad4761aceac0c670463fbe742b6a2ac986c","source_catalog_sha256":"c982975994b5043cd05d1e11b3cfe6840c889c1122524f6b12412bd306f4aa52","source_navigation_sha256":"5dd96e3ea0ca1037cf42e5e63f2bcc78c0a65271825b6b5455341f644f3ba714","source_topology_sha256":"9df46b84df66df62348f97811dbd1a235290b8af58480ba2d6177d668cdedd4c","item_profiles":{"plank_v1":{"physical_traits":{"schema_version":"physical_traits/v1","catalog_id":"coast_creative_bracing/v1","profile_id":"plank_v1","solid":true,"portable":true,"length_mm":1800,"section_mm":160,"mass_g":2800,"rigidity":2,"bearing":2},"presentation":{"form":"rectangular_timber","thickness_mm":18,"color":"aa784c"}},"oar_v1":{"physical_traits":{"schema_version":"physical_traits/v1","catalog_id":"coast_creative_bracing/v1","profile_id":"oar_v1","solid":true,"portable":true,"length_mm":1900,"section_mm":180,"mass_g":2200,"rigidity":2,"bearing":2},"presentation":{"form":"shaft_and_blade","thickness_mm":28,"color":"c19b63"}},"bar_v1":{"physical_traits":{"schema_version":"physical_traits/v1","catalog_id":"coast_creative_bracing/v1","profile_id":"bar_v1","solid":true,"portable":true,"length_mm":1650,"section_mm":40,"mass_g":4200,"rigidity":3,"bearing":3},"presentation":{"form":"flat_metal_bar","thickness_mm":8,"color":"687c83"}}},"items":{"item_brace_plank":{"profile_id":"plank_v1","name":"岸木长板","description":"单块硬木长板，长180厘米；可移动、可手持。尺寸和承力是编写的物理事实，不赋予武器或架桥能力。"},"item_brace_oar":{"profile_id":"oar_v1","name":"备用木桨","description":"完整的备用木桨，长190厘米；可移动、可手持。桨叶与刚性桨杆为同一个不可拆分物件。"},"item_brace_bar":{"profile_id":"bar_v1","name":"扁铁长杆","description":"长165厘米、宽40毫米、厚8毫米的实心扁铁杆，可移动、可手持；没有编写攻击能力。"}},"passage_targets":{"passage:coast_brace:north":{"schema_version":"passage_target/v1","id":"passage:coast_brace:north","name":"北坡窄口","scene_id":"scene_coast","catalog_id":"coast_creative_bracing/v1","endpoints":[[-1,13],[-1,14]],"support_hex":[-1,14],"anchor_id":"passage:coast_brace:north:span_contact","width_mm":1200,"min_section_mm":20,"max_section_mm":220,"required_bearing":2,"revision":0,"geometry_policy":"source_bound_span_contact/v1","pose_frames":{"braced":{"origin_mm":[20482,797,40825],"yaw_milliradians":731},"loose":{"origin_mm":[22309,225,41306],"yaw_milliradians":-840}},"source_support":{"from_face_index":1872,"to_face_index":1938}},"passage:coast_brace:south":{"schema_version":"passage_target/v1","id":"passage:coast_brace:south","name":"南岸窄口","scene_id":"scene_coast","catalog_id":"coast_creative_bracing/v1","endpoints":[[-2,14],[-2,15]],"support_hex":[-2,14],"anchor_id":"passage:coast_brace:south:span_contact","width_mm":1200,"min_section_mm":20,"max_section_mm":220,"required_bearing":2,"revision":0,"geometry_policy":"source_bound_span_contact/v1","pose_frames":{"braced":{"origin_mm":[18562,866,44150],"yaw_milliradians":524},"loose":{"origin_mm":[18596,444,42130],"yaw_milliradians":-1047}},"source_support":{"from_face_index":26797,"to_face_index":26833}}},"geometry":{"passage:coast_brace:north":{"center":{"position":[10.240750399750986,0.146150062333554,20.4125],"source_face_index":1929,"source_face_id":"hex:-1,14:face:3:3","barycentric":[0.2142857142857152,0.07142857142857195,0.7142857142857129]},"loose_ground":{"position":[11.1547232602893,0.0855398026038358,20.652837145553377],"source_face_index":1939,"source_face_id":"hex:-1,14:face:5:1","barycentric":[0.3418144167782408,0.28610709275301976,0.37207849046873936]},"contact_ground":[{"position":[10.017399972883997,0.15868356420245128,20.612786262180745],"source_face_index":1926,"source_face_id":"hex:-1,14:face:3:0","barycentric":[0.07128435862379845,0.6660043971546913,0.26271124422151027]},{"position":[10.464100826617976,0.12857622566842905,20.21221373781926],"source_face_index":1933,"source_face_id":"hex:-1,14:face:4:1","barycentric":[0.48789231069709615,0.18049625670071193,0.33161143260219195]}],"cheek_ground":[{"position":[9.905724759450504,0.16551794100237285,20.712929393271118],"source_face_index":1926,"source_face_id":"hex:-1,14:face:3:0","barycentric":[0.12615730716647136,0.8643912111166485,0.00945148171688015]},{"position":[10.575776040051469,0.11604285109619182,20.112070606728885],"source_face_index":1933,"source_face_id":"hex:-1,14:face:4:1","barycentric":[0.01755275175992719,0.13503009933678894,0.8474171489032838]}],"world_units_per_mm":0.0005,"cheek_span_mm":600,"cheek_depth_mm":440,"cheek_height_mm":800,"contact_height_mm":480,"loose_footprint_support":[{"position":[10.870964098124068,0.09231819479336356,20.269258690850982],"source_face_index":61916,"source_face_id":"hex:0,13:face:1:2","barycentric":[0.020272450147730017,0.1702874869260436,0.8094400629262264]},{"position":[10.83745515772538,0.09678915738000171,20.29929451801384],"source_face_index":1935,"source_face_id":"hex:-1,14:face:4:3","barycentric":[0.006319441561832084,0.8791803846554431,0.11450017378272481]},{"position":[10.803946217326692,0.10107453539612948,20.3293303451767],"source_face_index":1935,"source_face_id":"hex:-1,14:face:4:3","barycentric":[0.09840652055064213,0.7380883191631562,0.16350516028620166]},{"position":[11.188008940398689,0.08133567828944113,20.62296417283714],"source_face_index":1939,"source_face_id":"hex:-1,14:face:5:1","barycentric":[0.2320001517992964,0.4385432631116526,0.32945658508905096]},{"position":[11.1545,0.08556632505774993,20.653],"source_face_index":1939,"source_face_id":"hex:-1,14:face:5:1","barycentric":[0.34255098471039186,0.28523470458688865,0.37221431070271954]},{"position":[11.120991059601312,0.0897969718260587,20.683035827162858],"source_face_index":1939,"source_face_id":"hex:-1,14:face:5:1","barycentric":[0.4531018176214873,0.1319261460621247,0.4149720363163879]},{"position":[11.50505378267331,0.07332969866300941,20.976669654823297],"source_face_index":62063,"source_face_id":"hex:0,14:face:2:3","barycentric":[0.37109544260249044,0.186023437328241,0.4428811200692686]},{"position":[11.471544842274621,0.07674471900252797,21.006705481986156],"source_face_index":62063,"source_face_id":"hex:0,14:face:2:3","barycentric":[0.3620289910128796,0.29657427023933647,0.341396738747784]},{"position":[11.438035901875933,0.08015973934204654,21.036741309149015],"source_face_index":62063,"source_face_id":"hex:0,14:face:2:3","barycentric":[0.35296253942326866,0.407125103150432,0.2399123574262993]}]},"passage:coast_brace:south":{"center":{"position":[9.280905577223233,0.18130270782726007,22.075],"source_face_index":26851,"source_face_id":"hex:-2,15:face:3:0","barycentric":[0.1282051282051255,0.43589743589743624,0.43589743589743823]},"loose_ground":{"position":[9.298226085298921,0.18414299197471679,21.064999999999998],"source_face_index":26830,"source_face_id":"hex:-2,14:face:5:3","barycentric":[0.27619047619048137,0.24761904761904385,0.4761904761904747]},"contact_ground":[{"position":[9.021097956087901,0.19291236278078655,22.224999999999998],"source_face_index":26845,"source_face_id":"hex:-2,15:face:2:0","barycentric":[0.10256410256410191,0.025641025641021765,0.8717948717948764]},{"position":[9.540713198358565,0.1691954796498124,21.925],"source_face_index":26857,"source_face_id":"hex:-2,15:face:4:0","barycentric":[0.10256410256410177,0.8717948717948726,0.02564102564102566]}],"cheek_ground":[{"position":[8.891194145520236,0.19523597506093393,22.3],"source_face_index":26848,"source_face_id":"hex:-2,15:face:2:3","barycentric":[0.07326007326007439,0.2380952380952367,0.688644688644689]},{"position":[9.67061700892623,0.16424409632409684,21.849999999999998],"source_face_index":26860,"source_face_id":"hex:-2,15:face:4:3","barycentric":[0.6886446886446881,0.2380952380952461,0.07326007326006581]}],"world_units_per_mm":0.0005,"cheek_span_mm":600,"cheek_depth_mm":440,"cheek_height_mm":800,"contact_height_mm":480,"loose_footprint_support":[{"position":[9.099385437074345,0.2089466432416639,20.631177161281418],"source_face_index":26821,"source_face_id":"hex:-2,14:face:4:0","barycentric":[0.042530045732897225,0.17736954948238384,0.780100404784719]},{"position":[9.060418739566392,0.20982919799892114,20.653684859638286],"source_face_index":26821,"source_face_id":"hex:-2,14:face:4:0","barycentric":[0.11176870981368998,0.17735375708050446,0.7108775331058055]},{"position":[9.02145204205844,0.2107117527561784,20.676192557995154],"source_face_index":26821,"source_face_id":"hex:-2,14:face:4:0","barycentric":[0.18100737389448274,0.17733796467862514,0.6416546614268921]},{"position":[9.336966697507952,0.1829538713877959,21.042492301643133],"source_face_index":26830,"source_face_id":"hex:-2,14:face:5:3","barycentric":[0.24691226761051246,0.3754299212616429,0.3776578111278447]},{"position":[9.298,0.18415370176165086,21.065],"source_face_index":26830,"source_face_id":"hex:-2,14:face:5:3","barycentric":[0.27656342021388175,0.2468731595722322,0.476563420213886]},{"position":[9.259033302492048,0.18535353213550582,21.08750769835687],"source_face_index":26830,"source_face_id":"hex:-2,14:face:5:3","barycentric":[0.306214572817251,0.11831639788282151,0.5754690292999275]},{"position":[9.57454795794156,0.1652774455092064,21.453807442004848],"source_face_index":1921,"source_face_id":"hex:-1,14:face:2:1","barycentric":[0.15924480506595073,0.7674563264996077,0.07329886843444156]},{"position":[9.535581260433608,0.1657954576536166,21.476315140361717],"source_face_index":1921,"source_face_id":"hex:-1,14:face:2:1","barycentric":[0.030688043376540058,0.8960541484339042,0.07325780818955574]},{"position":[9.496614562925656,0.16735424442178565,21.498822838718585],"source_face_index":26798,"source_face_id":"hex:-2,14:face:0:1","barycentric":[0.05229767710333542,0.8839028652033156,0.06379945769334894]}]}},"render_policy":{"world_units_per_mm":0.0005,"measurement_note":"Authored miniature scale; solid length/section/thickness share one conversion. Pose origin is a fixed source-support anchor; each mesh underside is 22.5 mm below it, matching contact saddle and loose ground support.","blocking_scope":"Only the registered ground traversal edge; no sight/projectile occlusion, damage or water crossing.","pose_vertical_reference_mm":22.5}}'''
static var _data: Dictionary = {}
static var _metadata: Dictionary = {}

static func manifest() -> Dictionary:
	if not Bundle.ready(): return {}
	if _data.is_empty():
		var raw: Variant = JSON.parse_string(DATA)
		if not raw is Dictionary: return {}
		var source := Bundle.manifest()
		if raw.bundle_id != source.bundle_id or raw.source_mesh_sha256 != source.source_identity.mesh_sha256 or raw.source_catalog_sha256 != source.runtime.catalog.sha256 or raw.source_navigation_sha256 != source.runtime.navigation.sha256 or raw.source_topology_sha256 != source.runtime.source_topology.sha256: return {}
		var cells: Dictionary = {}
		for cell in Bundle.document("catalog").get("cells", []): cells[key([cell.q, cell.r])] = cell
		var navigation: Dictionary = Bundle.document("navigation").get("allowed_neighbors", {})
		for target in raw.passage_targets.values():
			var a: String = key(target.endpoints[0]); var b: String = key(target.endpoints[1])
			if not cells.has(a) or not cells.has(b) or not b in navigation.get(a, []) or not a in navigation.get(b, []): return {}
			if not cells[a].walkable or not cells[b].walkable or cells[a].dry_fraction < 0.99999 or cells[b].dry_fraction < 0.99999: return {}
			if cells[a].support.source_face_index != target.source_support.from_face_index or cells[b].support.source_face_index != target.source_support.to_face_index: return {}
		_data = C.normalized(raw)
		_metadata = {"schema_version": VERSION, "catalog_id": CATALOG_ID, "catalog_sha256": C.digest(_data), "bundle_id": _data.bundle_id, "source_mesh_sha256": _data.source_mesh_sha256}
	if _data.bundle_id != Bundle.bundle_id(): return {}
	return _data.duplicate(true)

static func metadata() -> Dictionary:
	return _metadata.duplicate(true) if not manifest().is_empty() else {}
static func profiles() -> Dictionary: return manifest().get("item_profiles", {}).duplicate(true)
static func passage_targets() -> Dictionary: return manifest().get("passage_targets", {}).duplicate(true)
static func geometry(target_id: String) -> Dictionary: return manifest().get("geometry", {}).get(target_id, {}).duplicate(true)
static func items() -> Dictionary:
	var data := manifest(); var result: Dictionary = {}
	for id in data.get("items", {}):
		var row: Dictionary = data.items[id]
		result[id] = {"id": id, "name": row.name, "description": row.description, "quantity": 1, "owner_actor_id": "actor_player", "physical_traits": data.item_profiles[row.profile_id].physical_traits.duplicate(true), "interaction_profile": {"schema_version": "coast_item_interaction/v1", "movable": true, "equip_slot": "weapon"}}
	return result

static func install_new_game(state: Dictionary) -> void:
	# Called solely by new-world construction, never by load/registry upgrades.
	if manifest().is_empty() or state.get("generated_world", {}).get("bundle_id") != _data.bundle_id or not state.get("actors", {}).has("actor_player"): return
	for field in EXTENSION_FIELDS:
		if state.has(field): return
	for id in ITEM_IDS:
		if state.get("items", {}).has(id): return
	state.physical_catalog = metadata(); state.passage_targets = passage_targets()
	state.creative_relations = {}; state.creative_placements = {}
	for id in items():
		state.items[id] = items()[id]
		state.actors.actor_player.inventory.append(id)

static func validate_catalog(state: Dictionary) -> Dictionary:
	if not state.get("items") is Dictionary: return C.fail("PHYSICAL_CATALOG", "Item collection must be a dictionary.")
	for item in state.items.values():
		if not item is Dictionary: return C.fail("PHYSICAL_CATALOG", "Physical item records must be dictionaries.")
	var count := 0
	for field in EXTENSION_FIELDS:
		if state.has(field): count += 1
	if count == 0:
		for id in state.get("items", {}):
			if state.items[id].has("physical_traits") or id in ITEM_IDS: return C.fail("PHYSICAL_CATALOG", "Physical items require the exact installed source-bound catalog.")
		return {"ok": true}
	if count != EXTENSION_FIELDS.size() or metadata().is_empty() or not _same(state.get("physical_catalog"), metadata()) or not _same(state.get("passage_targets"), passage_targets()) or not state.get("creative_relations") is Dictionary or not state.get("creative_placements") is Dictionary: return C.fail("PHYSICAL_CATALOG", "Partial, changed or mismatched creative physical catalog.")
	if not state.get("generated_world") is Dictionary or not state.generated_world.get("bundle_id") is String or state.generated_world.bundle_id != _data.bundle_id: return C.fail("PHYSICAL_CATALOG", "Creative content belongs to a different source bundle.")
	var originals := items()
	for id in originals:
		var item: Variant = state.get("items", {}).get(id)
		if not item is Dictionary or item.get("id") != id or not C.integer(item.get("quantity")) or item.get("quantity") != 1 or not _same(item.get("physical_traits"), originals[id].physical_traits) or not _same(item.get("interaction_profile"), originals[id].interaction_profile) or item.has("weapon_profile") or item.has("condition_source"): return C.fail("PHYSICAL_CATALOG", "Authored physical singleton identity, traits or capabilities changed.")
	for id in state.get("items", {}):
		if state.items[id].has("physical_traits") and not originals.has(id): return C.fail("PHYSICAL_CATALOG", "Unknown item cannot acquire authored physical traits.")
	if not state.get("hexes") is Dictionary: return C.fail("PHYSICAL_CATALOG", "Passage cells must be a dictionary.")
	for target in state.passage_targets.values():
		for hex in target.endpoints:
			if not state.get("hexes", {}).has(key(hex)) or not state.hexes[key(hex)] is Dictionary or state.hexes[key(hex)].get("scene_id") != SCENE: return C.fail("PHYSICAL_CATALOG", "Passage source cells are missing or in the wrong scene.")
	return {"ok": true}

static func active(state: Dictionary) -> bool:
	return state.has("physical_catalog") and validate_catalog(state).get("ok", false)
static func stable(before: Dictionary, after: Dictionary) -> bool:
	for field in EXTENSION_FIELDS:
		if before.has(field) != after.has(field): return false
	if not before.has("physical_catalog"): return validate_catalog(after).get("ok", false)
	return _same(before.physical_catalog, after.get("physical_catalog")) and _same(before.passage_targets, after.get("passage_targets")) and validate_catalog(after).get("ok", false)
static func key(hex: Array) -> String: return "%d,%d" % hex
static func _same(a: Variant, b: Variant) -> bool: return C.bytes(a) == C.bytes(b)
static func vector(value: Array) -> Vector3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
static func pose(target_id: String, posture: String) -> Transform3D:
	var target: Dictionary = passage_targets().get(target_id, {})
	if target.is_empty() or not posture in ["loose", "braced"]: return Transform3D.IDENTITY
	var frame: Dictionary = target.pose_frames[posture]
	return Transform3D(Basis(Vector3.UP, float(frame.yaw_milliradians) / 1000.0), vector(frame.origin_mm) * WORLD_UNITS_PER_MM)
static func item_hex(id: String, state: Dictionary) -> Array:
	var item: Dictionary = state.get("items", {}).get(id, {})
	var owner: String = str(item.get("owner_actor_id", ""))
	return state.get("actors", {}).get(owner, {}).get("hex", []).duplicate() if not owner.is_empty() else item.get("hex", []).duplicate()
static func item_scene(id: String, state: Dictionary) -> String:
	var item: Dictionary = state.get("items", {}).get(id, {})
	return str(state.get("actors", {}).get(item.get("owner_actor_id", ""), {}).get("scene_id", item.get("scene_id", "")))
static func item_focus_revision(item: Dictionary, placement: Dictionary, hex: Array, scene: String) -> int:
	# A custody counter and a removable placement counter cannot be safely added:
	# pickup may clear one while incrementing the other. Bind all public source
	# state in an exact JSON-safe 52-bit revision token instead.
	# Hash only projected public fields too: hashing a private extra field would
	# expose a guessable private-state oracle even if its literal text was omitted.
	var public_item: Dictionary = public_fields(item,PUBLIC_ITEM_FIELDS)
	return C.digest({"item": public_item, "placement": placement, "hex": hex, "scene_id": scene}).substr(0, 13).hex_to_int()
static func public_fields(value: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary={}
	for field in fields:
		if value.has(field): result[field]=C.normalized(value[field])
	return result
static func revision(id: String, state: Dictionary) -> int:
	if state.get("items", {}).has(id): return item_focus_revision(state.items[id], state.get("creative_placements", {}).get(id, {}), item_hex(id, state), item_scene(id, state))
	var revision_ := 0
	for relation in state.get("creative_relations", {}).values():
		if relation.get("target_id") == id: revision_ += int(relation.get("revision", 0)) + 1
	return revision_
static func entity_state(state: Dictionary, id: String) -> Dictionary:
	var active_relation: Dictionary = {}
	for relation in state.get("creative_relations", {}).values():
		if relation.get("target_id") == id and relation.get("active") == true: active_relation = relation.duplicate(true)
	return {"posture": "braced" if not active_relation.is_empty() else "open", "revision": revision(id, state), "ground_blocking": not active_relation.is_empty(), "relation": active_relation}
static func descriptors() -> Array:
	var result: Array = []
	for target in passage_targets().values(): result.append({"id": target.id, "kind": "passage_edge", "name": target.name, "hex": target.support_hex, "scene_id": SCENE, "public_facts": target.duplicate(true)})
	return result
static func make_reference(id: String, state: Dictionary) -> Dictionary:
	if not active(state): return {}
	var kind := "passage_edge"; var hex: Array = []; var scene := SCENE
	if id in ITEM_IDS:
		kind = "item"; hex = item_hex(id, state); scene = item_scene(id, state)
	elif state.passage_targets.has(id): hex = state.passage_targets[id].support_hex.duplicate()
	else: return {}
	if hex.size() != 2: return {}
	return {"world_id": state.world_id, "kind": kind, "id": id, "hex": hex, "scene_id": scene, "catalog_version": FOCUS_VERSION, "entity_revision": revision(id, state)}
static func focus_facts(id: String, state: Dictionary) -> Dictionary:
	var reference := make_reference(id, state)
	if reference.is_empty(): return {}
	var cell: Dictionary = Cells.cell(state, reference.scene_id, reference.hex)
	if cell.is_empty(): return {}
	var facts := {"scene_id": reference.scene_id, "physical_catalog": metadata(), "supporting_cell": public_fields(cell,PUBLIC_CELL_FIELDS), "selection_is_action": false}
	if reference.kind == "item":
		facts.item = public_fields(state.items[id],PUBLIC_ITEM_FIELDS)
		facts.placement = state.get("creative_placements", {}).get(id, {}).duplicate(true)
	else:
		facts.passage_target = state.passage_targets[id].duplicate(true)
		facts.state = entity_state(state, id)
	return facts
