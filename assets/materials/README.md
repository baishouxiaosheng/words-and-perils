# Miniature material library

Original, reproducible procedural material art for the low-poly fantasy miniature
board. No external image files or paid assets were used. The generator and all
images in this directory are dedicated under CC0-1.0. The separate project code
license is unchanged. This is a compatibility-focused raster PBR treatment, not
hardware ray tracing.

## Maps and scale

- Earth, limestone, oak: 1024² seamless maps
- Polished marble and brushed brass: 512² seamless maps
- Albedo maps: sRGB; intentionally near-neutral to multiply the game's existing
  semantic terrain, ivory/slate, wood and metal colors
- Normal maps: linear tangent-space, OpenGL +Y green convention
- Roughness maps: linear scalar in the red channel, with coherent microvariation.
  Marble/brass maps are high-range modulation maps calibrated near 0.93; helpers
  multiply them to preserve the requested polished roughness. Non-metallic felt
  and enamel use their requested dielectric roughness without brushed tooling
- Generated texture files: roughly 7.6 MiB; 3D textures are mipmapped on import
- World triplanar mapping for terrain/stone preserves seamless detail between
  separate mesh pieces and requires no added geometry, UVs or vertex tangents
- Object triplanar for wood and tokens keeps detail attached to moving pieces
- No displacement or parallax: silhouettes and low-poly faceting are retained
- Grass colors are semantic land colors multiplied by neutral earth detail;
  the texture does not impose repeating painted grass tufts

Regenerate with `python assets/materials/generate_textures.py` (NumPy, Pillow,
SciPy). Material seed: 465903; independent UI seed: 466003. The detailed earth, pores, mineral stratum, directional wood
rings and tool marks are material-specific structures rather than a shared noise
texture repeated across every surface.

## Integration

`const Materials = preload("res://view/miniature_materials.gd")`

- `ground_material()` for land or terrain skirt that contains explicit linear
  vertex COLOR. Existing TerrainField writes `.srgb_to_linear()`; do not convert
  this a second time
- `stone_material(color)` for walls and loose stones
- `wood_material(color)` for planks, poles and tree trunks
- `token_stone_material(color, roughness)` for ivory/slate token bodies
- `metal_material(color, metallic, roughness)` for brass borders and fittings
- `frame_style(color,border,padding,kind)` returns a StyleBoxTexture. Kind can be
  parchment, dark or pressed for larger panels (3px visible trim, 12px nine-slice
  margins), button or button_pressed (2px trim, 4px margins), or field (1px
  recessed edge, 3px margins). Narrow metal trim retains thickness, the center
  tiles to retain quiet paper/brushed grain, and border color is independently
  tinted. Reflections peak at 1.18× to avoid chrome-like white edges
- `range_material(color)` for board-draped mesh highlights; transparent with
  depth testing, slight pulse, restrained emissive response, no opaque hex fill
- `lighting_recipe()` is an optional warm directional key/cool ambient starting
  point. Main renderer code remains responsible for final light placement and QA

Compatibility renders core PBR and normal-mapped materials, regular shadows and
MSAA. Godot 4.6 also exposes glow and simplified SSAO on Compatibility (SSAO
only exposes Radius and Intensity). This library never switches renderers and
does not request SSR, SDFGI, hardware ray tracing or PCSS. Optional SSAO and glow
are left to the board environment and should be checked on the actual device.

## Primary technical sources

- Godot 4.6 renderer feature matrix:
  https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html
- StandardMaterial3D / ORMMaterial3D (triplanar mapping and material textures):
  https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html
- Environment/post processing (Compatibility SSAO and glow limitations):
  https://docs.godotengine.org/en/4.6/tutorials/3d/environment_and_post_processing.html
- Spatial shader built-ins (ALBEDO/ROUGHNESS and OUTPUT_IS_SRGB):
  https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html
- Shader source_color vs linear data textures:
  https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/shading_language.html

Technical references are not asset provenance. All images are original and the
provenance is recorded in manifest.json. A headless API/import check is not a
visual render check; actual desktop visual QA must be run after board integration.
