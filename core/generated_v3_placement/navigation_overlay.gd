extends RefCounted
## Opt-in physical obstruction layer; the frozen terrain graph remains intact.
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
const Policy=preload("res://core/ai_gm_rebuilt/traversal_policy.gd")
const Planner=preload("res://core/generated_v3_placement/planner.gd")
const ID="generated_v3_placement_navigation/v1"
var base: RefCounted
var placement_hash=""
var placement_profile=""
var source_hash=""
var geometry_hash=""
var renderer_profile=""
var allowed: Dictionary={}
var supported: Dictionary={}
var support_heights: Dictionary={}
var diagnostics: Dictionary={}
# PRECONDITION: manifest is a fresh Planner.build result, or persisted input has
# passed Planner.validate exact regeneration. This wrapper never authenticates
# a self-rehashed saved manifest by its hash alone.
func build(base_nav: RefCounted,manifest: Dictionary) -> Dictionary:
	var unsigned=manifest.duplicate(true);var supplied=unsigned.get("placement_hash","");unsigned.erase("placement_hash")
	if C.digest(unsigned)!=supplied or manifest.get("profile_id")!=Planner.PROFILE or manifest.get("schema_version")!=Planner.ID:return C.fail("PLACEMENT_NAV_HASH","Placement must be verified before navigation admission.")
	if base_nav.source_hash!=manifest.get("source_hash") or base_nav.geometry_hash!=manifest.get("geometry_hash") or C.bytes(base_nav.allowed)!=C.bytes(manifest.get("base_allowed_neighbors",{})):return C.fail("PLACEMENT_NAV_SOURCE","Placement graph belongs to another native source.")
	base=base_nav;placement_hash=supplied;placement_profile=manifest.profile_id;source_hash=base.source_hash;geometry_hash=base.geometry_hash;renderer_profile=base.renderer_profile
	allowed=manifest.allowed_neighbors.duplicate(true);supported=base.supported.duplicate(true);support_heights=base.support_heights.duplicate(true)
	for cell in base.allowed:
		if not allowed.has(cell):return C.fail("PLACEMENT_NAV_DOMAIN","Placement graph omitted an original cell.")
		for next in allowed[cell]:
			if not next in base.allowed[cell] or not cell in allowed.get(next,[]):return C.fail("PLACEMENT_NAV_EDGE","Placement graph adds or asymmetrically changes terrain edges.")
	diagnostics={"navigation_id":ID,"source_hash":source_hash,"geometry_hash":geometry_hash,"placement_hash":placement_hash,"placement_profile":placement_profile,"blocked_undirected_edges":manifest.blocked_edges.size(),"terrain_cost_modifier":1,"actor_clearance_radius":manifest.actor_clearance_radius}
	return {"ok":true}
func cell_center(hex: Array) -> Vector3:return base.cell_center(hex)
func cell_at_xz(point: Vector2) -> Dictionary:return base.cell_at_xz(point)
func height_at_xz(point: Vector2) -> Dictionary:return base.height_at_xz(point)
func step(from: Array,to: Array) -> Dictionary:
	var checked=base.step(from,to)
	if not checked.ok:return checked
	if not Planner.key(to) in allowed.get(Planner.key(from),[]):return C.fail("SETTLEMENT_OBSTRUCTION","A source-bound village building obstructs this ground route; use its clear entry.")
	return {"ok":true}
func route_points(route: Array) -> Array:
	for i in range(1,route.size()):
		if not step(route[i-1],route[i]).ok:return []
	return base.route_points(route)
func plan(state: Dictionary,target: Variant,budget: int) -> Dictionary:
	var identity: Dictionary=state.get("generated_world",{})
	if identity.get("source_contract")!="generated_v3_source/v1" or identity.get("content_hash")!=source_hash or identity.get("geometry_hash")!=geometry_hash or identity.get("renderer_profile")!=renderer_profile or identity.get("placement_hash")!=placement_hash or identity.get("placement_profile")!=placement_profile:
		return C.fail("PLACEMENT_NAV_IDENTITY","World and physical placement identities do not match; no movement was performed.")
	return Policy.plan(state,"actor_player",target,budget,func(a,b):return step(a,b))
func export_data(origin_hex: Array=[]) -> Dictionary:
	return {"source_hash":source_hash,"geometry_hash":geometry_hash,"renderer_profile":renderer_profile,"placement_hash":placement_hash,"placement_profile":placement_profile,"allowed":allowed.duplicate(true),"supported":supported.duplicate(true),"support_heights":support_heights.duplicate(true),"spawn":origin_hex.duplicate(),"diagnostics":diagnostics.duplicate(true)}
