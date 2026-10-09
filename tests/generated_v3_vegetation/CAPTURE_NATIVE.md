# Native vegetation captures and sampled body probe

New standalone test: `capture_native_vegetation.gd`. No runtime/core changes. The parent owns all native launches.

## Run

Use the owned display and Compatibility renderer, without `--headless`:

`godot --rendering-method gl_compatibility --path <candidate> --script res://tests/generated_v3_vegetation/capture_native_vegetation.gd`

For the initial matched screenshots and counters only, set `FOGBANK_VEGETATION_CAPTURE_ONLY=1`. It still captures both recipes. With that variable unset, each recipe's matched captures are checkpointed before its bounded motion probe begins. Output is under `artifacts/generated_v3_vegetation/`.

## Captures and measurements

- Both seed726381/radius12 recipes use the frozen VillageAdapter and settlement Board, with vegetation independently attached from Planner.build
- Overview uses the board's whole-map camera. Normal12 and closest7.5 use the same deterministic tree-rich source cell: most tree instances within4 world units, lexical cell tie-break
- Vegetation off/on preserves camera, terrain, actor, pack, village, lighting and source state. Each image pair records camera transform, resolution, actual viewport visible/shadow draw counters, actual primitive counters, memory/object/resource counters, and vegetation renderer counts
- Baselines distinguish the original board, vegetation planning/assets, and renderer configuration. Native counters are recorded directly; no GTX1660Ti frame-rate claim is made
- Complete pointer timing composes the frozen terrain/actor/pack/village query, raw vegetation within its nearest opaque distance, completeness checks, and nearest-hit arbitration. Reports65 deterministic pointer-grid timings plus30 repeated focus queries, with the vegetation-only subtime separately retained
- Source, navigation, adapter save, village placement and exact native ground/water vertex/index bytes are checked unchanged at the end of each recipe

`native_capture_report.json` is checkpointed after every off/on pair. Twelve matched PNGs are expected. The successful completion marker is `VEGETATION_NATIVE_CAPTURE` with the pass count; `VEGETATION_CAPTURE_READY` indicates one recipe's six matched PNGs have been written.

## Motion probe bounds

The body model is the real current player token's visible MeshInstance parts plus only carried inventory packs' explicit `mesh_parts`. There is no guessed person height, radius, capsule or substitute model. Native local raw arrays/bounds are cached per mesh; actor/pack raw vertices and hashes are exported to `body_raw_meshes_<recipe>.json`.

Candidate edges are actual admitted legal edges whose declared full-plinth center corridor overlaps a tree crown's outward-quantized projected footprint. The test deterministically selects up to64 undirected edges, ordered by descending crown-candidate count and then lexical edge key, and reports every eligible edge and whether it was sampled. It tests each selected edge in both directions. Motion uses native `navigation.route_points`, `board.token_support_pose`, the production intermediate-point lift, `presentation.move_actor_path`, and direct calls to its existing `_process` with automatic presentation processing disabled.

Each directed edge has41 samples, including both endpoints, using40 equal time intervals over the actual production motion duration. Every motion record declares its actual duration, interval/rate, route points, rotations, endpoint/midpoint conservative body bounds and actual token transforms. This includes the production hop and rotation sway; no new animation is substituted.

Part/plant AABB overlap is only a broadphase candidate. Candidate parts are transformed from their actual raw vertices. Refinement tests actual triangle pairs with separating axes, including coplanar axes, at1e-6 world-unit contact tolerance. At most1,000,000 triangle-pair broadphase checks are performed per recipe. The first32 triangle-contact witnesses include both exact world-space triangles and their instance transforms. Up to2,048 aggregate candidate records preserve directed edge, part, plant and inclusive sample ranges; any omitted record count is explicit.

A contact is reported as triangle-surface contact, not automatically visual penetration; it can be tangency within tolerance. Original tree surfaces are not certified closed volumes, so a part/plant AABB overlap with no surface contact still has unresolved containment. Exhausted refinement budget is separately unresolved. Unsampled edges and between-sample motion remain unproven. The report never claims swept-volume clearance or universal no-clipping from AABBs, no-contact samples, or a finite sample rate.

`body_canopy_probe_<recipe>.json` contains the detailed evidence. The exit status checks harness/source integrity, not an invented body-clearance acceptance policy. The parent must review actual contact witnesses and all unresolved ranges before deciding acceptance or focused follow-up.

## Original full-crown diagnostic result

The original full-crown probe completed934 harness-integrity checks, but found125 coast and134 plateau triangle contacts. Independent QA confirmed strict crossings in all64 retained witnesses and classified them as canopy triangles. Those results are preserved in `artifacts/generated_v3_vegetation/pre_cutaway_contact_generation_038/`; they are not clearance acceptance. The accepted follow-on is the visual-policy replay below.

## Whole-route extension applied after preliminary captures

The harness now additionally admits up to12 endpoint pairs/24 directed canonical routes through selected crown-overlap edges, with2–4 cell edges per route. Both directions use the existing native navigation planner on detached starting-hex state copies, retaining the actual actor's terrain costs, capabilities and current stamina budget. No authoritative state or stamina is changed. At most16 anchors,2 pairs per anchor and256 planner calls are considered.

Each multi-edge route is passed once to `move_actor_path` with its complete edge count, so it uses one whole-route production hop. Sampling uses40 intervals per edge, giving81–161 samples per directed multi-edge route at comparable time spacing. Route cost, budget, exact path, anchor-edge indices, hypothetical starting scope and rejected-plan counts are exported. Multi-edge jobs run first, and all jobs retain the original shared1,000,000 triangle-pair budget with explicit unresolved outcomes. Actual player/plinth/pack raw meshes remain the collision geometry.

The preliminary capture-only report and original logs are preserved at `artifacts/generated_v3_vegetation/preliminary_capture_before_multi_route_20261005/`. They do not establish body clearance or clean logs. The test now guards empty index buffers before `HashingContext.update`; the corrected test and route extension completed the preserved full-crown diagnostic described above.

## Accepted standalone visual-policy replay

Run `capture_cutaway_native.gd` on the real Compatibility display through the unchanged owned memory guard (512MiB reserve). This subclass uses the checked-in121KB `fixtures/cutaway_route_replay.json`; it does not require the rejected diagnostic archive or an existing save. The fixture includes exact NPC reservations, source/geometry/vegetation hashes,304 production routes and17,744 finite pose inputs, and original report hashes. Independent QA verified its complete provenance.

Example engine arguments for the guarded owner: `godot --rendering-method gl_compatibility --path <game> --script res://tests/generated_v3_vegetation/capture_cutaway_native.gd`. Do not run a second engine in parallel. The older `capture_native_vegetation.gd` diagnostic requires `artifacts/generated_v3_npc/placement_<recipe>_r12.json` exported by the NPC source fixture; the standalone replay overrides that dependency with its pinned fixture.

Final native replay/capture passed860 checks. It prepares the final shader with real current player/pack bounds before all12 landscape images, then replays all304 preserved motions with152 full/far transitions per recipe.17,649 crown/body mask obligations passed across17,744 poses, with zero visible crown/body AABB overlap.340 additional unmasked-solid control poses had zero body/solid AABB candidates; this finite control set does not establish continuous clearance. Cutaway update p95 was80/77µs; observed maxima0.695/1.887ms. The process completed in24.959s, peakRSS562,812KiB, below the unchanged guard.

Outputs are `cutaway_native_capture_report.json`, `cutaway_motion_policy_<recipe>.json`, the12 landscape PNGs and4 matched prior-contact PNGs. Independent final map QA passed1,186 checks and accepted the contact pairs and landscape presentation. Original mesh resources and source/nav/state bytes are preserved. Physical full-crown clearance, arbitrary writes into private far instance slots, target-GPU frame rate, composed Main/drop/save/restart and cumulative adoption are not claimed by this replay.
