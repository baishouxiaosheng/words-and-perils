> Current opt-in integration (2026-10-05 China): this isolated candidate uses the separately verified tiny-remnant-cleanup recipe and native structured mesh. See `../../view/generated_v3_runtime/README.md` for current admission, runtime and movement scope. The historical research status and original test counts below describe the earlier source foundation; they are not current playable-slice acceptance claims. The default v2 game remains separate.

# Coastal source v3: bounded research prototype

Status: **source foundation accepted; terrain art and gameplay migration not accepted**. New namespace only. Nothing imports this generator from the default game, and the canonical v2 source/contract/navigation files remain byte-identical. Library game versions v8/v9 are not replaced by this prototype.

## What is implemented

`generator.gd.generate(seed, radius, recipe)` produces a new `coastal_source_v3/prototype1` source, never a relabeled v2 world. Radius is an integer 4–24; seeds reuse the existing explicit UTF-8 normalization. Unsupported inputs return a failure, with no existing state available to mutate. No hidden retries or replacement seeds are used.

Two actual recipes:
- `coastal_range`: a major seeded curved spine, variable width and prominence, plus bounded spurs on larger maps
- `plateau_hinterland`: a different inland range composition and an irregular cap/apron field, with a genuinely constant raw core before conditioning

The pipeline is composition → cell samples → Dijkstra slope-limited lower envelope → priority-flood conditioning → final quantized elevation → temperature/water cycle → rainfall-fed accumulation → persisted-field biome/river classification → diagnostics/hash. Composition parameters are quantized before sampling. Stage-specific seeds prevent accidental dependence on unrelated RNG consumption.

Slope limit means adjacent **world-space cell-center edges**, with distance sqrt(3). It is not a continuous triangle-gradient or movement-clearance certificate. The persisted bound and rounding tolerance are explicit. The cap's final height range is reported separately because priority flood adds a small drainage tilt. All final fill depths equal final elevation minus the persisted slope-limited elevation exactly.

Climate is a fixed 48-cycle, double-buffered, six-neighbor heuristic: water evaporation, ordinary rainfall, elevation-limited cloud capacity, directional cloud transport, downhill moisture runoff, and land evaporation. Temperature uses the final conditioned elevation and the persisted lapse parameter. Saturation clipping and boundary cloud loss mean this is not a closed physical water-conservation model. Wind points in the direction air travels. Rainfall and soil moisture are distinct; runoff can keep a lee valley moist despite low local rainfall.

Radius increases the physical hex domain. Climate propagation is bounded in hex steps; no claim of scale-invariant rainfall or arbitrary continent realism is made. The larger samples are considerably drier inland, an explicit tuning/scale issue for future review.

## Mature references and adaptation boundaries

Reviewed 2026-10-03. This increment translates established algorithm structures into project-specific GDScript; it adds no upstream runtime dependency, asset or copied tutorial presentation. Pin exact upstream revisions before any later direct source vendoring. This file does not select a license for the project's own code.

- Azgaar [heightmap generator](https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/src/generators/heightmap-generator.ts), [recipe templates](https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/src/data/heightmap-templates.ts), [MIT license](https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/LICENSE): bounded seeded composition, range/spur primitives and explicit template parameters informed `_configure` and `_sample`. This prototype uses continuous spine-distance contributions, not Azgaar's graph-spreading implementation or exact templates
- Catlike Coding [Hex Map 25: water cycle](https://catlikecoding.com/unity/tutorials/hex-map/part-25/), [Hex Map 26: biomes](https://catlikecoding.com/unity/tutorials/hex-map/part-26/), [license](https://catlikecoding.com/license/): `climate_for_cells` adapts the tutorial's double-buffered cloud/moisture, evaporation, rainfall, wind, elevation-capacity and runoff structure. Coefficients, bounded cycle count, continuous heights, axial storage and directed weighted dispersion are project-specific. Code/assets are MIT-0; tutorial text/screenshots are CC BY-NC-SA and are not bundled
- Azgaar [precipitation](https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/src/generators/precipitation-generator.ts) and [biomes](https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/src/generators/biomes-generator.ts) provided independent checks that water supply, elevation and rainfall should drive ecological fields, rather than the previous perpendicular wet/dry gradient
- Red Blob [mapgen4 source](https://github.com/redblobgames/mapgen4/blob/main/map.ts), [Apache-2.0 license](https://github.com/redblobgames/mapgen4/blob/main/LICENSE): priority-queue drainage and separating rainfall from accumulated flow are cross-checks. No Mapgen4 mesh, code, painting interface or dependency is copied. Its README marks the project unmaintained

The min-heap/priority-flood pattern also follows the already-existing project generator. The new namespace deliberately does not edit that implementation.

## Running and recovering

In the game checkout, reserve the shared engine slot first:
- `bash tests/world_generation_v3/run.sh`: guarded source tests
- `bash tests/world_generation_v3/run_native.sh`: guarded lightweight native diagnostic, not the game's production renderer
- `python3 tests/world_generation_v3/plot_fields.py`: optional static source-field comparison; requires Matplotlib

The guard requires a verified physical cgroup memory limit no greater than 8 GiB and retains 512 MiB headroom. If the shell cannot see the cgroup, do not bypass the guard; use the authorized cloud desktop terminal. The native runner uses dummy audio and Compatibility rendering.

The separate recovery archive contains this new namespace, tests/docs/evidence, required unchanged source dependencies and a minimal project. Extract to a **new directory**, never over the canonical game. It is a reproducible research project, not a playable update. Archive extraction/file hashes and preload resolution are verified; standalone archive execution was not rerun after packaging.

## Explicit remaining work

- No source channel curves, ocean-beach geometry, 80% hex-support/readability metric, full continuous coastline sampler, gameplay/navigation admission, settlements or content migration
- The native diagnostic uses an 864-triangle cell-center lattice at r12. Its simple water plane is depth-tested display scaffolding, not a canonical water-footprint artifact. It draws no river geometry
- Final gameplay mesh topology, directional faceted style, distinct plateau silhouette and natural ecological transitions remain pending
- No target GPU/FPS acceptance and no claim about all seeds

See `VERIFICATION.md` and `artifacts/world_generation_v3/` for evidence and the bounded visual decision.
