# Seed-bound dry village profile v1 (implementation contract)

Owned by terrain placement lane. V17 source generator, native Geometry/Navigation and ordinary exploration remain unchanged. Gameplay owns admission, save namespace, public entity catalog and UI. This profile must be explicitly admitted for a new game; it must never be injected into an older save.

## Native API

- `core/generated_v3_placement/planner.gd`: `static build(source:Dictionary,built:Dictionary,base_nav:RefCounted,origin_hex:Array)->Dictionary` returns `{ok,manifest,placement_hash,surface,diagnostics}` or a precise failure. Does not mutate any input.
- `asset_catalog.gd`: selects the existing original cottage_a, barn and cottage_b full/LOD1 meshes, retains exact SHA identities and conservative measured full-AABB bounds. No new model or external asset license is introduced.
- `surface.gd`: reads the actual built ground ArrayMesh, bins triangles and clips complete convex envelopes. All support checks inspect interior triangle pieces, not perimeter samples. It also supplies source-conforming road/foundation geometry.
- `navigation_overlay.gd`: derived static blocked-edge graph, wraps base-nav center/height/route APIs and existing terrain/stamina policy. No road speed or stamina discount. Requires exact placement identity when active. A new Planner.build result may be installed; any persisted/external manifest MUST pass Planner.validate exact source-bound regeneration before this wrapper is constructed. Hash self-consistency alone does not authenticate a placement. Admission owner will choose this wrapper only for the new placement-enabled profile.
- `view/generated_v3_settlement/settlement_view.gd`: renders only an admitted manifest, actual surface and approved kit. No authority or save mutation.

## Fixed first profile

One one-hex village, three buildings at radial offset0.65, facing the plaza. Existing fitted reserved radii0.18/0.15/0.13 are retained. The actor's actual current sole radius0.332 motivates a conservative0.35 movement clearance radius, not the legacy0.26. At least one actual building envelope must obstruct a source neighbor segment. Blocked edges are symmetric and derived from those envelopes. Placement must preserve connectivity of the original origin component and retain a fully dry, clear entry neighbor.

Village and entry cells marked river=true in the persisted source are categorically reserved. The exact rule is included in the context identity as source_site_and_entry_cells/v1. No width, buffer or channel geometry is invented from that flag, and no physical river-clearance proof is claimed. If the reservation leaves no eligible site/entry, the profile fails closed.

Original source/mesh/biome values are unchanged. Seed/source-bound ranking considers eligible cells at graph distance≥2 from origin. Unsupported candidates are skipped deterministically, without changing source seed or parameters. If none fits, return placement-unavailable; never silently shrink assets, relax limits or rewrite terrain.

All building full-AABB polygons must be fully covered and dry above0.01; maximum actual triangle gradient0.18; maximum support height spread0.06. Foundation top is a quantized horizontal plane just above maximum support, with a source-conforming foundation below it. Plaza clearance circle radius0.35: gradient≤0.30, spread≤0.20. Entry road traveler corridor radius0.35: gradient≤0.45, complete positive support. Road art width0.40 is clipped to the real triangle boundaries, with a small explicit visual lift. These are one declared architectural profile, not universal movement limits.

The16-sided circle approximation is circumscribed, not inscribed, so it contains the stated physical disk. Persisted placement transforms/envelopes/support metrics use a1/4096 grid before eligibility checks, matching the proven source persistence precision. Actual native float32 centerline and anchor coordinates use integer q40 transport (scale1099511627776), which preserves these native values exactly while avoiding Godot JSON float parser last-bit drift. Persisted support min/max/gradient/spread fields are outward-rounded conservative bounds; eligibility is evaluated against the unrounded complete native triangle intersections before those diagnostics are serialized. They are not a relaxation of the limits.

Clearance envelopes conservatively include the full projected asset AABB including eaves. LOD1 bounds must stay inside the full mesh bounds; switch only the mesh, never refit or recenter.

## Manifest shape

`schema_version: generated_v3_placement/v1`, `profile_id: dry_village/v1`, exact source_hash/geometry_hash/renderer_profile, asset_catalog_hash, context_hash, origin_hex, placement_hash.

Context hash covers source identity, profile, asset catalog and origin. Stable entity IDs use that context namespace; placement_hash then covers the complete manifest without circular ID derivation.

- settlements: id, name, kind=village, center_hex, footprint_hexes(one), entry_hex, building_ids, road_ids
- buildings: id, settlement_id, asset_id, asset_sha256, lod1_sha256, position[x,y,z], yaw_radians, scale, footprint[x,z] polygon, clearance_envelope[x,z] polygon, foundation_plane[0,0,y], support_limits and measured support
- roads: id, settlement_id, route_hexes, centerline_q40[integer x,integer y,integer z], centerline_scale=1099511627776, width, clearance_radius, footprint[x,z], clearance_envelope[x,z], visual_lift, terrain_cost_modifier=1
- entry_anchors: role, hex, position_q40[integer x,integer y,integer z], position_scale=1099511627776
- blocked_edges: from/to hexes, building_ids, reason=building_clearance
- allowed_neighbors: exact source graph minus verified physical obstructions

All polygons are convex and consistently wound. Any concave future shape must be decomposed. Physical exports include actual mesh identity, every footprint/corridor and support plane for independent full-area subtraction QA.

## Acceptance

Deterministic repetition/JSON roundtrip, input preservation, wrong identity and tamper rejection, all-river/no-eligible fail-closed negative, wet-interior and coverage-hole negatives, slope/spread/overlap negatives, .332 actor-clearance regression, exact blocked edges, reachable entry and preserved origin component, source-conforming road vertices, actual GLB bounds, LOD containment, clear close/whole-map views. No gate, room entry, NPC behavior, item creation, city economy or physical rivers in this first profile.
