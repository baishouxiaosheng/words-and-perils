# Sparse biome vegetation interface (map-side native and independent QA accepted)

New files only; v18 terrain, village placement, inventory and static catalogs stay frozen.

- Placement schema `generated_v3_vegetation/v1`, profile `sparse_biomes/v1`.
- `Planner.build(source,built,navigation,placement_result,origin_hex,npc_reservations=[])` returns `{ok,manifest,assets,surface,diagnostics}`.
- `Planner.validate` must deterministically regenerate an external manifest before authority admission.
- Binding: exact source content hash, native geometry hash, village placement hash, effective navigation digest, asset catalog digest and reservation digest. Source cells/biomes and graph are unchanged.
- All numeric persisted transforms/footprints are q12. Every eligibility test is on the quantized values; integer-safe lossless coordinates are used if a native exact point is persisted.
- Manifest `plants` is a stable ID-sorted array. Each row has `id`, `hex`, `biome`, `asset_id`, `position:[x,y,z]`, `radius`, `height`, `yaw`, `tint`, `root_footprint`, `solid_footprint`, `canopy_footprint`, `support`, `row_hash`.
- Transform is `Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(radius,height,radius)),position)`; do not refit/recenter/rescale it.
- Asset IDs: `temperate`, `tropical`, `sapling`, `shrub`, `tuft`, `reed`. Assets result has `full_meshes` and `far_meshes` dictionaries of shared native ArrayMeshes keyed by asset ID, and `catalog` for exact raw buffer hashes/bounds/triangle counts. Tuft and reed use their full mesh at both LODs.
- The root surface is the already-verified village placement surface. No duplicate terrain bins.
- Trunk and low-foliage solidity are distinct from projected canopy. Stem or low-foliage solid envelopes stay outside admitted .38-radius full-plinth walking corridors. Woody crowns may overhang paths or overlap each other; they are not navigation walls. Actual canopy occlusion is tested separately. No graph mutation.
- Exclude source river-marked/ocean cells, spawn, village and entry cells and supplied NPC reservations. Keep roots within their declared source hex. Complete canopies avoid all reserved full cells/NPC footprints and have full-area dry support. A canopy may cross other dry source-cell borders; its identity and observation target remain its root cell. Full native footprint dry-support checks, fixed slope/embed thresholds, deterministic bounded candidates.

## Rendering ownership

`VegetationView.configure(result)` installs already-admitted rows/meshes, returns `{ok,report}`. `update_lod(camera)`, `report()`, `pick(origin,direction,limit)` and `select(id)` are public. Query returns actual current-LOD raw triangle hits `{id,hex,distance,point}` only; no catalog authority is synthesized by the renderer.

Use the existing material and shape factories. Batch by asset and fixed16-world-unit chunks offset by(+24,+24), at most54 active vegetation draws for the admitted r12 bounds. Full/far same-footprint LOD,22/20 camera-size hysteresis, shadows off. Do not use approximate circle hits, get_faces, per-plant scene nodes, or legacy cached instance identities. Selection highlight is excluded from picking. Mesh resources and immutable raw triangles are shared; no per-frame mesh rebuilding.

Hard budgets:1,024 plants,80,000 added full-LOD triangles,64 active batches. Measure native source admission, added memory, draw/primitive counts, complete pointer queries and matched whole-map/normal/closest images. GTX1660Ti30fps is a target only.

## Authority boundary

NEW vegetation catalog/focus/projection, never add plants to static catalog/v1. Stable `kind=vegetation`, revision0, exact selected source row/asset/biome. Clicking is read-only selection/priority context; observing still uses an assessed turn. No forage/cut/cover/custody capability.

Full authoritative rows remain in placement. Model requests contain only the selected compact descriptor and a tightly bounded nearby page, with truthful total/count/omission schema. Plan for <=2KiB vegetation projection because v18's worst current request already uses61,807 of65,536 bytes. Final combined NPC/plant request budget must be measured, not inferred.

## Full-plinth correction before freeze

The native traveler has a .332 sole but a .38 full visible plinth. The draft profile reserves .38 for plant stems/low foliage. Candidate radial distance is derived once from each unchanged scaled solid mesh radius plus the fixed conservative corridor expansion and margin; it never shrinks assets per seed. The actual quantized envelope predicate still makes the decision. Earlier .35 exports remain labeled first-scatter evidence only.

## Visual canopy cutaway

`visual_canopy_cutaway/v1` is a presentation policy. The final .38/NPC-bound scatter passes independent full-area support, raw full/far containment, reserved-space and unchanged-graph checks. Actual full crowns nevertheless intersect the traveler on sampled multi-edge hops (125 coast and 134 plateau contact observations). Those reports are preserved in `artifacts/generated_v3_vegetation/pre_cutaway_contact_generation_038/`; this policy does not recast them as physical clearance.

The board supplies conservative world AABBs derived from current raw player and visible carried/dropped-pack mesh bounds after movement transforms and before drawing/picking. The NPC is not a cutaway target. Near intersecting crowns are suppressed opaquely, leaving authoritative route-clear bark; a small exit margin prevents boundary flicker. No partial alpha is used. The same triangle suppression applies to current-LOD raw picking and selected highlights, so invisible foliage cannot select or occlude another object. Nearby spatial buckets and the currently suppressed set bound updates; no full placement deep copy occurs per frame. Affected far chunks may temporarily use their shared full mesh to retain bark without extra batches, within the existing full triangle cap.

Public renderer API: `set_body_cutaway_bounds(world_aabbs:Array[AABB], enabled=true)`, `is_canopy_cut_away(id)`, and `report().cutaway`. The board must refresh bounds after actor/pack presentation changes and immediately before pointer queries. The cutaway is reconstructed from actual live poses after reload; it never changes source rows, saved IDs, geometry, physical obstruction or gameplay cover. Native validation must cover prior contact poses, multi-edge motion, idle/drop, full/far transitions, repeated toggles, reconfiguration and actual Main save/restart.

Instance transforms are privately owned and immutable after configuration. Public renderer-parent transforms, camera LOD and body-bound inputs remain live. Nearby/active instance ownership checks are defensive; they do not establish detection of arbitrary unsupported writes to far-away private MultiMesh slots. Such writes require a complete reconfiguration rather than a local index update. The runtime does not scan or deep-copy every plant buffer each frame.

## Accepted map-side scope

Final native gates: physical placement3,867 checks, catalog/focus1,365, raw picker47, renderer140, cutaway96, actual capture/replay860. Independent physical scatter11,357 and final cutaway review1,186 checks passed. The replay covers17,744 finite production poses and340 additional unmasked-solid control poses. Full-crown contact evidence remains explicitly valid; the accepted remedy is visual suppression. Final map captures preserve readable biome regions and distant forest. Composed Main input/drop/conversation/save/restart/request-size and cumulative package gates are separate and must pass before adoption.
