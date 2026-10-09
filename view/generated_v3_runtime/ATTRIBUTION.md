# Structured native mesh attribution

`structured_hex_builder.gd` is the frozen native `v3_structured_hex_gd/1` port, adapted 2026-10-04 from the frozen `v3_structured_hex/1` Python producer. That producer selectively adapts David Pruitt's MIT-licensed [hex_map_godot](https://github.com/davepruitt/hex_map_godot/tree/135dc754245fa867385a0d4af01ee0ae594ce526), exact commit `135dc754245fa867385a0d4af01ee0ae594ce526`, Copyright (c) 2024 David Pruitt.

The full required MIT notice is retained in `provenance/upstream/LICENSE.md.txt`. Five exact upstream scripts are retained beside it as non-executable `.gd.txt` reference files. `provenance/frozen_python_builder.py.txt` and `provenance/PYTHON_PORT_ATTRIBUTION.md` record the intervening producer and adaptation. None is imported or executed by this game; no upstream executable or project was run.

The native port preserves fan/quarter-edge/quad diagonal/corner ownership, local source relief, sea-zero shared midpoint rows and full-hex caps. It uses scalar construction and float32 native buffers, adds bounded validation and fresh per-call workers, and omits upstream terraces, perturbation, roads, rivers and features. The optional bounded contour experiment is not this admitted builder.

`appearance.gd`, `geometry.gd` and `navigation.gd` are project integration code: they paint persisted v3 climate, reuse the unchanged native geometry, and establish actual-triangle movement clearance. They do not adopt a license for the project. Ground/water material code derives from the project's existing generated-adventure renderer. Source generation attribution and climate-method boundaries remain in `../../core/world_generation_v3/README.md`.

Only Godot and the supplied native code are needed at runtime. Python, NumPy and geometry-audit tools are test-only. This notice and the upstream MIT license must accompany redistribution of the adapted builder.
