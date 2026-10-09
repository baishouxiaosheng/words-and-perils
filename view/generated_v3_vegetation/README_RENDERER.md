# Bounded V3 vegetation renderer and raw picker

This is a new opt-in presentation layer, not a terrain/ecology authority. Canonical frozen v18 and the authoritative source assets are unchanged. These candidate files live in `view/generated_v3_vegetation/`.

## API

- `configure(result) -> {ok, report}`: requires `result.ok`, manifest `schema_version=generated_v3_vegetation/v1`, `profile_id=sparse_biomes/v1`, an ID-sorted `plants` array, and `assets.full_meshes` / `assets.far_meshes`. Planner must already have admitted source/hash/catalog/footprint/support/navigation bindings. Renderer shape checks are not authority admission.
- `update_lod(camera)`: global camera-size hysteresis, full→far at size22, far→full at size20. All source rows remain present. No thinning, refitting, recentering, terrain bins, collision bodies, or per-plant nodes.
- `pick(origin, direction, limit) -> Array[Dictionary]`: actual current raw surface triangle hits `{id, hex, distance, point}`, sorted by world distance then stable row ID. `limit` is the nearest actual external occluder distance, not a hit-count limit. Positive infinity is allowed; directions are normalized safely.
- `select(id) -> bool`: selects a known row or clears selection for an unknown/empty ID. One shared-mesh shell follows the selected current transform/LOD/visibility. The shell is not in the pick set. It is suppressed if adding its primitives would exceed80,000.
- `report()`: source row count, current visible submitted draws/triangles, full/far totals, buffers, LOD switches, mesh swaps, selection overhead, and the picker cache/query diagnostics. Draw estimates are submitted visible geometry, not driver/frustum-measured GPU calls. Buffer accounting is not total process/driver memory.

## Exact rendering choices

Six admitted asset IDs: temperate, tropical, sapling, shrub, tuft, reed. Tuft/reed must use the exact same full ArrayMesh resource in both dictionaries. The parent asset module verifies full/far projected footprint equality. Every asset must have one raw triangle surface. The exact persisted transform is `Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(radius,height,radius)), position)`; scalar tint becomes `(tint,tint,tint,1)`. Before cutaway preparation, all batches share the original `ecology_preview/vegetation_surface.gdshader`. Preparing the optional cutaway switches that shared material to `body_cutaway.gdshader`, an accurately documented opaque-mask derivative. Original full/far mesh resources and their position/index/normal/color buffers remain unchanged; see `CUTAWAY_POLICY.md` for pins and provenance.

Each fixed chunk is `floor((x+24)/16), floor((z+24)/16)`. There is one MultiMeshInstance3D per asset/chunk. Full/far changes select that MultiMesh's shared mesh; transforms, colors, row IDs and slots do not change. With cutaway active, an affected far group temporarily uses its full mesh to retain bark without another batch, while unaffected groups retain far LOD. The four custom-data mask floats are accounted for in the native instance-buffer report. The six-kind r12 bound is54 active plant batches, with a hard64-batch bound. A selected shell adds at most one draw. Each active plant asset is a single surface. All shadows are disabled. Godot performs its ordinary MultiMesh culling; the renderer adds no approximate center-only culling rule.

Limits:1,024 plants;80,000 full or active query triangles;64 captured/renderer batches;10 cached raw mesh resources. Cached data is raw `surface_get_arrays` vertex/index data, shared across all instances using that mesh. Resource IDs are only transient cache keys; source identity always comes from captured stable row IDs. Resource-change signals invalidate geometry snapshots; old LOD cache entries are removed after successful queries. Reconfigure clears every previous row, node, buffer binding and raw cache.

## Fail-closed pointer integration

The picker supports current mesh-only LOD swaps and current instance/global affine transforms, including nonuniform scale, reflection and shear. A batch's original MultiMesh object and row-slot count bind ownership. Replacing its MultiMesh or changing its instance count cannot inherit IDs. If that batch is visible, the entire query returns no hits with `report().picker.last_query.complete=false` and an error. A hidden invalid batch is omitted while hidden but its binding is retained so showing it later still fails closed. Detached/deleted batch nodes and their IDs are pruned.

The caller must check `last_query.complete` and must not fall through to ground or a farther target after an incomplete query. A legitimate miss reports `complete=true`. The picker has no duplicated terrain data; terrain/water/building/NPC occlusion comes from the caller's nearest actual world-distance cap. It tests every admitted current candidate within that cap, rather than early-exiting after an arbitrary hit or triangle count. If a changed visible mesh exceeds the budget, query preflight fails before any hits are returned.

A zero-basis instance is not rendered and is skipped. Hidden nodes/ancestors and instances beyond `visible_instance_count` cannot contribute hits. Selection nodes are never traversed or captured, regardless of their names, geometry or position.

## Verification available

- Workspace research harness `v3_vegetation_work_20261005/tests/check_picker_math.py` (outside the game project): executed 5,010 standalone double-precision specification checks across 1,000 affine cases, with maximum difference 3.20e-14. It is not a game-relative command or a native Godot pass.
- `tests/test_generated_v3_vegetation_picking.gd`: isolated raw-mesh fixture, without source terrain/planner/catalog/factory. Covers indexed/unindexed triangles, exact occlusion boundary, AABB false positives, two-sided hits, tiny/huge/invalid rays, affine transforms, LOD changes, resource changes, hidden ancestors, visible prefixes, disabled instances, shell exclusion, reconfigure, detachment, stable tie ordering and fail-closed visible ownership mismatch including hidden→visible transition.
- `tests/test_generated_v3_vegetation_view.gd`: synthetic admitted-shape fixture with108 rows in54 groups. Checks shared resources, exact row transform/tint, original material, disabled shadows,22/20 hysteresis, current-LOD picking/shell, replacement cleanup and hard budgets. It does not prove source/geometry/asset authority admission.

The parent completed real Compatibility validation: raw picker 47/47, renderer 140/140, focused cutaway 96/96, and final recorded-pose replay/capture 860/860. The final replay covered all 17,744 preserved production poses with zero visible crown/body AABB overlaps under the visual policy; this is finite sampled evidence, not physical canopy-clearance or swept-volume proof. The native reports are in `artifacts/generated_v3_vegetation/`. No GTX 1660 Ti 30 fps claim is made.

## Native backend requirement and resolved initial diagnostic

The parent ran the isolated picker using `--headless`:45 of47 checks passed; the scaled-instance and zero-basis cases failed. That run uses Godot dummy storage, which does not implement per-instance MultiMesh writes and returns identity for its transform getter. It cannot establish the live transformed-instance contract. The existing project's `docs/scene_entities/IMPLEMENTATION.md` also documents this limitation. Both synthetic fixtures must run under the real Compatibility renderer and an owned display (Xvfb is sufficient), without `--headless`. Assertions remain unchanged; no dummy-only skip or success claim was added.

Upstream references:
- [Dummy mesh storage, lines158–173](https://github.com/godotengine/godot/blob/4.6-stable/servers/rendering/dummy/storage/mesh_storage.h#L158-L173)
- [Public MultiMesh API delegates to RenderingServer, lines241–255](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/multimesh.cpp#L241-L255)

A packed-buffer experiment was fully reverted before retest. Production still reads the current native per-instance transform directly. There is no cached-source transform fallback or per-query bulk GPU-buffer readback. The unchanged raw picker and renderer subsequently passed 47/47 and 140/140 under real Compatibility; the dummy-backend failures are resolved test-environment diagnostics, not pending production failures.

## Accepted optional body cutaway

The renderer now supports the opt-in `visual_canopy_cutaway/v1` presentation policy via `set_body_cutaway_bounds` and `is_canopy_cut_away`. Read `CUTAWAY_POLICY.md` for exact original-mesh VERTEX_ID classification, the modified opaque shader's provenance, retained bark/LOD behavior, low-solid controls, error/ownership contract and accepted native results. This is a visual canopy policy, not physical canopy-clearance admission. The original source assets and authoritative placement are unchanged.
