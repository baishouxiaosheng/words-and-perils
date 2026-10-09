extends RefCounted
## Admission accepts only reproducible bounded macro v2 source, not resigned arbitrary JSON.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Generator = preload("res://core/world_generator.gd")
const Navigation = preload("res://view/generated_adventure/navigation.gd")
const ID := "generated_macro_source/v1"
const SCENE := "scene_generated"
const CELL := "generated_macro_cell/v1"
const MAX_SOURCE_BYTES := 4*1024*1024
const BIOMES := {"ocean":"ocean","grassland":"grass","desert":"arid","temperate_forest":"forest","jungle":"jungle","alpine":"alpine","wetland":"swamp"}
const LANDFORMS := ["ocean","lowland","ridge","plateau","mountain","highland","slope"]
const SOURCE_FIELDS := ["actor_spawn_hexes","board_radius","config","content_hash","generator_version","hexes","hydrology","macro_landscape","mountain_regions","river_edges","roads","seed","settlements","statistics"]
var data: Dictionary = {}
var world: Dictionary = {}
var navigation: RefCounted
var identity: Dictionary = {}
var immutable: Dictionary = {}

func admit(value: Variant) -> Dictionary:
	if not C.exact_fields(value,SOURCE_FIELDS) or not C.safe(value): return C.fail("GENERATED_SOURCE_SCHEMA","Expected the exact bounded macro-biomes source contract.")
	if not C.integer(value.seed) or absi(int(value.seed))>2147483647 or not C.integer(value.board_radius) or value.board_radius<4 or value.board_radius>24 or value.generator_version!=Generator.BIOMES_VERSION: return C.fail("GENERATED_SOURCE_VERSION","Only macro_hex_biomes_v2, signed32 seed and radius4–24 are supported.")
	if not value.hexes is Dictionary or value.hexes.size()!=1+3*int(value.board_radius)*(int(value.board_radius)+1) or not value.config is Dictionary or C.bytes(value).to_utf8_buffer().size()>MAX_SOURCE_BYTES: return C.fail("GENERATED_SOURCE_BOUNDS","Source cells, configuration or byte limit is invalid.")
	var unsigned: Dictionary=value.duplicate(true); unsigned.erase("content_hash")
	if not value.content_hash is String or value.content_hash!=C.digest(unsigned): return C.fail("GENERATED_SOURCE_HASH","Generated source content hash changed.")
	# v1 admits the default recipe only. Do not guess original unquantized options.
	var rebuilt: Dictionary = Generator.generate(int(value.seed),int(value.board_radius),{"generator_version":Generator.BIOMES_VERSION})
	if C.bytes(rebuilt)!=C.bytes(value): return C.fail("GENERATED_SOURCE_REPRODUCE","Source does not exactly reproduce under this versioned default recipe; use its original package.")
	var nav := Navigation.new()
	var checked: Dictionary=nav.build(rebuilt)
	if not checked.ok:return checked
	var cells := {}; var ids: Array = []
	for key in rebuilt.hexes:
		var row: Dictionary=rebuilt.hexes[key]
		if not BIOMES.has(row.biome) or not row.landform in LANDFORMS: return C.fail("GENERATED_SOURCE_VOCABULARY","Unregistered biome or landform.")
		for field in ["elevation","moisture","temperature","slope","plateau_weight"]:
			if not (row[field] is float or row[field] is int) or not is_finite(float(row[field])) or absf(float(row[field]))>32.0 or float(row[field])*4096!=roundf(float(row[field])*4096): return C.fail("GENERATED_SOURCE_NUMBER","Source descriptors must be finite and quantized.")
		var terrain: String=BIOMES[row.biome]
		if terrain=="alpine": terrain="mountain"
		elif row.landform=="ridge":terrain="hill"
		# Plateau is independent morphology, not a hidden cost surcharge or rock biome.
		cells[key]={"id":row.id,"q":row.q,"r":row.r,"scene_id":SCENE,"terrain":terrain,"ground_blocked":not nav.supported[key],"air_blocked":false,"all_blocked":false,
			"source_cell_version":CELL,"biome":BIOMES[row.biome],"landform":row.landform,"source_terrain":row.terrain,"plateau_region":row.plateau_region,"elevation_q4096":int(row.elevation*4096),"temperature_q4096":int(row.temperature*4096),"moisture_q4096":int(row.moisture*4096),"slope_q4096":int(row.slope*4096),"river":row.river,"road":row.road,"bridge":row.bridge}
		ids.append(row.id)
	var spawn: Array=rebuilt.actor_spawn_hexes.actor_player.duplicate()
	if nav.allowed.get("%d,%d"%spawn,[]).is_empty():
		var keys: Array = cells.keys();keys.sort()
		spawn=[]
		for key in keys:
			if nav.allowed[key].size()>0:spawn=[cells[key].q,cells[key].r];break
	if spawn.is_empty():return C.fail("GENERATED_NO_START","No connected verified dry starting anchor exists.")
	var source_identity := {"source_contract":ID,"generator_version":Generator.BIOMES_VERSION,"seed":rebuilt.seed,"board_radius":rebuilt.board_radius,"content_hash":rebuilt.content_hash,"navigation_id":Navigation.ID,"projection_id":"generated_public_context/v1","pipeline_sha256":pipeline_digest()}
	var derived_hash := C.digest({"identity":source_identity,"cells":cells,"allowed_neighbors":nav.allowed,"spawn":spawn})
	source_identity["runtime_hash"]=derived_hash
	var world_id: String="generated_macro_v1_"+rebuilt.content_hash
	var candidate := {"schema_version":"ai_gm_world/v1","world_id":world_id,"state_version":0,"turn":0,"actors":{},"items":{},"hexes":cells,"scenes":{SCENE:{"id":SCENE,"name":"多地貌探索 · %d"%rebuilt.seed,"layer_id":"layer_overworld","hex_ids":ids,"renderer_id":"generated_macro_renderer/v1","navigation_id":Navigation.ID,"bundle_id":derived_hash}},"story_anchors":{"anchor_generated_scope":{"id":"anchor_generated_scope","text":"多地貌固定规则探索第一阶段：观察当前或相邻地格、按已验证干燥路线移动、休息。所有主动行动先评估，再由程序结算。树木、聚落、桥梁和海岸剧情尚未接入，不可用名字推断能力。"}},"flags":{"observations":0,"last_observed_cell":""},"generated_world":source_identity,"board_radius":rebuilt.board_radius}
	candidate.actors.actor_player={"id":"actor_player","name":"旅人","hex":spawn,"scene_id":SCENE,"role":"player","faction":"traveler","health":{"current":12,"max":12},"stamina":{"current":8,"max":8},"inventory":[],"statuses":{},"hooks":["status_tick"]}
	data=C.normalized(rebuilt);world=C.normalized(candidate);navigation=nav;identity=source_identity
	immutable=immutable_fields(world)
	return {"ok":true,"identity":identity.duplicate(true),"navigation":checked.diagnostics}
static func pipeline_digest() -> String:
	var hashes := {}
	for path in ["res://core/world_generator.gd","res://view/terrain_field.gd","res://view/terrain_profiles.gd","res://view/channel_index.gd","res://view/generated_adventure/navigation.gd"]:
		hashes[path]=FileAccess.get_sha256(path)
	return C.digest(hashes)
static func immutable_fields(state: Dictionary) -> Dictionary:
	var result := {}
	for key in ["schema_version","world_id","hexes","scenes","story_anchors","generated_world","board_radius","items"]:result[key]=state.get(key)
	return C.normalized(result)
func validate_state(state: Variant) -> Dictionary:
	var checked: Dictionary=WorldSchema.validate(state)
	if not checked.ok:return checked
	if not state is Dictionary or not C.exact_fields(state,world.keys()) or C.bytes(immutable_fields(state))!=C.bytes(immutable):return C.fail("GENERATED_IDENTITY","World source, public cells or scene contract differ from the admitted exact map.")
	if not state.get("actors") is Dictionary or state.actors.keys()!=["actor_player"]:return C.fail("GENERATED_ACTORS","This generated version admits only its generic traveler.")
	var actor: Dictionary=state.actors.actor_player
	var actor_fixed: Dictionary=actor.duplicate(true); var original: Dictionary=world.actors.actor_player.duplicate(true)
	actor_fixed.erase("hex"); original.erase("hex")
	actor_fixed.get("stamina",{}).erase("current"); original.stamina.erase("current")
	if C.bytes(actor_fixed)!=C.bytes(original):return C.fail("GENERATED_ACTOR_CONTRACT","Generated actor identity, capability or fixed supplies differ.")
	if actor.get("scene_id")!=SCENE or not actor.get("hex") is Array or actor.hex.size()!=2 or not navigation.supported.get("%d,%d"%actor.hex,false):return C.fail("GENERATED_LANDING","Traveler has no exact dry source support.")
	if not C.exact_fields(state.get("flags"),["observations","last_observed_cell"]) or not C.integer(state.flags.observations) or state.flags.observations<0 or state.flags.observations>state.turn or not state.flags.last_observed_cell is String or (not state.flags.last_observed_cell.is_empty() and not state.hexes.has(state.flags.last_observed_cell)):return C.fail("GENERATED_FLAGS","Observation history is invalid.")
	return {"ok":true}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok:return {}
	var result: Dictionary=state.duplicate(true)
	result.generated_world=data.duplicate(true)
	result.hexes=data.hexes.duplicate(true)
	for key in result.hexes:result.hexes[key].scene_id=SCENE
	return result
