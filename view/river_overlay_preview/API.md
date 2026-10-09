# Real river local overlay, repaired ports

## Minimal world integration

Load `river_overlay.gd` as a Node3D and add it to the same unscaled world coordinates.

1. Read `artifacts/river_overlay_portfix_20261002/optimized_same_footprint/overlay_contract.json`.
2. Retire the contract's 23 `retire_original_ground_face_indices` from original terrain rendering and collision.
3. Call `overlay.load_cache(manifest_path, {})`. Check the boolean return and `last_error`.
4. Preserve existing world lake meshes exactly once. Exclude vegetation only where `overlay.contains_footprint(world_point)` is true.

Default options: `include_context_ground=false`, `include_existing_water=false`, `ground_collision_layer=1`, `water_collision_layer=2`. The filtered overlay is 3,964 triangles: 3,528 ground and 436 new-water triangles. It includes the whole remainder of each retired original face, the carved bed and banks, and only new river water outside old lake support. There is no full-context or old-water duplication by default.

To share the world palette, pass `materials={"ground": world_terrain_material, "water": world_water_material, "bank": local_sand_wet_soil_material, "bed": local_bed_material}` in options, or call `set_surface_material(kind, material)` after loading. The API adds no lights, camera or UI; all lighting and the Chinese interface belong to the main scene. COLOR4, UV2 and UV2_2 from the existing packed stride are retained for terrain shaders. Do not use the unavailable shore-distance sentinel UV2.x=-1 as an actual shore gate.

`get_integration_contract()` returns a defensive copy. `pick_surface(ray_from, ray_to, mask=3)` returns hit position, surface kind, original face, original hex, river-footprint inclusion, and actual source/receiver body identities. Physics uses exactly the same selected packed triangles as rendering. No movement, flight, cost or AI-GM decision is added by this module.

## Standalone viewer

`godot --path view/river_overlay_preview`

Right drag orbits, middle drag pans, wheel zooms, R resets, and left click inspects original face/hex context. The minimum orthographic size is 3.8 to respect the current renderer LOD error assumption. This viewer deliberately includes all 109 cropped source faces and old lake water (4,135 triangles total), unlike the integration default.

CLI: `-- --river-cache /absolute/path/render_cache_manifest_PENDING.json`, `--smoke`, `--filtered-integration`, or `--screenshot /absolute/path/preview.png` (actual native capture then exit).

## What is verified

- Failed baseline candidate SHA `24175aadd4bd3668d63d8095ecb35ba714e2ae2ea46686104070806dd555a853` and baseline archive remain unchanged
- Repaired candidate SHA `67846dad7766df69850fd16651231da07d783a271f3734f292a7f613a1b96b1a`
- Both actual positive-width lake interfaces have exactly zero saved-height water step; plateau extensions are 0.004881944 and 0.007654451 world units
- Maximum saved water/ground height change is 0.00012949003; all original XZ/face/barycentric/curve/water-footprint/P-ledger values remain unchanged
- Independent finite delta review passed monotone water, all overlap-vertex bed-under-water checks, exposed bank containment, terrain seams, unchanged original-H union and old-lake preservation
- New cache tested in Godot 4.6.3 Compatibility, full and filtered: three actual water/bed physics rays and face/hex provenance queries pass
- Actual native screenshot uses Mesa llvmpipe. This is not a target-device benchmark

The optimized cache keeps XZ supports and water planes; ground-interior renderer approximation is at most 0.003506275 world units against the high-detail cache, within one conservative pixel only at the declared 1080p / 3.8 orthographic assumption. This is render error, not scientific tolerance.

Scope remains one actual local reach, lake:28127 to lake:31. No whole river network, dynamic lake fill, final art, physical-world hydrology recomputation or GTX 1660 Ti acceptance is claimed. The manifest remains explicitly preview-only.

## Read-only movement geometry observations (additive extension)

`river_water_queries.gd` is a RefCounted helper and does not require a rendered scene or physics server. Create it, then `load_file("res://artifacts/river_overlay_portfix_20261002/optimized_same_footprint/new_water_query.json")`. The default SHA binding is in the helper. The 55,942-byte summary contains precisely the 264 original high-precision new-water polygons excluding old lake support, with original face/hex identities and both actual body IDs. It never treats the wider bed+bank footprint as water.

- `segment_intersects_water(from_xz: Vector2, to_xz: Vector2)` returns `ok`, `intersects`, `requires_separate_adjudication`, endpoint wet flags, contact intervals, original faces/hexes and actual water-body IDs
- `water_endpoint_context(xz: Vector2)` returns `is_new_river_water` and provenance
- `nearest_dry_candidate(origin_xz, prevalidated_candidates)` only filters the caller's already legal candidates against this new river; it never invents a point or validates old lakes, terrain or movement rules

The loaded Node3D overlay has wrappers with the same method names. Every query returns `movement_result_decided=false`. Boundary contact within 0.000002 world units is included conservatively, reflecting f32 world-vector precision. Contact intervals therefore express geometry plus this declared contact tolerance, not a hydraulic measurement. Existing lake water must still be checked by its existing owner. A failed query returns `ok=false`; callers must not treat that as permission to move.

The previously delivered 622,976-byte preview archive remains unchanged; this helper and its JSON are an additive main-integration extension.
