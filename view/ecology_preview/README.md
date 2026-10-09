# Independent ecology art preview 0.1.0

This namespace owns only a read-only display. It does not change main.tscn, Game state, frozen geometry/water, old loaders, scientific producers or entity/AI tools. Vegetation is decorative, not patchable gameplay entities.

Minimal interface: export exact zone face+bary polygons and shared narrow-shell weights into render triangles on the same original PL. Pin mesh/water/climate/dry/config/zone byte hashes, schema and source dependency hashes. Heights are always barycentric interpolation of designed_height. The consumer rejects mismatched source bytes before changing the current view. Cover declarations are proposals. The exporter materializes deterministic low-poly crown footprints and reports actual fixed-cell occupancy and deficits; a resource cap cannot be a density PASS.

Palette comes from producer linear RGB, texture albedos decode once from sRGB. Detail changes luminance only. Warm key/cool fill/warm rim lights, rough trunks and layered crowns retain facet shading. Water is opaque, has source-exact footprints/levels, depth color and normal-only micro-waves with cheap Fresnel; there is no SSR or displacement. 1x height is default. 2x is a reversible display transform shared by terrain/water/grid/vegetation and inverse picking.

The supplied seven-hex fixture has explicit synthetic climate fields and is clearly labeled FIXTURE. It exercises grass, shrub, temperate forest, denser tropical broadleaf and cold open. It is not the real world, final climate, full landscape morphology or art acceptance. The existing shoreline fixture can test exact water clipping. Whole-zone authority is unavailable until its independent source stage completes.

Run fixture producer wrapper:

    python tests/ecology_preview/build_fixture.py

The procedural broadleaf recipe is adapted from the existing v9 project-owned hex_board.gd cylinders and three crown lobes; no downloaded model is added. Existing Poly Haven CC0 textures remain in assets/materials/polyhaven with their original license/provenance. New procedural geometry is original CC0 work; see LICENSE.txt.

Native color-path correction: Godot 4.6 GLES3 scene.glsl explicitly applies srgb_to_linear to ALBEDO after custom fragment(), and linear_to_srgb to its final lit output. Therefore this adapter keeps source palette interpolation and texture detail in linear RGB, and encodes composed ALBEDO only when OUTPUT_IS_SRGB is true. Compatibility texture samples are explicitly decoded for linear detail computation. Forward+/Mobile use source_color and do not take the extra path. This corrects double-decoding of linear vertex palettes; it is not arbitrary albedo whitening. Primary source: https://raw.githubusercontent.com/godotengine/godot/4.6-stable/drivers/gles3/shaders/scene.glsl (color conversion before lighting and before framebuffer write).

The cache exporter owns a pinned copy of the producer's small pure polygon geometry reader in tests/ecology_preview/dependencies/render_geometry.py. It contains no classifier, climate, authority state or world mutation. This keeps an already verified preview from silently switching math when the ongoing scientific producer is edited. Cache headers pin this copy, the exporter and the unchanged v9 tree recipe by actual SHA. Source zone schema 0.1.0 and the explicitly resource-only 0.1.1 are admitted for small fixtures; whole remains hard blocked.

Native terminal launch shortcuts, from game:

    sh tests/ecology_preview/run.sh     # seven-hex artificial climate art sample
    sh tests/ecology_preview/run.sh s   # stored six-face clipped shore sample
    sh tests/ecology_preview/run.sh p   # unshaded color/texture reference probe
    sh tests/ecology_preview/run.sh w   # real r24 PL light/material/water study only

B switches the same camera between the byte-unchanged frozen viewer material and the new study. G toggles real draped grid, V decorative cover, H the explicit reversible 2x display, C perspective, Home overview, F12 native capture with source hashes, F10 idle software-renderer profiling, Escape exits. Dependencies: merge this small overlay into the already restored Godot game with its frozen two loaders/view and licensed fonts/material textures. Running cached previews does not need large upstream science JSONs. Rebuilding the fixture inputs additionally requires the separately preserved scientific producer source.

Consumer scope is explicitly immutable fixtures: cache_receipts.gd pins admitted render-cache bytes and their exact mesh/water/zone sources. An edited or unknown cache is rejected before it changes the current view. A manifest or a cache's own claimed density/PASS cannot authorize different bytes. This includes finite yet semantically altered ecology, crown kind, missing/duplicate patches and fabricated density fields. New caches need a reviewed byte receipt and a source version update; no general whole cache loader has been enabled.

B1/B2 visual-only ground experiments (J and K independently toggle):
- B1 shares grassy substrate for forest/jungle. Canopy remains independent; bounded 0..16% material AO comes from actual crown footprints. It is a cheap proxy, not a physical cast shadow. Dense jungle's Gaussian field can be nearly everywhere nonzero while spatially varying
- B2 bakes actual shared positive-area zone interfaces into symmetric, normalized six-way weights. The corrected signed smoothstep continuous 10–90% width is 0.24 XZ; complete support width is 0.39447745. Independent bilinear PNG samples give 0.23903–0.24188. These are this prototype's engineering values, not Civ's disclosed parameters
- Raw RGBA8 weights are not sRGB; fragment renormalizes them and mixes the source linear palette. B2 local sand/soil uses those same weights, with original PL rock detail retained. The first palette-only version left a hard arid UV seam; corrected source and evidence are preserved separately
- Mesh, water, ecology ownership, original protection geometry and cover receipts stay unchanged. Material blend cannot be counted as physical 80% support. Same-color cores are not a physical 80% gate
- Real GL same-camera four combinations and tree-off confirm grassy continuity and softer material seams, but the zero lines/exterior contours remain straight. This is not multi-scale intrusion or naturalized real shores/rivers, and it is not an art/whole PASS

B3/L frozen land-land material trial: shared fixed-seed multi-scale coordinate field resamples all six B2 channels together; geometry, logical masks and actual trees do not move. L is effective only with K. Seed271828 and cap .18XZ are disclosed in the frozen manifest; actual raster max .17070984. Native same-camera L off/on shows small local bends, still too mild/blurred for the requested natural boundary quality. This waterless sample is now frozen rather than iterated indefinitely.

Read `artifacts/ecology_preview_20261002/B3_FROZEN_SCOPE_AND_ERRATA.md` with the B3 manifest: its old `water_and_exterior_warp=false` does not prove an identically zero outside-domain coordinate field (1631 exterior texels are nonzero). C1 describes lattice noise only, not the entire display atlas. No true water protection, whole ecology or art PASS is claimed. Future real-r24 read-only fields and the four minimal derived caches are specified in `REAL_R24_MINIMAL_INTERFACE.md`; the proposal does not enable generic whole consumption.
