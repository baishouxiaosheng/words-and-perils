# Clear daylight gameplay rendering

An original, low-cost rendering profile for the real r24 coast. The visual target is the **gameplay** look of Totally Accurate Battle Simulator (TABS), not its UI. No TABS assets, textures, models or shader code are included.

## Observed references

Reviewed 2026-10-02 using the official [Landfall TABS press kit](https://landfall.se/tabs-press-kit/) and the developer's [Steam page](https://store.steampowered.com/app/508440/Totally_Accurate_Battle_Simulator/). The following official press-kit pictures were inspected visually:

- [Daylight battle, 4.png](https://images.squarespace-cdn.com/content/v1/55dc59cae4b07dc2ebbe3ea3/1617034143169-IK2LWDW33H5X7LFPESTX/4.png): pale cyan sky, yellow-green ground, olive crowns, cool blue/violet dark faces and strong red/blue actor separation. Broad faceted shapes dominate over photographic texture
- [Western sunset, 5.png](https://images.squarespace-cdn.com/content/v1/55dc59cae4b07dc2ebbe3ea3/1617034206225-PDS4J64L9KJ9332J55Y0/5.png): peach/salmon earth, warm sky and long purple-tinted shadows, rather than a universal green palette
- [Autumn mammoth battle](https://images.squarespace-cdn.com/content/v1/55dc59cae4b07dc2ebbe3ea3/1617034307292-OR984BVENOPQKMPKPGBY/ss_e502c3d72a454d8792fced42d241158d964af359.600x338.jpg): ochre/orange ground and foliage against turquoise sky, with dark blue-violet rocks and readable silhouettes
- [Bright cloud/fantasy architecture](https://images.squarespace-cdn.com/content/v1/55dc59cae4b07dc2ebbe3ea3/1617034292507-PJV9VVN0MAY0LE19IOVK/ss_f74f827e83eff5e9762711c42ccb3bdd4bc59af9.600x338.jpg): pale warm-white architecture, cool cyan shadows, very light background and selective gold accents. This is not evidence of snowfall

These images demonstrate environment-specific color design. They do **not** reveal exact proprietary shaders, numerical light settings, a strict universal two-band renderer, or a dynamic rain/snow/weather system. This implementation therefore uses an explicitly authored **clear-daylight coast interpretation**; it does not claim to reproduce all TABS maps or weather. The unit-creator screenshot was excluded from the gameplay-environment target.

## Original implementation recipe

Hexes are our authored approximation, not sampled proprietary values:

| Surface | Main authored color | Purpose |
|---|---|---|
| Grass | `#A8C95F` | Clear yellow-green land, minimal high-frequency detail |
| Canopy | `#83AD4F`, tropical `#40A175` | Saturated low-poly crowns with cool dark facets |
| Rock | `#A8B7CD` | Cool violet-blue family, no muddy neutral-grey overlay |
| Beach | `#E0C486` | Warm shore contrast, using the existing shore-distance support |
| Ocean | `#329BB5` | Legible saturated blue-cyan water |
| Shallows | `#64C9CA` | Clear local water transition |
| Background | `#BDDFE4` | Light cyan atmosphere |

- Normal-based fixed key direction `(-.55,.74,.39)` creates two broad light/shade groups with a narrow smooth boundary. Existing source normals and low-poly canopy geometry are retained
- Shade tint remains chromatic. Matte props use the same key and cool shadow grouping while retaining original chesspiece colors and silhouette
- Photography-frequency grass/rock texture is absent from the active ground shader. Quiet broad variation retains visual continuity
- Existing static canopy-contact field provides approximate localized grounding with chromatic shade. It is not dynamic cast shadow, SSAO or scientific cover data
- Existing pawn-contact meshes are broadened 1.75× and use soft alpha shade so the shadow extends beyond the base. Their placement continues following the existing presentation track; no source terrain or pawn geometry is changed
- Water uses the existing actual footprint and depth/shore attributes. River water has a matching visual shallow color; that color is not a hydrologic depth claim
- No shadow maps, screen-space reflection/refraction, raytracing, bloom or per-frame water simulation. Source dimensions, original picking, compact66 geometry, natural_v2 placement and river replacement contracts remain intact

## Integration and reversibility

`world_view66.gd` enables this profile after natural_v2 canopy loading, via a deferred call. It discovers later chess props only on content changes, not by traversing all nodes every frame. Local river materials are refreshed after river installation. Chess pieces are identified by their stable chess_piece metadata, including automatically renamed duplicate nodes. Call `set_clear_daylight(false)` to restore the prior shaders, prop materials, lighting and background, or set `clear_daylight_enabled=false` before loading canopies for isolated legacy-profile tests.

`tests/integrated_ecology_world/tabs_style/smoke.gd` checks profile startup and toggling, actual river-water material coverage, source picking equality, same mesh resource, unchanged canopy count and unchanged world state. `capture.gd` is a native GL Compatibility before/after comparison at 1920×1080 and 2×MSAA with the same cameras. Timings are only for the reported GPU; cloud llvmpipe results are not GTX1660Ti measurements.
