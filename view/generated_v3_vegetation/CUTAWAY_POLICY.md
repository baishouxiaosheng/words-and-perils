# visual_canopy_cutaway/v1

This is a presentation policy for the already admitted vegetation. The preserved strict full-crown contacts remain physical evidence. This policy makes no physical canopy-clearance, collision-free, navigation, cover, harvest or action claim.

## API and caller contract

`set_body_cutaway_bounds(world_aabbs:Array, enabled=true)` accepts at most8 finite world AABBs: one conservative union of the actual visible player mesh parts, plus one conservative union per visible carried or dropped pack. The caller excludes NPCs. It returns `ok`, changed mask IDs and bounded index diagnostics. It never writes actor state, custody, source cells, routes, placement or asset authority.

`is_canopy_cut_away(id)` reads the current native instance mask. `report().cutaway` includes the policy, suppressed IDs, revision, candidate/bucket/examined/update counts, elapsed time, ownership checks, forced-full group/triangle/draw counts, exact triangle sets, pins, errors and recovery requirement.

Bodies are transformed conservatively into the renderer's source frame. Full and far raw crown vertices are both included in each indexed crown AABB. The2-world-unit XZ index is built once. A query visits only body-overlapping bins and the active suppressed set. Bounds use an entry margin of0.015 and an exit margin of0.08 source units. Identical idle bounds avoid index rescans and mask writes; local immutable-transform checks remain active.

Bounds:8 body boxes,64 query bins,128 nearby candidates,256 candidates plus active entries examined,128 suppressed instances. The helper copies only these bounded ID sets/body boxes per update, never deep-copies all source rows. There is no all-instance per-frame buffer readback.

## Opaque mask and exact current geometry

Only temperate, tropical and sapling tree crowns participate. Shrub, tuft and reed geometry stays fully visible and pickable; their low-solid physical gate must not be hidden by this policy.

Full tree triangles are explicitly classified from the pinned original factory's unindexed single surface:
- Temperate/sapling: bark0–13, crown14–76
- Tropical: bark0–27, crown28–90
- Far tree mesh: crown0–6, no bark

The original unindexed full/far ArrayMesh resources are retained directly. Source position, index, normal and color arrays are strictly compared; they are not repacked or modified. The vertex shader uses VERTEX_ID against the exact bark-vertex prefix in INSTANCE_CUSTOM.y, with woody membership in INSTANCE_CUSTOM.z. Prefixes are42/84 at full LOD and0 at far LOD, and update with the current group mesh. The shader discards crown fragments when INSTANCE_CUSTOM.x is below0.5; the CPU picker skips exactly those crown triangles at the same threshold before continuing through all visible bark and farther instances. Authored masks are binary0/1, so there are no partially faded crowns or invisible crown hits.

No ALPHA output, transparent-depth mode or depth prepass is added. Immediate opaque suppression with exit hysteresis was chosen first because a smooth opacity fade would complicate depth ordering, draw count and partial-visibility picking. Smooth fading is not claimed.

## Far LOD and selection

A far-LOD asset/chunk containing a suppressed crown temporarily uses its existing shared full mesh. The crown mask retains its full bark. This adds no batch/node; other chunks remain at their original far LOD. Once restored, that chunk returns to the current normal22/20 camera hysteresis choice. The submitted triangle count is still bounded by the admitted full-geometry budget. Shader-discarded triangles remain submitted GPU primitives and are not falsely subtracted from native primitive counters.

The existing single selection shell uses a shared bark-only mesh when its crown is suppressed. It never redraws the hidden crown and remains excluded from picking. IDs, source rows, transforms, tint and the maximum64 plant batches remain unchanged.

## Ownership, integrity and fail-closed behavior

Every source-row transform is read back at configure. MultiMesh object/slot ownership remains captured by the picker. The renderer's instance transforms and batch-local transforms are private and immutable after configure; there is no public mutation API. Nearby/active candidates are checked against the captured native transform and object/count binding before mask application. Global renderer transforms are supported through inverse world-box conversion.

Arbitrary writes directly into private far-away MultiMesh slots violate this ownership contract. Nearby-only integrity detection cannot discover an arbitrary distant slot moved into the body region without a whole-buffer scan; the implementation does not claim otherwise. The integration board must not mutate those slots.

Invalid, excessive or ownership-inconsistent cutaway input latches an explicit error, hides the vegetation presentation and makes vegetation queries incomplete with no hits. Retrying or toggling cannot silently recover a partially applied mask set. A fresh successful `configure()` is required to rebuild ownership, masks and the index. Callers must honor query completeness before choosing ground or a farther target.

## Derivative provenance

`body_cutaway.gdshader` is a modified derivative of the project's frozen `view/ecology_preview/vegetation_surface.gdshader`. It retains that shader's faceted color, Compatibility color conversion, roughness, specular and culling expressions, and adds the opaque vertex-index/custom-data discard. It is not described as an unchanged shader/material.

Pinned source SHA-256 values are checked when preparing the visual derivative:
- Original factory:90f29e8c844d9f0094186c5a61060a831de50ef37ca35da36881c24a4c0c56bb
- Original shader:e7bc8bdf45017df68daf059c818778f1638a21f3d1f5859a2536d8ffacd8fafb
- Original namespace LICENSE.txt:8f2f09db1ebceff3581d6016eb2c4154c60d15b01709a9add27d83d88b716251

The original procedural geometry/preview namespace carries [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/legalcode). Existing project source, license and original shader files are untouched. The authoritative asset catalog and raw source mesh hashes remain unchanged.

## Focused validation

`tests/test_generated_v3_vegetation_cutaway.gd` is intended for real Compatibility rendering. It covers exact crown prefix membership, retained bark behind a hidden nearest crown, unrelated target occlusion, mask threshold, shell masking, motion/idle/pack changes, full/far restoration, low-solid controls, invalid input/error recovery, reconfigure and unchanged source vertices. It exports renderer/core/helper/shader file hashes and diagnostics. The parent separately replays preserved actual player/pack poses and retains contact-generation evidence. No Godot process was launched by the renderer worker.

## Repacking diagnostic and correction

An initial UV2-tag derivative failed the strict native array-equality gate: the temperate NORMAL array changed during native re-encoding even though both arrays had231 entries. That failed attempt was not accepted. The current implementation avoids the geometry repack entirely and keeps strict normal equality, using the [documented spatial shader vertex built-ins](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html#vertex-built-ins) for exact VERTEX_ID/INSTANCE_CUSTOM classification.

Only the shared bark-only selection shell is a separate unlit display mesh. Full and far vegetation positions, indices, normals, colors, resource identities and source catalog hashes remain unchanged. The MultiMesh native instance buffer includes four additional custom-data floats per instance; resource/memory diagnostics and the focused buffer test account for them. Full/far group transitions update only that group's mask-prefix metadata and instance custom values when the cutoff changes.

## Accepted native result for this revision

The parent ran the final real Compatibility batch; runtime/tests are now frozen. Focused cutaway96/96, unchanged raw picker47/47, renderer140/140, and final actual replay/capture860/860 passed with a clean final exit in24.959s.

The finite regression replay covered all17,744 preserved production poses across304 recorded directed motions. It found zero visible crown/body AABB overlaps under this visual policy. An additional340 unmasked-solid control poses had no AABB-overlap candidates. Each recipe exercised152 full/far transitions. Cutaway update p95 was80/77 microseconds; observed maxima were0.695/1.887ms for the two recipes. These are this environment's native test observations, not target-GPU frame-rate promises or swept-volume/physical canopy-clearance proof.

The accepted shader renders local crown cutouts while retaining bark. The original strict full-crown contact generation remains preserved independently. Independent final visual QA accepted the matched contact pairs and landscape set with1,186 checks. Eight of12 landscape images were pixel-identical to the prior generation; the other four differed by35 pixels total without a visible biome/relief regression. Both contact pairs clear the piece while retaining bark and distant forest. This is map-side acceptance; composed Main/drop/restart/memory and canonical adoption remain separate gates.

Frozen helper SHA-256: `bc2155a43116ae793b22de9c1945e62d22d56a2567d7660851c271a479775757`

Frozen shader SHA-256: `df01391b38ebad76b9994f029d465c4ef10b062ed62e98d06e8acb9b3a17b7b3`

Evidence is in `artifacts/generated_v3_vegetation/cutaway_focused_report.json`, `cutaway_native_capture_report.json`, and the recipe-specific `cutaway_motion_policy_*.json` files.
