# PBR response audit, 2026-10-01

## Confirmed code and texture pipeline

The 3D material helper uses StandardMaterial3D per-pixel lighting, Schlick-GGX
specular response, albedo texture modulation, enabled normal maps and roughness
textures. Roughness is read from the red channel and multiplied by the material
roughness scalar. Data maps remain linear; albedo maps are sRGB. Terrain's
explicit linear vertex COLOR is not converted twice. Texture mipmaps are enabled.

Reflection environment is present with a ProceduralSkyMaterial assigned to Sky
and `reflected_light_source = REFLECTION_SOURCE_SKY`. The COLOR background can
stay dark while the reflection sky is brighter. This is raster environment
reflection, not hardware ray tracing or screen-space reflection.

## Initial measured map response

Effective roughness percentiles, 5th / median / 95th:

- Earth: 0.816 / 0.871 / 0.922; normal scale 0.48; metallic 0
- Wall stone: 0.737 / 0.788 / 0.835; normal scale 0.56; metallic 0
- Oak: 0.627 / 0.663 / 0.698; normal scale 0.38; metallic 0
- Ivory: 0.417 / 0.430 / 0.442; normal scale 0.25; metallic 0.025
- Brass: 0.351 / 0.370 / 0.388; normal scale 0.23; initial edge metallic 0.63; now 0.93 after tuning

Neutral albedo map medians are earth 0.957, stone 0.949, oak 0.906, marble 0.969
and brass 0.965. These maps provide moderate material structure rather than black
staining. The dark global look therefore needs lighting/reflection balance and
shadow inspection, not removal of the data maps.

## Low-cost tuning candidates

- Brass fittings: metallic 0.90–1.0; roughness 0.32–0.38. The current intermediate
  metallic value blends dielectric and metal; solid metal should be close to 1
- Polished ivory: roughness 0.32–0.36. Slate miniature: 0.38–0.43
- Wall stone: retain 0.74–0.84 matte response. Oak: retain 0.63–0.70 or use a
  slightly smoother 0.55–0.62 only where an oiled finish is intended
- The helper currently reduces dielectric specular to 0.32 stone / 0.30 oak;
  returning to 0.5 yields standard physical dielectric reflection strength
- A brighter, desaturated reflection sky helps metal receive readable cool/warm
  reflections while preserving a dark background. Colored key/fill/rim lights
  remain responsible for subject separation and shadow color

No extra post-processing or expensive effects are needed for these changes.
Values are tuning candidates, not a claim that all have already been applied.

## Actual visual acceptance check

Use an integrated close view containing both a brass token base and pale stone,
then rotate the camera with the scene lights held still. The brass highlight
should change position/intensity; polished ivory should show a broader, weaker
moving lobe. Rough wall/wood should remain diffuse with gentle microtexture.
Inspect the shaded face for a colored fill instead of crushed black. Source
textures and headless API checks alone do not establish this visual behavior.

Primary source:
https://docs.godotengine.org/en/4.6/classes/class_basematerial3d.html

Godot explicitly documents roughness texture multiplication, dielectric vs metal
behavior, and recommends leaving metallic_specular at 0.5 in most cases.

## Actual revised lighting/material review

Reviewed `artifacts/miniature_material_closeup.png`,
`generated_city_roads_closeup.png` and `generated_world_second_angle.png`.
Updated palette uses ivory roughness 0.35, slate 0.41 and brass metallic 0.93 /
roughness 0.35. The colored side fill makes slate body shape readable; brass
bands catch narrow highlights; wood and stone remain differentiated and matte.
The ivory upper body and mountain crest are very close to white and lose
texture contrast, so bright-face clipping should be eased through key/rim or
supported exposure without darkening all albedo maps.

The currently reviewed alternate camera capture shows a different generated
scene; it does not yet establish same-object specular movement under a fixed
lighting setup. A matched close-up orbit remains the final response check.

Current palette effective roughness after tuning: ivory approximately
0.340 / 0.350 / 0.360, slate 0.398 / 0.410 / 0.421 and brass
0.332 / 0.350 / 0.367 (5th / median / 95th).

A light-only trial now preserves cool fill 0.58 and ambient 0.30 while reducing
key 1.30 to 1.05 and warm rim 0.78 to 0.48. This targets white-face clipping
without suppressing reflection or returning shadows to black. Actual matched
recapture is still needed before that trial is visually accepted.
