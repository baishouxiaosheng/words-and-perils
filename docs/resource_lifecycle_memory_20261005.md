# Default-coast memory optimization and missed-lifetime audit

Date: 2026-10-05. Status: adopted into new canonical v23 after independent review and final adopted-copy gates. Previous v22 remains unchanged.

## Result

The default 1,801-cell coast now keeps its active v03 source topology in lossless packed columns instead of 200,641 persistent per-vertex/per-face dictionaries. Original Float64 coordinates, face IDs, owners, legacy-parent indices and original JSON number types are preserved. Complete face dictionaries are constructed when an actual source hit needs one; unfamiliar fields or nonrepresentable indices retain the entire original data as a safe fallback.

This is a memory optimization. It neither removes map content nor changes visual quality. Exactly one existing production script changes (`shore_layer.gd`), plus one new helper (`packed_topology.gd`). Ground/water meshes, canopy density, picking buffers, baseline topology, compact renderer, source manifests, navigation and save contracts remain unchanged.

## Actual full 1080p measurements

Godot 4.6.3, GL Compatibility, Mesa llvmpipe on the cloud computer. Native 1920×1080, scale 1.0, existing software-renderer AA setting, identical cameras, 20 warm-up frames then four-second focus/overview samples. Each run instantiates the real `main.tscn` and waits for the deferred active-shoreline setup. The first pair runs baseline then candidate; the second reverses that order.

| Metric | First pair: baseline → candidate | Reversed pair: baseline → candidate |
|---|---:|---:|
| Ready engine static memory | 699.47 → 506.90 MiB | 699.47 → 506.90 MiB |
| Process RSS high-water (`VmHWM`) | 1,562.51 → 1,319.06 MiB | 1,468.77 → 1,342.46 MiB |
| RSS high-water saving | 243.45 MiB / 15.6% | 126.31 MiB / 8.6% |
| Sampled RSS peak | 1,562.51 → 1,315.76 MiB | 1,468.77 → 1,342.46 MiB |
| First settled scene, from add-child start | 18.733 → 14.590 s | 13.862 → 14.589 s |
| Entire profiling harness | 34.573 → 29.564 s | 29.060 → 29.244 s |

The stable result is **192.57 MiB less ready static allocation (27.5%)**, with **126–243 MiB lower process RSS high-water** in the two actual native pairs. RSS varies with allocator, renderer and cache conditions. Static, graphics and RSS counters overlap and must not be added.

Runtime packing has a CPU cost. In the warm reversed pair, the settled-startup measurement increases by about **0.73 s**. There is no supported loading-speed or FPS improvement claim. Focus frame means are 55–58 ms on this software renderer; these runs do not certify the GTX1660Ti Laptop ≥30 FPS target. VSync disable was requested, but the driver's effective VSync remains unverified.

This harness includes screenshots and geometry/picking verification. Its peak must not be directly subtracted from the earlier, different 1,429 MiB UI-capture harness. OS idle-copy page-cache advice is recorded separately and is not counted as a code saving.

## Functional and visual proof

- All 67,289 vertices: 201,867 original Float64 coordinate values exact
- All 133,352 full source-face dictionaries: Variant bytes exactly equal to the original JSON-parsed records, including number types, field order and provenance
- All 400,056 triangle indices exact; 5,798 stratified barycentric/height results exact
- Unknown extra fields, int32 overflow, repeated helper loads and non-JSON numeric types preserve full fallback; component gate **14/14**
- Both 1080p focus and overview images in both native pairs are **pixel-identical** before/after (zero changed pixels)
- All recorded active mesh-array hashes, shader hashes, transforms, camera states, source hit payloads and source-context results are exactly equal
- Render work is unchanged: focus 121 draw calls / 153,487 primitives; overview 500 / 300,784
- Complete scene inventory is unchanged: active v03 96 meshes; old ground 51; old water 45; compact 51; original vegetation 32 groups; whole canopy 279 near/far groups
- Four complete native profiles each pass **5/5** and preserve authoritative state during inspection
- Current physical-navigation/flight/source-save suite: **167/167**
- Existing seeded coast adapter/save phases: **54/54**
- Production release adapter, including ready/rolled/staged exact JSON reloads: **75/75**
- Actual native tree/mountain/lamp selection and frozen context: **34/34**
- Actual Main save/RNG preservation, two shoreline fallback/reactivation cycles, and two legacy↔coast roundtrips: **18/18**. Old board weak references become null. The second reentry's static allocation differs from the first by only 8,624 bytes; this bounded test does not prove the absence of every possible leak

The original `test_navigation.gd` is obsolete: it references the removed `RIVER_WATER_PATH` constant and fails to parse in both unchanged baseline and candidate. It is preserved as failed evidence; the current 167-check source-flight suite supplies the navigation coverage instead. No production code was altered to satisfy the stale test.

The unmodified entity-selection fixture emits the same `ObjectDB instances leaked at exit` warning in baseline and candidate, both with 34/34 and exit 0. This is not described as a warning-free run. The complete startup and new resource-lifecycle tests finish without that warning or script/runtime errors.

## Why the earlier optimization missed closing this issue

1. **It was discovered but deferred.** The 2026-10-04 full-startup report already measured a complete coast peak of 1,384.5 MiB at 720p, counted hidden representations, and explicitly recorded 232.37 MiB of retained new topology and 150.32 MiB of older cache/display setup. Calling this three independently loaded maps would be inaccurate: one world retained several rendering and source-support representations.
2. **Acceptance proved a narrower improvement.** That pass removed the initial, immediately discarded legacy `set_world` construction. Its 18.2% startup and 37.33 MiB texture-counter gains were real, but the report explicitly said whole-process RSS changed little. The entry/fallback tests did not assert a retained-resource lifetime budget.
3. **Generated-mode progress did not close coast-mode costs.** The later 228.29 MiB build-only vertex-cache release applies to `hex_board.gd` and the generated radius-24 path. The default coast uses `playable_build/board.gd → world_view66.gd → shore_layer.gd`.
4. **Known memory peaks were not used in admission.** A later capture started with about 7.05 GB of host usage, leaving about 1.00 GB before the unchanged safety threshold despite a previously measured ~1.45 GB coast peak. The owned-process guard correctly stopped it. This work now checks known full-startup headroom before launching, instead of learning it again through a mid-startup abort.
5. **Hidden did not mean released.** Old render roots were hidden while source picking, river replacement and presentation switches still used related data. Deleting them blindly would have broken behavior. The missing step was an explicit consumer/ownership audit and a regression gate, now supplied here.

## What stays and what can be addressed next

- Keep old ground/water and compact meshes for now: river filtering/remainder materials and existing presentation switches reference them
- Keep old picks and baseline source topology: river barycentrics, old-source inspection and mountain source tracing still need them
- Keep both active canopy LODs and entity CPU geometry: real selection and LOD need them
- The original 32 decorative vegetation groups can be separately investigated for retirement after a successful whole-canopy install; a proposed second patch remains unapplied and unverified. Existing arbitrary canopy-variant replacement also needs a shoreline-binding lifecycle check
- A later source-bound prepacked cache may avoid the runtime JSON+packed coexistence and packing cost, but it requires its own invalidation, fidelity and fallback proof

## Safety, source integrity and reproduction

Every engine process used the actual host 8 GiB cgroup, one owned PID, unchanged 512 MiB reserve and **8,053,063,680-byte stop threshold**. No platform-process kill, system cache flush, credential access, real provider call or target-laptop run occurred. Read-only cache advice covered explicitly confirmed closed copies and excluded symlinks, multiply linked inodes and active descriptors/mappings. All file bytes and permissions were preserved.

302 existing production text/code files were compared; only `shore_layer.gd` differs. Independent acceptance additionally checked 645 existing runtime/asset/entry files, the exact two-file allowlist, all image bytes and source-cache pins. The source topology SHA remains `9df46b84df66df62348f97811dbd1a235290b8af58480ba2d6177d668cdedd4c`; the mesh source SHA remains `68931983818b291b07022477029d4ad4761aceac0c670463fbe742b6a2ac986c`.

Frozen production pins:

- `shore_layer.gd`: before `f9db6171b26566c2aecb04b34947bc76cb9b086873d904b16dcabbe2aa7f2c17`; after `ee6e1d32c7b09a71e445f6a0d08494140ecc8f84373d1d4ac239184bbb005e0e`
- New `packed_topology.gd`: `04d178dda01fc24153a22f83f83738b943afb674555755849dc9201928f28842`

Repository evidence: `updates/v23/manifest.json` records exact production pins and the adopted gate summary. Raw benchmark logs and screenshots are not included in this source distribution. Test entry points are `tests/resource_lifecycle/test_packed_topology.gd`, `profile_lifecycle.gd` (via `profile_native1080.gd`) and `test_main_lifecycle.gd`. The existing guard is `tests/loading_performance/run_owned_guard.py`; use isolated user/config/cache paths and do not run engine stages concurrently.

## Final adoption gate

The new v23 copy passed the 14-check component gate, actual full 1080p 5-check profile, and 18-check Main save/resource-reentry gate. All three owned processes exited 0 without script/runtime errors, ObjectDB exit warnings or guard stops. Adopted screenshots and source/pick/mesh/shader contracts are exactly equal to the accepted candidate. The same two production hashes were verified after execution; the original v22 files remain unchanged.

The additional adopted-copy native validation used fresh isolated user/config/cache directories and recorded VmHWM **1,480.48 MiB**, with ready static **506.89 MiB**. It is an unpaired validation run, not another A/B result; no baseline was measured under those new cache conditions. It is retained in the evidence and is not folded into the paired 126–243 MiB saving range. RSS savings are therefore measured observations under the stated pairs, not a universal peak-memory guarantee.
