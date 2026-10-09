extends RefCounted
## Synthetic JSON transport only. These rows are deliberately NOT physical
## admission evidence and must never be substituted for Planner.validate.
const C = preload("res://core/ai_gm_rebuilt/canonical.gd")
const Catalog = preload("res://core/generated_v3_vegetation/catalog.gd")
const PROFILE := "generated_v3_vegetation_transport_test/v1"
static func digest(value: String) -> String: return value.sha256_text()
static func seal(value: Dictionary, field: String) -> void:
	value.erase(field); value[field] = C.digest(value)
static func assets() -> Dictionary:
	var pins: Dictionary = {}; var records: Dictionary = {}
	for path in Catalog.PIN_PATHS: pins[path] = digest(path)
	for kind in Catalog.KINDS:
		records[kind] = {"id":kind, "habit":Catalog.habit(kind), "full_sha256":digest(kind + ":full"), "far_sha256":digest(kind + ":far"), "triangles":63, "far_triangles":7, "visual_bounds":{"min":[-1,0,-1], "max":[1,1,1]}, "root_bounds":{"min":[-1,0,-1], "max":[1,0,1]}, "solid_bounds":{"min":[-1,0,-1], "max":[1,1,1]}, "canopy_bounds":{"min":[-1,0,-1], "max":[1,1,1]}, "source_minimum_y_q40":0, "minimum_y_scale":1099511627776, "same_projected_footprint":true}
	var result := {"schema_version":Catalog.ASSET_ID, "pins":pins, "assets":records, "license":"Synthetic transport fixture; not admitted native geometry"}
	seal(result, "catalog_hash")
	return result
static func transport(count: int = 18) -> Dictionary:
	var asset_catalog := assets()
	var source := {"source_contract":"unit_vegetation_source/v1", "content_hash":digest("source"), "geometry_hash":digest("geometry"), "runtime_hash":digest("upstream_runtime"), "placement_hash":digest("village"), "effective_navigation_hash":digest("navigation")}
	var manifest := {"schema_version":Catalog.MANIFEST_ID, "profile_id":Catalog.PROFILE, "source_hash":source.content_hash, "geometry_hash":source.geometry_hash, "renderer_profile":"structured_v1", "placement_hash":source.placement_hash, "navigation_hash":source.effective_navigation_hash, "asset_catalog_hash":asset_catalog.catalog_hash, "reservation_hash":C.digest([]), "origin_hex":[-12,-12], "river_reservation":"full_source_river_cells/v1"}
	manifest["context_hash"] = C.digest(manifest)
	var plants: Array = []
	var cells: Array = []
	# Put the first seven roots near the player and all later roots farther out.
	for q in range(-12,13):
		for r in range(-12,13):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) <= 12: cells.append([q,r])
	cells.sort_custom(func(a,b):
		var ad: int = maxi(absi(a[0]), maxi(absi(a[1]), absi(a[0] + a[1])))
		var bd: int = maxi(absi(b[0]), maxi(absi(b[1]), absi(b[0] + b[1])))
		return C.bytes(a) < C.bytes(b) if ad == bd else ad < bd)
	for i in count:
		var hex: Array = cells[i / 6]
		var root := [[0,0],[0.0625,0],[0.0625,0.0625],[0,0.0625]]
		var support := {"ok":true,"min_height":0.5,"max_height":0.5078125,"max_gradient":0.125,"height_spread":0.0078125,"area":0.00390625,"uncovered_area_upper_bound":0,"intersected_triangles":2}
		var bounds := {"min":[0,0.5,0],"max":[0.0625,0.625,0.0625]}
		var row := {"id":"vegetation:v3:" + manifest.context_hash.substr(0,16) + ":%d_%d:%d" % [hex[0],hex[1],i % 6], "hex":hex, "biome":"dry_steppe", "asset_id":"shrub", "position":[hex[0],0.5,hex[1]], "radius":0.0625, "height":0.125, "yaw":0, "tint":1, "root_footprint":root, "solid_footprint":root, "canopy_footprint":root, "solid_envelope":root, "support":support, "canopy_support":support, "solid_kind":"low_foliage", "visual_bounds":bounds, "far_bounds":bounds, "root_bounds":bounds, "canopy_ground_gap":-0.0078125}
		seal(row, "row_hash"); plants.append(row)
	plants.sort_custom(func(a,b):return a.id < b.id)
	manifest.merge({"plants":plants, "solid_clearance_radius":0.38, "limits":{"max_plants":1024,"max_full_triangles":80000,"max_active_batches":64,"dry_clearance":0.01,"root_max_gradient":0.55,"root_max_spread":0.04,"low_max_gradient":0.30,"low_max_spread":0.016,"root_embed":0.003}, "statistics":{"instances":count,"full_triangles":count * 63,"biomes":{} if count == 0 else {"dry_steppe":count},"assets":{} if count == 0 else {"shrub":count}}, "scope":{"source_biomes_unchanged":true,"navigation_unchanged":true,"solid_policy":"stem_or_low_foliage_outside_existing_corridors/v1","canopy_is_navigation_wall":false,"cover_or_harvest_gameplay":false,"selection_is_action":false}})
	seal(manifest, "vegetation_hash")
	return C.normalized({"source":source,"manifest":manifest,"assets":asset_catalog})
static func world(input: Dictionary, catalog: Dictionary) -> Dictionary:
	var metadata: Dictionary = input.source.duplicate(true)
	metadata.merge({"profile":PROFILE,"runtime_hash":digest("composed_runtime"),"vegetation_base_runtime_hash":input.source.runtime_hash,"vegetation_profile":Catalog.PROFILE,"vegetation_hash":input.manifest.vegetation_hash,"vegetation_catalog_hash":catalog.catalog_hash,"vegetation_entity_catalog":catalog}, true)
	var state := {"world_id":"vegetation_test_world","turn":0,"state_version":0,"actors":{"actor_player":{"id":"actor_player","hex":[0,0],"scene_id":"test_scene"}},"items":{},"scenes":{"test_scene":{"id":"test_scene"}},"hexes":{},"generated_world":metadata,"flags":{}}
	for row in input.manifest.plants:
		var key := "%d,%d" % row.hex
		state.hexes[key] = {"id":"hex_" + key.replace(",","_"),"q":row.hex[0],"r":row.hex[1],"scene_id":"test_scene","biome":row.biome,"terrain":"steppe","ocean":false,"river":false,"secret_cell_note":"not public"}
	return C.normalized(state)
