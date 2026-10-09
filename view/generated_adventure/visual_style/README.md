# Generated macro matte profile

Rendering-only `generated_macro_matte/v1` for the opt-in `generated_macro_renderer/v1` board. The default coast and legacy read-only preview are unchanged. This is a material/palette alignment with the project's existing original TABS-inspired clear-daylight style, not a migration of current-coast topology or the active PL source bundle.

## Appearance and data contract

- Bright yellow-green grass, warm sand, cooler green jungle, cool blue-violet alpine/exposed stone, cyan water, pale cyan background
- Terrain uses its exact existing linear `COLOR.rgb` palette and `UV2` soil/alpine weights. Jungle weight is recovered from the source's documented palette interpolation. Forest remains distinguished by existing source canopy placement, rather than a fabricated new biome mask
- Plateau caps keep their biome. Exposed stone is based on existing slope normals and alpine weight, never absolute altitude
- Ground and props use two broad normal-based light groups. The ground transition spans key-dot values 0.24–0.44 with the existing coast profile's 0.70/0.80/0.90 cool shade multiplier. This reduces amplification of tiny source-normal changes without a framebuffer blur. Existing double-sided terrain normals are oriented for their visible face in the shader, matching the old material's convention; the mesh normals are never edited
- Crown shading uses the face normals of its existing triangles. No geometry is decimated, added, displaced, re-positioned, or re-triangulated
- No photographic textures, normal-map noise, screen blur, generated replacement assets, dynamic lighting simulation, or fake hydrologic depth
- Water and bank materials retain the actual emitted mesh footprint and height. The channel-distance color cue is cosmetic, not a depth field. Angular rivers remain angular; this pass does not fix their source geometry
- Existing pawn contact meshes use the project's original tinted contact shader, with no transform or mesh changes. This pass adds no canopy-contact field

`profile.set_enabled(false)` restores original materials/environment/light settings for A/B inspection. All material replacements are per-instance overrides, leaving shared material resources untouched. World and camera state are not written. The only production integration is the generated board subclass; `hex_board.gd`, source generation, dry navigation, save format, current coast, and main remain unchanged.

The existing world-SubViewport quality selector continues to apply native-resolution off/2×/4× MSAA. The profile neither applies screen-space blur nor changes HUD layout. Fine terrain silhouette/triangle detail is limited by the existing macro mesh and real framebuffer resolution.

## References and original work

This profile reuses the project's original `integrated_ecology_world/tabs_style` rendering approach and contact shader. That profile records its visual review of the official [Landfall TABS press kit](https://landfall.se/tabs-press-kit/) and developer screenshots. No TABS models, textures, shaders or other game assets are copied. The official image endpoint was unavailable during this pass; the earlier project's recorded image review and existing accepted coast profile were the visual references.

Current primary Godot references checked for this pass:
- [Spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html): unshaded mode, COLOR/UV2, OUTPUT_IS_SRGB, and unchanged vertex data semantics
- [3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html): geometry MSAA and renderer-specific options

The fixed two-group recipe is an original stylistic approximation. It is not a claim about proprietary TABS shader internals.

See `docs/generated_adventure/visual_style/ACCEPTANCE.md` for executed tests and remaining limitations.
