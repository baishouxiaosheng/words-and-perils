extends RefCounted
## Exact V3 source custody. Admission adds a separate gameplay identity; it never
## rewrites source scope, biomes, seed lineage, cleanup or renderer profile.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const Generator = preload("res://core/world_generation_v3/generator.gd")
const Geometry = preload("res://view/generated_v3_rivers/geometry.gd")
const Navigation = preload("res://view/generated_v3_rivers/navigation.gd")
const ID := "generated_v3_river_source/v1"
const PROFILE := "generated_v3_rivers_exploration/v1"
const SCENE := "scene_generated_v3_rivers"
const CELL_VERSION := "generated_v3_rivers_cell/v1"
const CELL := CELL_VERSION
const PROJECTION_ID := "generated_v3_rivers_public_context/v1"
const RENDERER_PROFILE := "structured_rivers_v1"
const TERRAIN_MAPPING_ID := "generated_v3_biome_terrain/v1"
const SPAWN_POLICY := "largest_actual_dry_river_clearance_component_degree_origin_lexical/v1"
const RIVER_PROFILE := "structured_rivers_v1"
const ADMISSION_SCOPE := "one_verified_source_hash/v1"
const VERIFIED_SOURCE_HASH := "ddbfb153ea7278c355092f7b3d5daba4d42c4363f126fdcdaba8b59263cc8009"
const TRAVERSAL_LIMITATION := "Temporary one-anchor-per-cell traversal: a wet river-center anchor is blocked. Remaining land in that cell is not inherently impassable. Bank anchors and crossings are not implemented."
const MAX_SOURCE_BYTES := 4 * 1024 * 1024
# Descriptive source biome is never changed. Only the separate legal terrain
# field maps into the unchanged trusted terrain_traversal/v1 integer costs.
const BIOME_TERRAIN := {"ocean":"ocean", "grassland":"grass", "dry_steppe":"grass", "desert":"arid", "temperate_forest":"forest", "jungle":"jungle", "alpine":"mountain", "wetland":"swamp"}
const SOURCE_FIELDS := ["schema_version","recipe_version","climate_version","seed_token","seed","normalization_version","board_radius","recipe","cells","river_edges","config","scope","source_cleanup","diagnostics","content_hash"]
const RAW_CELL_FIELDS := ["q","r","raw_elevation","elevation","plateau_weight","plateau_core","uplift","ocean","flow_to","fill_depth","slope_limited_elevation","temperature","moisture","rainfall","air_humidity","flow","biome","river"]
const DESCRIPTORS := ["biome","elevation","ocean","temperature","moisture","rainfall","flow","flow_to","river","uplift","plateau_weight","plateau_core"]
var data: Dictionary = {}
var world: Dictionary = {}
var navigation: RefCounted
var renderer_bundle: Dictionary = {}
var identity: Dictionary = {}
var immutable: Dictionary = {}
var spawn_component: Dictionary = {}

func admit(value: Variant, renderer_profile: String = RENDERER_PROFILE) -> Dictionary:
	if renderer_profile != RENDERER_PROFILE: return C.fail("V3_RENDERER_PROFILE", "此探索版本只支持 structured_rivers_v1；不会自动改用其他地形。")
	var checked := validate_source(value)
	if not checked.ok: return checked
	var pipeline_hash := pipeline_digest()
	if not valid_hash(pipeline_hash): return C.fail("RIVER_PIPELINE_IDENTITY", "A pinned river pipeline file is missing or unreadable; no world was admitted.")
	# Detach caller-owned JSON before the renderer/navigation retain references.
	value = C.normalized(value)
	var built: Dictionary = Geometry.build(value, renderer_profile)
	if not built.get("ok", false): return built
	if built.get("source_hash") != value.content_hash or built.get("renderer_profile") != renderer_profile or not valid_hash(built.get("geometry_hash")) or not valid_hash(built.get("water_hash")) or not valid_hash(built.get("river_layout_hash")) or not valid_hash(built.get("river_surface_hash")) or built.get("river_profile") != RIVER_PROFILE:
		return C.fail("V3_GEOMETRY_IDENTITY", "地形与地图来源不一致，未开启探索。")
	var nav := Navigation.new()
	checked = nav.build(value, built)
	if not checked.get("ok", false): return checked
	var start := choose_spawn(value, nav)
	if not start.ok: return start
	var cells := {}; var ids: Array = []
	var keys: Array = value.cells.keys(); keys.sort()
	for key in keys:
		var row: Dictionary = value.cells[key]
		var cell := {"id":"hex_%d_%d" % [int(row.q),int(row.r)], "q":int(row.q), "r":int(row.r), "scene_id":SCENE, "terrain":BIOME_TERRAIN[row.biome], "ground_blocked":not nav.supported[key], "air_blocked":false, "all_blocked":false, "source_cell_version":CELL_VERSION, "terrain_mapping_id":TERRAIN_MAPPING_ID}
		for field in DESCRIPTORS: cell[field] = row[field]
		cells[key] = cell; ids.append(cell.id)
	var source_identity := {"source_contract":ID,"profile":PROFILE,"source_schema":Generator.ID,"recipe_version":Generator.RECIPE_VERSION,"recipe_id":value.recipe.id,"seed":value.seed,"seed_token":value.seed_token,"board_radius":value.board_radius,"content_hash":value.content_hash,"renderer_profile":renderer_profile,"geometry_hash":built.geometry_hash,"water_hash":built.water_hash,"river_layout_hash":built.river_layout_hash,"river_surface_hash":built.river_surface_hash,"river_profile":str(built.get("river_profile",RIVER_PROFILE)),"admission_scope":ADMISSION_SCOPE,"navigation_id":Navigation.RIVER_ID,"projection_id":PROJECTION_ID,"terrain_mapping_id":TERRAIN_MAPPING_ID,"spawn_policy":SPAWN_POLICY,"pipeline_sha256":pipeline_hash}
	var runtime_hash := C.digest({"identity":source_identity,"cells":cells,"allowed_neighbors":nav.allowed,"spawn":start.hex,"component":start.component})
	source_identity["runtime_hash"] = runtime_hash
	var candidate := {"schema_version":"ai_gm_world/v1","world_id":"generated_v3_rivers_v1_"+runtime_hash,"state_version":0,"turn":0,"actors":{},"items":{},"hexes":cells,"scenes":{SCENE:{"id":SCENE,"name":"实体河流探索 · %s" % value.seed_token,"layer_id":"layer_overworld","hex_ids":ids,"renderer_id":renderer_profile,"navigation_id":Navigation.RIVER_ID,"bundle_id":built.geometry_hash}},"story_anchors":{"anchor_generated_v3_scope":{"id":"anchor_generated_v3_scope","text":"你是一位旅人，可以观察当前或相邻地格、沿可通行的干地移动、原地休息。行动先评估，再由程序结算。河槽与水面来自已校验的真实网格。暂时每格只有一个通行锚点：河心锚点入水时，该锚点不可达；不代表该格其余陆地不可通行。河岸锚点、渡河、桥梁、聚落、物品和战斗尚未实现。"}},"flags":{"observations":0,"last_observed_cell":""},"generated_world":source_identity,"board_radius":value.board_radius}
	candidate.actors.actor_player = {"id":"actor_player","name":"旅人","hex":start.hex,"scene_id":SCENE,"role":"player","faction":"traveler","health":{"current":12,"max":12},"stamina":{"current":8,"max":8},"inventory":[],"statuses":{},"hooks":["status_tick"]}
	candidate = C.normalized(candidate)
	checked = WorldSchema.validate(candidate)
	if not checked.ok: return checked
	# Publish only after source, exact emitted geometry and connected spawn agree.
	data = C.normalized(value); world = C.normalized(candidate); navigation = nav
	renderer_bundle = built; identity = C.normalized(source_identity)
	spawn_component = start.component.duplicate(true); immutable = immutable_fields(world)
	return {"ok":true,"identity":identity.duplicate(true),"start":start.hex.duplicate(),"component_size":spawn_component.size(),"navigation":checked_navigation(nav)}

static func checked_navigation(nav: RefCounted) -> Dictionary: return nav.diagnostics.duplicate(true)
static func valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true
static func validate_source(value: Variant) -> Dictionary:
	if not C.exact_fields(value,SOURCE_FIELDS) or not C.safe(value): return C.fail("V3_SOURCE_SCHEMA", "地图资料不完整，无法开启此版本探索。")
	if value.schema_version != Generator.ID or value.recipe_version != Generator.RECIPE_VERSION or value.climate_version != Generator.CLIMATE_VERSION: return C.fail("V3_SOURCE_VERSION", "地图生成版本不匹配，请使用原版本。")
	if not C.integer(value.board_radius) or int(value.board_radius) != 4: return C.fail("V3_SOURCE_RADIUS", "此实体河流探索首版只支持半径4；不会缩小或替换地图。")
	if not C.integer(value.seed) or absi(int(value.seed)) > 2147483647 or not value.seed_token is String or value.seed_token.is_empty() or value.seed_token.to_utf8_buffer().size() > 256 or not value.recipe is Dictionary or not value.recipe.get("id") in Generator.RECIPES: return C.fail("V3_SOURCE_RECIPE", "地图种子或配方无效。")
	# This first playable gate has an independent full-surface audit for exactly
	# this source. Synthetic/r12 geometry remains test-only; station-only bounds
	# are not advertised as arbitrary-seed whole-surface admission.
	if value.seed != 726381 or value.seed_token != "726381" or value.recipe.id != "coastal_range" or value.content_hash != VERIFIED_SOURCE_HASH:
		return C.fail("RIVER_SOURCE_NOT_VERIFIED", "实体河流首版仅准入已完成完整网格校验的种子726381、半径4、海岸配方；其他种子仍可使用原版，现有进度不会改写。")
	if not value.cells is Dictionary or value.cells.size() != 1+3*int(value.board_radius)*(int(value.board_radius)+1) or C.bytes(value).to_utf8_buffer().size() > MAX_SOURCE_BYTES: return C.fail("V3_SOURCE_BOUNDS", "地图大小或资料长度超出此版本范围。")
	var unsigned: Dictionary = value.duplicate(true); unsigned.erase("content_hash")
	if not valid_hash(value.content_hash) or C.digest(unsigned) != value.content_hash: return C.fail("V3_SOURCE_HASH", "地图内容已改变，未载入。")
	for key in value.cells:
		var row: Variant = value.cells[key]
		if not C.exact_fields(row,RAW_CELL_FIELDS) or not C.integer(row.q) or not C.integer(row.r) or key != "%d,%d" % [int(row.q),int(row.r)] or maxi(absi(int(row.q)),maxi(absi(int(row.r)),absi(int(row.q+row.r)))) > int(value.board_radius): return C.fail("V3_SOURCE_CELL", "地图坐标或地格资料无效。")
		if not row.biome is String or not BIOME_TERRAIN.has(row.biome) or not row.ocean is bool or not row.plateau_core is bool or not row.river is bool or not row.flow_to is String: return C.fail("V3_SOURCE_CELL", "地格类型或水流记录无效。")
		for field in ["raw_elevation","elevation","plateau_weight","uplift","fill_depth","slope_limited_elevation","temperature","moisture","rainfall","air_humidity","flow"]:
			var number: Variant = row[field]
			if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 65536.0 or float(number)*4096.0 != roundf(float(number)*4096.0): return C.fail("V3_SOURCE_NUMBER", "地格数值必须保持原地图的精确精度。")
	var regenerated: Dictionary = Generator.generate(value.seed_token,int(value.board_radius),value.recipe.id)
	if not regenerated.get("ok",false) or C.bytes(regenerated.get("source")) != C.bytes(value): return C.fail("V3_SOURCE_REPRODUCE", "地图不能按原种子和配方精确重建，未载入。")
	return {"ok":true}

static func choose_spawn(raw: Dictionary, nav: RefCounted) -> Dictionary:
	var keys: Array = raw.cells.keys(); keys.sort()
	var visited := {}; var best: Array = []
	for key in keys:
		if visited.has(key) or not nav.supported.get(key,false): continue
		var queue: Array = [key]; visited[key] = true; var cursor := 0
		while cursor < queue.size():
			var current: String = queue[cursor]; cursor += 1
			for neighbor in nav.allowed.get(current,[]):
				if not raw.cells.has(neighbor) or not nav.supported.get(neighbor,false) or not current in nav.allowed.get(neighbor,[]): return C.fail("V3_NAV_GRAPH", "可通行地格的连接资料不一致。")
				if not visited.has(neighbor): visited[neighbor] = true; queue.append(neighbor)
		queue.sort()
		if queue.size() > best.size() or (queue.size() == best.size() and not queue.is_empty() and String(queue[0]) < String(best[0])): best = queue
	var minimum := 7 if int(raw.board_radius) == 4 else 19
	if best.size() < minimum: return C.fail("V3_NO_CONNECTED_START", "这张地图没有足够连通的干地起点，未开启探索。")
	var chosen: String = best[0]
	for key in best:
		var degree: int = nav.allowed.get(key,[]).size(); var best_degree: int = nav.allowed.get(chosen,[]).size()
		var row: Dictionary = raw.cells[key]; var current: Dictionary = raw.cells[chosen]
		var distance := maxi(absi(int(row.q)),maxi(absi(int(row.r)),absi(int(row.q+row.r))))
		var best_distance := maxi(absi(int(current.q)),maxi(absi(int(current.r)),absi(int(current.q+current.r))))
		if degree > best_degree or (degree == best_degree and (distance < best_distance or (distance == best_distance and String(key) < chosen))): chosen = key
	if nav.allowed.get(chosen,[]).size() < 2: return C.fail("V3_NO_CONNECTED_START", "地图起点没有足够的干地出口。")
	var component := {}
	for key in best: component[key] = true
	return {"ok":true,"hex":[int(raw.cells[chosen].q),int(raw.cells[chosen].r)],"component":component}

static func pipeline_digest() -> String:
	var hashes := {}
	for path in ["res://core/world_generation_v3/generator.gd","res://core/world_generation_v3/tiny_remnant_cleanup.gd","res://view/generated_v3_rivers/geometry.gd","res://view/generated_v3_rivers/structured_builder.gd","res://view/generated_v3_rivers/navigation.gd","res://view/generated_v3_runtime/navigation.gd","res://core/generated_v3_rivers/layout.gd","res://view/generated_v3_rivers/water_queries.gd","res://view/generated_v3_rivers/source.gd","res://view/generated_v3_rivers/projection.gd","res://view/generated_v3_rivers/resolver.gd","res://view/generated_v3_rivers/rule.gd","res://view/generated_v3_rivers/assessments.gd"]:
		var file_hash := FileAccess.get_sha256(path)
		if not valid_hash(file_hash): return ""
		hashes[path] = file_hash
	return C.digest(hashes)
static func immutable_fields(state: Dictionary) -> Dictionary:
	var result := {}
	for key in ["schema_version","world_id","hexes","scenes","story_anchors","generated_world","board_radius","items"]: result[key] = state.get(key)
	return C.normalized(result)
func validate_state(state: Variant) -> Dictionary:
	var checked: Dictionary = WorldSchema.validate(state)
	if not checked.ok: return checked
	if not C.exact_fields(state,world.keys()) or C.bytes(immutable_fields(state)) != C.bytes(immutable): return C.fail("V3_IDENTITY", "世界状态与原地图或地形版本不一致。")
	if state.actors.keys() != ["actor_player"]: return C.fail("V3_ACTORS", "此版本只支持一位旅人。")
	var actor: Dictionary = state.actors.actor_player
	var fixed: Dictionary = actor.duplicate(true); var original: Dictionary = world.actors.actor_player.duplicate(true)
	fixed.erase("hex"); original.erase("hex"); fixed.stamina.erase("current"); original.stamina.erase("current")
	if C.bytes(fixed) != C.bytes(original): return C.fail("V3_ACTOR_CONTRACT", "旅人身份或能力与此版本不一致。")
	if not spawn_component.has("%d,%d" % actor.hex) or not navigation.supported.get("%d,%d" % actor.hex,false): return C.fail("V3_LANDING", "旅人位置不在已验证连通的干地上。")
	if not C.exact_fields(state.flags,["observations","last_observed_cell"]) or not C.integer(state.flags.observations) or state.flags.observations < 0 or state.flags.observations > state.turn or not state.flags.last_observed_cell is String or (not state.flags.last_observed_cell.is_empty() and not state.hexes.has(state.flags.last_observed_cell)) or (state.flags.observations == 0) != state.flags.last_observed_cell.is_empty(): return C.fail("V3_FLAGS", "观察记录无效。")
	if state.state_version != state.turn: return C.fail("V3_TURN", "行动回合与世界版本不一致。")
	return {"ok":true}
func render_state(state: Dictionary) -> Dictionary:
	if not validate_state(state).ok: return {}
	var result := state.duplicate(true)
	result["generated_v3_rivers_source"] = data.duplicate(true)
	return result
