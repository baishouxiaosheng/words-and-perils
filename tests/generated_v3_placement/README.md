# Source-bound village checks

All scripts run against the current project and write only their named fixture
artifacts. Use a serialized engine queue and the host's normal memory guard.
The original validation used Godot4.6.3 compatibility renderer, a512MiB cgroup
reserve and a240-second owned-process timeout.

- `test_placement.gd`:373 native checks;12 seed/radius/recipe fixtures, deterministic
  manifest reproduction/JSON admission, full-area support negatives, blocked-edge
  preservation, and all-river fail-close. Exports actual source, mesh, nav and
  placement data for an independent geometric oracle.
- `capture_placement.gd`:28 native renderer checks; full/LOD imported vertex bounds,
  foundations, exact terrain-clipped roads and six matched camera captures.
- `test_static_picking.gd`:163 raw indexed/nonindexed geometry, transformed rays,
  LOD/cache lifetime, aggregate ownership, occlusion and glow-exclusion checks.
- `test_village_board.gd`:68 combined-source checks at radius12 for both recipes;
  selection timing/purity, assessed journey, pack support, local-approach sampled
  clearance and exact long-history save readmission. Requires the admitted new
  village source and the shared historical-focus correction.
- `view/generated_v3_settlement/verify_assets.py`: independent offline raw GLB
  position/bounds/hash audit; does not replace native import validation.

For example, from the project directory, a headless harness command is
`godot --headless --path . --script res://tests/generated_v3_placement/test_village_board.gd`.
The renderer capture runs without `--headless`, under the same owned-process guard.
Fixture/debug launchers tied to the development workspace are not release files.
