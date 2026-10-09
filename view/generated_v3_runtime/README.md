# V3 native terrain runtime

This directory serves the explicit v3 exploration candidate only. First playable profile: `structured_v1`, seed-driven `coastal_source_v3/prototype1`, recipe version `coastal_recipes/v2_tiny_remnant_cleanup`, radius 4 or 12. The source cleanup and baseline builder are frozen verified inputs. The optional local shoreline contour remains a separate experiment and is not admitted here.

`Geometry.build(source)` produces one native mesh used by both rendering and movement. Appearance adds only COLOR/UV2, interpolating persisted v3 climate; it asserts unchanged positions and indices. `Navigation.build(source,built)` independently reads actual ArrayMesh triangles and checks complete center-to-center segment coverage and positive sea clearance. Route points include triangle crossings. `cell_center`, `height_at_xz` and `cell_at_xz` expose the same coordinate geometry to the gameplay adapter. A physical dry route does not bypass the existing generic terrain/stamina policy.

The board uses the whole mesh (`Geometry.create_view(built)` default false). The optional chunk path has a strict ground-normal equality failure during native ArrayMesh repacking (maximum measured component delta 5.79e-5; positions/colors/UV2 remain exact). It is not accepted for this release. It is not required for supported radius 4/12. No lower-resolution LOD is claimed.

Independent oracle evidence: 1,060 anchors and 2,976 undirected neighbor segments across both radii and both recipes, seed 726381; zero falsely admitted wet routes or conservative dry omissions. The source module has separate multi-seed determinism/cleanup tests. These bounded fixtures are not an all-seed guarantee.

The ground shader uses the established palette with continuous cool-sky/warm-sun diffuse response, normalized to preserve upward-flat palette brightness. Native comparison kept all source, position, index, normal, COLOR and UV2 buffers unchanged. It fixes saturation of gentle relief, not coastline shape or missing scene content.

Source river records are descriptive only. No rendered river channel, physical river movement, settlement or city compatibility is claimed. This geometry is an opt-in exploration foundation, not final terrain-art acceptance.

See ATTRIBUTION.md and the retained MIT notice. The exact owned production-file list is `OWNED_RUNTIME_ALLOWLIST.json`; gameplay admission, persistence and HUD live in the separate generated_v3_adventure module.
