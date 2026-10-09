# Faceted city district kit · v1

Original Blender-authored miniature architecture for **雾岸纪事**. The current map
contract is a **one-hex village**, a **one-hex city-state**, and a largest city of
only a few hexes (initial integration target: three). District identity is conveyed
by small architectural pockets, **not a separate hex for every district**.

## Contents

- `models/`: 13 independent Godot-ready GLB assets
- `lod1/`: 13 deliberately simplified GLBs retaining main silhouettes
- `source/city_district_kit.blend`: editable Blender 4.3.2 scene, complete mesh
  palette and a contact-sheet camera/light setup
- `source/build_city_districts.py`: reproducible original mesh generator
- `source/validate_glb.py`: independent ordinary-Python export validator
- `manifest.json`: exact footprints, heights, triangle counts and SHA-256 hashes
- `validation.json`: per-export test evidence, 26 GLBs checked
- `previews/`: asset-only previews; these are not gameplay screenshots

The `source/.gdignore` file is intentional. Godot should import the explicit GLB
files, not launch Blender to import the editable scene or preview setup.

## Asset vocabulary

| Family | Assets | Main silhouette / use cues |
|---|---|---|
| Village | `village_cottage_a`, `village_cottage_b`, `village_barn` | Clay/teal roof choices, timber-framed plaster, shuttered windows, flower box, tall barn doors |
| Shared | `shared_well` | Open stone well, two supports, winding spindle and pitched cover |
| Affluent | `rich_manor`, `rich_townhouse`, `garden_court` | Pale plaster, cool masonry, teal hip roof, paired chimneys, open portico, balcony, planted court |
| Industrial | `industrial_forge`, `industrial_workshop`, `workyard` | Distinct flue/chimney, covered work frontage, anvil, barrel/crate/log storage |
| Modest residential | `poor_home_a`, `poor_home_b` | Narrow warm/blue plaster homes, sensible timber bracing, small lean-to and laundry bar |
| Civic | `civic_hall` | Large paired doors, open bell cupola, slender pennant |

The `poor` machine identifier matches the requested district contract. Its visual
depiction is maintained modest housing; no association with danger, dirt or decay
is encoded. Building variants are art only: they do not imply ownership, inhabitants,
production, economy, a traversable interior or a newly permitted game action.

## Geometry / placement contract

- GLB axes: **Y up, front -Z**, ground-center pivot at Y=0; exported transforms are
  identity. Blender's editing scene uses Z up, as usual
- Every full module, including overhangs, porch, chimney, garden/yard props, fits a
  maximum **0.55 × 0.55** XZ AABB. Smaller separate well/garden/yard modules are
  0.34/0.39/0.38 world units wide respectively
- Main building authoring heights are **1.12–1.50 before scene fitting**. Uniform
  fitting into legal map pockets also reduces height. Compare the transformed
  roof bounds with the actual wall crown, not these unscaled asset heights. This
  is miniature map art, not a real-world architectural scale model
- Hex radius is 1; neighboring centers are √3 units apart. Per-asset exact bounds
  and conservative circumscribed footprint radii are in `manifest.json`
- The full footprint is a **placement clearance bound**. There are no physics
  nodes or collision meshes. A footprint must not silently create movement or
  line-of-sight rules. Settlement rule/selection identity remains the world's job
- Ground the module on the highest sampled point below its AABB, then bridge any
  remaining slope with a source-height-aware foundation skirt. Do not flatten
  the terrain or move the canonical cell support point to accommodate an asset
- Reserve all actual route corridors, gate sweep/opening and actor clearance
  before placing a module. Scale down or skip a module that does not fit; never
  force it into an occupied route or expand the settlement footprint

For a one-hex settlement, choose just a few major silhouettes and one small shared
prop. It is not necessary to put all 13 assets in one settlement. Gardens, yards,
timber/clay versus pale-stone/teal differences communicate district mix even when
several houses are close together. Asset placement is handled by the settlement
renderer, outside this kit.

### Compact composition study

`source/scan_composition_capacity.py` and `composition_capacity.json` are a
read-only advisory study of the current source terrain anchors and authored
road/boundary geometry. They do not alter any world or settlement authority.

The study preserves the 0.26 actor/route clearance, including **all six pinned
navigation-neighbor spokes for the unwalled village**, not only its drawn road.
At a 0.025 candidate grid and a 0.035 gap between conservative footprint circles,
the current geometry admits:

- Three-hex city: nine roofs and three separate district props; affluent two
  roofs plus garden, industrial three plus yard, modest four plus shared well
- One-hex village: three roofs plus shared well
- One-hex city-state: four roofs plus garden

Exact coordinates, radii, uniform scales and resulting heights are in the JSON.
The village requires a small deterministic backtracking search: largest-clearance
greedy placement alone wastes the split eastern pocket. The recorded solution
takes 51 legal partial states and 449 candidate visits. Runtime must still add
open-gate-leaf exclusions, sample terrain height and verify the actual pixels.
These packing results are not gameplay or visual acceptance on their own.

For the revised composition, the proposed **final wall crown is about 0.42**,
including cap and merlons. Low side-hinged gate leaves avoid an overhead frame
that would dwarf the fitted houses or clip the taller character chess pieces.
The settlement renderer owns implementation and native verification of that
presentation; the kit neither changes gate permissions nor introduces barriers.

## Rendering / performance

| Cost | Full detail | LOD1 |
|---|---:|---:|
| All 13 unique assets, total triangles | 10,996 | 7,148 |
| Smallest module | 412 | 196 |
| Largest module | 1,328 | 940 |
| Meshes / material surfaces per module | 1 / 1 | 1 / 1 |
| Texture images | 0 | 0 |

The combined 26 GLB files occupy approximately **1.4 MB**. Flat normals, restrained
two-value face colors and actual silhouette geometry give the faceted look. Roof
slabs, projected frames and sills, portico/balcony supports, capped chimneys and
cupola openings have real geometry. Opaque COLOR_0 vertex colors feed one rough
material; there are no alpha-cutout textures, skinned meshes or animation tracks.

The kit-local `city_vertex_color.tres` material is applied by the settlement
renderer to imported kit meshes. glTF stores linear vertex colors, whereas
Godot's Compatibility rendering path calculates sRGB output. The shared shader
converts those colors only when `OUTPUT_IS_SRGB` is true, retaining linear data
for Forward+/Mobile. This keeps valid, portable GLBs while avoiding the known
[Compatibility vertex-color mismatch](https://github.com/godotengine/godot/issues/87486).
The standard material's sRGB flag is ineffective in Compatibility; see the
[Godot BaseMaterial3D documentation](https://docs.godotengine.org/en/4.5/classes/class_basematerial3d.html)
and [shader output-color reference](https://docs.godotengine.org/en/4.3/tutorials/shaders/shader_reference/spatial_shader.html).
Shader compilation and in-game palette verification belong to the native
settlement test; the independent GLB validator does not claim to test a shader.

Recommended runtime policy (guidance, not an installed runtime feature):

1. Cache each mesh/material once and reuse it. For repeated buildings, use
   spatially bounded MultiMesh batches per asset/LOD, or the project's existing
   static mesh batcher. Avoid a whole-world batch that defeats frustum culling
2. Use full detail while the building is about 70+ pixels high. Below that, use
   the explicit LOD1 variant or Godot-generated mesh LODs after visual comparison
3. Hide tiny garden/workyard details at distant overview scale rather than adding
   more micro-geometry. Preserve the main roof and chimney silhouettes
4. Do not run both LOD variants at the same time. LOD1 uses the same pivot and
   full-detail reference scale, so switching does not recenter or resize a house
5. Use shared shadows sensibly and measure the actual gameplay frame, including
   terrain and UI. Geometry counts alone do not prove a frame-rate target

**No GTX 1660 Ti laptop benchmark has been performed.** The 1080p/30fps target is
an unverified target. Native Godot integration/placement is a separate test owned
by the settlement renderer; an asset contact sheet is not evidence for gameplay
frame rate or traversal correctness.

## Rebuild and verify

From the game project directory:

```sh
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 blender -b -t 1 \
  --python assets/city_districts/source/build_city_districts.py
python assets/city_districts/source/validate_glb.py
```

The script overwrites this kit's generated GLBs, manifest and Blender scene. Keep
manual revisions in a separate `.blend` before regenerating. No internet connection
or external Python package is required. To produce the optional asset preview,
append `-- --render`; its CPU renderer uses two threads and 16 samples. Coordinate
rendering with any concurrent Godot native test on memory-constrained machines.
For the labeled individual-card contact sheet, run `render_asset_cards.py` with
Blender (two threads, 32 samples), then `assemble_contactsheet.py` with ordinary
Python and Pillow. Denoising is disabled because the installed Blender build
does not include OpenImageDenoise; no extra software is installed to render.

The editable Blender scene lays the full-detail models out for inspection. Each
asset remains a separate joined mesh with editable geometry and corner colors.
Scene camera, floor and lighting are explicitly named `PreviewOnly_*` and are not
exported. To export a manually edited asset, export only the chosen mesh, reset its
display-grid location to zero, retain +Y as its Blender forward direction and use
glTF's Y-up conversion. Re-run the independent validator after updating metadata.

## Provenance and design research

All delivered geometry, colors and generation code are newly authored for this
project. No external models, textures, architectural drawings or commercial game
assets are redistributed. TABS was a broad visual direction supplied in the task;
this is not a replica of a TABS building or asset pack.

Design references inform broad architectural vocabulary, not historical fidelity:

- [Weald & Downland Museum: North Cray medieval hall-house](https://www.wealddown.co.uk/buildings/medieval-house-north-cray/)
  informed the readable hall-and-bay arrangement and exposed timber framing
- [English Heritage: medieval architecture](https://www.english-heritage.org.uk/learn/story-of-england/medieval/architecture/)
  supports using both timber and masonry across modest houses, town houses,
  agricultural buildings and civic halls rather than making every building a castle
- [Weald & Downland Museum: Southwater smithy](https://www.wealddown.co.uk/buildings/smithy-from-southwater/)
  informed workshop, protective masonry flue and tool-yard cues. The museum's
  surviving building is nineteenth-century; this kit borrows functional cues and
  does not claim that structure is medieval
- [Godot 4.5: 3D import configuration](https://docs.godotengine.org/en/4.5/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html)
  documents Blender/glTF mesh color import and explicit import settings

Sources were checked on 2026-10-03. References are links only and impose no
third-party asset license dependency on these newly authored meshes.
