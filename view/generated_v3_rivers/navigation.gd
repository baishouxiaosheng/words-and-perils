extends "res://view/generated_v3_runtime/navigation.gd"
## New physical-water filter over the unchanged actual-ground triangle oracle.
## Wet river centers are temporarily unsupported in the one-anchor-per-cell model.
const RIVER_ID = "generated_v3_native_ground_water_clearance/v1"
const WaterQueries = preload("res://view/generated_v3_rivers/water_queries.gd")
const ACTOR_WATER_CLEARANCE = 0.38
var water_hash: String = ""
var river_layout_hash: String = ""
var water_queries: RefCounted
var river_ready: bool = false

func build(source: Dictionary, built: Dictionary) -> Dictionary:
	river_ready = false; water_hash = ""; river_layout_hash = ""; water_queries = null
	if built.get("renderer_profile") != "structured_rivers_v1" or not built.get("water_mesh") is ArrayMesh:
		return C.fail("RIVER_NAV_PROFILE", "Physical river navigation requires its exact new renderer profile.")
	var checked: Dictionary = super.build(source,built)
	if not checked.ok: return checked
	var query := WaterQueries.new()
	checked = query.build(built.water_mesh,str(built.get("water_hash","")))
	if not checked.ok: return checked
	water_queries = query; water_hash = query.water_hash
	river_layout_hash = str(built.get("river_layout_hash",""))
	if river_layout_hash.length() != 64: return C.fail("RIVER_NAV_LAYOUT", "River layout identity is missing.")
	var original_supported: int = 0; var rejected_anchors: int = 0
	var keys: Array = source.cells.keys(); keys.sort()
	for key in keys:
		if not supported.get(key,false): continue
		original_supported += 1
		var c: Dictionary = source.cells[key]; var p: Vector3 = raw_center([c.q,c.r])
		var contact: Dictionary = query.point_contact(Vector2(p.x,p.z),ACTOR_WATER_CLEARANCE)
		if not contact.ok: return contact
		if contact.intersects: supported[key] = false; rejected_anchors += 1
	var removed: Array = []; var remaining: int = 0
	for a in keys:
		var row: Dictionary = source.cells[a]; var start: Vector3 = raw_center([row.q,row.r])
		for b in allowed[a].duplicate():
			if a >= b: continue
			var next: Dictionary = source.cells[b]; var finish: Vector3 = raw_center([next.q,next.r])
			var reason: String = ""
			if not supported.get(a,false) or not supported.get(b,false): reason = "water_clearance_anchor"
			else:
				var contact: Dictionary = query.segment_contact(Vector2(start.x,start.z),Vector2(finish.x,finish.z),ACTOR_WATER_CLEARANCE)
				if not contact.ok: return contact
				if contact.intersects: reason = "water_clearance_route"
			if not reason.is_empty():
				allowed[a].erase(b); allowed[b].erase(a)
				_edge_points.erase(a+"|"+b); _edge_points.erase(b+"|"+a)
				removed.append({"from":a,"to":b,"reason":reason})
			else: remaining += 1
	for key in allowed: allowed[key].sort()
	diagnostics["navigation_id"] = RIVER_ID
	diagnostics["water_hash"] = water_hash; diagnostics["river_layout_hash"] = river_layout_hash
	diagnostics["water_authority"] = "actual visible sea and elevated river triangles"
	diagnostics["actor_water_clearance"] = ACTOR_WATER_CLEARANCE
	diagnostics["center_anchor_limit"] = "one anchor per cell; wet center unavailable, remaining land is not inherently impassable; no bank-anchor or crossing capability"
	diagnostics["dry_anchors_before_water_filter"] = original_supported
	diagnostics["water_clearance_rejected_anchors"] = rejected_anchors
	diagnostics["water_clearance_removed_edges"] = removed
	diagnostics["dry_undirected_edges"] = remaining
	diagnostics["blocked_undirected_edges"] = int(diagnostics.checked_undirected_edges)-remaining
	diagnostics["water_query"] = query.diagnostics.duplicate(true)
	river_ready = true
	return {"ok":true,"diagnostics":diagnostics.duplicate(true)}

func step(from: Array, to: Array) -> Dictionary:
	if not river_ready: return C.fail("WATER_QUERY_FAILED", "Physical river navigation has not been admitted.")
	if from.size()!=2 or to.size()!=2 or not C.integer(from[0]) or not C.integer(from[1]) or not C.integer(to[0]) or not C.integer(to[1]):
		return C.fail("RIVER_NAV_HEX", "Movement needs two exact current-map coordinates.")
	var a: String = "%d,%d" % [int(from[0]),int(from[1])]; var b: String = "%d,%d" % [int(to[0]),int(to[1])]
	if not supported.get(a,false) or not supported.get(b,false):
		return C.fail("RIVER_WET_ANCHOR", "This center anchor lacks dry water clearance. Bank anchors and crossings are not implemented; no movement was performed.")
	if not b in allowed.get(a,[]) or not a in allowed.get(b,[]):
		return C.fail("RIVER_WET_ROUTE", "No complete ground-supported, water-clear route is admitted. A visible bridge or narrative cannot grant crossing.")
	return {"ok":true}

func route_points(route: Array) -> Array:
	if not river_ready or route.is_empty(): return []
	for i in range(route.size()):
		var h: Variant = route[i]
		if not h is Array or h.size()!=2 or not C.integer(h[0]) or not C.integer(h[1]): return []
		if not supported.get("%d,%d" % [int(h[0]),int(h[1])],false): return []
		if i>0 and not step(route[i-1],h).ok: return []
	return super.route_points(route)

func plan(state: Dictionary, target: Variant, budget: int) -> Dictionary:
	var identity: Variant = state.get("generated_world",{})
	if not river_ready or not identity is Dictionary or identity.get("source_contract") != "generated_v3_river_source/v1" or identity.get("content_hash")!=source_hash or identity.get("geometry_hash")!=geometry_hash or identity.get("water_hash")!=water_hash or identity.get("river_layout_hash")!=river_layout_hash or identity.get("renderer_profile")!=renderer_profile:
		return C.fail("BUNDLE_MISMATCH", "Movement belongs to another exact source, ground, river layout or water mesh.")
	return Policy.plan(state,"actor_player",target,budget,func(a,b): return step(a,b))

func export_data(spawn: Array = []) -> Dictionary:
	var result: Dictionary = super.export_data(spawn)
	result["water_hash"] = water_hash; result["river_layout_hash"] = river_layout_hash
	return result
