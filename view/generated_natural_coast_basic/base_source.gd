extends RefCounted
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const WorldSchema = preload("res://core/ai_gm_rebuilt/world.gd")
const LegacySource = preload("res://view/generated_v3_adventure/source.gd")
const Custody = preload("res://view/generated_v3_natural_coast/source_custody.gd")
const Navigation = preload("res://view/generated_natural_coast_basic/navigation.gd")
const ID := "natural_coast_source/v1"
const PROFILE := "natural_coast_physical_world/v1"
const SCENE := "scene_natural_coast_basic_v1"
const CELL_VERSION := "generated_v3_cell/v1"
const RENDERER_PROFILE := "natural_coast_shared_chain/experimental2"
const PROJECTION_ID := "natural_coast_basic_context/v1"
const TERRAIN_MAPPING_ID := "generated_v3_biome_terrain/v1"
const SPAWN_POLICY := "largest_actual_dry_component_degree_origin_lexical/v1"
const BIOME_TERRAIN := LegacySource.BIOME_TERRAIN
const DESCRIPTORS := LegacySource.DESCRIPTORS
var data: Dictionary = {}
var identity: Dictionary = {}
var world: Dictionary = {}
var renderer_bundle: Dictionary = {}
var navigation: RefCounted
var custody: RefCounted
var spawn_component: Dictionary = {}
static func valid_hash(value: Variant) -> bool: return LegacySource.valid_hash(value)
func admit(value: Variant, renderer_profile: String = RENDERER_PROFILE) -> Dictionary:
	if renderer_profile != RENDERER_PROFILE: return C.fail("COAST_RENDERER_PROFILE","此入口需要独立自然海岸地形；不会替换旧地形身份。")
	var physical := Custody.new()
	var checked: Dictionary = physical.admit(value)
	if not checked.ok: return checked
	var nav := Navigation.new()
	checked = nav.build(physical.data,physical.renderer_bundle)
	if not checked.ok: return checked
	var stable_nav := {"supported":nav.supported,"support_heights":nav.support_heights,"allowed":nav.allowed}
	if C.digest(stable_nav) != physical.identity.navigation_content_hash: return C.fail("COAST_NAV_PARITY","游戏通行资料与冻结物理来源不一致。")
	var start: Dictionary = LegacySource.choose_spawn(physical.data,nav)
	if not start.ok: return start
	var cells := {}; var ids: Array = []
	var keys: Array = physical.data.cells.keys(); keys.sort()
	for key in keys:
		var row: Dictionary = physical.data.cells[key]
		var cell := {"id":"hex_%d_%d" % [int(row.q),int(row.r)],"q":int(row.q),"r":int(row.r),"scene_id":SCENE,"terrain":BIOME_TERRAIN[row.biome],"ground_blocked":not nav.supported[key],"air_blocked":false,"all_blocked":false,"source_cell_version":CELL_VERSION,"terrain_mapping_id":TERRAIN_MAPPING_ID}
		for field in DESCRIPTORS: cell[field] = row[field]
		cells[key] = cell; ids.append(cell.id)
	var source_identity := {"source_contract":ID,"profile":PROFILE,"source_schema":physical.data.schema_version,"recipe_version":physical.data.recipe_version,"recipe_id":physical.data.recipe.id,"seed":physical.data.seed,"seed_token":physical.data.seed_token,"board_radius":physical.data.board_radius,"content_hash":physical.data.content_hash,"renderer_profile":renderer_profile,"geometry_hash":physical.identity.geometry_hash,"water_hash":physical.identity.water_hash,"shore_graph_hash":physical.identity.shore_graph_hash,"navigation_id":Navigation.COAST_ID,"navigation_content_hash":physical.identity.navigation_content_hash,"projection_id":PROJECTION_ID,"terrain_mapping_id":TERRAIN_MAPPING_ID,"spawn_policy":SPAWN_POLICY,"pipeline_sha256":physical.identity.pipeline_sha256,"physical_custody":physical.identity.duplicate(true)}
	source_identity["runtime_hash"] = C.digest({"identity":source_identity,"cells":cells,"allowed_neighbors":nav.allowed,"spawn":start.hex,"component":start.component})
	var candidate := {"schema_version":"ai_gm_world/v1","world_id":"natural_coast_physical_v1_"+source_identity.runtime_hash,"state_version":0,"turn":0,"actors":{},"items":{},"hexes":cells,"scenes":{SCENE:{"id":SCENE,"name":"自然海岸探索 · "+physical.data.recipe.id,"layer_id":"layer_overworld","hex_ids":ids,"renderer_id":renderer_profile,"navigation_id":Navigation.COAST_ID,"bundle_id":physical.identity.geometry_hash}},"story_anchors":{"anchor_generated_v3_scope":{"id":"anchor_generated_v3_scope","text":"独立自然海岸基础探索。"}},"flags":{"observations":0,"last_observed_cell":""},"generated_world":source_identity,"board_radius":physical.data.board_radius}
	candidate.actors.actor_player = {"id":"actor_player","name":"旅人","hex":start.hex,"scene_id":SCENE,"role":"player","faction":"traveler","health":{"current":12,"max":12},"stamina":{"current":8,"max":8},"inventory":[],"statuses":{},"hooks":["status_tick"]}
	candidate = C.normalized(candidate)
	checked = WorldSchema.validate(candidate)
	if not checked.ok: return checked
	custody = physical; data = physical.data; renderer_bundle = physical.renderer_bundle; navigation = nav
	world = candidate; identity = C.normalized(source_identity); spawn_component = start.component.duplicate(true)
	return {"ok":true,"identity":identity.duplicate(true),"start":start.hex.duplicate(),"component_size":spawn_component.size(),"navigation":navigation.diagnostics.duplicate(true)}
