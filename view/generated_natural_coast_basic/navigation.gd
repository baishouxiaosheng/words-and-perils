extends "res://view/generated_v3_runtime/navigation.gd"
## Natural-coast identity seam. Triangle support, route union and costs are inherited.
const COAST_ID := "natural_coast_mesh_sea_navigation/v1"
func plan(state: Dictionary,target: Variant,budget: int) -> Dictionary:
	var identity: Dictionary=state.get("generated_world",{})
	if identity.get("content_hash","")!=source_hash or identity.get("geometry_hash","")!=geometry_hash or identity.get("renderer_profile","")!=renderer_profile or identity.get("source_contract","")!="natural_coast_source/v1":
		return C.fail("BUNDLE_MISMATCH","Navigation belongs to another exact v3 source or native mesh.")
	return Policy.plan(state,"actor_player",target,budget,func(a,b):return step(a,b))
