# Structured geometry adaptation

Research namespace, not the production game. Adapted 2026-10-04 from David Pruitt's MIT-licensed [hex_map_godot](https://github.com/davepruitt/hex_map_godot/tree/135dc754245fa867385a0d4af01ee0ae594ce526), exact inspected commit 135dc754245fa867385a0d4af01ee0ae594ce526. Copyright (c) 2024 David Pruitt. Full notice in upstream/LICENSE.md.txt; upstream scripts retained as non-executable .txt provenance.

Selected structures: edge_vertices.gd `_init` quarter-point partition; hex_metrics.gd solid corners; hex_grid_chunk.gd `_triangulate_edge_fan`, `_triangulate_edge_strip`, ownership in `_triangulate_connection` and plain triangular corner path; hex_mesh_primitive.gd paired quad triangulation. Read the exact scripts before porting. No upstream executable or project was run.

Modifications: Python authoring and logical shared-index output; v3 source-data adapter; float same-class source relief instead of integer elevation; explicit sea-level midpoint row for mixed edges and a matching mixed-corner split; full-original-hex boundary caps; canonical once-owned edge/corner registry; retained original denominator polygons; deterministic float32 output. Deliberately omitted terraces, noise perturbation, roads, rivers, features, stock water overlays, and all sorting/render-priority workarounds.

SOLID_FACTOR=.8 specifies radial inset, not 80% area. Actual final class areas are independently measured against the original full hexes. All gameplay admission and derived fields remain explicitly unverified.
