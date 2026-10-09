# Static entity transport fixture

`static_placement_v1.json` is an exact byte copy of the final accepted placement artifact
`artifacts/generated_v3_placement/placement_20261005_r12_coastal_range.json`.
It was copied into the test tree so the unit test does not depend on research artifacts.

- File SHA-256: `5a6fb99fa7b02afdd0e14e17ad984e8c2ef036e5b6f1b677f68930bf7b6b5d2e`
- Size: 47,811 bytes
- Placement schema/profile: `generated_v3_placement/v1`, `dry_village/v1`
- Placement hash: `df8b97401578df856ef9a382dc7097c3f5a9028b2a0092efc02aa3c6caba9b7b`
- Context hash: `ab76cbf699ffdd758be41d3942534871722c055665183eabd33a2f5c037a0506`
- Origin: generated seed `20261005`, radius `12`, recipe `coastal_range`, final river-reservation placement profile

The test checks immutable catalog binding, bounded transport shape, references, frozen
history and public projection. It does not generate or validate terrain geometry;
production admission must first run the physical placement validator against the exact
source, mesh and navigation. The original artifact is unchanged.
