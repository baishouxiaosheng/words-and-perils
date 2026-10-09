# Original faceted mountain ranges

A rendering-only mountain sculpture layer for the existing r24 world. Enabled by the default clear-daylight profile. It adds no gameplay geography, collision, changed source heights or new selection identities.

## Visual direction

Reference: official [Landfall TABS press kit](https://landfall.se/tabs-press-kit/), especially [Western gameplay 5.png](https://images.squarespace-cdn.com/content/v1/55dc59cae4b07dc2ebbe3ea3/1617034206225-PDS4J64L9KJ9332J55Y0/5.png), inspected on 2026-10-02. Its large rock silhouettes have broad planar faces, quiet material color and decisive lit/shadow separation. The sunset palette is specific to that environment; this project keeps its previously approved bright clear-daylight green/cyan palette. See also the sibling `tabs_style/README.md` for official daytime gameplay references.

The meshes and shader here are original, deterministic authoring. No TABS asset, mesh, texture or proprietary algorithm is copied or inferred as an exact implementation. Photography-frequency rock and grass texture is absent from the active renderer.

## Mesh and integration

- The bake reads only frozen source-topology and ecology zone polygons with `rawrelief=mountain`, `domain=dry`
- New visible XZ support is inset 0.045 world units inside those polygons; the existing local river corridor plus a 0.12-unit margin is excluded
- Connected components receive unequal medial-interior ridge seeds, primary peaks, secondary peaks and smaller foothills. Eight- or nine-spoke control meshes add broken crowns, multiple shoulder levels, radial buttresses and smaller secondary crags. Their joined envelopes form ridges and saddles; finer faces are actually non-coplanar, rather than subdivided four-face cones
- Display uplift is distinct from unchanged source height. Flat normals are written per face; the model is 17,966 triangles, 11 display groups, roughly 550 KiB compressed
- Rock faces use cool blue-violet shade and pale slate lit faces. A very narrow color-only base join uses the exact existing biome-weight texture. No alpha, fog mask, large added texture, screen-space effect, shadow map or dynamic physics is added
- `world_view66.gd` mounts the layer under the existing identity-scale content parent. Its source compact meshes, water geometry, source picks and world data are untouched
- `set_faceted_mountains(false)` hides this layer for matched comparison. `set_clear_daylight(false)` also hides it

Selection follows the visible mountain surface: a visual ray hit is resolved through the frozen original dry-triangle provenance at the same XZ. Returned source face, canonical hex, barycentric coordinates and gameplay height remain original; the lifted display position is a separate field. A float32 contour-sliver consistency check rejects false ray hits. No physics shape or rule height is added. Nonmountain and nearer source/river hits keep the original picker.

`picking.gd` tests summit and nearby face selection from yaw 0.18 and 1.45 radians, validates the board-selected tile, reconstructs the original source position independently from saved face/barycentric data, and checks the original fallback and unchanged world state.

The native screenshot is intentionally a visual representation, not a claim of a new scientifically accepted height field. The scientific status of the existing world is unchanged.

## Checks and reproducibility

Authoring: `PYTHONPATH=/tmp/mountain-python python tests/integrated_ecology_world/faceted_mountains/bake.py` (NumPy, SciPy and Shapely authoring dependencies only, none required at runtime). The dependency directory is environmental; use any environment providing these packages.

Headless: `godot --headless --path . --script tests/integrated_ecology_world/faceted_mountains/smoke.gd`. Set XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME to writable directories in restricted executors.

Native: run `./mc` from an actual desktop terminal. It saves 1920×1080 GL Compatibility / 2×MSAA matched-before/after mountain, northern-range, overview and river screenshots plus 2.5-second per-camera timings. These are cloud llvmpipe samples, not GTX1660Ti hardware measurements.

The smoke checks original source surfaces and ordinary source-pick equality across toggles, unchanged source mesh resources, camera transform, world state, canopy count, no colliders, flat face normals, and the baked mountain/water support certificates. Native visual QA is separate.

Revision 2 matched comparisons are in `artifacts/faceted_mountains_20261002/native_refinement/`; the before view uses the actual revision-1 mesh at exactly the same camera. The previous model is retained only as QA reference under `revision1/`, not required by runtime.

Source integration: `shore_v03/` contains the accepted revision-2 artwork clipped and rebased against the final separately-versioned new dry support. It contains 18,226 triangles; 217 previous triangles intersected changed boundaries. No artistic regeneration was done. The manifest binds the new mesh, drainage, dry support and final render manifest. Runtime validates the source geometry hashes; the canonical world bundle pins the full render manifest and exact mountain files.

Presentation grounding: source actor supports/from/to remain authoritative source positions. A spatially indexed display-height sampler places tokens, labels, markers and contact shadows on the visible mountain, including every movement-arc sample. Save files do not acquire display heights or changed movement permissions. Same-cell actors receive small symmetric offsets only if their complete sampled token footprints fit inside the owning active dry hex; their heights are resampled. If no fit exists, a same-cell count and the actor selection list remain instead of moving a token into water.

Final targeted reports: `picking_alignment_new_source.json`, `grounding_alignment_new_source.json`, `crowding_alignment.json`, and `verification_final_source.json`. They cover visible summit selection from two camera angles, independent new-source barycentric reconstruction, an actual legal committed mountain move with unchanged stamina cost, all animation samples above the surface, exact save/load, dry-bounded shared-cell spacing, token picking and label/shadow alignment.
